@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/doc_index.dart' show DocIndex;
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart'
    show GeneratorRegistry;
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/agent_files.dart'
    show inlineBlock;
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart';
import 'package:specstone_core/src/shipped_generators.dart'
    show shippedGenerators;
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:test/test.dart';

import '../../helpers/cold_node.dart';
import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart';
import '../../helpers/relative_link.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_files.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/upgrade_fixture.dart';
import '../../helpers/write_fixture.dart';

const _trustLine =
    'trust the Specstone hook in Codex: open /hooks in a trusted project';
const _commit1Message = 'move docs to their new pack paths';
const _commit2Message = 'upgrade pack pins';

/// The subject `commitRepo` gives the first commit of a fixture; rename it
/// with [_spacedSubject], the same idea for [_spacedUpgradeFixture], when
/// Task 27 settles `commitRepo`.
const _fixtureSubject = 'legacy';

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

/// An instruction file whose Specstone block is out of date, so an upgrade
/// writes it.
const _staleClaude =
    '# Acme\n<!-- BEGIN specstone v0.0.1 -->\nold rules\n'
    '<!-- END specstone -->\n';

/// A Claude Code settings file whose hook entry is out of date, so a run over
/// a project holding it writes that file alone.
const _staleSettings =
    '{"permissions":{"allow":["Bash(ls)"]},"hooks":{"PostToolUse":'
    '[{"matcher":"Write","hooks":[{"type":"command","command":'
    '"specstone","args":["hook","post-edit"]}]}]}}\n';

/// The files of a project on the shipped pins that a run changes with no
/// personal pack, so the run needs no home folder to plan.
Map<String, String> _agentOnlyFiles() => {
  '.specstone/config.yaml': shippedPinsConfig(),
  ...skillFileTexts(),
  settingsFilePath: _staleSettings,
};

/// The subject of the one commit of [_spacedUpgradeFixture].
const _spacedSubject = 'spaced';

/// Writes the fixture under `<tmp>/NTD OS/acme/` and commits it.
Future<Directory> _spacedUpgradeFixture(Map<String, String> files) async {
  final tmp = await writeTree({
    for (final MapEntry(:key, :value) in files.entries)
      'NTD OS/acme/$key': value,
  });
  final root = Directory.fromUri(tmp.uri.resolve('NTD OS/acme/'));
  expect(git(root, ['init', '-q']).exitCode, 0);
  expect(git(root, ['config', 'user.name', 't']).exitCode, 0);
  expect(git(root, ['config', 'user.email', 't@t']).exitCode, 0);
  expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
  commitAll(root, _spacedSubject);
  return root;
}

/// The `config.yaml` of an upgrade project: the shipped pins plus `acme`
/// pinned below its home version, then [extra].
///
/// A run over it is an upgrade with every shipped pin at its floor; pass
/// [acmeHome] as the home folder.
String _upgradeConfig([String extra = '']) =>
    '${shippedPinsConfig()}$acmeOldPinLine$extra';

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
  List<String>? progress,
  List<String>? warningLog,
  RunGit runGit = runMigrateGit,
  List<String> addedPacks = const [],
  GeneratorRegistry<DocIndex>? generators,
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
      say: (progress ?? <String>[]).add,
      warningLog: warningLog,
      generators: generators ?? shippedGenerators(),
    ),
  );
}

/// The shipped generators, each call adding the index it reads to [seen], by
/// identity.
GeneratorRegistry<DocIndex> _recordingGenerators(Set<DocIndex> seen) {
  final shipped = shippedGenerators();
  return GeneratorRegistry<DocIndex>(
    {
      for (final kind in shipped.kinds)
        kind: (doc, docPath, type, index) {
          seen.add(index);
          return shipped[kind]!(doc, docPath, type, index);
        },
    },
    companions: {
      for (final kind in shipped.kinds)
        if (shipped.companionsOf(kind) case final companions?)
          kind: (docPath, type, index) {
            seen.add(index);
            return companions(docPath, type, index);
          },
    },
  );
}

