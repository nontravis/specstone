import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart'
    show inlineBlock;
import 'package:specstone_core/src/setup_migration/legacy_plan.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_files.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _commit1Message = 'move legacy docs to their new paths';
const _commit2Message =
    'rewrite titles, keys, and links; add project configuration';

/// The text of every file under [root] outside `.git`, the index, and the
/// trash, keyed by its `/`-separated path relative to [root].
Map<String, String> _bytesUnder(Directory root) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  final texts = <String, String>{};
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(prefix.length)
        .replaceAll(Platform.pathSeparator, '/');
    if (relative.startsWith('.git/') ||
        relative.startsWith('.specstone/index.sqlite') ||
        relative.startsWith('.specstone/trash/')) {
      continue;
    }
    texts[relative] = entity.readAsStringSync();
  }
  return texts;
}

/// Writes the fixture under `<tmp>/NTD OS/acme/` and commits it.
Future<Directory> _spacedFixture(Map<String, String> files) async {
  final tmp = await writeTree({
    for (final MapEntry(:key, :value) in files.entries)
      'NTD OS/acme/$key': value,
  });
  final root = Directory.fromUri(tmp.uri.resolve('NTD OS/acme/'));
  expect(git(root, ['init', '-q']).exitCode, 0);
  expect(git(root, ['config', 'user.name', 't']).exitCode, 0);
  expect(git(root, ['config', 'user.email', 't@t']).exitCode, 0);
  expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
  commitAll(root, 'legacy');
  return root;
}

/// Pack pins below the versions that write the agent files, so a run is an
/// upgrade that plans them.
const _belowSince = 'packs:\n  prd-core: 1.0.0\n  software-tech: 1.0.0\n';

/// A committed project pinning pack `acme` at 1.0.0, whose 1.1.0 in the
/// returned home renames the runbook's `Steps` section, with one runbook.
Future<({Directory project, Directory home})> _upgradeFixture() async {
  final home = await writeTree({
    '.specstone/packs/acme/pack.yaml': '''
name: acme
version: 1.1.0
extends: software-tech
migrations:
  - from: 1.0.0
    steps:
      - rename_section: {doc_type: runbook, from: {id: steps, header: Steps}, to: {id: procedure, header: Procedure}}
''',
    '.specstone/packs/acme/runbook.yaml': '''
id: runbook
description: A runbook.
path: prds/runbooks/{slug}/RUNBOOK.md
sections:
  - {id: procedure, header: Procedure, required: true}
''',
  });
  final project = await gitFixture({
    '.specstone/config.yaml': '${shippedPinsConfig()}  acme: 1.0.0\n',
    'docs/prds/runbooks/deploy/RUNBOOK.md': '# Deploy\n\n## Steps\n\nRun it.\n',
  });
  return (project: project, home: home);
}

/// A committed project below the pack versions that write the agent files,
/// whose `lib/a.dart` holds a number label the label pass converts.
Future<Directory> _labelledCodeFixture() => gitFixture({
  '.specstone/config.yaml': _belowSince,
  'docs/prds/features/f01_a/FEATURE.md': '# A\n',
  'docs/prds/features/f01_a/us01_b/USER_STORY.md': '# B\n',
  'docs/prds/features/f01_a/us01_b/fr01_c.md': '# C\n',
  'docs/specs/TECH_STACK.md': '---\ncode:\n  - lib/\n---\n# Tech stack\n',
  'lib/a.dart': '// See F-01 US-01\n',
});

/// Writes [files] under a new canonical folder, makes each key of [links] a
/// link to its value, then commits `proj/` and [other] as two repositories.
Future<Directory> _twoRepositories(
  Map<String, String> files, {
  required String other,
  Map<String, String> links = const {},
}) async {
  final base = Directory((await writeTree(files)).resolveSymbolicLinksSync());
  for (final MapEntry(key: path, value: target) in links.entries) {
    Link('${base.path}/$path').createSync(target);
  }
  commitRepo(Directory('${base.path}/$other'));
  commitRepo(Directory('${base.path}/proj'));
  return base;
}

/// Returns the hash on the `plan <hash>` line a dry run of [root] prints.
Future<String> _dryRunPlanHash(Directory root) async {
  final out = StringBuffer();
  expect(await _run(root, out, dryRun: true), 0);
  final lines = out.toString().split('\n');
  return lines[lines.length - 3].substring('plan '.length);
}

/// Returns the hash on the `plan <hash>` line of [text].
String _planHashIn(String text) => text
    .split('\n')
    .firstWhere((line) => line.startsWith('plan '))
    .substring('plan '.length);

/// Writes a legacy `ws` whose `code/docs` links to its `docs`, with [files]
/// over it; null, marking the test skipped, where links need privileges.
Future<Directory?> _linkedTree([Map<String, String> files = const {}]) async {
  final tree = await writeTree(linkedAcme(files));
  return linkCodeDocs(tree) ? tree : null;
}

/// Expects the refusal a write at the untrusted `ws/code` of [tree] draws: the
/// project folder `ws` was reached through the docs link in `ws/code`.
Matcher _untrustedRefusal(Directory tree) {
  final project = Directory('${tree.path}/ws').resolveSymbolicLinksSync();
  final linked = Directory('${tree.path}/ws/code').resolveSymbolicLinksSync();
  return throwsA(
    isA<RenderFault>()
        .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
        .having((f) => f.exitStatus, 'exit', 73)
        .having((f) => f.file, 'file', MoveJournal.journalPath)
        .having(
          (f) => f.message,
          'message',
          'cannot write ${MoveJournal.journalPath}: the project folder '
              '$project was reached through the docs link in $linked; run '
              'specstone trust at a terminal to allow it',
        ),
  );
}

/// Expects the refusal of a journal for [reason], as every write command
/// gives it.
Matcher _journalRefusal(String reason) => throwsA(
  isA<RenderFault>()
      .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
      .having((f) => f.exitStatus, 'exit', 73)
      .having((f) => f.file, 'file', MoveJournal.journalPath)
      .having(
        (f) => f.message,
        'message',
        '$reason; check .specstone/trash/ and delete it to go on',
      ),
);

Future<int> _run(
  Directory root,
  StringBuffer out, {
  OwnerConfirmation confirmation = OwnerConfirmation.prompt,
  List<String?> answers = const [],
  bool dryRun = false,
  bool asJson = false,
  Directory? home,
  String? planHash,
  List<String>? warnings,
  RunGit runGit = runMigrateGit,
  List<String> addedPacks = const [],
}) async {
  var call = 0;
  return await runMigrate(
    MigrateRequest(
      workingDirectory: root,
      homeDirectory: home ?? testHome(),
      templates: TemplateResolver(),
      dryRun: dryRun,
      asJson: asJson,
      confirmation: confirmation,
      planHash: planHash,
      runGit: runGit,
      addedPacks: addedPacks,
      readLine: () => call++ < answers.length ? answers[call - 1] : null,
      out: out,
      warn: (warnings ?? <String>[]).add,
    ),
  );
}

