import 'dart:io';

import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/setup_migration/git_gate.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart';
import '../../helpers/temp_tree.dart';

/// A `RunGit` that throws `ProcessException`, as a missing `git` does.
ProcessResult _gitMissing(
  List<String> arguments, {
  required String workingDirectory,
}) => throw const ProcessException('git', []);

void main() {
  test('f06/us01/fr02/e03, f06/us01/s12: a folder outside git is '
      'git_work_tree_required', () async {
    final outside = await Directory.systemTemp.createTemp('specstone_test_');
    addTearDown(() => outside.delete(recursive: true));

    expect(
      () => requireGitWorkTree(outside, runRealGit),
      throwsA(
        isA<MigrateFault>()
            .having((f) => f.code, 'code', MigrateFaultCode.gitWorkTreeRequired)
            .having((f) => f.exitStatus, 'exit', 78)
            .having(
              (f) => f.message,
              'message',
              'the project is not in a git work tree with a first commit; '
                  'put the project under git, git init and a first commit, '
                  'then run specstone migrate again',
            ),
      ),
    );
  });

  test('f06/us01/fr02/e03: a repository with no commit is '
      'git_work_tree_required', () async {
    final root = await gitFixture(acmeLegacy);
    expect(git(root, ['update-ref', '-d', 'HEAD']).exitCode, 0);

    expect(
      () => requireGitWorkTree(root, runRealGit),
      throwsA(
        isA<MigrateFault>().having(
          (f) => f.code,
          'code',
          MigrateFaultCode.gitWorkTreeRequired,
        ),
      ),
    );
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us01/fr02/e03: git missing is git_work_tree_required', () async {
    final root = await writeTree(acmeLegacy);

    expect(
      () => requireGitWorkTree(root, _gitMissing),
      throwsA(
        isA<MigrateFault>().having(
          (f) => f.code,
          'code',
          MigrateFaultCode.gitWorkTreeRequired,
        ),
      ),
    );
  });

  test('f06/us01/fr02/e04, f06/us01/s11: an uncommitted change is '
      'working_tree_dirty', () async {
    final root = await gitFixture(acmeLegacy);

    File.fromUri(root.uri.resolve('docs/prds/d01_context.md'))
        .writeAsStringSync('# D-01 — Project context\n\nchanged\n');

    expect(
      () => requireCleanWorkTree(root, runRealGit),
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
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us01/fr02/e04, f06/us01/s11: an untracked file is '
      'working_tree_dirty', () async {
    final root = await gitFixture(acmeLegacy);

    File.fromUri(root.uri.resolve('notes.txt')).writeAsStringSync('x\n');

    expect(
      () => requireCleanWorkTree(root, runRealGit),
      throwsA(
        isA<MigrateFault>().having(
          (f) => f.code,
          'code',
          MigrateFaultCode.workingTreeDirty,
        ),
      ),
    );
  }, skip: hasGit ? null : 'git is not available');

  test('f06/us01/fr02/e04: a git status that fails is '
      'git_work_tree_required', () async {
    final root = await writeTree(acmeLegacy);
    ProcessResult failing(
      List<String> arguments, {
      required String workingDirectory,
    }) => ProcessResult(0, 128, '', 'fatal: not a git repository');

    expect(
      () => requireCleanWorkTree(root, failing),
      throwsA(
        isA<MigrateFault>().having(
          (f) => f.code,
          'code',
          MigrateFaultCode.gitWorkTreeRequired,
        ),
      ),
    );
  });

  test('f06/us01/fr07: headSha returns the full HEAD sha; commitsSince '
      'lists commits since a base with short shas', () async {
    final root = await gitFixture(acmeLegacy);
    final base = headSha(root, runRealGit);
    File.fromUri(root.uri.resolve('notes.txt')).writeAsStringSync('x\n');
    commitAll(root, 'second');
    final head = headSha(root, runRealGit);

    expect(base, matches(RegExp(r'^[0-9a-f]{40}$')));
    final commits = commitsSince(root, base, runRealGit);
    expect(commits, hasLength(1));
    expect(commits.single.subject, 'second');
    expect(head, startsWith(commits.single.sha));
    expect(commits.single.sha, matches(RegExp(r'^[0-9a-f]{7,}$')));
  }, skip: hasGit ? null : 'git is not available');
}
