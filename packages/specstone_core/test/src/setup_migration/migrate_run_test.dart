import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/legacy_plan.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

const _commit1Message = 'move legacy docs to their new paths';
const _commit2Message =
    'rewrite titles, keys, and links; add project configuration';

/// The text of every file under [root] outside `.git` and the trash, keyed by
/// its `/`-separated path relative to [root].
Map<String, String> _bytesUnder(Directory root) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  final texts = <String, String>{};
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(prefix.length)
        .replaceAll(Platform.pathSeparator, '/');
    if (relative.startsWith('.git/') ||
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

int _run(
  Directory root,
  StringBuffer out, {
  bool interactive = true,
  List<String?> answers = const [],
  bool dryRun = false,
}) {
  var call = 0;
  return runMigrate(
    MigrateRequest(
      workingDirectory: root,
      homeDirectory: null,
      templates: TemplateResolver(),
      dryRun: dryRun,
      interactive: interactive,
      readLine: () => call++ < answers.length ? answers[call - 1] : null,
      out: out,
    ),
  );
}

void main() {
  test(
    'f06/us01/fr07, f06/us01/s1: y makes two commits, the first pure renames',
    () async {
      final root = await _spacedFixture(acmeLegacy);
      final out = StringBuffer();

      final status = _run(root, out, answers: ['y']);

      expect(status, 0);
      final subjects = (git(root, ['log', '--format=%s']).stdout as String)
          .trim()
          .split('\n');
      expect(subjects, [_commit2Message, _commit1Message, 'legacy']);
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
      final names =
          (git(root, ['show', '--name-only', '--format=', 'HEAD']).stdout
                  as String)
              .trim()
              .split('\n');
      expect(names.toSet(), {
        '.specstone/config.yaml',
        '.specstone/.gitignore',
        '.specstone/templates/gnfr.yaml',
        'docs/specs/TECH_STACK.md',
        'docs/prds/PROJECT.md',
        'docs/prds/FEATURES.md',
        'docs/prds/GNFR.md',
        'docs/prds/features/f01_login/FEATURE.md',
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md',
        'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
        'docs/specs/f01_login/ARCHITECTURE.md',
      });
      expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
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
            r'run specstone check to list what is left to fill\n$',
          ),
        ),
      );
      expect(out.toString(), startsWith('legacy migration: '));
    },
    skip: hasGit ? null : 'git is not available',
  );

  test('f06/us01/fr07/e02: one git reset undoes the run', () async {
    final root = await gitFixture(acmeLegacy);
    final legacy = _bytesUnder(root);
    final out = StringBuffer();

    expect(_run(root, out, answers: ['y']), 0);

    expect(git(root, ['reset', '-q', '--hard', 'HEAD~2']).exitCode, 0);
    expect(_bytesUnder(root), legacy);
    expect(
      File.fromUri(root.uri.resolve('.specstone/config.yaml')).existsSync(),
      isFalse,
    );
  }, skip: hasGit ? null : 'git is not available');

  test(
    'f06/us01/fr02/e07, f06/us01/fr06/e06: no moved or rewritten doc holds a '
    'draft key; TECH_STACK.md is a draft',
    () async {
      final root = await gitFixture(acmeLegacy);
      final out = StringBuffer();

      expect(_run(root, out, answers: ['y']), 0);

      for (final file in _bytesUnder(root).entries) {
        if (file.key == '.specstone/.gitignore') continue;
        if (file.key == 'docs/specs/TECH_STACK.md') continue;
        expect(file.value, isNot(contains('draft:')), reason: file.key);
      }
      expect(
        File.fromUri(root.uri.resolve('docs/specs/TECH_STACK.md'))
            .readAsStringSync(),
        startsWith('---\ndraft: true\n'),
      );
    },
    skip: hasGit ? null : 'git is not available',
  );

  test('f06/us01/fr07/e08: INDEX.md, the untyped files, and the container doc '
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

    expect(_run(root, out, answers: ['y']), 0);

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

  test(
    'f06/us01/fr02/e05, f06/us01/s3: any answer but y writes nothing',
    () async {
      for (final answer in ['n', '', 'yes', null]) {
        final root = await gitFixture(acmeLegacy);
        final legacy = _bytesUnder(root);
        final head = (git(root, ['rev-parse', 'HEAD']).stdout as String).trim();
        final out = StringBuffer();

        final status = _run(root, out, answers: [answer]);

        expect(status, 0, reason: 'answer $answer');
        expect(
          (git(root, ['rev-parse', 'HEAD']).stdout as String).trim(),
          head,
          reason: 'answer $answer',
        );
        expect(_bytesUnder(root), legacy, reason: 'answer $answer');
        expect(out.toString().contains('apply? [y/N] '), isTrue);
      }
    },
    skip: hasGit ? null : 'git is not available',
  );

  group('f06/us01/fr02/e04, final I1: a change while the Owner reads the '
      'plan', () {
    final skipGit = hasGit ? null : 'git is not available';

    /// Runs bare migrate on [root] at a terminal, running [meanwhile] while
    /// the prompt waits, then answering `y`.
    int answerAfter(
      Directory root,
      void Function() meanwhile, {
      Directory? home,
      StringSink? out,
    }) => runMigrate(
      MigrateRequest(
        workingDirectory: root,
        homeDirectory: home,
        templates: TemplateResolver(),
        dryRun: false,
        interactive: true,
        readLine: () {
          meanwhile();
          return 'y';
        },
        out: out ?? StringBuffer(),
      ),
    );

    test('f06/us01/fr02/e04: a doc edited before the y is '
        'working_tree_dirty, and the edit and the tree stay', () async {
      final root = await gitFixture(acmeLegacy);
      final head = headOf(root);
      final context = File('${root.path}/docs/prds/d01_context.md');

      expect(
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

    test('f06/us01/fr02/e04: a commit made before the y is '
        'working_tree_dirty, and nothing is written', () async {
      final root = await gitFixture(acmeLegacy);

      expect(
        () => answerAfter(root, () {
          File('${root.path}/notes.txt').writeAsStringSync('x\n');
          commitAll(root, 'meanwhile');
        }),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.workingTreeDirty)
              .having(
                (f) => f.message,
                'message',
                'the repository that holds the docs gained a commit while '
                    'the plan was shown; run specstone migrate again to plan '
                    'from it',
              ),
        ),
      );
      expect(_bytesUnder(root), {...acmeLegacy, 'notes.txt': 'x\n'});
      expect(MoveJournal.pending(root), isFalse);
    }, skip: skipGit);

    test('f06/us02/fr02: an upgrade doc edited before the y is '
        'working_tree_dirty, and the edit stays', () async {
      final (:project, :home) = await _upgradeFixture();
      final runbook = File(
        '${project.path}/docs/prds/runbooks/deploy/RUNBOOK.md',
      );
      final out = StringBuffer();

      expect(
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
  });

  test('f06/us01/fr07/e04, final M7: a dry run over a journal that does not '
      'parse refuses as bare migrate does', () async {
    final root = await gitFixture(acmeLegacy);
    File('${root.path}/${MoveJournal.journalPath}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{');

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
    expect(() => _run(root, dryOut, dryRun: true), refusal());
    expect(dryOut.toString(), isEmpty);
    expect(() => _run(root, StringBuffer(), answers: ['y']), refusal());
    expect(
      File('${root.path}/${MoveJournal.journalPath}').readAsStringSync(),
      '{',
    );
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us01/fr02/e02, f06/us01/s13: no interactive terminal prints the '
      'plan, then refuses owner_terminal_required, exit 77', () async {
    final root = await gitFixture(acmeLegacy);
    final legacy = _bytesUnder(root);
    final out = StringBuffer();

    expect(
      () => _run(root, out, interactive: false),
      throwsA(
        isA<WriteFault>()
            .having((f) => f.code, 'code', WriteFaultCode.ownerTerminalRequired)
            .having((f) => f.exitStatus, 'exit', 77)
            .having(
              (f) => f.message,
              'message',
              'migrate applies only at an interactive terminal; ask the '
                  'Owner to run specstone migrate',
            ),
      ),
    );
    expect(out.toString(), startsWith('legacy migration: '));
    expect(out.toString(), endsWith('specs/INDEX.md\n'));
    expect(_bytesUnder(root), legacy);
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us01/fr02/e06: a plan refusal in bare migrate comes after the git '
      'checks', () async {
    const duplicateWithContext = {
      ...duplicateGroupLegacy,
      'docs/prds/d01_context.md': '# D-01 — Context\n',
    };
    final clean = await gitFixture(duplicateWithContext);
    final out = StringBuffer();

    expect(
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

    expect(
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

  test('f06/us01/fr07/e01: a plan that moves no file journals one commit', () {
    const plan = RunPlan(
      header: 'legacy migration: x',
      moves: [],
      prunes: [],
      rewrites: [],
      creates: [],
      left: [],
      commit1Message: _commit1Message,
      commit2Message: _commit2Message,
    );

    final steps = plan.journalSteps(base: 'abc');

    expect(steps.whereType<CommitStep>(), hasLength(1));
    expect(steps.whereType<CommitStep>().single.message, _commit2Message);
  });

  test('f06/us01/fr01: a root whose path holds a space migrates; '
      'f06/us01/fr01/e04: migrate after an applied run prints nothing to '
      'migrate', () async {
    final root = await _spacedFixture(acmeLegacy);
    final out = StringBuffer();

    expect(_run(root, out, answers: ['y']), 0);
    expect(
      (git(root, ['rev-list', '--count', 'HEAD']).stdout as String).trim(),
      '3',
    );

    final again = StringBuffer();
    expect(_run(root, again), 0);
    expect(again.toString(), 'nothing to migrate\n');
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us01/fr07, f06/us01/fr03: a git-ignored file in a moved '
      'cross-cutting folder moves on disk and stays out of both '
      'commits', () async {
    final root = await gitFixture({...acmeLegacy, '.gitignore': '.DS_Store\n'});
    File('${root.path}/docs/specs/shared/.DS_Store')
        .writeAsStringSync('finder\n');
    final out = StringBuffer();

    expect(_run(root, out, answers: ['y']), 0);

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

  group('f06/us01/fr07: resume and replay', () {
    final skipGit = hasGit ? null : 'git is not available';

    test('f06/us01/fr07/e03, f06/us01/fr01/e07, f06/us01/s9: a run stopped '
        'after commit 1 finishes with no second y', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      expect(hasDoc(root, 'prds/d01_context.md'), isFalse);
      expect(File('${root.path}/.specstone/config.yaml').existsSync(), isFalse);
      final out = StringBuffer();

      final status = runMigrate(
        MigrateRequest(
          workingDirectory: root,
          homeDirectory: null,
          templates: TemplateResolver(),
          dryRun: false,
          interactive: true,
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
      expect(lines.last, 'run specstone check to list what is left to fill');
      expect(
        out.toString(),
        startsWith('pending migration: ${root.resolveSymbolicLinksSync()} '),
      );
    }, skip: skipGit);

    test('f06/us01/fr07/e04: --dry-run lists the remaining steps and writes '
        'nothing', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final head = headOf(root);
      final journal = File('${root.path}/${MoveJournal.journalPath}')
          .readAsStringSync();
      final out = StringBuffer();

      expect(_run(root, out, dryRun: true), 0);

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

    test('f06/us01/fr07/e05: bare migrate with no terminal lists the '
        'remaining steps and exits 77', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final head = headOf(root);
      final out = StringBuffer();

      expect(
        () => _run(root, out, interactive: false),
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

    test('f06/us01/fr07/e07: a pending F-02 journal is replayed, then the '
        'clean-tree check runs', () async {
      final files = {
        '.specstone/config.yaml': shippedPinsConfig(),
        'docs/prds/a.md': 'x\n',
      };
      final root = await gitFixture(files);
      writeJournal(root, [const MoveStep('docs/prds/a.md', 'docs/prds/b.md')]);

      expect(
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

      final dry = await gitFixture(files);
      writeJournal(dry, [const MoveStep('docs/prds/a.md', 'docs/prds/b.md')]);
      _run(dry, StringBuffer(), dryRun: true);
      expect(hasDoc(dry, 'prds/a.md'), isTrue);
      expect(hasDoc(dry, 'prds/b.md'), isFalse);
    }, skip: skipGit);

    test('f06/us01/fr07/e09: a commit a hook refuses stops the run, and the '
        'next migrate resumes it', () async {
      final root = await gitFixture(acmeLegacy);
      final hook = File('${root.path}/.git/hooks/pre-commit')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho "lint failed" >&2\nexit 1\n');
      expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);

      expect(
        () => _run(root, StringBuffer(), answers: ['y']),
        throwsA(
          isA<MigrateFault>()
              .having((f) => f.code, 'code', MigrateFaultCode.gitFailed)
              .having((f) => f.exitStatus, 'exit', 75)
              .having(
                (f) => f.message,
                'message',
                'git commit failed: lint failed; fix the cause, then run '
                    'specstone migrate at an interactive terminal to finish '
                    'the run',
              ),
        ),
      );
      expect(MoveJournal.pending(root), isTrue);

      hook.deleteSync();
      final out = StringBuffer();
      expect(_run(root, out), 0);

      final subjects = (git(root, ['log', '--format=%s']).stdout as String)
          .trim()
          .split('\n');
      expect(subjects, [_commit2Message, _commit1Message, 'legacy']);
      expect(MoveJournal.pending(root), isFalse);
    }, skip: Platform.isWindows ? 'the hook is a sh script' : skipGit);

    test('f06/us01/fr07/e09: a resume commits only its own paths and leaves '
        "the Owner's staged change staged", () async {
      final root = await gitFixture(acmeLegacy);
      final hook = File('${root.path}/.git/hooks/pre-commit')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho "lint failed" >&2\nexit 1\n');
      expect(Process.runSync('chmod', ['755', hook.path]).exitCode, 0);
      expect(
        () => _run(root, StringBuffer(), answers: ['y']),
        throwsA(isA<MigrateFault>()),
      );
      File('${root.path}/notes.txt').writeAsStringSync('mine\n');
      expect(git(root, ['add', 'notes.txt']).exitCode, 0);
      hook.deleteSync();

      expect(_run(root, StringBuffer()), 0);

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

    test('f06/us01/fr07/e03: the resume lists only the commits of the '
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

      expect(_run(root, out), 0);

      expect(out.toString(), isNot(contains('owner work')));
      expect(out.toString(), contains(': $_commit1Message\n'));
      expect(out.toString(), contains('commit 2 '));
    }, skip: skipGit);

    test('f06/us01/fr07/e09: git that cannot start during a resume is '
        'git_work_tree_required', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);

      expect(
        () => runMigrate(
          MigrateRequest(
            workingDirectory: root,
            homeDirectory: null,
            templates: TemplateResolver(),
            dryRun: false,
            interactive: true,
            readLine: () => null,
            out: StringBuffer(),
            runGit: (arguments, {required workingDirectory}) =>
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

    test('f06/us01/fr07, f06/us01/fr02/e03: a resume under a git older than '
        '2.25 is git_work_tree_required, and no step runs', () async {
      final root = await gitFixture(acmeLegacy);
      _stopAfterCommit1(root);
      final before = _bytesUnder(root);

      expect(
        () => runMigrate(
          MigrateRequest(
            workingDirectory: root,
            homeDirectory: null,
            templates: TemplateResolver(),
            dryRun: false,
            interactive: true,
            readLine: () => null,
            out: StringBuffer(),
            runGit: (arguments, {required workingDirectory}) =>
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

    test('f06/us01/fr07/e09: git that cannot start after the checks is '
        'git_failed naming the command, and the journal stays', () async {
      final root = await gitFixture(acmeLegacy);

      expect(
        () => runMigrate(
          MigrateRequest(
            workingDirectory: root,
            homeDirectory: null,
            templates: TemplateResolver(),
            dryRun: false,
            interactive: true,
            readLine: () => 'y',
            out: StringBuffer(),
            runGit: (arguments, {required workingDirectory}) =>
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
                    'at an interactive terminal to finish the run',
              ),
        ),
      );
      expect(MoveJournal.pendingMigrate(root), isTrue);
    }, skip: skipGit);
  });
}

/// Returns the full sha HEAD of [root] points at.
String headOf(Directory root) =>
    (git(root, ['rev-parse', 'HEAD']).stdout as String).trim();

/// Leaves [root] as a crash after commit 1 of the legacy plan does: the
/// journal saved, its steps applied through the first commit.
void _stopAfterCommit1(Directory root) {
  final steps = planLegacyRun(
    root,
    templates: TemplateResolver(),
    homeDirectory: null,
  ).journalSteps(base: headOf(root));
  final specstone = Directory('${root.path}/.specstone')
    ..createSync(recursive: true);
  ensureSpecstoneGitignore(specstone);
  Directory('${root.path}/${MoveJournal.trashPath}').createSync();
  writeJournal(root, steps);
  final target = JournalTarget(
    projectRoot: root,
    docsRoot: Directory('${root.path}/docs'),
  );
  for (final step in steps) {
    step.apply(target);
    if (step is CommitStep) break;
  }
}