void main() {
  group('the names an add checks before the trust and git checks', () {
    Matcher usageError(String message) => throwsA(
      isA<MigrateUsageError>().having((e) => e.message, 'message', message),
    );

    Matcher packNotFound(String name) => throwsA(
      isA<TemplateFault>()
          .having((f) => f.code, 'code', FaultCode.packNotFound)
          .having((f) => f.file, 'file', '.specstone/config.yaml')
          .having((f) => f.key, 'key', 'packs.$name')
          .having(
            (f) => f.message,
            'message',
            'no shipped or personal pack named $name',
          ),
    );

    test('an add on a pending journal is a usage error', () async {
      final root = await gitFixture({
        '.specstone/config.yaml': shippedPinsConfig(),
      });
      writeJournal(root, [
        CommitStep(message: 'move', paths: const ['a'], base: headOf(root)),
      ]);

      await expectLater(
        _run(root, StringBuffer(), addedPacks: ['agent-skills']),
        usageError(
          'finish the pending migrate run first: run specstone migrate',
        ),
      );
    });

    test('an add on a legacy tree is a usage error', () async {
      final root = await gitFixture({
        '.specstone/config.yaml': shippedPinsConfig(),
        legacyContextPath: '# D-01\n',
      });

      await expectLater(
        _run(root, StringBuffer(), addedPacks: ['agent-skills']),
        usageError(
          '--add needs a project on the new format; run specstone migrate '
          'first',
        ),
      );
    });

    test('an add of a pinned pack is a usage error naming its pin', () async {
      final root = await gitFixture({
        '.specstone/config.yaml':
            '${shippedPinsConfig()}  agent-skills: 0.9.0\n',
      });

      await expectLater(
        _run(root, StringBuffer(), addedPacks: ['agent-skills']),
        usageError(
          'agent-skills is already pinned at 0.9.0; run specstone migrate to '
          'upgrade it',
        ),
      );
    });

    test('an add no pack holds is pack_not_found before the git '
        'checks', () async {
      final root = await gitFixture({
        '.specstone/config.yaml': shippedPinsConfig(),
      });
      File('${root.path}/stray.txt').writeAsStringSync('dirty\n');

      await expectLater(
        _run(root, StringBuffer(), addedPacks: ['nope']),
        packNotFound('nope'),
      );
    });

    test('an add no pack holds refuses before a pending document-writing '
        'journal is replayed', () async {
      final root = await gitFixture({
        '.specstone/config.yaml': shippedPinsConfig(),
      });
      writeJournal(root, [const WriteStep.unguarded('notes.md', 'new\n')]);

      await expectLater(
        _run(root, StringBuffer(), addedPacks: ['nope']),
        packNotFound('nope'),
      );

      expect(File('${root.path}/notes.md').existsSync(), isFalse);
      expect(MoveJournal.pending(root), isTrue);
    });

    test('the first failing added name refuses alone, in name '
        'order', () async {
      final root = await gitFixture({
        '.specstone/config.yaml': shippedPinsConfig(),
      });

      await expectLater(
        _run(root, StringBuffer(), addedPacks: ['zeta', 'beta']),
        packNotFound('beta'),
      );
    });
  });

  test('y makes two commits, the first pure renames', () async {
    final root = await _spacedFixture(acmeLegacy);
    final out = StringBuffer();

    final status = await _run(root, out, answers: ['y']);

    expect(status, 0);
    final subjects = (git(root, ['log', '--format=%s']).stdout as String)
        .trim()
        .split('\n');
    expect(subjects, [_commit2Message, _commit1Message, 'legacy']);
    final renames =
        git(root, ['show', '--name-status', '-M', '--format=', 'HEAD~1']).stdout
            as String;
    for (final line in renames.trim().split('\n')) {
      expect(line, startsWith('R100'), reason: line);
    }
    final names =
        (git(root, ['show', '--name-only', '--format=', 'HEAD']).stdout
                as String)
            .trim()
            .split('\n');
    expect(names.toSet(), {
      '.specstone/AGENT.md',
      'AGENTS.md',
      ...skillPaths(),
      '.specstone/config.yaml',
      '.specstone/.gitignore',
      '.specstone/templates/gnfr.yaml',
      'docs/specs/TECH_STACK.md',
      'docs/prds/GOAL.md',
      'docs/prds/GLOSSARY.md',
      'docs/prds/PROJECT.md',
      'docs/prds/FEATURES.md',
      'docs/prds/GNFR.md',
      'docs/prds/features/f01_login/FEATURE.md',
      'docs/prds/features/f01_login/us01_email_login/USER_STORY.md',
      'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
      'docs/specs/f01_login/ARCHITECTURE.md',
      'docs/specs/f01_login/DOMAIN.md',
    });
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
    expect(
      File('${root.path}/.specstone/config.yaml').readAsStringSync(),
      endsWith('agent_files_version: $specstoneVersion\n'),
    );
    expect(
      Directory.fromUri(root.uri.resolve('.specstone/trash/')).existsSync(),
      isFalse,
    );

    final promptAt = out.toString().indexOf('apply? [y/N] ');
    final tail = out.toString().substring(promptAt);
    expect(
      tail,
      matches(
        RegExp(
          r'^apply\? \[y/N\] '
          r'commit 1 ([0-9a-f]{7,}): move legacy docs to their new paths\n'
          'commit 2 ([0-9a-f]{7,}): rewrite titles, keys, and links; '
          r'add project configuration\n'
          r'check: \d+ findings left; run specstone check to see them\n$',
        ),
      ),
    );
    expect(out.toString(), startsWith('legacy migration: '));
  }, skip: hasGit ? null : 'git is not available');

  group('the closing count and the JSON plan', () {
    final skipGit = hasGit ? null : 'git is not available';

    Future<int> findingsOf(Directory root) => ReadSession.runAsync(
      (session) async => (await runCheck(session)).findings.length,
      templates: TemplateResolver(),
      workingDirectory: root,
      homeDirectory: testHome(),
    );

    test('an applied legacy run ends with the findings a whole-project check '
        'reports after its last commit', () async {
      final root = await gitFixture(acmeLegacy);
      final out = StringBuffer();

      expect(await _run(root, out, answers: ['y']), 0);

      final last = out.toString().trim().split('\n').last;
      expect(
        last,
        'check: ${await findingsOf(root)} findings left; '
        'run specstone check to see them',
      );
    }, skip: skipGit);

    test('an applied upgrade ends with the same closing line', () async {
      final fixture = await _upgradeFixture();
      final out = StringBuffer();

      expect(
        await _run(fixture.project, out, home: fixture.home, answers: ['y']),
        0,
      );

      expect(
        out.toString().trim().split('\n').last,
        matches(r'^check: \d+ findings left; run specstone check to see them$'),
      );
    }, skip: skipGit);

    test('--dry-run --json prints the plan as one object whose keys hold the '
        'path lists, and the plan hash is the one of the text plan', () async {
      final root = await gitFixture(acmeLegacy);
      final text = StringBuffer();
      final json = StringBuffer();
      expect(await _run(root, text, dryRun: true), 0);

      expect(await _run(root, json, dryRun: true, asJson: true), 0);

      final object = jsonDecode(json.toString()) as Map<String, Object?>;
      expect(object.keys, [
        'plan',
        'dirty',
        'formatLayout',
        'numberLabels',
        'cites',
        'renumberIds',
        'agentFiles',
        'stamps',
        'steps',
        'mentions',
        'tests',
      ]);
      expect(object, isNot(contains('planHash')));
      expect(text.toString(), startsWith(object['plan']! as String));
      expect(
        (object['plan']! as String).trimRight().split('\n').last,
        'plan ${await _dryRunPlanHash(root)}',
      );
      expect(object['formatLayout'], ['specs/f01_login/DOMAIN.md']);
      expect(object['agentFiles'], [
        '.specstone/AGENT.md',
        'AGENTS.md',
        ...skillPaths(),
      ]);
      expect(object['numberLabels'], {
        'rewritten': ['prds/features/f01_login/FEATURE.md'],
        'left': isA<List<Object?>>(),
      });
      expect(object['stamps'], {'skipped': <Object?>[]});
      expect(object['tests'], {
        'written': <Object?>[],
        'rewritten': <Object?>[],
        'left': <Object?>[],
      });
      expect(json.toString().trim().split('\n').first, '{');
    }, skip: skipGit);

    test('--yes --plan --json applies the run and prints the one object; '
        'the commit lines and the closing line go to the warnings', () async {
      final fixture = await _upgradeFixture();
      final dry = StringBuffer();
      expect(
        await _run(
          fixture.project,
          dry,
          home: fixture.home,
          dryRun: true,
          asJson: true,
        ),
        0,
      );
      final hash = _planHashIn(
        (jsonDecode(dry.toString()) as Map<String, Object?>)['plan']! as String,
      );
      final out = StringBuffer();
      final notes = <String>[];

      final status = await _run(
        fixture.project,
        out,
        home: fixture.home,
        confirmation: OwnerConfirmation.given,
        planHash: hash,
        asJson: true,
        warnings: notes,
      );

      expect(status, 0);
      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['plan'], isNot(contains('plan $hash')));
      expect(object['steps'], [
        {
          'from': '1.0.0',
          'step': 'rename_section runbook steps -> procedure',
          'paths': ['prds/runbooks/deploy/RUNBOOK.md'],
        },
      ]);
      expect(notes.last, matches(r'^check: \d+ findings left; '));
      expect(MoveJournal.pending(fixture.project), isFalse);
    }, skip: skipGit);

    test('--dry-run --json on a dirty tree holds dirty true', () async {
      final root = await gitFixture(acmeLegacy);
      File('${root.path}/notes.txt').writeAsStringSync('scratch\n');
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true, asJson: true), 0);

      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['dirty'], isTrue);
    }, skip: skipGit);

    test('--dry-run --json on a clean tree holds dirty false', () async {
      final root = await gitFixture(acmeLegacy);
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true, asJson: true), 0);

      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['dirty'], isFalse);
    }, skip: skipGit);

    test('--yes --plan --json holds no dirty key', () async {
      final fixture = await _upgradeFixture();
      final dry = StringBuffer();
      expect(
        await _run(
          fixture.project,
          dry,
          home: fixture.home,
          dryRun: true,
          asJson: true,
        ),
        0,
      );
      final hash = _planHashIn(
        (jsonDecode(dry.toString()) as Map<String, Object?>)['plan']! as String,
      );
      final out = StringBuffer();

      final status = await _run(
        fixture.project,
        out,
        home: fixture.home,
        confirmation: OwnerConfirmation.given,
        planHash: hash,
        asJson: true,
      );

      expect(status, 0);
      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object.keys, isNot(contains('dirty')));
    }, skip: skipGit);

    test('--json changes no byte of the plan the hash covers', () async {
      final root = await gitFixture(acmeLegacy);
      final withJson = StringBuffer();
      final without = StringBuffer();
      expect(await _run(root, withJson, dryRun: true, asJson: true), 0);
      expect(await _run(root, without, dryRun: true), 0);

      final object = jsonDecode(withJson.toString()) as Map<String, Object?>;

      expect(
        _planHashIn(object['plan']! as String),
        _planHashIn(without.toString()),
      );
    }, skip: skipGit);
  });

  group('a migrate run with no home folder to record its journal', () {
    final skipGit = hasGit ? null : 'git is not available';

    Matcher refusesHomeless() => throwsA(
      isA<RenderFault>()
          .having((f) => f.exitStatus, 'exit', 73)
          .having((f) => f.file, 'file', MoveJournal.journalPath)
          .having(
            (f) => f.message,
            'message',
            'cannot write .specstone/trash/journal.json: no home folder '
                'to record it in',
          ),
    );

    Future<int> runHomeless(
      Directory root,
      StringBuffer out, {
      OwnerConfirmation confirmation = OwnerConfirmation.prompt,
      String? planHash,
    }) async => await runMigrate(
      MigrateRequest(
        workingDirectory: root,
        homeDirectory: null,
        templates: TemplateResolver(),
        dryRun: false,
        confirmation: confirmation,
        planHash: planHash,
        readLine: () => 'y',
        out: out,
      ),
    );

    test(
      'outside a git work tree refuses git_work_tree_required first',
      () async {
        final root = await writeTree(acmeLegacy);

        await expectLater(
          () => runHomeless(root, StringBuffer()),
          throwsA(
            isA<MigrateFault>()
                .having(
                  (f) => f.code,
                  'code',
                  MigrateFaultCode.gitWorkTreeRequired,
                )
                .having((f) => f.exitStatus, 'exit', 78),
          ),
        );
      },
      skip: skipGit,
    );

    test(
      'at a terminal prints the plan, never asks, and changes nothing',
      () async {
        final root = await gitFixture(acmeLegacy);
        final before = treeBytes(root);
        final out = StringBuffer();

        await expectLater(() => runHomeless(root, out), refusesHomeless());

        expect(out.toString(), startsWith('legacy migration: '));
        expect(out.toString(), isNot(contains('apply?')));
        expect(treeBytes(root), before);
      },
      skip: skipGit,
    );

    test(
      'under --yes with the seen plan refuses and changes nothing',
      () async {
        final root = await gitFixture(acmeLegacy);
        final hash = await _dryRunPlanHash(root);
        final before = treeBytes(root);

        await expectLater(
          () => runHomeless(
            root,
            StringBuffer(),
            confirmation: OwnerConfirmation.given,
            planHash: hash,
          ),
          refusesHomeless(),
        );

        expect(treeBytes(root), before);
      },
      skip: skipGit,
    );
  });

  test('one git reset undoes the run', () async {
    final root = await gitFixture(acmeLegacy);
    final legacy = _bytesUnder(root);
    final out = StringBuffer();

    expect(await _run(root, out, answers: ['y']), 0);

    expect(git(root, ['reset', '-q', '--hard', 'HEAD~2']).exitCode, 0);
    expect(_bytesUnder(root), legacy);
    expect(
      File.fromUri(root.uri.resolve('.specstone/config.yaml')).existsSync(),
      isFalse,
    );
  }, skip: hasGit ? null : 'git is not available');

  test(
    'no moved or rewritten doc holds a '
    'draft key; TECH_STACK.md, GOAL.md, and GLOSSARY.md are drafts',
    () async {
      final root = await gitFixture(acmeLegacy);
      final out = StringBuffer();

      expect(await _run(root, out, answers: ['y']), 0);

      for (final file in _bytesUnder(root).entries) {
        if (file.key == '.specstone/.gitignore') continue;
        if (file.key == 'docs/specs/TECH_STACK.md') continue;
        if (file.key == 'docs/prds/GOAL.md') continue;
        if (file.key == 'docs/prds/GLOSSARY.md') continue;
        if (skillPaths().contains(file.key)) continue;
        expect(file.value, isNot(contains('draft:')), reason: file.key);
      }
      expect(
        File.fromUri(root.uri.resolve('docs/specs/TECH_STACK.md'))
            .readAsStringSync(),
        startsWith('---\ndraft: true\n'),
      );
      expect(
        File.fromUri(root.uri.resolve('docs/prds/GOAL.md')).readAsStringSync(),
        startsWith('---\ndraft: true\n'),
      );
      expect(
        File.fromUri(root.uri.resolve('docs/prds/GLOSSARY.md'))
            .readAsStringSync(),
        startsWith('---\ndraft: true\n'),
      );
    },
    skip: hasGit ? null : 'git is not available',
  );

  test('the '
      'applied run leaves each typed doc stamped with the hash of its text, '
      'and '
      'the created draft keeps draft: true', () async {
    final root = await gitFixture(acmeLegacy);

    expect(await _run(root, StringBuffer(), answers: ['y']), 0);

    final files = _bytesUnder(root);
    for (final path in [
      'docs/prds/PROJECT.md',
      'docs/prds/FEATURES.md',
      'docs/prds/features/f01_login/FEATURE.md',
      'docs/prds/features/f01_login/us01_email_login/USER_STORY.md',
      'docs/specs/f01_login/ARCHITECTURE.md',
      'docs/specs/f01_login/DOMAIN.md',
    ]) {
      expect(files[path], startsWith('---\napproved: "'), reason: path);
    }
    expect(files['docs/specs/TECH_STACK.md'], startsWith('---\ndraft: true'));
    expect(files['docs/specs/INDEX.md'], isNot(contains('approved:')));
  }, skip: hasGit ? null : 'git is not available');

  test('INDEX.md, the untyped files, and the container doc '
      'stay after both commits', () async {
    const indexText = '# Spec index\n';
    const untypedText = '# Notes\n';
    final root = await gitFixture({
      ...containerLegacy,
      'docs/prds/d01_context.md': '# D-01 — Context\n',
      'docs/specs/INDEX.md': indexText,
      'docs/prds/features/components/co07_navigation/notes.md': untypedText,
    });
    final out = StringBuffer();

    expect(await _run(root, out, answers: ['y']), 0);

    expect(
      File.fromUri(root.uri.resolve('docs/specs/INDEX.md')).readAsStringSync(),
      indexText,
      reason: 'INDEX.md stays with its bytes',
    );
    expect(
      File.fromUri(
        root.uri.resolve(
          'docs/prds/features/components/co07_navigation/notes.md',
        ),
      ).readAsStringSync(),
      untypedText,
      reason: 'an untyped file stays where it was',
    );
    expect(
      File.fromUri(root.uri.resolve('docs/prds/features/utilities/FEATURE.md'))
          .existsSync(),
      isTrue,
      reason: 'the container doc moved under the group',
    );
    expect(
      File.fromUri(
        root.uri.resolve('docs/prds/features/utilities/f01_slot/FEATURE.md'),
      ).existsSync(),
      isTrue,
    );
    expect(
      File.fromUri(
        root.uri.resolve(
          'docs/prds/features/components/f07_navigation/FEATURE.md',
        ),
      ).existsSync(),
      isTrue,
      reason: 'a flat feature under a group folder keeps its old folder',
    );
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');

  test('any answer but y writes nothing', () async {
    for (final answer in ['n', '', 'yes', null]) {
      final root = await gitFixture(acmeLegacy);
      final legacy = _bytesUnder(root);
      final head = (git(root, ['rev-parse', 'HEAD']).stdout as String).trim();
      final out = StringBuffer();

      final status = await _run(root, out, answers: [answer]);

      expect(status, 0, reason: 'answer $answer');
      expect(
        (git(root, ['rev-parse', 'HEAD']).stdout as String).trim(),
        head,
        reason: 'answer $answer',
      );
      expect(_bytesUnder(root), legacy, reason: 'answer $answer');
      expect(out.toString().contains('apply? [y/N] '), isTrue);
    }
  }, skip: hasGit ? null : 'git is not available');

  group('a change while the Owner reads the '
      'plan', () {
    final skipGit = hasGit ? null : 'git is not available';

    /// Runs bare migrate on [root] at a terminal, running [meanwhile] while
    /// the prompt waits, then answering `y`.
    Future<int> answerAfter(
      Directory root,
      void Function() meanwhile, {
      Directory? home,
      StringSink? out,
    }) => runMigrate(
      MigrateRequest(
        workingDirectory: root,
        homeDirectory: home ?? testHome(),
        templates: TemplateResolver(),
        dryRun: false,
        confirmation: OwnerConfirmation.prompt,
        readLine: () {
          meanwhile();
          return 'y';
        },
        out: out ?? StringBuffer(),
      ),
    );

    test('a doc edited before the y is '
        'working_tree_dirty, and the edit and the tree stay', () async {
      final root = await gitFixture(acmeLegacy);
      final head = headOf(root);
      final context = File('${root.path}/docs/prds/d01_context.md');

      await expectLater(
        () => answerAfter(
          root,
          () => context.writeAsStringSync('# D-01 — Project context\n\nedit\n'),
        ),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.workingTreeDirty,
          ),
        ),
      );
      expect(headOf(root), head);
      expect(context.readAsStringSync(), '# D-01 — Project context\n\nedit\n');
      expect(_bytesUnder(root), {
        ...acmeLegacy,
        'docs/prds/d01_context.md': '# D-01 — Project context\n\nedit\n',
      });
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('a commit that leaves every input as it was, made '
        'while the prompt waits, lets the run apply on top of it', () async {
      final root = await gitFixture(acmeLegacy);
      late final String meanwhile;

      expect(
        await answerAfter(root, () {
          File('${root.path}/notes.txt').writeAsStringSync('x\n');
          commitAll(root, 'meanwhile');
          meanwhile = headOf(root);
        }),
        0,
      );

      final subjects = (git(root, ['log', '--format=%s']).stdout as String)
          .trim()
          .split('\n');
      expect(subjects, [
        _commit2Message,
        _commit1Message,
        'meanwhile',
        'legacy',
      ]);
      expect(
        (git(root, ['rev-parse', 'HEAD~2']).stdout as String).trim(),
        meanwhile,
        reason: 'commit 1 builds on the commit made while the prompt waited',
      );
    }, skip: skipGit);

    test('a committed edit to an input, made while the '
        'prompt waits, is working_tree_dirty naming it, and nothing is '
        'written', () async {
      final root = await gitFixture(acmeLegacy);
      const input = 'docs/prds/d01_context.md';

      await expectLater(
        () => answerAfter(root, () {
          File('${root.path}/$input').writeAsStringSync('# edited\n');
          commitAll(root, 'meanwhile');
        }),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.workingTreeDirty)
              .having(
                (f) => f.message,
                'message',
                '$input, an input of the plan, changed while the plan was '
                    'shown; run specstone migrate again to plan from it',
              ),
        ),
      );
      expect(_bytesUnder(root), {...acmeLegacy, input: '# edited\n'});
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('a committed deletion of an input, made while the '
        'prompt waits, is working_tree_dirty naming it, never a raw '
        'FileSystemException', () async {
      final root = await gitFixture(acmeLegacy);
      const input = 'docs/prds/d01_context.md';

      await expectLater(
        () => answerAfter(root, () {
          expect(git(root, ['rm', '-q', input]).exitCode, 0);
          expect(git(root, ['commit', '-q', '-m', 'meanwhile']).exitCode, 0);
        }),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.workingTreeDirty)
              .having((f) => f.message, 'message', startsWith('$input, ')),
        ),
      );
      expect(File('${root.path}/$input').existsSync(), isFalse);
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('an upgrade doc edited before the y is '
        'working_tree_dirty, and the edit stays', () async {
      final (:project, :home) = await _upgradeFixture();
      final runbook = File(
        '${project.path}/docs/prds/runbooks/deploy/RUNBOOK.md',
      );
      final out = StringBuffer();

      await expectLater(
        () => answerAfter(
          project,
          () => runbook.writeAsStringSync('# Deploy\n\n## Steps\n\nedited\n'),
          home: home,
          out: out,
        ),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.workingTreeDirty,
          ),
        ),
      );
      expect(out.toString(), contains('apply? [y/N] '));
      expect(runbook.readAsStringSync(), '# Deploy\n\n## Steps\n\nedited\n');
      expect(MoveJournal.pending(project), isFalse);
    }, skip: skipGit);

    /// Expects [meanwhile], run while the prompt waits, to make the run refuse
    /// `working_tree_dirty` naming [input], with nothing written after it.
    Future<void> expectRefusedNaming(
      Directory root,
      String input,
      void Function() meanwhile, {
      Directory? home,
    }) async {
      late final String head;
      await expectLater(
        () => answerAfter(root, () {
          meanwhile();
          head = headOf(root);
        }, home: home),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.workingTreeDirty)
              .having((f) => f.message, 'message', contains(input)),
        ),
      );
      expect(headOf(root), head);
      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
      expect(MoveJournal.pending(root), isFalse);
    }

    test('a legacy doc committed while the prompt waits is '
        'working_tree_dirty naming it, and nothing is written', () async {
      final root = await gitFixture(acmeLegacy);
      const added = 'docs/prds/d09_extra.md';

      await expectRefusedNaming(root, added, () {
        File('${root.path}/$added').writeAsStringSync('# D-09 — Extra\n');
        commitAll(root, 'meanwhile');
      });

      expect(_bytesUnder(root), {...acmeLegacy, added: '# D-09 — Extra\n'});
    }, skip: skipGit);

    test('a committed doc that makes the re-plan refuse '
        'legacy_collision, made while the prompt waits, refuses '
        'legacy_collision, and nothing is written', () async {
      final root = await gitFixture(acmeLegacy);
      const collided = 'prds/PROJECT.md';
      late final String head;

      await expectLater(
        () => answerAfter(root, () {
          File('${root.path}/docs/$collided').writeAsStringSync('# Project\n');
          commitAll(root, 'meanwhile');
          head = headOf(root);
        }),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.legacyCollision)
              .having((f) => f.exitStatus, 'exitStatus', 65),
        ),
      );
      expect(headOf(root), head);
      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
      expect(MoveJournal.pending(root), isFalse);
      expect(_bytesUnder(root), {
        ...acmeLegacy,
        'docs/$collided': '# Project\n',
      });
    }, skip: skipGit);

    test('an ignored legacy doc made unreadable while the '
        'prompt waits is working_tree_dirty naming that doc, and nothing is '
        'written', () async {
      const ignored = 'docs/prds/zz_local.md';
      final root = await gitFixture({
        ...acmeLegacy,
        '.gitignore': 'zz_local.md\n',
        ignored: '# D-09 — Local\n',
      });
      final file = File('${root.path}/$ignored');
      addTearDown(() => Process.runSync('chmod', ['644', file.path]));

      // The read's RenderFault carries no file; the recorded read names it.
      await expectRefusedNaming(root, ignored, () {
        expect(Process.runSync('chmod', ['000', file.path]).exitCode, 0);
      });
    }, skip: Platform.isWindows ? 'chmod does not apply on Windows' : skipGit);

    test('a runbook committed while an upgrade prompt '
        'waits is working_tree_dirty naming it, and nothing is '
        'written', () async {
      final (:project, :home) = await _upgradeFixture();
      const added = 'docs/prds/runbooks/other/RUNBOOK.md';

      await expectRefusedNaming(project, added, () {
        File('${project.path}/$added')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('# Other\n\n## Steps\n\nRun it.\n');
        commitAll(project, 'meanwhile');
      }, home: home);

      expect(
        File('${project.path}/.specstone/config.yaml').readAsStringSync(),
        contains('acme: 1.0.0'),
      );
    }, skip: skipGit);

    test('a file added to the personal pack while an '
        'upgrade prompt waits is working_tree_dirty naming it, and nothing '
        'is written', () async {
      final (:project, :home) = await _upgradeFixture();
      // The refusal names a path outside the project as the code builds it.
      final added = [
        '',
        '.specstone',
        'packs',
        'acme',
        'playbook.yaml',
      ].join(Platform.pathSeparator);

      await expectRefusedNaming(project, added, () {
        File('${home.path}$added').writeAsStringSync('''
id: playbook
description: A playbook.
path: prds/playbooks/{slug}/PLAYBOOK.md
sections:
  - {id: body, header: Body, required: true}
''');
      }, home: home);
    }, skip: skipGit);

    test('a config committed as deleted while an upgrade '
        'prompt waits is working_tree_dirty naming it, never a raw '
        'FileSystemException', () async {
      final (:project, :home) = await _upgradeFixture();
      const config = '.specstone/config.yaml';

      await expectRefusedNaming(project, config, () {
        expect(git(project, ['rm', '-q', config]).exitCode, 0);
        commitAll(project, 'meanwhile');
      }, home: home);

      expect(File('${project.path}/$config').existsSync(), isFalse);
    }, skip: skipGit);

    test('a personal pack.yaml deleted while an upgrade '
        'prompt waits is working_tree_dirty naming it, and nothing is '
        'written', () async {
      final (:project, :home) = await _upgradeFixture();
      const packPath = '.specstone/packs/acme/pack.yaml';

      await expectRefusedNaming(project, packPath, () {
        File('${home.path}/$packPath').deleteSync();
      }, home: home);

      expect(
        File('${project.path}/.specstone/config.yaml').readAsStringSync(),
        contains('acme: 1.0.0'),
      );
    }, skip: skipGit);

    test('an invalid file dropped in the personal pack '
        'while an upgrade prompt waits is working_tree_dirty naming it, and '
        'nothing is written', () async {
      final (:project, :home) = await _upgradeFixture();
      const broken = 'playbook.yaml';

      await expectRefusedNaming(project, broken, () {
        File('${home.path}/.specstone/packs/acme/$broken')
            .writeAsStringSync('id: [unclosed\n');
      }, home: home);
    }, skip: skipGit);

    test('a tracked file committed while an upgrade with a '
        'labelled code file waits leaves every input, and the run applies '
        'without reading the code file', () async {
      final project = await _labelledCodeFixture();

      expect(
        await answerAfter(project, () {
          File('${project.path}/notes.txt').writeAsStringSync('x\n');
          commitAll(project, 'meanwhile');
        }),
        0,
      );

      expect(git(project, ['status', '--porcelain']).stdout, isEmpty);
      expect(
        File('${project.path}/lib/a.dart').readAsStringSync(),
        '// See F-01 US-01\n',
      );
    }, skip: skipGit);

    test('a tree made dirty while the prompt waits refuses with the message of '
        'the first clean-tree check, and nothing is written', () async {
      final root = await gitFixture(acmeLegacy);
      final head = headOf(root);

      await expectLater(
        () => answerAfter(
          root,
          () => File('${root.path}/notes.txt').writeAsStringSync('x\n'),
        ),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.workingTreeDirty)
              .having((f) => f.exitStatus, 'exit', 75)
              .having(
                (f) => f.message,
                'message',
                'the repository that holds the docs has uncommitted changes; '
                    'commit or stash them, then run specstone migrate again',
              ),
        ),
      );

      expect(headOf(root), head);
      expect(_bytesUnder(root), {...acmeLegacy, 'notes.txt': 'x\n'});
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('a file that changes only the plan text, committed while the prompt '
        'waits, refuses naming the plan alone, and nothing is '
        'written', () async {
      final root = await gitFixture(acmeLegacy);
      const added = 'docs/specs/schema.dbml';
      late final String head;

      await expectLater(
        () => answerAfter(root, () {
          File('${root.path}/$added').writeAsStringSync('Table t {}\n');
          commitAll(root, 'meanwhile');
          head = headOf(root);
        }),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.workingTreeDirty)
              .having((f) => f.exitStatus, 'exit', 75)
              .having(
                (f) => f.message,
                'message',
                'the plan changed while the plan was shown; run specstone '
                    'migrate again to plan from it',
              ),
        ),
      );

      expect(headOf(root), head);
      expect(_bytesUnder(root), {...acmeLegacy, added: 'Table t {}\n'});
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('two inputs committed changed while the prompt waits refuse naming '
        'the first in code point order, an upper-case name before a '
        'lower-case one', () async {
      final root = await gitFixture(acmeLegacy);
      const first = 'docs/specs/INDEX.md';
      const second = 'docs/specs/api/auth/s02_api_login.md';

      await expectLater(
        () => answerAfter(root, () {
          for (final path in [second, first]) {
            final file = File('${root.path}/$path');
            file.writeAsStringSync('${file.readAsStringSync()}\nedit\n');
          }
          commitAll(root, 'meanwhile');
        }),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.workingTreeDirty)
              .having(
                (f) => f.message,
                'message',
                '$first, an input of the plan, changed while the plan was '
                    'shown; run specstone migrate again to plan from it',
              ),
        ),
      );

      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('a committed .specstone/config.yaml that cannot parse, made while an '
        'upgrade prompt waits, refuses naming it as an input', () async {
      final (:project, :home) = await _upgradeFixture();
      const config = '.specstone/config.yaml';
      late final String head;

      await expectLater(
        () => answerAfter(project, () {
          File('${project.path}/$config')
              .writeAsStringSync('packs: [unclosed\n');
          commitAll(project, 'meanwhile');
          head = headOf(project);
        }, home: home),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.workingTreeDirty)
              .having(
                (f) => f.message,
                'message',
                '$config, an input of the plan, changed while the plan was '
                    'shown; run specstone migrate again to plan from it',
              ),
        ),
      );

      expect(headOf(project), head);
      expect(git(project, ['status', '--porcelain']).stdout, isEmpty);
      expect(MoveJournal.pending(project), isFalse);
    }, skip: skipGit);

    test('the next bare run after a refused re-check plans again from the '
        'tree as it then is, and applies it', () async {
      final root = await gitFixture(acmeLegacy);
      final hashBefore = await _dryRunPlanHash(root);
      await expectLater(
        () => answerAfter(root, () {
          File('${root.path}/docs/prds/d01_context.md')
              .writeAsStringSync('# edited\n');
          commitAll(root, 'meanwhile');
        }),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.workingTreeDirty,
          ),
        ),
      );
      expect(await _dryRunPlanHash(root), isNot(hashBefore));

      expect(await _run(root, StringBuffer(), answers: ['y']), 0);

      final subjects = (git(root, ['log', '--format=%s']).stdout as String)
          .trim()
          .split('\n');
      expect(subjects, [
        _commit2Message,
        _commit1Message,
        'meanwhile',
        'legacy',
      ]);
      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);
  });

  test('commit 2 holds the agent files, a CLAUDE.md block appended', () async {
    final root = await _spacedFixture({...acmeLegacy, 'CLAUDE.md': '# Acme\n'});
    final out = StringBuffer();

    expect(await _run(root, out, answers: ['y']), 0);

    final names =
        (git(root, ['show', '--name-only', '--format=', 'HEAD']).stdout
                as String)
            .trim()
            .split('\n');
    expect(names, containsAll(['.specstone/AGENT.md', 'CLAUDE.md']));
    expect(names, isNot(contains('AGENTS.md')));
    final claude = File.fromUri(root.uri.resolve('CLAUDE.md'));
    expect(claude.readAsStringSync(), startsWith('# Acme\n'));
    expect(
      claude.readAsStringSync(),
      contains('<!-- BEGIN specstone v$specstoneVersion -->'),
    );
    expect(
      out.toString(),
      contains('  agent files: ${2 + skillFileCount} files\n'),
    );
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');

  group('the Claude Code settings file', () {
    const stale =
        '{"permissions":{"allow":["Bash(ls)"]},"hooks":{"PostToolUse":'
        '[{"matcher":"Write","hooks":[{"type":"command","command":'
        '"specstone","args":["hook","post-edit"]}]}]}}\n';

    Future<Directory> fixture(String settings) => gitFixture({
      '.specstone/config.yaml': shippedPinsConfig(),
      ...skillFileTexts(),
      settingsFilePath: settings,
    });

    test('a run whose only change is the hook merges it in commit 2 and '
        'keeps the Owner keys', () async {
      final root = await fixture(stale);
      final out = StringBuffer();

      expect(await _run(root, out, answers: ['y']), 0);

      final names =
          (git(root, ['show', '--name-only', '--format=', 'HEAD']).stdout
                  as String)
              .trim()
              .split('\n');
      expect(names, contains(settingsFilePath));
      expect(names, isNot(contains('.claude/skills/specstone-init/SKILL.md')));
      expect(names, contains('.specstone/config.yaml'));
      expect(
        File('${root.path}/.specstone/config.yaml').readAsStringSync(),
        '${shippedPinsConfig()}agent_files_version: $specstoneVersion\n',
      );
      final text = File('${root.path}/$settingsFilePath').readAsStringSync();
      expect(text, contains('"Bash(ls)"'));
      expect(text, isNot(contains('"matcher": "Write",')));
      expect(out.toString(), contains('  agent files: 1 files\n'));
      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
    }, skip: hasGit ? null : 'git is not available');

    test('a dry run writes no stamp and no file', () async {
      final root = await fixture(stale);

      expect(await _run(root, StringBuffer(), dryRun: true), 0);

      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
      expect(
        File('${root.path}/.specstone/config.yaml').readAsStringSync(),
        shippedPinsConfig(),
      );
    }, skip: hasGit ? null : 'git is not available');

    test('a malformed file refuses the dry run and the apply before any '
        'write', () async {
      final root = await fixture('{"hooks": []}');
      final commits = git(root, ['rev-list', '--count', 'HEAD']).stdout;
      Matcher fault() => throwsA(
        isA<MigrateFault>()
            .having((f) => f.code, 'code', MigrateFaultCode.agentBlockMalformed)
            .having((f) => f.file, 'file', settingsFilePath),
      );
      final dryOut = StringBuffer();

      await expectLater(() => _run(root, dryOut, dryRun: true), fault());
      await expectLater(
        () => _run(root, StringBuffer(), answers: ['y']),
        fault(),
      );

      expect(dryOut.toString(), isEmpty);
      expect(git(root, ['rev-list', '--count', 'HEAD']).stdout, commits);
      expect(
        File('${root.path}/$settingsFilePath').readAsStringSync(),
        '{"hooks": []}',
      );
    }, skip: hasGit ? null : 'git is not available');

    test('the dry run plan hash follows the settings bytes', () async {
      final root = await fixture(stale);
      final before = await _dryRunPlanHash(root);

      File('${root.path}/$settingsFilePath')
          .writeAsStringSync(stale.replaceFirst('Bash(ls)', 'Bash(pwd)'));
      commitAll(root, 'edit settings');

      expect(await _dryRunPlanHash(root), isNot(before));
    }, skip: hasGit ? null : 'git is not available');
  });

  test('a dry run from the folder holding the docs link plans code_root '
      'when the legacy paths resolve from there', () async {
    final tree = await writeTree(
      linkedAcme({
        legacyFrPath: implementingDoc('Validate credentials', ['lib/a.dart']),
        'code/lib/a.dart': 'class A {}\n',
        // Git for Windows may store a link as a file; the plan needs none.
        '.gitignore': 'code/docs\n',
      }),
    );
    if (!linkCodeDocs(tree)) return;
    commitRepo(Directory('${tree.path}/ws'));
    final code = Directory('${tree.path}/ws/code');
    locateSetupTrust(code, homeDirectory: testHome()).record();
    final out = StringBuffer();

    expect(await _run(code, out, dryRun: true), 0);

    expect(
      out.toString(),
      matches(
        RegExp(
          r'\n  \.specstone/config\.yaml: .*; code_root code \(1 of 2 paths\)\n',
        ),
      ),
    );
  }, skip: hasGit ? null : 'git is not available');

  test('a dry run over a journal that does not '
      'parse refuses as bare migrate does', () async {
    final root = await gitFixture(acmeLegacy);
    File('${root.path}/${MoveJournal.journalPath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{');
    recordJournalFile(root);

    Matcher refusal() => throwsA(
      isA<RenderFault>()
          .having((f) => f.code, 'code', RenderFaultCode.outputNotWritable)
          .having(
            (f) => f.message,
            'message',
            startsWith('cannot replay ${MoveJournal.journalPath}: '),
          ),
    );
    final dryOut = StringBuffer();
    await expectLater(() => _run(root, dryOut, dryRun: true), refusal());
    expect(dryOut.toString(), isEmpty);
    await expectLater(
      () => _run(root, StringBuffer(), answers: ['y']),
      refusal(),
    );
    expect(
      File('${root.path}/${MoveJournal.journalPath}').readAsStringSync(),
      '{',
    );
  }, skip: hasGit ? null : 'git is not available');

  test('a dry run prints plan <hash>, the hash of the plan text above '
      'it, before its last line', () async {
    final root = await gitFixture(acmeLegacy);
    final out = StringBuffer();

    expect(await _run(root, out, dryRun: true), 0);

    final text = out.toString();
    final lines = text.split('\n');
    expect(lines[lines.length - 2], 'dry run: nothing written');
    final planLine = lines[lines.length - 3];
    final plan = text.substring(0, text.lastIndexOf(planLine));
    expect(plan, startsWith('legacy migration: '));
    final inputs = planLegacyRun(
      root,
      templates: TemplateResolver(),
      homeDirectory: testHome(),
    ).inputs;
    expect(planLine, 'plan ${planHashOf(plan, inputs)}');
  }, skip: hasGit ? null : 'git is not available');

  group('a dry run on a dirty tree', () {
    const dirtyLine =
        'dry run: nothing written; the run needs a clean working tree';

    test('prints the plan, its hash line, and the dirty-tree line, exits 0, '
        'and writes nothing', () async {
      final root = await gitFixture(acmeLegacy);
      File('${root.path}/notes.txt').writeAsStringSync('x\n');
      final before = _bytesUnder(root);
      final head = headOf(root);
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      final lines = out.toString().split('\n');
      expect(out.toString(), startsWith('legacy migration: '));
      expect(lines[lines.length - 2], dirtyLine);
      expect(lines[lines.length - 3], matches(RegExp(r'^plan [0-9a-f]{12}$')));
      expect(_bytesUnder(root), before);
      expect(headOf(root), head);
    }, skip: hasGit ? null : 'git is not available');

    test('hashes the files as they are, edits not yet committed '
        'included', () async {
      final root = await gitFixture(acmeLegacy);
      final clean = await _dryRunPlanHash(root);
      File('${root.path}/docs/prds/d01_context.md')
          .writeAsStringSync('edited\n');
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      final text = out.toString();
      final planLine = 'plan ${_planHashIn(text)}\n';
      final plan = text.substring(0, text.lastIndexOf(planLine));
      final inputs = planLegacyRun(
        root,
        templates: TemplateResolver(),
        homeDirectory: testHome(),
      ).inputs;
      expect(_planHashIn(text), planHashOf(plan, inputs));
      expect(_planHashIn(text), isNot(clean));
    }, skip: hasGit ? null : 'git is not available');

    test('a clean tree prints the plain last line', () async {
      final root = await gitFixture(acmeLegacy);
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      expect(out.toString(), endsWith('\ndry run: nothing written\n'));
      expect(out.toString(), isNot(contains('clean working tree')));
    }, skip: hasGit ? null : 'git is not available');

    test('--plan with its hash is still working_tree_dirty and writes '
        'nothing', () async {
      final root = await gitFixture(acmeLegacy);
      File('${root.path}/notes.txt').writeAsStringSync('x\n');
      final hash = await _dryRunPlanHash(root);
      final before = _bytesUnder(root);
      final head = headOf(root);

      await expectLater(
        () => _run(
          root,
          StringBuffer(),
          confirmation: OwnerConfirmation.given,
          planHash: hash,
        ),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.workingTreeDirty,
          ),
        ),
      );
      expect(_bytesUnder(root), before);
      expect(headOf(root), head);
    }, skip: hasGit ? null : 'git is not available');

    test('outside a git work tree is still git_work_tree_required', () async {
      final root = await writeTree(acmeLegacy);
      final out = StringBuffer();

      await expectLater(
        () => _run(root, out, dryRun: true),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.gitWorkTreeRequired,
          ),
        ),
      );
      expect(out.toString(), isEmpty);
    }, skip: hasGit ? null : 'git is not available');

    test('bare migrate outside a git work tree prints no plan and writes no '
        'file', () async {
      final root = await writeTree(acmeLegacy);
      final before = treeBytes(root);
      final out = StringBuffer();

      await expectLater(
        () => _run(root, out, answers: ['y']),
        throwsA(
          isA<MigrateFault>()
              .having(
                (f) => f.code,
                'code',
                MigrateFaultCode.gitWorkTreeRequired,
              )
              .having((f) => f.exitStatus, 'exit', 78),
        ),
      );

      expect(out.toString(), isEmpty);
      expect(treeBytes(root), before);
    }, skip: hasGit ? null : 'git is not available');

    test('--yes with a stale plan hash is working_tree_dirty on a dirty tree '
        'and git_work_tree_required outside git, before any hash '
        'check', () async {
      final dirty = await gitFixture(acmeLegacy);
      File('${dirty.path}/notes.txt').writeAsStringSync('x\n');
      final outside = await writeTree(acmeLegacy);

      for (final (root, code) in [
        (dirty, MigrateFaultCode.workingTreeDirty),
        (outside, MigrateFaultCode.gitWorkTreeRequired),
      ]) {
        final before = treeBytes(root);
        final out = StringBuffer();

        await expectLater(
          () => _run(
            root,
            out,
            confirmation: OwnerConfirmation.given,
            planHash: '000000000000',
          ),
          throwsA(isA<MigrateFault>().having((f) => f.code, 'code', code)),
          reason: '$code',
        );

        expect(out.toString(), isEmpty, reason: '$code');
        expect(treeBytes(root), before, reason: '$code');
      }
    }, skip: hasGit ? null : 'git is not available');
  });

  test('a committed edit to a doc between '
      'the dry run and --yes changes the plan hash, so --yes refuses '
      'plan_mismatch and writes nothing', () async {
    final root = await gitFixture(acmeLegacy);
    final hash = await _dryRunPlanHash(root);
    File('${root.path}/docs/prds/d01_context.md').writeAsStringSync('later\n');
    commitAll(root, 'edit a doc');
    final legacy = _bytesUnder(root);
    final head = headOf(root);

    await expectLater(
      () => _run(
        root,
        StringBuffer(),
        confirmation: OwnerConfirmation.given,
        planHash: hash,
      ),
      throwsA(
        isA<MigrateFault>().having(
          (f) => f.code,
          'code',
          MigrateFaultCode.planMismatch,
        ),
      ),
    );
    expect(_bytesUnder(root), legacy);
    expect(headOf(root), head);
  }, skip: hasGit ? null : 'git is not available');

  test('a commit that touches no input '
      'between the dry run and --yes leaves the plan hash, so --yes '
      'applies', () async {
    final root = await gitFixture(acmeLegacy);
    final hash = await _dryRunPlanHash(root);
    File('${root.path}/notes.txt').writeAsStringSync('later\n');
    commitAll(root, 'unrelated');

    expect(
      await _run(
        root,
        StringBuffer(),
        confirmation: OwnerConfirmation.given,
        planHash: hash,
      ),
      0,
    );

    expect(MoveJournal.pending(root), isFalse);
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');

  test("--yes with the dry run's plan hash applies the plan with no "
      "prompt, as the Owner's y does", () async {
    final root = await gitFixture(acmeLegacy);
    final hash = await _dryRunPlanHash(root);
    final out = StringBuffer();

    final status = await runMigrate(
      MigrateRequest(
        workingDirectory: root,
        homeDirectory: testHome(),
        templates: TemplateResolver(),
        dryRun: false,
        confirmation: OwnerConfirmation.given,
        planHash: hash,
        readLine: () => throw StateError('--yes must not ask'),
        out: out,
      ),
    );

    expect(status, 0);
    expect(out.toString(), startsWith('legacy migration: '));
    expect(out.toString(), isNot(contains('apply? [y/N] ')));
    final subjects = (git(root, ['log', '--format=%s']).stdout as String)
        .trim()
        .split('\n');
    expect(subjects, [_commit2Message, _commit1Message, 'legacy']);
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');

  for (final (label, planHash) in [
    ('a plan changed since the dry run', '000000000000'),
    ('no plan hash', null),
  ]) {
    test('--yes with $label prints the plan, refuses plan_mismatch, '
        'exit 75, and writes nothing', () async {
      final root = await gitFixture(acmeLegacy);
      final legacy = _bytesUnder(root);
      final head = headOf(root);
      final out = StringBuffer();

      await expectLater(
        () => _run(
          root,
          out,
          confirmation: OwnerConfirmation.given,
          planHash: planHash,
        ),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.planMismatch)
              .having((f) => f.exitStatus, 'exit', 75)
              .having(
                (f) => f.message,
                'message',
                'the plan is not the one the Owner saw in the dry run; run '
                    'specstone migrate --dry-run again, show it, and ask for '
                    'a new ok',
              ),
        ),
      );
      expect(out.toString(), startsWith('legacy migration: '));
      expect(_bytesUnder(root), legacy);
      expect(headOf(root), head);
    }, skip: hasGit ? null : 'git is not available');
  }

  test('no interactive terminal prints the '
      'plan, then refuses owner_terminal_required, exit 77', () async {
    final root = await gitFixture(acmeLegacy);
    final legacy = _bytesUnder(root);
    final out = StringBuffer();

    await expectLater(
      () => _run(root, out, confirmation: OwnerConfirmation.missing),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.ownerTerminalRequired)
            .having((f) => f.exitStatus, 'exit', 77)
            .having(
              (f) => f.message,
              'message',
              'migrate applies only at an interactive terminal, or with '
                  "--yes after the Owner's ok in the chat",
            ),
      ),
    );
    expect(out.toString(), startsWith('legacy migration: '));
    expect(out.toString(), endsWith('specs/f01_login/DOMAIN.md\n'));
    expect(_bytesUnder(root), legacy);
  }, skip: hasGit ? null : 'git is not available');

  test('a plan refusal in bare migrate comes after the git '
      'checks', () async {
    const duplicateWithContext = {
      ...duplicateGroupLegacy,
      'docs/prds/d01_context.md': '# D-01 — Context\n',
    };
    final clean = await gitFixture(duplicateWithContext);
    final out = StringBuffer();

    await expectLater(
      () => _run(clean, out),
      throwsA(
        isA<MigrateFault>().having(
          (f) => f.code,
          'code',
          MigrateFaultCode.groupSlugDuplicate,
        ),
      ),
    );
    expect(out.toString(), isEmpty);

    final dirty = await gitFixture(duplicateWithContext);
    File.fromUri(dirty.uri.resolve('notes.txt')).writeAsStringSync('x\n');
    final dirtyOut = StringBuffer();

    await expectLater(
      () => _run(dirty, dirtyOut),
      throwsA(
        isA<MigrateFault>().having(
          (f) => f.code,
          'code',
          MigrateFaultCode.workingTreeDirty,
        ),
      ),
    );
    expect(dirtyOut.toString(), isEmpty);
  }, skip: hasGit ? null : 'git is not available');

  test(
    'bare migrate over two groups that share a slug writes nothing',
    () async {
      final root = await gitFixture({
        ...duplicateGroupLegacy,
        'docs/prds/d01_context.md': '# D-01 — Context\n',
      });
      final before = _bytesUnder(root);
      final head = headOf(root);
      final out = StringBuffer();

      await expectLater(
        () => _run(root, out, answers: ['y']),
        throwsA(
          isA<MigrateFault>()
              .having(
                (f) => f.code,
                'code',
                MigrateFaultCode.groupSlugDuplicate,
              )
              .having((f) => f.exitStatus, 'exit', 65),
        ),
      );

      expect(out.toString(), isEmpty);
      expect(_bytesUnder(root), before);
      expect(headOf(root), head);
      expect(MoveJournal.pending(root), isFalse);
    },
    skip: hasGit ? null : 'git is not available',
  );

  test('two moves onto one path, and a move cycle, refuse legacy_collision in '
      'the dry run and in bare migrate, with nothing printed or '
      'written', () async {
    const cycleIndex = '''
## Spec map

| Code path | Spec path | feature_id |
|-----------|-----------|------------|
| `c/` | `specs/f01_alpha/q/` | `f02_beta` |
| `c/` | `specs/z/` | `f02_beta` |
| `c/` | `specs/f02_beta/q/` | `f01_alpha` |
| `c/` | `specs/y/` | `f01_alpha` |
''';
    const context = {'docs/prds/d01_context.md': '# D-01 — Context\n'};
    final trees = {
      'two moves onto one path': {
        ...context,
        'docs/prds/features/co01_utilities/co01_01_slot/FEATURE.md': '# A\n',
        'docs/prds/features/co01_utilities/ai01_slot/FEATURE.md': '# B\n',
      },
      'a move cycle': {
        ...context,
        'docs/prds/features/f01_alpha/FEATURE.md': '# F-01 — Alpha\n',
        'docs/prds/features/f02_beta/FEATURE.md': '# F-02 — Beta\n',
        'docs/specs/INDEX.md': cycleIndex,
        for (final folder in ['f01_alpha/q', 'z', 'f02_beta/q', 'y'])
          'docs/specs/$folder/s02_api_n.md': '# S\n',
      },
    };

    for (final MapEntry(key: reason, value: files) in trees.entries) {
      for (final dryRun in [true, false]) {
        final root = await gitFixture(files);
        final before = _bytesUnder(root);
        final out = StringBuffer();

        await expectLater(
          () => _run(root, out, dryRun: dryRun, answers: ['y']),
          throwsA(
            isA<MigrateFault>()
                .having((f) => f.code, 'code', MigrateFaultCode.legacyCollision)
                .having((f) => f.exitStatus, 'exit', 65),
          ),
          reason: '$reason, dry run $dryRun',
        );

        expect(out.toString(), isEmpty, reason: '$reason, dry run $dryRun');
        expect(_bytesUnder(root), before, reason: '$reason, dry run $dryRun');
      }
    }
  }, skip: hasGit ? null : 'git is not available');

  test('a dangling override and an upgrade collision refuse in the dry run '
      'and in bare migrate, with nothing printed or written', () async {
    final dangling = await gitFixture({
      '.specstone/config.yaml': _belowSince,
      '.specstone/templates/ghost.yaml':
          'id: ghost\nsections:\n  - {id: body, header: Body}\n',
    });
    final (:project, :home) = await _upgradeFixture();
    File('${project.path}/docs/prds/runbooks/deploy/RUNBOOK.md')
        .writeAsStringSync(
          '# Deploy\n\n## Steps\n\nRun it.\n\n'
          '## Procedure\n\nHeld.\n',
        );
    commitAll(project, 'collide');
    final cases = [
      (root: dangling, home: null, code: MigrateFaultCode.overrideDangling),
      (root: project, home: home, code: MigrateFaultCode.upgradeCollision),
    ];

    for (final (:root, :home, :code) in cases) {
      for (final dryRun in [true, false]) {
        final before = _bytesUnder(root);
        final out = StringBuffer();

        await expectLater(
          () => _run(root, out, home: home, dryRun: dryRun, answers: ['y']),
          throwsA(isA<MigrateFault>().having((f) => f.code, 'code', code)),
          reason: '$code, dry run $dryRun',
        );

        expect(out.toString(), isEmpty, reason: '$code, dry run $dryRun');
        expect(_bytesUnder(root), before, reason: '$code, dry run $dryRun');
      }
    }
  }, skip: hasGit ? null : 'git is not available');

  test('a legacy collision refuses in --dry-run and bare '
      'migrate before any plan line prints', () async {
    final root = await gitFixture({
      ...acmeLegacy,
      'docs/prds/FEATURES.md': '# Features\n',
    });
    final before = _bytesUnder(root);
    Matcher refusal() => throwsA(
      isA<MigrateFault>().having(
        (f) => f.code,
        'code',
        MigrateFaultCode.legacyCollision,
      ),
    );
    final dryOut = StringBuffer();
    final out = StringBuffer();

    await expectLater(() => _run(root, dryOut, dryRun: true), refusal());
    await expectLater(() => _run(root, out, answers: ['y']), refusal());

    expect(dryOut.toString(), isEmpty);
    expect(out.toString(), isEmpty);
    expect(_bytesUnder(root), before);
  }, skip: hasGit ? null : 'git is not available');

  test('a plan that moves no file journals one commit', () {
    final plan = RunPlan(
      header: 'legacy migration: x',
      moves: [],
      prunes: [],
      rewrites: [],
      creates: [],
      left: [],
      commit1Message: _commit1Message,
      commit2Message: _commit2Message,
      inputs: PlanInputs(Directory.systemTemp),
    );

    final steps = plan.journalSteps(
      base: 'abc',
      projectRoot: Directory.systemTemp,
    );

    expect(steps.whereType<CommitStep>(), hasLength(1));
    expect(steps.whereType<CommitStep>().single.message, _commit2Message);
  });

  test('a root whose path holds a space migrates; '
      'migrate after an applied run prints nothing to '
      'migrate', () async {
    final root = await _spacedFixture(acmeLegacy);
    final out = StringBuffer();

    expect(await _run(root, out, answers: ['y']), 0);
    expect(
      (git(root, ['rev-list', '--count', 'HEAD']).stdout as String).trim(),
      '3',
    );

    final again = StringBuffer();
    expect(await _run(root, again), 0);
    expect(again.toString(), 'nothing to migrate\n');
  }, skip: hasGit ? null : 'git is not available');

  test('a git-ignored file in a moved '
      'cross-cutting folder moves on disk and stays out of both '
      'commits', () async {
    final root = await gitFixture({...acmeLegacy, '.gitignore': '.DS_Store\n'});
    File('${root.path}/docs/specs/shared/.DS_Store')
        .writeAsStringSync('finder\n');
    final out = StringBuffer();

    expect(await _run(root, out, answers: ['y']), 0);

    final subjects = (git(root, ['log', '--format=%s']).stdout as String)
        .trim()
        .split('\n');
    expect(subjects, [_commit2Message, _commit1Message, 'legacy']);
    expect(
      File('${root.path}/docs/specs/topics/shared/.DS_Store')
          .readAsStringSync(),
      'finder\n',
    );
    final committed =
        git(root, ['log', '--name-only', '--format=', 'HEAD~2..HEAD']).stdout
            as String;
    expect(committed, isNot(contains('.DS_Store')));
    expect(MoveJournal.pending(root), isFalse);
  }, skip: hasGit ? null : 'git is not available');

  group('resume and replay', () {
    final skipGit = hasGit ? null : 'git is not available';

    test(
      'a stopped migrate whose journal writes the CLAUDE.md of the repository '
      'top above the project refuses and leaves the file',
      () async {
        final base = await gitFixture({
          'CLAUDE.md': 'Owner\n',
          'specs/.specstone/config.yaml': shippedPinsConfig(),
          'specs/docs/prds/PROJECT.md': '# Project\n',
        });
        final project = Directory('${base.path}/specs');
        final head = (git(base, ['rev-parse', 'HEAD']).stdout as String).trim();
        writeJournal(
          project,
          [
            WriteStep(
              '../CLAUDE.md',
              'Owner\nblock\n',
              before: textHashOf('Owner\n'),
            ),
            CommitStep(message: 'agent files', paths: const [], base: head),
          ],
          agentFiles: {'${base.resolveSymbolicLinksSync()}/CLAUDE.md'},
        );

        await expectLater(
          () => runMigrate(
            MigrateRequest(
              workingDirectory: project,
              homeDirectory: testHome(),
              templates: TemplateResolver(),
              dryRun: false,
              confirmation: OwnerConfirmation.prompt,
              readLine: () => throw StateError('resume must not ask'),
              out: StringBuffer(),
            ),
          ),
          throwsA(
            isA<RenderFault>()
                .having(
                  (f) => f.code,
                  'code',
                  RenderFaultCode.outputNotWritable,
                )
                .having((f) => f.exitStatus, 'exit', 73)
                .having((f) => f.file, 'file', MoveJournal.journalPath),
          ),
        );

        expect(File('${base.path}/CLAUDE.md').readAsStringSync(), 'Owner\n');
        expect(MoveJournal.pending(project), isTrue);
      },
      skip: skipGit,
    );

    test('a '
        'stopped migrate replays the CLAUDE.md of the project it wrote, whose '
        'real path is recorded', () async {
      final base = await gitFixture({
        'CLAUDE.md': 'Owner\n',
        '.specstone/config.yaml': shippedPinsConfig(),
        'docs/prds/PROJECT.md': '# Project\n',
      });
      final head = (git(base, ['rev-parse', 'HEAD']).stdout as String).trim();
      writeJournal(
        base,
        [
          WriteStep(
            'CLAUDE.md',
            'Owner\nblock\n',
            before: textHashOf('Owner\n'),
          ),
          CommitStep(message: 'agent files', paths: const [], base: head),
        ],
        agentFiles: {'${base.resolveSymbolicLinksSync()}/CLAUDE.md'},
      );

      final status = await runMigrate(
        MigrateRequest(
          workingDirectory: base,
          homeDirectory: testHome(),
          templates: TemplateResolver(),
          dryRun: false,
          confirmation: OwnerConfirmation.prompt,
          readLine: () => throw StateError('resume must not ask'),
          out: StringBuffer(),
        ),
      );

      expect(status, 0);
      expect(
        File('${base.path}/CLAUDE.md').readAsStringSync(),
        'Owner\nblock\n',
      );
      expect(MoveJournal.pending(base), isFalse);
    }, skip: skipGit);

    test('a '
        'migrate stopped at commit 2 resumes the agent file it wrote at the '
        "top of a repository nested in the project's code root", () async {
      final base = await _twoRepositories({
        'proj/.specstone/config.yaml':
            '${shippedPinsConfig()}code_root: mono/services/api\n',
        'proj/.gitignore': 'mono/\n',
        'proj/mono/services/api/main.dart': 'void main() {}\n',
      }, other: 'proj/mono');
      final project = Directory('${base.path}/proj');
      final hook = File('${project.path}/.git/hooks/pre-commit')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho "lint failed" >&2\nexit 1\n');
      expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);
      final topFile = File('${project.path}/mono/AGENTS.md');

      await expectLater(
        () => _run(project, StringBuffer(), answers: ['y']),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.gitFailed,
          ),
        ),
      );
      expect(
        topFile.readAsStringSync(),
        inlineBlock(cliVersion: specstoneVersion),
      );
      expect(MoveJournal.pending(project), isTrue);

      hook.deleteSync();
      expect(await _run(project, StringBuffer()), 0);

      expect(MoveJournal.pending(project), isFalse);
      expect(
        topFile.readAsStringSync(),
        inlineBlock(cliVersion: specstoneVersion),
      );
      expect(
        File('${project.path}/.specstone/config.yaml').readAsStringSync(),
        contains('agent_file_roots:\n  - mono\n'),
      );
      expect(git(project, ['status', '--porcelain']).stdout, isEmpty);
    }, skip: Platform.isWindows ? 'the hook is a sh script' : skipGit);

    test(
      'a migrate whose code root sits in a repository outside the project '
      'plans and writes no agent file there, names it, and finishes',
      () async {
        final base = await _twoRepositories({
          'proj/.specstone/config.yaml':
              '${_belowSince}code_root: ../mono/services/api\n',
          'mono/services/api/main.dart': 'void main() {}\n',
        }, other: 'mono');
        final project = Directory('${base.path}/proj');
        final topFile = File('${base.path}/mono/AGENTS.md');
        final dryOut = StringBuffer();
        final dryWarnings = <String>[];
        final out = StringBuffer();
        final warnings = <String>[];
        const skipLines = [
          '../mono/AGENTS.md reaches outside the project root; left as it is',
          '../mono reaches outside the project root; left as it is',
        ];

        expect(
          await _run(project, dryOut, dryRun: true, warnings: dryWarnings),
          0,
        );
        expect(await _run(project, out, answers: ['y'], warnings: warnings), 0);

        expect(dryOut.toString(), isNot(contains('mono')));
        expect(out.toString(), isNot(contains('mono/AGENTS.md')));
        expect(dryWarnings, skipLines);
        expect(warnings, skipLines);
        expect(topFile.existsSync(), isFalse);
        expect(
          File('${project.path}/.specstone/config.yaml').readAsStringSync(),
          isNot(contains('agent_file_roots')),
        );
        expect(MoveJournal.pending(project), isFalse);
      },
      skip: skipGit,
    );

    test('a '
        'legacy migrate stopped at commit 1, before its config exists, '
        'resumes and still writes no agent file at the top of a repository '
        'outside the project', () async {
      final base = await _twoRepositories(
        {
          for (final MapEntry(:key, :value) in acmeLegacy.entries)
            'proj/$key': value,
          'proj/$legacyFrPath': implementingDoc('Validate credentials', [
            'lib/a.dart',
          ]),
          'app/lib/a.dart': 'class A {}\n',
        },
        other: 'app',
        links: {'app/docs': '../proj/docs'},
      );
      final project = Directory('${base.path}/proj');
      final app = Directory('${base.path}/app');
      locateSetupTrust(app, homeDirectory: testHome()).record();
      final hook = File('${project.path}/.git/hooks/pre-commit')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho "lint failed" >&2\nexit 1\n');
      expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);
      final warnings = <String>[];

      await expectLater(
        () => _run(app, StringBuffer(), answers: ['y'], warnings: warnings),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.gitFailed,
          ),
        ),
      );
      expect(
        File('${project.path}/.specstone/config.yaml').existsSync(),
        isFalse,
      );

      hook.deleteSync();
      expect(await _run(app, StringBuffer()), 0);

      expect(MoveJournal.pending(project), isFalse);
      expect(warnings, [
        '../app/AGENTS.md reaches outside the project root; left as it is',
        '../app reaches outside the project root; left as it is',
      ]);
      expect(File('${app.path}/AGENTS.md').existsSync(), isFalse);
      expect(
        File('${project.path}/.specstone/config.yaml').readAsStringSync(),
        contains('code_root: ../app\n'),
      );
    }, skip: Platform.isWindows ? 'symbolic links need a privilege' : skipGit);

    group('a root '
        'AGENTS.md that is a link', () {
      test(
        'to the AGENTS.md of a top outside the project is named and '
        'left, and the run finishes with no agent write',
        () async {
          final base = await _twoRepositories(
            {
              'proj/.specstone/config.yaml':
                  '${_belowSince}code_root: ../app\n',
              'app/AGENTS.md':
                  'Owner\n<!-- BEGIN specstone v0.0.1 -->\nold rules\n'
                  '<!-- END specstone -->\n',
            },
            other: 'app',
            links: {'proj/AGENTS.md': '../app/AGENTS.md'},
          );
          final project = Directory('${base.path}/proj');
          final before = File('${base.path}/app/AGENTS.md').readAsStringSync();
          final out = StringBuffer();
          final warnings = <String>[];

          final status = await _run(
            project,
            out,
            answers: ['y'],
            warnings: warnings,
          );

          expect(status, 0);
          expect(warnings, [
            'AGENTS.md reaches outside the project root; left as it is',
            '../app reaches outside the project root; left as it is',
          ]);
          expect(File('${base.path}/app/AGENTS.md').readAsStringSync(), before);
          expect(
            Link('${project.path}/AGENTS.md').targetSync(),
            '../app/AGENTS.md',
          );
          expect(MoveJournal.pending(project), isFalse);
        },
        skip: Platform.isWindows ? 'symbolic links need a privilege' : skipGit,
      );

      test(
        'a root CLAUDE.md linked to a file outside the project is '
        'named and left, and the journal clears',
        () async {
          final base = await _twoRepositories(
            {
              'proj/.specstone/config.yaml': _belowSince,
              'shared/CLAUDE.md': 'Shared\n',
            },
            other: 'shared',
            links: {'proj/CLAUDE.md': '../shared/CLAUDE.md'},
          );
          final project = Directory('${base.path}/proj');
          final out = StringBuffer();
          final warnings = <String>[];

          expect(
            await _run(project, out, answers: ['y'], warnings: warnings),
            0,
          );

          expect(warnings, [
            'CLAUDE.md reaches outside the project root; left as it is',
          ]);
          expect(
            File('${base.path}/shared/CLAUDE.md').readAsStringSync(),
            'Shared\n',
          );
          expect(
            Link('${project.path}/CLAUDE.md').targetSync(),
            '../shared/CLAUDE.md',
          );
          expect(MoveJournal.pending(project), isFalse);
        },
        skip: Platform.isWindows ? 'symbolic links need a privilege' : skipGit,
      );

      test('a linked .specstone/AGENT.md leading outside the project is '
          'named and left, and the file outside keeps its bytes', () async {
        final base = await _twoRepositories(
          {
            'proj/.specstone/config.yaml': _belowSince,
            'victim.txt': 'mine\n',
            'shared/keep.txt': '',
          },
          other: 'shared',
          links: {'proj/.specstone/AGENT.md': '../../victim.txt'},
        );
        final project = Directory('${base.path}/proj');
        final warnings = <String>[];

        expect(
          await _run(
            project,
            StringBuffer(),
            answers: ['y'],
            warnings: warnings,
          ),
          0,
        );

        expect(warnings, [
          '.specstone/AGENT.md reaches outside the project root; left as it is',
        ]);
        expect(File('${base.path}/victim.txt').readAsStringSync(), 'mine\n');
        expect(MoveJournal.pending(project), isFalse);
      }, skip: Platform.isWindows ? 'links need a privilege' : skipGit);

      test(
        'a CLAUDE.md linked into .git is named and left, and '
        '.git/config keeps its bytes',
        () async {
          final base = await _twoRepositories(
            {'proj/.specstone/config.yaml': _belowSince, 'shared/keep.txt': ''},
            other: 'shared',
            links: {'proj/CLAUDE.md': '.git/config'},
          );
          final project = Directory('${base.path}/proj');
          final config = File('${project.path}/.git/config');
          final before = config.readAsStringSync();
          final warnings = <String>[];

          expect(
            await _run(
              project,
              StringBuffer(),
              answers: ['y'],
              warnings: warnings,
            ),
            0,
          );

          expect(warnings, ['CLAUDE.md lies under .git; left as it is']);
          expect(config.readAsStringSync(), before);
          expect(MoveJournal.pending(project), isFalse);
        },
        skip: Platform.isWindows ? 'symbolic links need a privilege' : skipGit,
      );

      test(
        'to the CLAUDE.md of the project takes one block and the '
        'link stays',
        () async {
          final base = await _twoRepositories(
            {
              'proj/.specstone/config.yaml': shippedPinsConfig(),
              'proj/CLAUDE.md':
                  'Owner\n<!-- BEGIN specstone v0.0.1 -->\nold rules\n'
                  '<!-- END specstone -->\n',
              'app/.keep': '',
            },
            other: 'app',
            links: {'proj/AGENTS.md': 'CLAUDE.md'},
          );
          final project = Directory('${base.path}/proj');
          final out = StringBuffer();
          final warnings = <String>[];

          expect(
            await _run(project, out, answers: ['y'], warnings: warnings),
            0,
          );

          expect(warnings, isEmpty);
          expect(
            File('${project.path}/CLAUDE.md').readAsStringSync(),
            'Owner\n${inlineBlock(cliVersion: specstoneVersion)}',
          );
          expect(Link('${project.path}/AGENTS.md').targetSync(), 'CLAUDE.md');
          expect(MoveJournal.pending(project), isFalse);
        },
        skip: Platform.isWindows ? 'symbolic links need a privilege' : skipGit,
      );
    });

    test('a run stopped after commit 1 finishes with no second y', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      expect(hasDoc(root, 'prds/d01_context.md'), isFalse);
      expect(File('${root.path}/.specstone/config.yaml').existsSync(), isFalse);
      final out = StringBuffer();

      final status = await runMigrate(
        MigrateRequest(
          workingDirectory: root,
          homeDirectory: testHome(),
          templates: TemplateResolver(),
          dryRun: false,
          confirmation: OwnerConfirmation.prompt,
          readLine: () => throw StateError('resume must not ask'),
          out: out,
        ),
      );

      expect(status, 0);
      final subjects = (git(root, ['log', '--format=%s']).stdout as String)
          .trim()
          .split('\n');
      expect(subjects, [_commit2Message, _commit1Message, 'legacy']);
      expect(MoveJournal.pending(root), isFalse);
      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
      final lines = out.toString().trim().split('\n');
      expect(lines[lines.length - 3], matches(r'^commit 1 [0-9a-f]{7,}: .*$'));
      expect(lines[lines.length - 3], endsWith(_commit1Message));
      expect(lines[lines.length - 2], matches(r'^commit 2 [0-9a-f]{7,}: .*$'));
      expect(lines[lines.length - 2], endsWith(_commit2Message));
      expect(
        lines.last,
        matches(r'^check: \d+ findings left; run specstone check to see them$'),
      );
      expect(
        out.toString(),
        startsWith('pending migration: ${root.resolveSymbolicLinksSync()} '),
      );
    }, skip: skipGit);

    test('a resumed '
        'migrate leaves an edited doc and an edited CLAUDE.md as they are and '
        'finishes the rest', () async {
      final root = await gitFixture({...acmeLegacy, 'CLAUDE.md': '# Acme\n'});
      _stopAfterCommit1(root);
      final journal = jsonDecode(
        File('${root.path}/${MoveJournal.journalPath}').readAsStringSync(),
      ) as Map<String, Object?>;
      final writes = [
        for (final step in journal['steps']! as List<Object?>)
          if ((step! as Map<String, Object?>)['write']
              case final Map<String, Object?> write)
            write['path']! as String,
      ];
      final doc = writes.firstWhere((path) => path.startsWith('docs/'));
      expect(writes, contains('CLAUDE.md'));
      final edits = <String, String>{};
      for (final path in [doc, 'CLAUDE.md']) {
        final file = File('${root.path}/$path');
        file.writeAsStringSync('${file.readAsStringSync()}\nuser edit\n');
        edits[path] = file.readAsStringSync();
      }

      expect(await _run(root, StringBuffer()), 0);

      for (final MapEntry(:key, :value) in edits.entries) {
        expect(File('${root.path}/$key').readAsStringSync(), value);
      }
      expect(MoveJournal.pending(root), isFalse);
      expect(File('${root.path}/.specstone/config.yaml').existsSync(), isTrue);
    }, skip: skipGit);

    test('--dry-run lists the remaining steps and writes '
        'nothing', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final head = headOf(root);
      final journal = File('${root.path}/${MoveJournal.journalPath}')
          .readAsStringSync();
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      final lines = out.toString().trim().split('\n');
      expect(
        lines.first,
        'pending migration: ${root.resolveSymbolicLinksSync()} '
        '(.specstone/trash/journal.json)',
      );
      expect(lines[1], 'remaining steps:');
      expect(lines, contains('  write docs/prds/PROJECT.md'));
      expect(lines.last, 'dry run: nothing written');
      expect(headOf(root), head);
      expect(
        File('${root.path}/${MoveJournal.journalPath}').readAsStringSync(),
        journal,
      );
    }, skip: skipGit);

    test('bare migrate with no terminal lists the '
        'remaining steps and exits 77', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final head = headOf(root);
      final out = StringBuffer();

      await expectLater(
        () => _run(root, out, confirmation: OwnerConfirmation.missing),
        throwsA(
          isA<WriteFault>()
              .having(
                (f) => f.code,
                'code',
                WriteFaultCode.ownerTerminalRequired,
              )
              .having((f) => f.exitStatus, 'exit', 77),
        ),
      );
      expect(out.toString(), contains('remaining steps:\n'));
      expect(out.toString(), contains('  write docs/prds/PROJECT.md\n'));
      expect(headOf(root), head);
      expect(MoveJournal.pending(root), isTrue);
    }, skip: skipGit);

    test("--yes with the dry run's plan hash finishes the stopped "
        'run with no terminal', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final hash = await _dryRunPlanHash(root);
      final out = StringBuffer();

      expect(
        await _run(
          root,
          out,
          confirmation: OwnerConfirmation.given,
          planHash: hash,
        ),
        0,
      );
      expect(out.toString(), contains('remaining steps:\n'));
      expect(MoveJournal.pending(root), isFalse);
      final subjects = (git(root, ['log', '--format=%s']).stdout as String)
          .trim()
          .split('\n');
      expect(subjects.first, _commit2Message);
    }, skip: skipGit);

    test('a resume plan hash survives a new commit and '
        'changes with the cursor file', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final cursor = File('${root.path}/${MoveJournal.cursorPath}')
        ..writeAsStringSync('0');
      final hash = await _dryRunPlanHash(root);

      expect(
        git(root, [
          'commit',
          '-q',
          '--allow-empty',
          '-m',
          'meanwhile',
        ]).exitCode,
        0,
      );
      expect(await _dryRunPlanHash(root), hash);

      cursor.writeAsStringSync('00');
      expect(await _dryRunPlanHash(root), isNot(hash));
    }, skip: skipGit);

    test('--yes with a stale plan hash leaves the stopped run '
        'pending, plan_mismatch', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final head = headOf(root);
      final out = StringBuffer();

      await expectLater(
        () => _run(
          root,
          out,
          confirmation: OwnerConfirmation.given,
          planHash: '000000000000',
        ),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.planMismatch,
          ),
        ),
      );
      expect(out.toString(), contains('remaining steps:\n'));
      expect(headOf(root), head);
      expect(MoveJournal.pending(root), isTrue);
    }, skip: skipGit);

    test('a pending journal is replayed, then the '
        'clean-tree check runs', () async {
      final files = {
        '.specstone/config.yaml': shippedPinsConfig(),
        'docs/prds/a.md': 'x\n',
      };
      final root = await gitFixture(files);
      writeJournal(root, [const MoveStep('docs/prds/a.md', 'docs/prds/b.md')]);

      await expectLater(
        () => _run(root, StringBuffer()),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.workingTreeDirty,
          ),
        ),
      );
      expect(hasDoc(root, 'prds/a.md'), isFalse);
      expect(hasDoc(root, 'prds/b.md'), isTrue);

      // A real project ignores `trash/`, so the journal leaves the tree clean.
      final dry = await gitFixture({
        ...files,
        '.specstone/.gitignore': '${specstoneGitignoreLines.join('\n')}\n',
      });
      writeJournal(dry, [const MoveStep('docs/prds/a.md', 'docs/prds/b.md')]);
      final journal = File('${dry.path}/.specstone/trash/journal.json');
      final journalBytes = journal.readAsBytesSync();
      final out = StringBuffer();

      await expectLater(
        () => _run(dry, out, dryRun: true),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.workingTreeDirty)
              .having(
                (f) => f.message,
                'message',
                allOf(
                  contains(MoveJournal.journalPath),
                  contains('run specstone migrate to finish the move'),
                  contains('plan again'),
                ),
              ),
        ),
      );

      expect(out.toString(), isEmpty);
      expect(journal.readAsBytesSync(), journalBytes);
      expect(hasDoc(dry, 'prds/a.md'), isTrue);
      expect(hasDoc(dry, 'prds/b.md'), isFalse);
    }, skip: skipGit);

    test('a commit a hook refuses stops the run, and the '
        'next migrate resumes it', () async {
      final root = await gitFixture(acmeLegacy);
      final hook = File('${root.path}/.git/hooks/pre-commit')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho "lint failed" >&2\nexit 1\n');
      expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);

      await expectLater(
        () => _run(root, StringBuffer(), answers: ['y']),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.gitFailed)
              .having((f) => f.exitStatus, 'exit', 75)
              .having(
                (f) => f.message,
                'message',
                'git commit failed: lint failed; fix the cause, then run '
                    'specstone migrate at an interactive terminal, or with '
                    "--yes after the Owner's ok in the chat, to finish the "
                    'run',
              ),
        ),
      );
      expect(MoveJournal.pending(root), isTrue);

      hook.deleteSync();
      final out = StringBuffer();
      expect(await _run(root, out), 0);

      final subjects = (git(root, ['log', '--format=%s']).stdout as String)
          .trim()
          .split('\n');
      expect(subjects, [_commit2Message, _commit1Message, 'legacy']);
      expect(MoveJournal.pending(root), isFalse);
    }, skip: Platform.isWindows ? 'the hook is a sh script' : skipGit);

    test('a resume commits only its own paths and leaves '
        "the Owner's staged change staged", () async {
      final root = await gitFixture(acmeLegacy);
      final hook = File('${root.path}/.git/hooks/pre-commit')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho "lint failed" >&2\nexit 1\n');
      expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);
      await expectLater(
        () => _run(root, StringBuffer(), answers: ['y']),
        throwsA(isA<MigrateFault>()),
      );
      File('${root.path}/notes.txt').writeAsStringSync('mine\n');
      expect(git(root, ['add', 'notes.txt']).exitCode, 0);
      hook.deleteSync();

      expect(await _run(root, StringBuffer()), 0);

      final renames =
          git(root, [
                'show',
                '--name-status',
                '-M',
                '--format=',
                'HEAD~1',
              ]).stdout
              as String;
      for (final line in renames.trim().split('\n')) {
        expect(line, startsWith('R100'), reason: line);
      }
      expect(
        git(root, ['diff', '--cached', '--name-only']).stdout,
        'notes.txt\n',
      );
    }, skip: Platform.isWindows ? 'the hook is a sh script' : skipGit);

    test('the resume lists only the commits of the '
        "journal's steps", () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      expect(
        git(root, [
          'commit',
          '-q',
          '--allow-empty',
          '-m',
          'owner work',
        ]).exitCode,
        0,
      );
      final out = StringBuffer();

      expect(await _run(root, out), 0);

      expect(out.toString(), isNot(contains('owner work')));
      expect(out.toString(), contains(': $_commit1Message\n'));
      expect(out.toString(), contains('commit 2 '));
    }, skip: skipGit);

    test('git that cannot start during a resume is '
        'git_work_tree_required', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);

      await expectLater(
        () => runMigrate(
          MigrateRequest(
            workingDirectory: root,
            homeDirectory: testHome(),
            templates: TemplateResolver(),
            dryRun: false,
            confirmation: OwnerConfirmation.prompt,
            readLine: () => null,
            out: StringBuffer(),
            runGit: (arguments, {required workingDirectory, environment}) =>
                throw const ProcessException('git', []),
          ),
        ),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.gitWorkTreeRequired,
          ),
        ),
      );
    }, skip: skipGit);

    test('a resume under a git older than '
        '2.25 is git_work_tree_required, and no step runs', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final before = _bytesUnder(root);

      await expectLater(
        () => runMigrate(
          MigrateRequest(
            workingDirectory: root,
            homeDirectory: testHome(),
            templates: TemplateResolver(),
            dryRun: false,
            confirmation: OwnerConfirmation.prompt,
            readLine: () => null,
            out: StringBuffer(),
            runGit: (arguments, {required workingDirectory, environment}) =>
                arguments.first == '--version'
                ? ProcessResult(0, 0, 'git version 2.24.4\n', '')
                : runRealGit(arguments, workingDirectory: workingDirectory),
          ),
        ),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.gitWorkTreeRequired,
          ),
        ),
      );
      expect(_bytesUnder(root), before);
      expect(MoveJournal.pendingMigrate(root), isTrue);
    }, skip: skipGit);

    test('git that cannot start after the checks is '
        'git_failed naming the command, and the journal stays', () async {
      final root = await gitFixture(acmeLegacy);

      await expectLater(
        () => runMigrate(
          MigrateRequest(
            workingDirectory: root,
            homeDirectory: testHome(),
            templates: TemplateResolver(),
            dryRun: false,
            confirmation: OwnerConfirmation.prompt,
            readLine: () => 'y',
            out: StringBuffer(),
            runGit: (arguments, {required workingDirectory, environment}) =>
                arguments.first == 'add'
                ? throw ProcessException(
                    'git',
                    arguments,
                    'The filename or extension is too long.',
                    206,
                  )
                : runRealGit(arguments, workingDirectory: workingDirectory),
          ),
        ),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.gitFailed)
              .having(
                (f) => f.message,
                'message',
                'git add failed: cannot start git: The filename or extension '
                    'is too long.; fix the cause, then run specstone migrate '
                    'at an interactive terminal, or with --yes after the '
                    "Owner's ok in the chat, "
                    'to finish the run',
              ),
        ),
      );
      expect(MoveJournal.pendingMigrate(root), isTrue);
    }, skip: skipGit);

    /// The refusal of a journal no run recorded, as a write command gives it.
    Matcher unrecordedRefusal() =>
        _journalRefusal('no Specstone run on this machine wrote it');

    /// The refusal of a journal whose step [path] leaves the roots.
    Matcher outsideRefusal(String path) => _journalRefusal(
      'its step path $path leaves the project and docs roots',
    );

    WriteStep docWrite() => WriteStep(
      'docs/prds/d01_context.md',
      'replaced\n',
      before: textHashOf(acmeLegacy['docs/prds/d01_context.md']!),
    );

    final outsideWrite = WriteStep(
      '../outside.md',
      'x\n',
      before: textHashOf(''),
    );

    test('a dry run over an unrecorded journal, or one whose step leaves the '
        'roots, refuses output_not_writable and prints nothing', () async {
      final cases = [
        (recorded: false, steps: [docWrite()], refusal: unrecordedRefusal()),
        (
          recorded: true,
          steps: [docWrite(), outsideWrite],
          refusal: outsideRefusal('../outside.md'),
        ),
      ];

      for (final (:recorded, :steps, :refusal) in cases) {
        final root = await gitFixture(acmeLegacy);
        writeJournal(root, steps, recorded: recorded);
        final before = treeBytes(root);
        final out = StringBuffer();
        final calls = <List<String>>[];

        await expectLater(
          () => _run(root, out, dryRun: true, runGit: _fakeGit(calls)),
          refusal,
          reason: 'recorded $recorded',
        );

        expect(out.toString(), isEmpty, reason: 'recorded $recorded');
        expect(calls, isEmpty, reason: 'recorded $recorded');
        expect(treeBytes(root), before, reason: 'recorded $recorded');
      }
    }, skip: skipGit);

    test('a bare run over an unrecorded journal, or one whose step leaves the '
        'roots, refuses output_not_writable before any step', () async {
      final cases = [
        (recorded: false, steps: [docWrite()], refusal: unrecordedRefusal()),
        (
          recorded: true,
          steps: [docWrite(), outsideWrite],
          refusal: outsideRefusal('../outside.md'),
        ),
      ];

      for (final (:recorded, :steps, :refusal) in cases) {
        final root = await gitFixture(acmeLegacy);
        writeJournal(root, steps, recorded: recorded);
        final before = treeBytes(root);

        await expectLater(
          () => _run(root, StringBuffer(), answers: ['y']),
          refusal,
          reason: 'recorded $recorded',
        );

        expect(treeBytes(root), before, reason: 'recorded $recorded');
        expect(MoveJournal.pending(root), isTrue, reason: 'recorded $recorded');
      }
    }, skip: skipGit);

    test('a bare run over a migrate journal no run recorded refuses '
        'output_not_writable after its git check, and the journal '
        'stays', () async {
      final root = await gitFixture(acmeLegacy);
      writeJournal(root, [
        docWrite(),
        CommitStep(message: 'agent files', paths: const [], base: headOf(root)),
      ], recorded: false);
      final before = treeBytes(root);
      final calls = <List<String>>[];

      await expectLater(
        () => _run(root, StringBuffer(), runGit: _fakeGit(calls)),
        unrecordedRefusal(),
      );

      expect(calls, isNotEmpty);
      expect(treeBytes(root), before);
      expect(MoveJournal.pendingMigrate(root), isTrue);
    }, skip: skipGit);

    test('a bare run over a recorded migrate journal whose step leaves the '
        'roots refuses with the message of the step path, before any '
        'step', () async {
      final root = await gitFixture(acmeLegacy);
      writeJournal(root, [
        docWrite(),
        outsideWrite,
        CommitStep(message: 'agent files', paths: const [], base: headOf(root)),
      ]);
      final before = treeBytes(root);

      await expectLater(
        () => _run(root, StringBuffer()),
        outsideRefusal('../outside.md'),
      );

      expect(treeBytes(root), before);
      expect(MoveJournal.pendingMigrate(root), isTrue);
    }, skip: skipGit);

    test('a commit git cannot start is git_failed, exit 75, naming the '
        'command, and the journal stays', () async {
      final root = await gitFixture(acmeLegacy);

      await expectLater(
        () => _run(
          root,
          StringBuffer(),
          answers: ['y'],
          runGit: (arguments, {required workingDirectory, environment}) =>
              arguments.first == 'commit'
              ? throw ProcessException('git', arguments, 'no process', 2)
              : runRealGit(arguments, workingDirectory: workingDirectory),
        ),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.gitFailed)
              .having((f) => f.exitStatus, 'exit', 75)
              .having(
                (f) => f.message,
                'message',
                allOf(
                  startsWith('git commit failed: cannot start git: '),
                  endsWith(
                    'fix the cause, then run specstone migrate at an '
                    "interactive terminal, or with --yes after the Owner's "
                    'ok in the chat, to finish the run',
                  ),
                ),
              ),
        ),
      );

      expect(MoveJournal.pendingMigrate(root), isTrue);
    }, skip: skipGit);

    test('a dry run over a journal with a step left refuses with the whole '
        'working_tree_dirty message before any git call', () async {
      final root = await gitFixture(acmeLegacy);
      _writeF02Journal(root);
      final calls = <List<String>>[];
      final out = StringBuffer();

      await expectLater(
        () => _run(root, out, dryRun: true, runGit: _fakeGit(calls)),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.workingTreeDirty)
              .having((f) => f.exitStatus, 'exit', 75)
              .having(
                (f) => f.message,
                'message',
                'the move journal (.specstone/trash/journal.json) has steps '
                    'left; run specstone migrate to finish the move, commit '
                    'it, and plan again',
              ),
        ),
      );

      expect(calls, isEmpty);
      expect(out.toString(), isEmpty);
    }, skip: skipGit);

    test('a bare run replays a pending journal, then refuses a missing work '
        'tree or a git below 2.25', () async {
      final cases = [
        (
          git: _fakeGit([], outsideWorkTree: true),
          message: isNot(contains('2.25')),
        ),
        (git: _fakeGit([], version: '2.24.0'), message: contains('2.25')),
      ];

      for (final (:git, :message) in cases) {
        final root = await gitFixture({
          '.specstone/config.yaml': shippedPinsConfig(),
          'docs/prds/a.md': 'x\n',
        });
        writeJournal(root, [
          const MoveStep('docs/prds/a.md', 'docs/prds/b.md'),
        ]);

        await expectLater(
          () => _run(root, StringBuffer(), runGit: git),
          throwsA(
            isA<MigrateFault>()
                .having(
                  (f) => f.code,
                  'code',
                  MigrateFaultCode.gitWorkTreeRequired,
                )
                .having((f) => f.exitStatus, 'exit', 78)
                .having((f) => f.message, 'message', message),
          ),
        );

        expect(hasDoc(root, 'prds/a.md'), isFalse);
        expect(hasDoc(root, 'prds/b.md'), isTrue);
        expect(MoveJournal.pending(root), isFalse);
      }
    }, skip: skipGit);

    test('--dry-run lists a commit step only when the git log lacks its '
        'commit', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final made = StringBuffer();
      expect(await _run(root, made, dryRun: true), 0);

      expect(git(root, ['reset', '-q', '--soft', 'HEAD~1']).exitCode, 0);
      final unmade = StringBuffer();
      expect(await _run(root, unmade, dryRun: true), 0);

      expect(made.toString(), isNot(contains('  commit "$_commit1Message"')));
      expect(made.toString(), contains('  commit "$_commit2Message"'));
      expect(unmade.toString(), contains('  commit "$_commit1Message"'));
      expect(unmade.toString(), contains('  commit "$_commit2Message"'));
    }, skip: skipGit);

    test('a resume plan hash changes with the journal file, and --yes with the '
        'old hash is plan_mismatch, exit 75', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final hash = await _dryRunPlanHash(root);
      final head = headOf(root);
      final journal = File('${root.path}/${MoveJournal.journalPath}');
      journal.writeAsStringSync('${journal.readAsStringSync()}\n');
      recordJournalFile(root);
      expect(await _dryRunPlanHash(root), isNot(hash));

      await expectLater(
        () => _run(
          root,
          StringBuffer(),
          confirmation: OwnerConfirmation.given,
          planHash: hash,
        ),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.planMismatch)
              .having((f) => f.exitStatus, 'exit', 75),
        ),
      );

      expect(headOf(root), head);
      expect(MoveJournal.pendingMigrate(root), isTrue);
    }, skip: skipGit);
  });

  group('the dry run and apply share one preflight', () {
    final skipGit = hasGit ? null : 'git is not available';

    Matcher gitRefusal() => throwsA(
      isA<MigrateFault>().having(
        (f) => f.code,
        'code',
        MigrateFaultCode.gitWorkTreeRequired,
      ),
    );

    Matcher trustRefusal() => throwsA(
      isA<RenderFault>().having(
        (f) => f.code,
        'code',
        RenderFaultCode.outputNotWritable,
      ),
    );

    test('a dry run outside a work tree, or under git '
        '2.24, refuses git_work_tree_required, as does a resume dry run '
        'outside one', () async {
      final root = await gitFixture(acmeLegacy);
      final out = StringBuffer();

      await expectLater(
        () => _run(
          root,
          out,
          dryRun: true,
          runGit: _fakeGit([], outsideWorkTree: true),
        ),
        gitRefusal(),
      );
      await expectLater(
        () => _run(
          root,
          out,
          dryRun: true,
          runGit: _fakeGit([], version: '2.24.0'),
        ),
        throwsA(
          isA<MigrateFault>()
              .having(
                (f) => f.code,
                'code',
                MigrateFaultCode.gitWorkTreeRequired,
              )
              .having((f) => f.message, 'message', contains('2.25')),
        ),
      );
      expect(out.toString(), isEmpty);

      _stopAfterCommit1(root);
      await expectLater(
        () => _run(
          root,
          out,
          dryRun: true,
          runGit: _fakeGit([], outsideWorkTree: true),
        ),
        gitRefusal(),
      );
      expect(out.toString(), isEmpty);
    }, skip: skipGit);

    test('a dry run over untrusted '
        'roots refuses output_not_writable before any git call', () async {
      final tree = await writeTree(linkedAcme({}));
      if (!linkCodeDocs(tree)) return;
      final calls = <List<String>>[];
      final out = StringBuffer();

      await expectLater(
        () => _run(
          Directory('${tree.path}/ws/code'),
          out,
          dryRun: true,
          runGit: _fakeGit(calls),
        ),
        trustRefusal(),
      );
      expect(calls, isEmpty);
      expect(out.toString(), isEmpty);
    });

    test('a resume dry run over a dirty tree prints the '
        'remaining steps and a plan line', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      File('${root.path}/notes.txt').writeAsStringSync('x\n');
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      expect(out.toString(), contains('remaining steps:'));
      expect(out.toString(), contains('\nplan '));
    }, skip: skipGit);

    test('a resume dry run --json holds dirty false', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      File('${root.path}/notes.txt').writeAsStringSync('x\n');
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true, asJson: true), 0);

      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['dirty'], isFalse);
    }, skip: skipGit);

    test('a dry run over a pending journal refuses '
        'untrusted roots first and replays nothing', () async {
      final tree = await writeTree(linkedAcme({}));
      if (!linkCodeDocs(tree)) return;
      final project = Directory('${tree.path}/ws');
      final calls = <List<String>>[];
      _writeF02Journal(project);
      final journal = File('${project.path}/${MoveJournal.journalPath}');
      final before = journal.readAsStringSync();

      await expectLater(
        () => _run(
          Directory('${tree.path}/ws/code'),
          StringBuffer(),
          dryRun: true,
          runGit: _fakeGit(calls),
        ),
        trustRefusal(),
      );

      expect(calls, isEmpty);
      expect(journal.readAsStringSync(), before);
    });

    test('a dry run over a pending journal with a step '
        'left replays nothing and refuses before any git call', () async {
      final root = await gitFixture(acmeLegacy);
      _writeF02Journal(root);
      final journal = File('${root.path}/${MoveJournal.journalPath}');
      final before = journal.readAsStringSync();
      final out = StringBuffer();
      final calls = <List<String>>[];

      await expectLater(
        () => _run(root, out, dryRun: true, runGit: _fakeGit(calls)),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.workingTreeDirty,
          ),
        ),
      );

      expect(calls, isEmpty);
      expect(out.toString(), isEmpty);
      expect(journal.readAsStringSync(), before);
      expect(
        File('${root.path}/docs/prds/d01_context.md').readAsStringSync(),
        acmeLegacy['docs/prds/d01_context.md'],
      );
    }, skip: skipGit);

    Matcher refusesWith(MigrateFaultCode code) =>
        throwsA(isA<MigrateFault>().having((f) => f.code, 'code', code));

    test('a dry run over a pending journal whose step '
        'is applied plans the tree as it stands and names it dirty', () async {
      final root = await gitFixture({
        ...acmeLegacy,
        '.specstone/.gitignore': '${specstoneGitignoreLines.join('\n')}\n',
      });
      _writeF02Journal(root);
      File('${root.path}/docs/prds/d01_context.md')
          .writeAsStringSync('replaced\n');
      final journal = File('${root.path}/${MoveJournal.journalPath}');
      final before = journal.readAsStringSync();
      final out = StringBuffer();
      final calls = <List<String>>[];

      expect(await _run(root, out, dryRun: true, runGit: _fakeGit(calls)), 0);

      expect(calls, isNotEmpty);
      expect(out.toString(), contains('\nplan '));
      expect(
        out.toString(),
        endsWith(
          'dry run: nothing written; the run needs a clean working tree\n',
        ),
      );
      expect(journal.readAsStringSync(), before);
    }, skip: skipGit);

    test('a dry run over a pending journal with no '
        'step left and a clean tree passes the git checks and plans', () async {
      final root = await gitFixture({
        ...acmeLegacy,
        'docs/prds/d01_context.md': 'replaced\n',
        '.specstone/.gitignore': '${specstoneGitignoreLines.join('\n')}\n',
      });
      _writeF02Journal(root);
      final out = StringBuffer();
      final calls = <List<String>>[];

      expect(await _run(root, out, dryRun: true, runGit: _fakeGit(calls)), 0);

      expect(calls, isNotEmpty);
      expect(out.toString(), contains('\nplan '));
      expect(out.toString(), endsWith('dry run: nothing written\n'));
    }, skip: skipGit);

    test('a dry run over a two-step journal goes by '
        'the cursor: a step left refuses, none left passes', () async {
      const replaced = 'replaced\n';
      const first = 'docs/prds/d01_context.md';
      const second = 'docs/prds/d02_features.md';
      for (final (:cursor, :secondDone, :refuses) in [
        (cursor: 1, secondDone: false, refuses: true),
        (cursor: 1, secondDone: true, refuses: false),
        (cursor: 2, secondDone: false, refuses: false),
      ]) {
        final root = await gitFixture({
          ...acmeLegacy,
          first: replaced,
          if (secondDone) second: replaced,
          '.specstone/.gitignore': '${specstoneGitignoreLines.join('\n')}\n',
        });
        writeJournal(root, [
          WriteStep(first, replaced, before: textHashOf(acmeLegacy[first]!)),
          WriteStep(second, replaced, before: textHashOf(acmeLegacy[second]!)),
        ]);
        File('${root.path}/${MoveJournal.cursorPath}')
            .writeAsStringSync('$cursor');
        final out = StringBuffer();
        final calls = <List<String>>[];
        final reason = 'cursor $cursor, second step done: $secondDone';

        if (refuses) {
          await expectLater(
            () => _run(root, out, dryRun: true, runGit: _fakeGit(calls)),
            refusesWith(MigrateFaultCode.workingTreeDirty),
            reason: reason,
          );
          expect(calls, isEmpty, reason: reason);
          expect(out.toString(), isEmpty, reason: reason);
        } else {
          expect(
            await _run(root, out, dryRun: true, runGit: _fakeGit(calls)),
            0,
            reason: reason,
          );
          expect(calls, isNotEmpty, reason: reason);
          expect(out.toString(), contains('\nplan '), reason: reason);
        }
      }
    }, skip: skipGit);

    test('a resume dry run over untrusted roots refuses output_not_writable '
        'before any git call', () async {
      final tree = await writeTree(linkedAcme({'.gitignore': 'code/docs\n'}));
      if (!linkCodeDocs(tree)) return;
      final ws = Directory('${tree.path}/ws');
      commitRepo(ws);
      _stopAfterCommit1(ws);
      final calls = <List<String>>[];
      final out = StringBuffer();

      await expectLater(
        () => _run(
          Directory('${ws.path}/code'),
          out,
          dryRun: true,
          runGit: _fakeGit(calls),
        ),
        trustRefusal(),
      );

      expect(calls, isEmpty);
      expect(out.toString(), isEmpty);
    }, skip: skipGit);

    test('a resume dry run under git '
        '2.24 refuses git_work_tree_required and names 2.25', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final out = StringBuffer();

      await expectLater(
        () => _run(
          root,
          out,
          dryRun: true,
          runGit: _fakeGit([], version: '2.24.0'),
        ),
        throwsA(
          isA<MigrateFault>()
              .having(
                (f) => f.code,
                'code',
                MigrateFaultCode.gitWorkTreeRequired,
              )
              .having((f) => f.message, 'message', contains('2.25')),
        ),
      );
      expect(out.toString(), isEmpty);
    }, skip: skipGit);

    group('an upgrade dry run', () {
      final upgrade = {'.specstone/config.yaml': _belowSince};

      test('over a dirty tree prints the '
          'plan and names the clean tree the run needs', () async {
        final root = await gitFixture(upgrade);
        File('${root.path}/notes.txt').writeAsStringSync('x\n');
        final out = StringBuffer();

        expect(await _run(root, out, dryRun: true), 0);

        expect(out.toString(), contains('\nplan '));
        expect(
          out.toString(),
          endsWith(
            'dry run: nothing written; the run needs a clean working tree\n',
          ),
        );
      }, skip: skipGit);

      test('outside a work tree refuses '
          'git_work_tree_required', () async {
        final root = await gitFixture(upgrade);
        final out = StringBuffer();

        await expectLater(
          () => _run(
            root,
            out,
            dryRun: true,
            runGit: _fakeGit([], outsideWorkTree: true),
          ),
          gitRefusal(),
        );

        expect(out.toString(), isEmpty);
      }, skip: skipGit);

      test('under git 2.24 refuses '
          'git_work_tree_required and names 2.25', () async {
        final root = await gitFixture(upgrade);
        final out = StringBuffer();

        await expectLater(
          () => _run(
            root,
            out,
            dryRun: true,
            runGit: _fakeGit([], version: '2.24.0'),
          ),
          throwsA(
            isA<MigrateFault>()
                .having(
                  (f) => f.code,
                  'code',
                  MigrateFaultCode.gitWorkTreeRequired,
                )
                .having((f) => f.message, 'message', contains('2.25')),
          ),
        );

        expect(out.toString(), isEmpty);
      }, skip: skipGit);
    });

    test('a dry run over a tree dirty only by a '
        'git-ignored file prints the plan', () async {
      final root = await gitFixture({...acmeLegacy, '.gitignore': '*.log\n'});
      File('${root.path}/build.log').writeAsStringSync('x\n');
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      expect(out.toString(), endsWith('dry run: nothing written\n'));
    }, skip: skipGit);

    test('an untracked file counts whatever the git '
        'configuration hides', () async {
      final root = await gitFixture(acmeLegacy);
      expect(
        git(root, ['config', 'status.showUntrackedFiles', 'no']).exitCode,
        0,
      );
      File('${root.path}/notes.txt').writeAsStringSync('x\n');
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      expect(
        out.toString(),
        endsWith(
          'dry run: nothing written; the run needs a clean working tree\n',
        ),
      );
    }, skip: skipGit);

    test('an up-to-date project outside git has nothing '
        'to migrate, with or without --dry-run', () async {
      final root = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
      });

      for (final dryRun in [false, true]) {
        final out = StringBuffer();

        expect(await _run(root, out, dryRun: dryRun), 0);

        expect(out.toString(), 'nothing to migrate\n');
      }
    });

    test(
      'an up-to-date project writes nothing, with or without --dry-run',
      () async {
        final root = await gitFixture({
          '.specstone/config.yaml': shippedPinsConfig(),
        });
        final before = _bytesUnder(root);
        final head = headOf(root);

        for (final dryRun in [false, true]) {
          final out = StringBuffer();

          expect(await _run(root, out, dryRun: dryRun), 0);

          expect(out.toString(), 'nothing to migrate\n', reason: '$dryRun');
          expect(_bytesUnder(root), before, reason: '$dryRun');
          expect(headOf(root), head, reason: '$dryRun');
          expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
        }
      },
      skip: skipGit,
    );
  });

  group('a migrate run at roots that wait for a trust record', () {
    final skipGit = hasGit ? null : 'git is not available';

    test('a bare run with no home folder refuses the trust record before the '
        'missing home, and writes nothing', () async {
      final tree = await _linkedTree();
      if (tree == null) return;
      final ws = Directory('${tree.path}/ws');
      final before = treeBytes(ws);
      final out = StringBuffer();

      await expectLater(
        () => runMigrate(
          MigrateRequest(
            workingDirectory: Directory('${ws.path}/code'),
            homeDirectory: null,
            templates: TemplateResolver(),
            dryRun: false,
            confirmation: OwnerConfirmation.prompt,
            readLine: () => throw StateError('the refusal comes first'),
            out: out,
          ),
        ),
        _untrustedRefusal(tree),
      );

      expect(out.toString(), isEmpty);
      expect(treeBytes(ws), before);
    });

    test('with no home folder, the plan refusal, the terminal check, and the '
        'plan-hash check each come before the no-home refusal', () async {
      final refusals = {
        'a plan refusal': (
          files: {
            ...duplicateGroupLegacy,
            'docs/prds/d01_context.md': '# D-01 — Context\n',
          },
          confirmation: OwnerConfirmation.prompt,
          matcher: isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.groupSlugDuplicate,
          ),
        ),
        'no interactive terminal': (
          files: acmeLegacy,
          confirmation: OwnerConfirmation.missing,
          matcher: isA<WriteFault>().having(
            (f) => f.code,
            'code',
            WriteFaultCode.ownerTerminalRequired,
          ),
        ),
        'a stale plan hash under --yes': (
          files: acmeLegacy,
          confirmation: OwnerConfirmation.given,
          matcher: isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.planMismatch,
          ),
        ),
      };

      for (final MapEntry(key: reason, value: refusal) in refusals.entries) {
        final root = await gitFixture(refusal.files);
        final before = treeBytes(root);

        await expectLater(
          () => runMigrate(
            MigrateRequest(
              workingDirectory: root,
              homeDirectory: null,
              templates: TemplateResolver(),
              dryRun: false,
              confirmation: refusal.confirmation,
              planHash: '000000000000',
              readLine: () => 'y',
              out: StringBuffer(),
            ),
          ),
          throwsA(refusal.matcher),
          reason: reason,
        );

        expect(treeBytes(root), before, reason: reason);
        expect(MoveJournal.pending(root), isFalse, reason: reason);
      }
    }, skip: skipGit);

    test('a bare run over a pending journal refuses before its replay and any '
        'git call, and leaves the journal', () async {
      final tree = await _linkedTree();
      if (tree == null) return;
      final ws = Directory('${tree.path}/ws');
      _writeF02Journal(ws);
      final before = treeBytes(ws);
      final calls = <List<String>>[];
      final out = StringBuffer();

      await expectLater(
        () => _run(
          Directory('${ws.path}/code'),
          out,
          answers: ['y'],
          runGit: _fakeGit(calls),
        ),
        _untrustedRefusal(tree),
      );

      expect(calls, isEmpty);
      expect(out.toString(), isEmpty);
      expect(treeBytes(ws), before);
      expect(MoveJournal.pending(ws), isTrue);
    });

    test('a write command refuses to replay a pending journal, leaves it, and '
        'changes nothing', () async {
      final tree = await _linkedTree({
        '.specstone/config.yaml': shippedPinsConfig(),
      });
      if (tree == null) return;
      final ws = Directory('${tree.path}/ws');
      _writeF02Journal(ws);
      final journal = File('${ws.path}/${MoveJournal.journalPath}');
      final journalBytes = journal.readAsBytesSync();
      final before = _bytesUnder(ws);

      await expectLater(
        () => writeIn(Directory('${ws.path}/code'), (session) {}),
        _untrustedRefusal(tree),
      );

      // Opening the project makes the index `.gitignore`, as any read does.
      expect(_bytesUnder(ws)..remove('.specstone/.gitignore'), before);
      expect(journal.readAsBytesSync(), journalBytes);
    });

    test('a dry run refuses before the plan and before it reads a journal, '
        'with a pending journal or none', () async {
      final journals = <String, void Function(Directory)>{
        'no journal': (_) {},
        'a journal that does not parse': (ws) {
          File('${ws.path}/${MoveJournal.journalPath}')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('{');
          recordJournalFile(ws);
        },
        'a journal with a step left': _writeF02Journal,
      };

      for (final MapEntry(key: reason, value: write) in journals.entries) {
        final tree = await _linkedTree();
        if (tree == null) return;
        final ws = Directory('${tree.path}/ws');
        write(ws);
        final before = treeBytes(ws);
        final calls = <List<String>>[];
        final out = StringBuffer();

        await expectLater(
          () => _run(
            Directory('${ws.path}/code'),
            out,
            dryRun: true,
            runGit: _fakeGit(calls),
          ),
          _untrustedRefusal(tree),
          reason: reason,
        );

        expect(calls, isEmpty, reason: reason);
        expect(out.toString(), isEmpty, reason: reason);
        expect(treeBytes(ws), before, reason: reason);
      }
    });

    test(
      'a bare resume refuses before its git check and writes nothing',
      () async {
        final tree = await _linkedTree({'.gitignore': 'code/docs\n'});
        if (tree == null) return;
        final ws = Directory('${tree.path}/ws');
        commitRepo(ws);
        _stopAfterCommit1(ws);
        final before = treeBytes(ws);
        final head = headOf(ws);
        final calls = <List<String>>[];
        final out = StringBuffer();

        await expectLater(
          () =>
              _run(Directory('${ws.path}/code'), out, runGit: _fakeGit(calls)),
          _untrustedRefusal(tree),
        );

        expect(calls, isEmpty);
        expect(out.toString(), isEmpty);
        expect(treeBytes(ws), before);
        expect(headOf(ws), head);
        expect(MoveJournal.pendingMigrate(ws), isTrue);
      },
      skip: skipGit,
    );
  });

  group('a planned create onto a path that holds an entry', () {
    final skipGit = hasGit ? null : 'git is not available';
    Matcher refusedAt(String path) => throwsA(
      isA<MigrateFault>()
          .having((f) => f.code, 'code', MigrateFaultCode.valueUnplaced)
          .having((f) => f.file, 'file', path),
    );

    test('a legacy tree that holds the override file '
        'the run creates refuses in the dry run, nothing written', () async {
      final root = await gitFixture({
        ...acmeLegacy,
        '.specstone/templates/gnfr.yaml': 'id: gnfr\n',
      });
      final before = _bytesUnder(root);
      final out = StringBuffer();

      await expectLater(
        () => _run(root, out, dryRun: true),
        refusedAt('.specstone/templates/gnfr.yaml'),
      );

      expect(out.toString(), isEmpty);
      expect(_bytesUnder(root), before);
    }, skip: skipGit);

    test('a draft path the volume reads as the name '
        'of a file there refuses in the dry run, nothing written', () async {
      final root = await gitFixture({
        ...acmeLegacy,
        'docs/specs/tech_stack.md': '# Stack\n',
      });
      if (!File('${root.path}/docs/specs/TECH_STACK.md').existsSync()) {
        markTestSkipped('the volume tells names apart by case');
        return;
      }
      final before = _bytesUnder(root);
      final out = StringBuffer();

      await expectLater(
        () => _run(root, out, dryRun: true),
        refusedAt('docs/specs/TECH_STACK.md'),
      );

      expect(out.toString(), isEmpty);
      expect(_bytesUnder(root), before);
    }, skip: skipGit);
  });
}