void main() {
  useColdHostNode();

  test('an apply that crosses a regenerate step builds one index for the '
      'shown plan and the plan before the write', () async {
    final seen = <DocIndex>{};
    final pins = shippedPinsConfig().replaceFirst(
      '  prd-core: ${shippedPackVersions()['prd-core']}\n',
      '  prd-core: 1.31.0\n',
    );
    final root = await gitFixture({
      '.specstone/config.yaml':
          '${pins}agent_files_version: $specstoneVersion\n',
      'docs/prds/features/f01_recipes/FEATURE.md': '# Recipes\n',
      'docs/prds/FEATURES.md': '# Feature map\n\n## Features\n',
    });
    final out = StringBuffer();

    final status = await _run(
      root,
      out,
      answers: ['y'],
      generators: _recordingGenerators(seen),
    );

    expect(status, 0);
    expect(out.toString(), contains('regenerate: feature_catalog'));
    expect(seen, hasLength(1));
  }, skip: hasGit ? null : 'git is not available');

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

    test('an add of a pinned pack is a usage error naming its pin', () async {
      final root = await gitFixture({
        '.specstone/config.yaml': shippedPinsConfig([
          'agent-skills',
          'prd-core',
          'software-tech',
        ]),
      });

      await expectLater(
        _run(root, StringBuffer(), addedPacks: ['agent-skills']),
        usageError(
          'agent-skills is already pinned at '
          '${shippedPackVersions()['agent-skills']}; run specstone migrate to '
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

  group('a shipped pin below its floor', () {
    Matcher belowFloorRefusal() => throwsA(
      isA<TemplateFault>()
          .having((f) => f.code, 'code', FaultCode.packPinBelowFloor)
          .having((f) => f.exitStatus, 'exit', 78)
          .having((f) => f.file, 'file', '.specstone/config.yaml')
          .having((f) => f.key, 'key', 'packs.prd-core'),
    );

    for (final dryRun in [false, true]) {
      test('${dryRun ? 'a dry run' : 'bare migrate'} refuses before any '
          'run kind and leaves the tree byte for byte', () async {
        final root = await gitFixture({
          '.specstone/config.yaml': shippedPinsBelowFloor(),
        });
        final before = _bytesUnder(root);

        await expectLater(
          _run(root, StringBuffer(), dryRun: dryRun, answers: ['y']),
          belowFloorRefusal(),
        );

        expect(_bytesUnder(root), before);
      });
    }

    test('an add refuses the floor before it checks the added name', () async {
      final root = await gitFixture({
        '.specstone/config.yaml': shippedPinsBelowFloor(),
      });
      final before = _bytesUnder(root);

      await expectLater(
        _run(root, StringBuffer(), addedPacks: ['nope']),
        belowFloorRefusal(),
      );

      expect(_bytesUnder(root), before);
    });

    test('the floor wins over a newer pin that sorts first', () async {
      final root = await gitFixture({
        '.specstone/config.yaml': shippedPinsBelowFloor(
          extra: 'agent-skills: 99.0.0',
        ),
      });
      final before = _bytesUnder(root);

      await expectLater(
        _run(root, StringBuffer(), dryRun: true),
        belowFloorRefusal(),
      );

      expect(_bytesUnder(root), before);
    });

    test('a pending document-writing journal is refused before its replay, '
        'with the journal file unchanged', () async {
      final root = await gitFixture({
        '.specstone/config.yaml': shippedPinsBelowFloor(),
      });
      writeJournal(root, [const WriteStep.unguarded('notes.md', 'new\n')]);
      final journal = File('${root.path}/${MoveJournal.journalPath}');
      final before = _bytesUnder(root);
      final journalBefore = journal.readAsStringSync();

      await expectLater(_run(root, StringBuffer()), belowFloorRefusal());

      expect(_bytesUnder(root), before);
      expect(journal.readAsStringSync(), journalBefore);
      expect(File('${root.path}/notes.md').existsSync(), isFalse);
      expect(MoveJournal.pending(root), isTrue);
    });
  }, skip: hasGit ? null : 'git is not available');

  test('y makes two commits, the first pure renames', () async {
    final root = await _spacedUpgradeFixture(upgradeFiles());
    acmeInTestHome();
    final out = StringBuffer();

    final status = await _run(root, out, answers: ['y']);

    expect(status, 0);
    final subjects = (git(root, ['log', '--format=%s']).stdout as String)
        .trim()
        .split('\n');
    expect(subjects, [_commit2Message, _commit1Message, _spacedSubject]);
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
      '.specstone/.gitignore',
      '.specstone/config.yaml',
      acmeMovedRunbookPath,
    });
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
    expect(
      File('${root.path}/.specstone/config.yaml').readAsStringSync(),
      contains('acme: 1.1.0'),
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
          r'commit 1 ([0-9a-f]{7,}): move docs to their new pack paths\n'
          r'commit 2 ([0-9a-f]{7,}): upgrade pack pins\n'
          r'check: \d+ findings left; run specstone check to see them\n$',
        ),
      ),
    );
    expect(out.toString(), startsWith('pack upgrade: acme 1.0.0 -> 1.1.0'));
  }, skip: hasGit ? null : 'git is not available');

  test('an old cite form outlives a layout-only upgrade, and check reports '
      'it as cite_unlinked', () async {
    const cite = 'Users forget; `architecture:login`.';
    final root = await gitFixture({
      '.specstone/config.yaml': shippedPinsConfig(),
      'docs/prds/features/f01_login/FEATURE.md':
          '## Benefit hypothesis\n\ng\n\n\n## Problem\n\n$cite\n',
      'docs/specs/f01_login/ARCHITECTURE.md':
          '# Login architecture\n\n## Components\n\n'
          '| Component | Responsibility |\n|---|---|\n| Form | Signs in. |\n',
    });

    final out = StringBuffer();

    expect(await _run(root, out, answers: ['y']), 0);

    expect(
      out.toString(),
      startsWith('pack upgrade: pins unchanged, layout only'),
    );
    final feature = File('${root.path}/docs/prds/features/f01_login/FEATURE.md')
        .readAsStringSync();
    expect(feature, contains('\n$cite\n'));
    final cites = await ReadSession.runAsync(
      (session) async => [
        for (final finding in (await runCheck(session)).findings)
          if (finding.kind == FindingKind.citeUnlinked) finding.keys['value'],
      ],
      templates: TemplateResolver(),
      workingDirectory: root,
      homeDirectory: testHome(),
    );
    expect(cites, ['architecture:login']);
  }, skip: hasGit ? null : 'git is not available');

  group('the closing count and the JSON plan', () {
    final skipGit = hasGit ? null : 'git is not available';

    Future<int> findingsOf(Directory root) => ReadSession.runAsync(
      (session) async => (await runCheck(session)).findings.length,
      templates: TemplateResolver(),
      workingDirectory: root,
      homeDirectory: testHome(),
    );

    test('an applied upgrade ends with the findings a whole-project check '
        'reports after its last commit', () async {
      final root = (await upgradeFixture()).project;
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
      final fixture = await upgradeFixture();
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
      final root = (await upgradeFixture(files: {'CLAUDE.md': _staleClaude}))
          .project;
      final text = StringBuffer();
      final json = StringBuffer();
      expect(await _run(root, text, dryRun: true), 0);

      expect(await _run(root, json, dryRun: true, asJson: true), 0);

      final object = jsonDecode(json.toString()) as Map<String, Object?>;
      expect(object.keys, [
        'plan',
        'dirty',
        'formatLayout',
        'agentFiles',
        'stamps',
        'steps',
        'mentions',
      ]);
      expect(object, isNot(contains('planHash')));
      expect(text.toString(), startsWith(object['plan']! as String));
      expect(
        (object['plan']! as String).trimRight().split('\n').last,
        'plan ${await _dryRunPlanHash(root)}',
      );
      expect(object['formatLayout'], <Object?>[]);
      expect(
        object['agentFiles'],
        unorderedEquals(['CLAUDE.md', '.specstone/AGENT.md']),
      );
      expect(object['stamps'], {'skipped': <Object?>[]});
      expect(json.toString().trim().split('\n').first, '{');
    }, skip: skipGit);

    test('--yes --plan --json sends the commit lines and the closing line to '
        'progress and keeps warnings empty', () async {
      final fixture = await upgradeFixture();
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
        progress: notes,
        warningLog: <String>[],
      );

      expect(status, 0);
      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['plan'], isNot(contains('plan $hash')));
      expect(object['steps'], [
        {
          'from': '1.0.0',
          'step':
              'move_file runbook prds/runbooks/{slug}/RUNBOOK.md -> '
              'prds/ops/{slug}/RUNBOOK.md',
          'paths': ['prds/ops/deploy/RUNBOOK.md'],
        },
        {
          'from': '1.0.0',
          'step': 'rename_section runbook steps -> procedure',
          'paths': ['prds/ops/deploy/RUNBOOK.md'],
        },
      ]);
      expect(object['warnings'], <Object?>[]);
      expect(notes.first, matches('^commit [12] [0-9a-f]{7,}: '));
      expect(notes.last, matches(r'^check: \d+ findings left; '));
      expect(MoveJournal.pending(fixture.project), isFalse);
    }, skip: skipGit);

    test('--dry-run --json holds an empty warnings array when none', () async {
      final root = (await upgradeFixture()).project;
      final out = StringBuffer();

      expect(
        await _run(root, out, dryRun: true, asJson: true, warningLog: []),
        0,
      );

      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['warnings'], <Object?>[]);
      expect(object.keys.last, 'warnings');
    }, skip: skipGit);

    test('--dry-run --json lists a skipped agent file in warnings and prints '
        'no stderr line', () async {
      final base = await _twoRepositories({
        'proj/.specstone/config.yaml': _upgradeConfig(
          'code_root: ../mono/services/api\n',
        ),
        'mono/services/api/main.dart': 'void main() {}\n',
      }, other: 'mono');
      final out = StringBuffer();
      final warnings = <String>[];
      const skipLines = [
        '../mono/AGENTS.md reaches outside the project root; left as it is',
        '../mono reaches outside the project root; left as it is',
      ];

      expect(
        await _run(
          Directory('${base.path}/proj'),
          out,
          home: await acmeHome(),
          dryRun: true,
          asJson: true,
          warnings: warnings,
          warningLog: <String>[],
        ),
        0,
      );

      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['warnings'], skipLines);
      expect(warnings, isEmpty);
    }, skip: skipGit);

    test('--yes --plan --json lists a journal replay warning in warnings and '
        'prints no stderr line', () async {
      final root = (await upgradeFixture(files: {'CLAUDE.md': _staleClaude}))
          .project;
      _stopAfterCommit1(root);
      final claude = File('${root.path}/CLAUDE.md');
      claude.writeAsStringSync('${claude.readAsStringSync()}\nuser edit\n');
      final hash = await _dryRunPlanHash(root);
      final out = StringBuffer();
      final warnings = <String>[];

      final status = await _run(
        root,
        out,
        confirmation: OwnerConfirmation.given,
        planHash: hash,
        asJson: true,
        warnings: warnings,
        warningLog: <String>[],
      );

      expect(status, 0);
      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['warnings'], [
        'CLAUDE.md changed since the stopped run; left as it is',
      ]);
      expect(warnings, isEmpty);
    }, skip: skipGit);

    test(
      '--json that declines at the prompt still prints the object',
      () async {
        final root = (await upgradeFixture()).project;
        final out = StringBuffer();
        final progress = <String>[];

        final status = await _run(
          root,
          out,
          answers: ['n'],
          asJson: true,
          progress: progress,
          warningLog: <String>[],
        );

        expect(status, 0);
        final object = jsonDecode(out.toString()) as Map<String, Object?>;
        expect(progress, [
          (object['plan']! as String).trimRight(),
          'apply? [y/N]',
        ]);
        expect(object['warnings'], <Object?>[]);
      },
      skip: skipGit,
    );

    test('--yes --plan --json that refuses leaves stdout empty', () async {
      final root = (await upgradeFixture()).project;
      final out = StringBuffer();

      await expectLater(
        () => _run(
          root,
          out,
          confirmation: OwnerConfirmation.given,
          planHash: '000000000000',
          asJson: true,
          warningLog: <String>[],
        ),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.planMismatch,
          ),
        ),
      );

      expect(out.toString(), isEmpty);
    }, skip: skipGit);

    test('--dry-run --json on a dirty tree holds dirty true', () async {
      final root = (await upgradeFixture()).project;
      File('${root.path}/notes.txt').writeAsStringSync('scratch\n');
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true, asJson: true), 0);

      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['dirty'], isTrue);
    }, skip: skipGit);

    test('--dry-run --json on a clean tree holds dirty false', () async {
      final root = (await upgradeFixture()).project;
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true, asJson: true), 0);

      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['dirty'], isFalse);
    }, skip: skipGit);

    test('--yes --plan --json holds no dirty key', () async {
      final fixture = await upgradeFixture();
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
      final root = (await upgradeFixture()).project;
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
        generators: shippedGenerators(),
      ),
    );

    test(
      'outside a git work tree refuses git_work_tree_required first',
      () async {
        final root = await writeTree(_agentOnlyFiles());

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
        final root = await gitFixture(_agentOnlyFiles());
        final before = treeBytes(root);
        final out = StringBuffer();

        await expectLater(() => runHomeless(root, out), refusesHomeless());

        expect(out.toString(), startsWith('pack upgrade: '));
        expect(out.toString(), isNot(contains('apply?')));
        expect(treeBytes(root), before);
      },
      skip: skipGit,
    );

    test(
      'under --yes with the seen plan refuses and changes nothing',
      () async {
        final root = await gitFixture(_agentOnlyFiles());
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
    final root = (await upgradeFixture()).project;
    final before = _bytesUnder(root);
    final out = StringBuffer();

    expect(await _run(root, out, answers: ['y']), 0);

    expect(git(root, ['reset', '-q', '--hard', 'HEAD~2']).exitCode, 0);
    expect(_bytesUnder(root), before);
    expect(
      File.fromUri(root.uri.resolve('.specstone/config.yaml'))
          .readAsStringSync(),
      contains('acme: 1.0.0'),
    );
  }, skip: hasGit ? null : 'git is not available');

  test('any answer but y writes nothing', () async {
    for (final answer in ['n', '', 'yes', null]) {
      final root = (await upgradeFixture()).project;
      final before = _bytesUnder(root);
      final head = (git(root, ['rev-parse', 'HEAD']).stdout as String).trim();
      final out = StringBuffer();

      final status = await _run(root, out, answers: [answer]);

      expect(status, 0, reason: 'answer $answer');
      expect(
        (git(root, ['rev-parse', 'HEAD']).stdout as String).trim(),
        head,
        reason: 'answer $answer',
      );
      expect(_bytesUnder(root), before, reason: 'answer $answer');
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
        generators: shippedGenerators(),
      ),
    );

    test('a doc edited before the y is '
        'working_tree_dirty, and the edit and the tree stay', () async {
      final root = (await upgradeFixture()).project;
      final head = headOf(root);
      final before = _bytesUnder(root);
      final runbook = File('${root.path}/$acmeRunbookPath');
      const edited = '$acmeRunbookText\nedit\n';

      await expectLater(
        () => answerAfter(root, () => runbook.writeAsStringSync(edited)),
        throwsA(
          isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.workingTreeDirty,
          ),
        ),
      );
      expect(headOf(root), head);
      expect(runbook.readAsStringSync(), edited);
      expect(_bytesUnder(root), {...before, acmeRunbookPath: edited});
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('a commit that leaves every input as it was, made '
        'while the prompt waits, lets the run apply on top of it', () async {
      final root = (await upgradeFixture()).project;
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
        _fixtureSubject,
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
      final root = (await upgradeFixture()).project;
      const input = acmeRunbookPath;

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
      expect(_bytesUnder(root), {...upgradeFiles(), input: '# edited\n'});
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('a committed deletion of an input, made while the '
        'prompt waits, is working_tree_dirty naming it, never a raw '
        'FileSystemException', () async {
      final root = (await upgradeFixture()).project;
      const input = acmeRunbookPath;

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
      final UpgradeFixture(:project, :home) = await upgradeFixture();
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

    test('an untyped doc committed while the prompt waits is '
        'working_tree_dirty naming it, and nothing is written', () async {
      final root = (await upgradeFixture()).project;
      const added = 'docs/prds/d09_extra.md';

      await expectRefusedNaming(root, added, () {
        File('${root.path}/$added').writeAsStringSync('# D-09 — Extra\n');
        commitAll(root, 'meanwhile');
      });

      expect(_bytesUnder(root), {...upgradeFiles(), added: '# D-09 — Extra\n'});
    }, skip: skipGit);

    test('an ignored doc made unreadable while the '
        'prompt waits is working_tree_dirty naming that doc, and nothing is '
        'written', () async {
      const ignored = 'docs/prds/zz_local.md';
      final root = (await upgradeFixture(
        files: {'.gitignore': 'zz_local.md\n', ignored: '# D-09 — Local\n'},
      )).project;
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
      final UpgradeFixture(:project, :home) = await upgradeFixture();
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
      final UpgradeFixture(:project, :home) = await upgradeFixture();
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
      final UpgradeFixture(:project, :home) = await upgradeFixture();
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
      final UpgradeFixture(:project, :home) = await upgradeFixture();
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
      final UpgradeFixture(:project, :home) = await upgradeFixture();
      const broken = 'playbook.yaml';

      await expectRefusedNaming(project, broken, () {
        File('${home.path}/.specstone/packs/acme/$broken')
            .writeAsStringSync('id: [unclosed\n');
      }, home: home);
    }, skip: skipGit);

    test('a tree made dirty while the prompt waits refuses with the message of '
        'the first clean-tree check, and nothing is written', () async {
      final root = (await upgradeFixture()).project;
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
      expect(_bytesUnder(root), {...upgradeFiles(), 'notes.txt': 'x\n'});
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('a layer file of a dropped doc type, committed while an upgrade '
        'prompt waits, refuses naming the plan alone, and nothing is '
        'written', () async {
      final UpgradeFixture(:project, :home) = await upgradeFixture();
      File('${home.path}/.specstone/packs/acme/pack.yaml').writeAsStringSync(
        '      - drop_doc_type: {id: x, path: "xs/{slug}.md"}\n',
        mode: FileMode.append,
      );
      const added = '.specstone/templates/x.yaml';
      late final String head;

      await expectLater(
        () => answerAfter(project, () {
          File('${project.path}/$added')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('sections: [{id: gone}]\n');
          commitAll(project, 'meanwhile');
          head = headOf(project);
        }, home: home),
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

      expect(headOf(project), head);
      expect(MoveJournal.pending(project), isFalse);
    }, skip: skipGit);

    test('two inputs committed changed while the prompt waits refuse naming '
        'the first in code point order, an upper-case name before a '
        'lower-case one', () async {
      const first = 'docs/INDEX.md';
      const second = acmeRunbookPath;
      final root = (await upgradeFixture(files: {first: '# Index\n'})).project;

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
      final UpgradeFixture(:project, :home) = await upgradeFixture();
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
      final root = (await upgradeFixture()).project;
      final hashBefore = await _dryRunPlanHash(root);
      await expectLater(
        () => answerAfter(root, () {
          File('${root.path}/$acmeRunbookPath').writeAsStringSync('# edited\n');
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
        _fixtureSubject,
      ]);
      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);
  });

  test('commit 2 holds the agent files, a CLAUDE.md block refreshed', () async {
    final root = await _spacedUpgradeFixture({
      ...upgradeFiles(),
      'CLAUDE.md': _staleClaude,
    });
    acmeInTestHome();
    final out = StringBuffer();

    expect(await _run(root, out, answers: ['y']), 0);

    final names =
        (git(root, ['show', '--name-only', '--format=', 'HEAD']).stdout
                as String)
            .trim()
            .split('\n');
    // The agent files of the run: the stale instruction file and AGENT.md.
    const agentFiles = {'CLAUDE.md', '.specstone/AGENT.md'};
    expect(names.toSet(), {
      ...agentFiles,
      '.specstone/.gitignore',
      '.specstone/config.yaml',
      acmeMovedRunbookPath,
    });
    final claude = File.fromUri(root.uri.resolve('CLAUDE.md'));
    expect(claude.readAsStringSync(), startsWith('# Acme\n'));
    expect(
      claude.readAsStringSync(),
      contains('<!-- BEGIN specstone v$specstoneVersion -->'),
    );
    expect(
      out.toString(),
      contains('  agent files: ${agentFiles.length} files\n'),
    );
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');

  group('the Claude Code settings file', () {
    const stale = _staleSettings;

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

  group('the Codex trust line', () {
    const staleHooks = '{}\n';
    const checkLine =
        r'^check: \d+ findings left; run specstone check to see them$';
    const ownerSettings = '{"permissions":{"allow":["Bash(ls)"]}}\n';

    Future<Directory> fixture(Map<String, String> files) =>
        gitFixture({'.specstone/config.yaml': shippedPinsConfig(), ...files});

    test('a run that changes .codex/hooks.json prints the line after the '
        'commit lines and before the closing line', () async {
      final root = await fixture({
        ...skillFileTexts(),
        codexHooksFilePath: staleHooks,
      });
      final out = StringBuffer();

      expect(await _run(root, out, answers: ['y']), 0);

      final lines = out.toString().trim().split('\n');
      expect(lines[lines.length - 3], matches('commit 2 [0-9a-f]{7,}: '));
      expect(lines[lines.length - 2], _trustLine);
      expect(lines.last, matches(checkLine));
      expect(lines.where((line) => line == _trustLine), hasLength(1));
      expect(
        File('${root.path}/$codexHooksFilePath').readAsStringSync(),
        codexHooksFileText,
      );
    }, skip: hasGit ? null : 'git is not available');

    test('under --json the line goes to progress with the commit and closing '
        'lines, and the object on stdout does not hold it', () async {
      final root = await fixture({
        ...skillFileTexts(),
        codexHooksFilePath: staleHooks,
      });
      final out = StringBuffer();
      final notes = <String>[];

      final status = await _run(
        root,
        out,
        answers: ['y'],
        asJson: true,
        progress: notes,
        warningLog: <String>[],
      );

      expect(status, 0);
      expect(notes[notes.length - 3], matches('^commit 2 [0-9a-f]{7,}: '));
      expect(notes[notes.length - 2], _trustLine);
      expect(notes.last, matches(checkLine));
      expect(out.toString(), isNot(contains(_trustLine)));
      expect(jsonDecode(out.toString()), isA<Map<String, Object?>>());
    }, skip: hasGit ? null : 'git is not available');

    test(
      'a run that leaves .codex/hooks.json current prints no line',
      () async {
        final root = await fixture({
          ...skillFileTexts(),
          settingsFilePath: ownerSettings,
        });
        final out = StringBuffer();

        expect(await _run(root, out, answers: ['y']), 0);

        expect(out.toString(), isNot(contains(_trustLine)));
        expect(
          File('${root.path}/$codexHooksFilePath').readAsStringSync(),
          codexHooksFileText,
        );
      },
      skip: hasGit ? null : 'git is not available',
    );

    test('a run with the Codex agents group opted out prints no line and '
        'writes no .codex/hooks.json', () async {
      final texts = skillFileTexts()
        ..removeWhere((path, _) => path.startsWith('.codex/'))
        ..[settingsFilePath] = ownerSettings;
      final root = await fixture(texts);
      final out = StringBuffer();

      expect(await _run(root, out, answers: ['y']), 0);

      expect(out.toString(), isNot(contains(_trustLine)));
      expect(File('${root.path}/$codexHooksFilePath').existsSync(), isFalse);
    }, skip: hasGit ? null : 'git is not available');

    test('a resumed run whose journal creates the hooks file through a '
        'linked .codex folder prints the line', () async {
      final root = await fixture({'shared/keep.txt': 'x\n'});
      try {
        createRelativeLink('${root.path}/.codex', 'shared');
      } on FileSystemException {
        markTestSkipped('symbolic links need privileges on this machine');
        return;
      }
      writeJournal(root, [
        CreateStep('shared/hooks.json', codexHooksFileText),
        CommitStep(
          message: 'agent files',
          paths: const ['shared/hooks.json'],
          base: headOf(root),
        ),
      ]);
      final out = StringBuffer();

      expect(await _run(root, out), 0);

      final lines = out.toString().trim().split('\n');
      expect(lines[lines.length - 2], _trustLine);
      expect(lines.last, matches(checkLine));
    }, skip: hasGit ? null : 'git is not available');

    String listing(String top) =>
        '${shippedPinsConfig()}agent_file_roots:\n  - $top\n';

    Future<Directory> linkedTopFixture(String top, String target) async {
      final root = await fixture({
        '.specstone/config.yaml': listing(top),
        '$top/keep.txt': 'x\n',
        'vendor/shared/keep.txt': 'x\n',
        'other/shared/keep.txt': 'x\n',
      });
      createRelativeLink('${root.path}/$top/.codex', target);
      return root;
    }

    for (final (top, target, written) in [
      ('vendor', 'shared', 'vendor/shared/hooks.json'),
      ('vendor', '../other/shared', 'other/shared/hooks.json'),
    ]) {
      test('a resumed run whose journal creates the hooks file of a listed '
          'top through its linked .codex folder to $target prints the '
          'line', () async {
        final Directory root;
        try {
          root = await linkedTopFixture(top, target);
        } on FileSystemException {
          markTestSkipped('symbolic links need privileges on this machine');
          return;
        }
        writeJournal(root, [
          CreateStep(written, codexHooksFileText),
          CommitStep(
            message: 'agent files',
            paths: [written],
            base: headOf(root),
          ),
        ]);
        final out = StringBuffer();

        expect(await _run(root, out), 0);

        final lines = out.toString().trim().split('\n');
        expect(lines[lines.length - 2], _trustLine);
        expect(lines.last, matches(checkLine));
      }, skip: hasGit ? null : 'git is not available');
    }

    test('a resumed run whose journal lists a top and creates its hooks '
        'file through a linked .codex folder prints the line', () async {
      final root = await fixture({'vendor/shared/keep.txt': 'x\n'});
      try {
        createRelativeLink('${root.path}/vendor/.codex', 'shared');
      } on FileSystemException {
        markTestSkipped('symbolic links need privileges on this machine');
        return;
      }
      writeJournal(root, [
        WriteStep(
          '.specstone/config.yaml',
          listing('vendor'),
          before: textHashOf(shippedPinsConfig()),
        ),
        CreateStep('vendor/shared/hooks.json', codexHooksFileText),
        CommitStep(
          message: 'agent files',
          paths: const ['.specstone/config.yaml', 'vendor/shared/hooks.json'],
          base: headOf(root),
        ),
      ]);
      final out = StringBuffer();

      expect(await _run(root, out), 0);

      final lines = out.toString().trim().split('\n');
      expect(lines[lines.length - 2], _trustLine);
      expect(lines.last, matches(checkLine));
    }, skip: hasGit ? null : 'git is not available');

    test('a resumed run whose journal holds no hooks file prints no '
        'line', () async {
      final root = await fixture({'keep.txt': 'x\n'});
      writeJournal(root, [
        const CreateStep('docs/notes.md', 'note\n'),
        CommitStep(
          message: 'notes',
          paths: const ['docs/notes.md'],
          base: headOf(root),
        ),
      ]);
      final out = StringBuffer();

      expect(await _run(root, out), 0);

      expect(out.toString(), isNot(contains(_trustLine)));
      expect(File('${root.path}/docs/notes.md').existsSync(), isTrue);
    }, skip: hasGit ? null : 'git is not available');
  });

  test('a dry run over a journal that does not '
      'parse refuses as bare migrate does', () async {
    final root = (await upgradeFixture()).project;
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
    final root = (await upgradeFixture()).project;
    final out = StringBuffer();

    expect(await _run(root, out, dryRun: true), 0);

    final text = out.toString();
    final lines = text.split('\n');
    expect(lines[lines.length - 2], 'dry run: nothing written');
    final planLine = lines[lines.length - 3];
    final plan = text.substring(0, text.lastIndexOf(planLine));
    expect(plan, startsWith('pack upgrade: '));
    final inputs = planUpgradeRun(
      root,
      templates: TemplateResolver(),
      homeDirectory: testHome(),
      generators: shippedGenerators(),
    ).inputs;
    expect(planLine, 'plan ${planHashOf(plan, inputs)}');
  }, skip: hasGit ? null : 'git is not available');

  group('a dry run on a dirty tree', () {
    const dirtyLine =
        'dry run: nothing written; the run needs a clean working tree';

    test('prints the plan, its hash line, and the dirty-tree line, exits 0, '
        'and writes nothing', () async {
      final root = (await upgradeFixture()).project;
      File('${root.path}/notes.txt').writeAsStringSync('x\n');
      final before = _bytesUnder(root);
      final head = headOf(root);
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      final lines = out.toString().split('\n');
      expect(out.toString(), startsWith('pack upgrade: '));
      expect(lines[lines.length - 2], dirtyLine);
      expect(lines[lines.length - 3], matches(RegExp(r'^plan [0-9a-f]{12}$')));
      expect(_bytesUnder(root), before);
      expect(headOf(root), head);
    }, skip: hasGit ? null : 'git is not available');

    test('hashes the files as they are, edits not yet committed '
        'included', () async {
      final root = (await upgradeFixture()).project;
      final clean = await _dryRunPlanHash(root);
      File('${root.path}/$acmeRunbookPath').writeAsStringSync('edited\n');
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      final text = out.toString();
      final planLine = 'plan ${_planHashIn(text)}\n';
      final plan = text.substring(0, text.lastIndexOf(planLine));
      final inputs = planUpgradeRun(
        root,
        templates: TemplateResolver(),
        homeDirectory: testHome(),
        generators: shippedGenerators(),
      ).inputs;
      expect(_planHashIn(text), planHashOf(plan, inputs));
      expect(_planHashIn(text), isNot(clean));
    }, skip: hasGit ? null : 'git is not available');

    test('a clean tree prints the plain last line', () async {
      final root = (await upgradeFixture()).project;
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      expect(out.toString(), endsWith('\ndry run: nothing written\n'));
      expect(out.toString(), isNot(contains('clean working tree')));
    }, skip: hasGit ? null : 'git is not available');

    test('--plan with its hash is still working_tree_dirty and writes '
        'nothing', () async {
      final root = (await upgradeFixture()).project;
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
      acmeInTestHome();
      final root = await writeTree(upgradeFiles());
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
      acmeInTestHome();
      final root = await writeTree(upgradeFiles());
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
      final dirty = (await upgradeFixture()).project;
      File('${dirty.path}/notes.txt').writeAsStringSync('x\n');
      final outside = await writeTree(upgradeFiles());

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
    final root = (await upgradeFixture()).project;
    final hash = await _dryRunPlanHash(root);
    File('${root.path}/$acmeRunbookPath').writeAsStringSync('later\n');
    commitAll(root, 'edit a doc');
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
          MigrateFaultCode.planMismatch,
        ),
      ),
    );
    expect(_bytesUnder(root), before);
    expect(headOf(root), head);
  }, skip: hasGit ? null : 'git is not available');

  test('a commit that touches no input '
      'between the dry run and --yes leaves the plan hash, so --yes '
      'applies', () async {
    final root = (await upgradeFixture()).project;
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
    final root = (await upgradeFixture()).project;
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
        generators: shippedGenerators(),
      ),
    );

    expect(status, 0);
    expect(out.toString(), startsWith('pack upgrade: '));
    expect(out.toString(), isNot(contains('apply? [y/N] ')));
    final subjects = (git(root, ['log', '--format=%s']).stdout as String)
        .trim()
        .split('\n');
    expect(subjects, [_commit2Message, _commit1Message, _fixtureSubject]);
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: hasGit ? null : 'git is not available');

  for (final (label, planHash) in [
    ('a plan changed since the dry run', '000000000000'),
    ('no plan hash', null),
  ]) {
    test('--yes with $label prints the plan, refuses plan_mismatch, '
        'exit 75, and writes nothing', () async {
      final root = (await upgradeFixture()).project;
      final before = _bytesUnder(root);
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
      expect(out.toString(), startsWith('pack upgrade: '));
      expect(_bytesUnder(root), before);
      expect(headOf(root), head);
    }, skip: hasGit ? null : 'git is not available');
  }

  test('no interactive terminal prints the '
      'plan, then refuses owner_terminal_required, exit 77', () async {
    final root = (await upgradeFixture()).project;
    final before = _bytesUnder(root);
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
    expect(out.toString(), startsWith('pack upgrade: '));
    expect(out.toString(), endsWith('.specstone/config.yaml: acme 1.1.0\n'));
    expect(_bytesUnder(root), before);
  }, skip: hasGit ? null : 'git is not available');

  test('a plan refusal in bare migrate comes after the git '
      'checks', () async {
    const collidingRunbook = '$acmeRunbookText\n## Procedure\n\nHeld.\n';
    final clean = (await upgradeFixture(
      files: {acmeRunbookPath: collidingRunbook},
    )).project;
    final out = StringBuffer();

    await expectLater(
      () => _run(clean, out),
      throwsA(
        isA<MigrateFault>().having(
          (f) => f.code,
          'code',
          MigrateFaultCode.upgradeCollision,
        ),
      ),
    );
    expect(out.toString(), isEmpty);

    final dirty = (await upgradeFixture(
      files: {acmeRunbookPath: collidingRunbook},
    )).project;
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

  test('a dangling override and an upgrade collision refuse in the dry run '
      'and in bare migrate, with nothing printed or written', () async {
    final UpgradeFixture(project: dangling, home: danglingHome) =
        await upgradeFixture();
    File('${dangling.path}/.specstone/templates/ghost.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'id: ghost\nsections:\n  - {id: body, header: Body}\n',
      );
    commitAll(dangling, 'ghost');
    final UpgradeFixture(:project, :home) = await upgradeFixture();
    File('${project.path}/docs/prds/runbooks/deploy/RUNBOOK.md')
        .writeAsStringSync(
          '# Deploy\n\n## Steps\n\nRun it.\n\n'
          '## Procedure\n\nHeld.\n',
        );
    commitAll(project, 'collide');
    final cases = [
      (
        root: dangling,
        home: danglingHome,
        code: MigrateFaultCode.overrideDangling,
      ),
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

  test('a plan that moves no file journals one commit', () {
    final plan = RunPlan(
      header: 'pack upgrade: x',
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
    final root = await _spacedUpgradeFixture(upgradeFiles());
    acmeInTestHome();
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
              generators: shippedGenerators(),
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
          generators: shippedGenerators(),
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
          'proj/.specstone/config.yaml': _upgradeConfig(
            'code_root: ../mono/services/api\n',
          ),
          'mono/services/api/main.dart': 'void main() {}\n',
        }, other: 'mono');
        final project = Directory('${base.path}/proj');
        final home = await acmeHome();
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
          await _run(
            project,
            dryOut,
            home: home,
            dryRun: true,
            warnings: dryWarnings,
          ),
          0,
        );
        expect(
          await _run(
            project,
            out,
            home: home,
            answers: ['y'],
            warnings: warnings,
          ),
          0,
        );

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

    group('a root '
        'AGENTS.md that is a link', () {
      test(
        'to the AGENTS.md of a top outside the project is named and '
        'left, and the run finishes with no agent write',
        () async {
          final base = await _twoRepositories(
            {
              'proj/.specstone/config.yaml': _upgradeConfig(
                'code_root: ../app\n',
              ),
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
            home: await acmeHome(),
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

      test('a linked .specstone/AGENT.md leading outside the project is '
          'named and left, and the file outside keeps its bytes', () async {
        final base = await _twoRepositories(
          {
            'proj/.specstone/config.yaml': _upgradeConfig(),
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
            home: await acmeHome(),
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
      final root = (await upgradeFixture()).project;
      _stopAfterCommit1(root);
      expect(hasDoc(root, 'prds/runbooks/deploy/RUNBOOK.md'), isFalse);
      expect(hasDoc(root, 'prds/ops/deploy/RUNBOOK.md'), isTrue);
      expect(
        File('${root.path}/.specstone/config.yaml').readAsStringSync(),
        contains('acme: 1.0.0'),
      );
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
          generators: shippedGenerators(),
        ),
      );

      expect(status, 0);
      final subjects = (git(root, ['log', '--format=%s']).stdout as String)
          .trim()
          .split('\n');
      expect(subjects, [_commit2Message, _commit1Message, _fixtureSubject]);
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
      final root = (await upgradeFixture(files: {'CLAUDE.md': _staleClaude}))
          .project;
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
      expect(
        File('${root.path}/.specstone/config.yaml').readAsStringSync(),
        contains('acme: 1.1.0'),
      );
    }, skip: skipGit);

    test('--dry-run lists the remaining steps and writes '
        'nothing', () async {
      final root = (await upgradeFixture()).project;
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
      expect(lines, contains('  write $acmeMovedRunbookPath'));
      expect(lines.last, 'dry run: nothing written');
      expect(headOf(root), head);
      expect(
        File('${root.path}/${MoveJournal.journalPath}').readAsStringSync(),
        journal,
      );
    }, skip: skipGit);

    test('bare migrate with no terminal lists the '
        'remaining steps and exits 77', () async {
      final root = (await upgradeFixture()).project;
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
      expect(out.toString(), contains('  write $acmeMovedRunbookPath\n'));
      expect(headOf(root), head);
      expect(MoveJournal.pending(root), isTrue);
    }, skip: skipGit);

    test("--yes with the dry run's plan hash finishes the stopped "
        'run with no terminal', () async {
      final root = (await upgradeFixture()).project;
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
      final root = (await upgradeFixture()).project;
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
      final root = (await upgradeFixture()).project;
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
      final root = (await upgradeFixture()).project;
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
      expect(subjects, [_commit2Message, _commit1Message, _fixtureSubject]);
      expect(MoveJournal.pending(root), isFalse);
    }, skip: Platform.isWindows ? 'the hook is a sh script' : skipGit);

    test('a resume commits only its own paths and leaves '
        "the Owner's staged change staged", () async {
      final root = (await upgradeFixture()).project;
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
      final root = (await upgradeFixture()).project;
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
      final root = (await upgradeFixture()).project;
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
            generators: shippedGenerators(),
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
      final root = (await upgradeFixture()).project;
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
            generators: shippedGenerators(),
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
      final root = (await upgradeFixture()).project;

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
            generators: shippedGenerators(),
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
      acmeRunbookPath,
      'replaced\n',
      before: textHashOf(acmeRunbookText),
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
        final root = (await upgradeFixture()).project;
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
        final root = (await upgradeFixture()).project;
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
      final root = (await upgradeFixture()).project;
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
      final root = (await upgradeFixture()).project;
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
      final root = (await upgradeFixture()).project;

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
      final root = (await upgradeFixture()).project;
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
      final root = (await upgradeFixture()).project;
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
      final root = (await upgradeFixture()).project;
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
      final root = (await upgradeFixture()).project;
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
      final linked = await linkedUpgradeFixture();
      if (linked == null) return;
      final calls = <List<String>>[];
      final out = StringBuffer();

      await expectLater(
        () => _run(linked.code, out, dryRun: true, runGit: _fakeGit(calls)),
        trustRefusal(),
      );
      expect(calls, isEmpty);
      expect(out.toString(), isEmpty);
    });

    test('a resume dry run over a dirty tree prints the '
        'remaining steps and a plan line', () async {
      final root = (await upgradeFixture()).project;
      _stopAfterCommit1(root);
      File('${root.path}/notes.txt').writeAsStringSync('x\n');
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      expect(out.toString(), contains('remaining steps:'));
      expect(out.toString(), contains('\nplan '));
    }, skip: skipGit);

    test('a resume dry run --json holds dirty false', () async {
      final root = (await upgradeFixture()).project;
      _stopAfterCommit1(root);
      File('${root.path}/notes.txt').writeAsStringSync('x\n');
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true, asJson: true), 0);

      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['dirty'], isFalse);
    }, skip: skipGit);

    test('a dry run over a pending journal refuses '
        'untrusted roots first and replays nothing', () async {
      final linked = await linkedUpgradeFixture();
      if (linked == null) return;
      final LinkedUpgradeFixture(:project, :code) = linked;
      final calls = <List<String>>[];
      _writeF02Journal(project);
      final journal = File('${project.path}/${MoveJournal.journalPath}');
      final before = journal.readAsStringSync();

      await expectLater(
        () => _run(code, StringBuffer(), dryRun: true, runGit: _fakeGit(calls)),
        trustRefusal(),
      );

      expect(calls, isEmpty);
      expect(journal.readAsStringSync(), before);
    });

    test('a dry run over a pending journal with a step '
        'left replays nothing and refuses before any git call', () async {
      final root = (await upgradeFixture()).project;
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
        File('${root.path}/$acmeRunbookPath').readAsStringSync(),
        acmeRunbookText,
      );
    }, skip: skipGit);

    Matcher refusesWith(MigrateFaultCode code) =>
        throwsA(isA<MigrateFault>().having((f) => f.code, 'code', code));

    test('a dry run over a pending journal whose step '
        'is applied plans the tree as it stands and names it dirty', () async {
      final root = (await upgradeFixture(
        files: {
          '.specstone/.gitignore': '${specstoneGitignoreLines.join('\n')}\n',
        },
      )).project;
      _writeF02Journal(root);
      File('${root.path}/$acmeRunbookPath').writeAsStringSync('replaced\n');
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
      final root = (await upgradeFixture(
        files: {
          acmeRunbookPath: 'replaced\n',
          '.specstone/.gitignore': '${specstoneGitignoreLines.join('\n')}\n',
        },
      )).project;
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
      const first = acmeRunbookPath;
      const second = 'docs/prds/notes.md';
      const secondText = '# Notes\n';
      for (final (:cursor, :secondDone, :refuses) in [
        (cursor: 1, secondDone: false, refuses: true),
        (cursor: 1, secondDone: true, refuses: false),
        (cursor: 2, secondDone: false, refuses: false),
      ]) {
        final root = (await upgradeFixture(
          files: {
            first: replaced,
            second: secondDone ? replaced : secondText,
            '.specstone/.gitignore': '${specstoneGitignoreLines.join('\n')}\n',
          },
        )).project;
        writeJournal(root, [
          WriteStep(first, replaced, before: textHashOf(acmeRunbookText)),
          WriteStep(second, replaced, before: textHashOf(secondText)),
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
      final linked = await linkedUpgradeFixture(commit: true);
      if (linked == null) return;
      final LinkedUpgradeFixture(project: ws, :code) = linked;
      _stopAfterCommit1(ws);
      final calls = <List<String>>[];
      final out = StringBuffer();

      await expectLater(
        () => _run(code, out, dryRun: true, runGit: _fakeGit(calls)),
        trustRefusal(),
      );

      expect(calls, isEmpty);
      expect(out.toString(), isEmpty);
    }, skip: skipGit);

    test('a resume dry run under git '
        '2.24 refuses git_work_tree_required and names 2.25', () async {
      final root = (await upgradeFixture()).project;
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
      test('over a dirty tree prints the '
          'plan and names the clean tree the run needs', () async {
        final UpgradeFixture(project: root, :home) = await upgradeFixture();
        File('${root.path}/notes.txt').writeAsStringSync('x\n');
        final out = StringBuffer();

        expect(await _run(root, out, home: home, dryRun: true), 0);

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
        final UpgradeFixture(project: root, :home) = await upgradeFixture();
        final out = StringBuffer();

        await expectLater(
          () => _run(
            root,
            out,
            home: home,
            dryRun: true,
            runGit: _fakeGit([], outsideWorkTree: true),
          ),
          gitRefusal(),
        );

        expect(out.toString(), isEmpty);
      }, skip: skipGit);

      test('under git 2.24 refuses '
          'git_work_tree_required and names 2.25', () async {
        final UpgradeFixture(project: root, :home) = await upgradeFixture();
        final out = StringBuffer();

        await expectLater(
          () => _run(
            root,
            out,
            home: home,
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
      final root = (await upgradeFixture(files: {'.gitignore': '*.log\n'}))
          .project;
      File('${root.path}/build.log').writeAsStringSync('x\n');
      final out = StringBuffer();

      expect(await _run(root, out, dryRun: true), 0);

      expect(out.toString(), endsWith('dry run: nothing written\n'));
    }, skip: skipGit);

    test('an untracked file counts whatever the git '
        'configuration hides', () async {
      final root = (await upgradeFixture()).project;
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

    test('--json with nothing to migrate prints the plan object with '
        'warnings', () async {
      final root = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(),
        '.claude/settings.local.json':
            '{"enabledPlugins": {"specstone@specstone": true}}',
      });
      final out = StringBuffer();
      final warnings = <String>[];

      expect(
        await _run(
          root,
          out,
          asJson: true,
          warnings: warnings,
          warningLog: <String>[],
        ),
        0,
      );

      final object = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(object['plan'], 'nothing to migrate\n');
      expect(object.keys, contains('formatLayout'));
      expect(object['formatLayout'], <Object?>[]);
      expect(object.keys, isNot(contains('dirty')));
      expect(object['warnings'], [
        startsWith(
          'specstone: the Specstone plugin for Claude Code is still on',
        ),
      ]);
      expect(object.keys.last, 'warnings');
      expect(warnings, isEmpty);
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
      // A personal pack pin would need the home folder this run lacks.
      final linked = await linkedUpgradeFixture(files: _agentOnlyFiles());
      if (linked == null) return;
      final LinkedUpgradeFixture(:tree, project: ws, :code) = linked;
      final before = treeBytes(ws);
      final out = StringBuffer();

      await expectLater(
        () => runMigrate(
          MigrateRequest(
            workingDirectory: code,
            homeDirectory: null,
            templates: TemplateResolver(),
            dryRun: false,
            confirmation: OwnerConfirmation.prompt,
            readLine: () => throw StateError('the refusal comes first'),
            out: out,
            generators: shippedGenerators(),
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
          files: {..._agentOnlyFiles(), settingsFilePath: '{"hooks": []}'},
          confirmation: OwnerConfirmation.prompt,
          matcher: isA<MigrateFault>().having(
            (f) => f.code,
            'code',
            MigrateFaultCode.agentBlockMalformed,
          ),
        ),
        'no interactive terminal': (
          files: _agentOnlyFiles(),
          confirmation: OwnerConfirmation.missing,
          matcher: isA<WriteFault>().having(
            (f) => f.code,
            'code',
            WriteFaultCode.ownerTerminalRequired,
          ),
        ),
        'a stale plan hash under --yes': (
          files: _agentOnlyFiles(),
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
              generators: shippedGenerators(),
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
      final linked = await linkedUpgradeFixture();
      if (linked == null) return;
      final LinkedUpgradeFixture(:tree, project: ws, :code) = linked;
      _writeF02Journal(ws);
      final before = treeBytes(ws);
      final calls = <List<String>>[];
      final out = StringBuffer();

      await expectLater(
        () => _run(code, out, answers: ['y'], runGit: _fakeGit(calls)),
        _untrustedRefusal(tree),
      );

      expect(calls, isEmpty);
      expect(out.toString(), isEmpty);
      expect(treeBytes(ws), before);
      expect(MoveJournal.pending(ws), isTrue);
    });

    test('a write command refuses to replay a pending journal, leaves it, and '
        'changes nothing', () async {
      final linked = await linkedUpgradeFixture(
        files: {'.specstone/config.yaml': shippedPinsConfig()},
      );
      if (linked == null) return;
      final LinkedUpgradeFixture(:tree, project: ws, :code) = linked;
      _writeF02Journal(ws);
      final journal = File('${ws.path}/${MoveJournal.journalPath}');
      final journalBytes = journal.readAsBytesSync();
      final before = _bytesUnder(ws);

      await expectLater(
        () => writeIn(code, (session) {}),
        _untrustedRefusal(tree),
      );

      // Opening the project makes the index `.gitignore`, as any read does.
      expect(_bytesUnder(ws)..remove('.specstone/.gitignore'), before);
      expect(journal.readAsBytesSync(), journalBytes);
    });

    test('a write command refuses a pending migrate journal in a tree whose '
        'config is not written yet, and leaves it', () async {
      final root = await writeTree({'docs/prds/PROJECT.md': '# Project\n'});
      writeJournal(root, [
        const MoveStep('docs/prds/a.md', 'docs/prds/b.md'),
        const CommitStep(message: 'move', paths: ['a'], base: 'abc'),
      ]);
      expect(File('${root.path}/.specstone/config.yaml').existsSync(), isFalse);
      final journal = File('${root.path}/${MoveJournal.journalPath}');
      final journalBytes = journal.readAsBytesSync();

      expect(
        () => writeIn(root, (session) {}),
        throwsA(
          isA<WriteFault>()
              .having((f) => f.code, 'code', WriteFaultCode.migratePending)
              .having((f) => f.exitStatus, 'exit', 75)
              .having((f) => f.file, 'file', MoveJournal.journalPath),
        ),
      );

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
        final linked = await linkedUpgradeFixture();
        if (linked == null) return;
        final LinkedUpgradeFixture(:tree, project: ws, :code) = linked;
        write(ws);
        final before = treeBytes(ws);
        final calls = <List<String>>[];
        final out = StringBuffer();

        await expectLater(
          () => _run(code, out, dryRun: true, runGit: _fakeGit(calls)),
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
        final linked = await linkedUpgradeFixture(commit: true);
        if (linked == null) return;
        final LinkedUpgradeFixture(:tree, project: ws, :code) = linked;
        _stopAfterCommit1(ws);
        final before = treeBytes(ws);
        final head = headOf(ws);
        final calls = <List<String>>[];
        final out = StringBuffer();

        await expectLater(
          () => _run(code, out, runGit: _fakeGit(calls)),
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
}

/// Writes a pending F-02 journal, one write step and no commit, at [root].
void _writeF02Journal(Directory root) => writeJournal(root, [
  WriteStep(acmeRunbookPath, 'replaced\n', before: textHashOf(acmeRunbookText)),
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

/// Leaves [root] as a crash after commit 1 of the upgrade plan does: the
/// journal saved, its steps applied through the first commit.
void _stopAfterCommit1(Directory root) {
  final steps = planUpgradeRun(
    root,
    templates: TemplateResolver(),
    homeDirectory: testHome(),
    generators: shippedGenerators(),
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
    trust: trustOf(root),
  );
  for (final step in steps) {
    step.apply(target);
    if (step is CommitStep) break;
  }
}
