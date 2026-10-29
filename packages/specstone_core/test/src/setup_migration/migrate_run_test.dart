import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/migrate_run.dart';
import 'package:specstone_core/src/setup_migration/run_plan.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart';
import '../../helpers/temp_tree.dart';

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
}