/// Writes a pending F-02 journal, one write step and no commit, at [root].
void _writeF02Journal(Directory root) => writeJournal(root, [
  WriteStep(
    'docs/prds/d01_context.md',
    'replaced\n',
    before: textHashOf(acmeLegacy['docs/prds/d01_context.md']!),
  ),
]);

/// Starts real git like [runMigrateGit], records each argument list in
/// [calls], and answers `--version` with [version] or the work-tree query
/// with `false` when asked.
RunGit _fakeGit(
  List<List<String>> calls, {
  String? version,
  bool outsideWorkTree = false,
}) => (arguments, {required workingDirectory, environment}) {
  calls.add(arguments);
  if (version != null && arguments.first == '--version') {
    return ProcessResult(0, 0, 'git version $version\n', '');
  }
  if (outsideWorkTree && arguments.contains('--is-inside-work-tree')) {
    return ProcessResult(0, 0, 'false\n', '');
  }
  return runRealGit(arguments, workingDirectory: workingDirectory);
};

/// Returns the full sha HEAD of [root] points at.
String headOf(Directory root) =>
    (git(root, ['rev-parse', 'HEAD']).stdout as String).trim();

/// Leaves [root] as a crash after commit 1 of the legacy plan does: the
/// journal saved, its steps applied through the first commit.
void _stopAfterCommit1(Directory root) {
  final steps = planLegacyRun(
    root,
    templates: TemplateResolver(),
    homeDirectory: testHome(),
  ).journalSteps(base: headOf(root), projectRoot: root);
  final specstone = Directory('${root.path}/.specstone')
    ..createSync(recursive: true);
  ensureSpecstoneGitignore(specstone);
  Directory('${root.path}/${MoveJournal.trashPath}').createSync();
  writeJournal(root, steps);
  final target = JournalTarget(
    projectRoot: root,
    docsRoot: Directory('${root.path}/docs'),
    homeDirectory: testHome(),
  );
  for (final step in steps) {
    step.apply(target);
    if (step is CommitStep) break;
  }
}
