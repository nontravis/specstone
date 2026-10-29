import 'dart:io';

import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';

/// Refuses a [root] outside a git work tree with no first commit.
///
/// Throws `MigrateFault` `git_work_tree_required` when `git` cannot start,
/// `git rev-parse --is-inside-work-tree` does not print `true`, or HEAD names
/// no commit.
void requireGitWorkTree(Directory root, RunGit runGit) {
  final bool inside;
  final bool hasHead;
  try {
    final insideResult = runGit([
      'rev-parse',
      '--is-inside-work-tree',
    ], workingDirectory: root.path);
    inside =
        insideResult.exitCode == 0 &&
        (insideResult.stdout as String).trim() == 'true';
    hasHead =
        inside &&
        runGit([
              'rev-parse',
              '--verify',
              '-q',
              'HEAD',
            ], workingDirectory: root.path).exitCode ==
            0;
  } on ProcessException {
    throw _workTreeRequired();
  }
  if (!inside || !hasHead) throw _workTreeRequired();
}

MigrateFault _workTreeRequired() => MigrateFault(
  MigrateFaultCode.gitWorkTreeRequired,
  'the project is not in a git work tree with a first commit; put the '
  'project under git, git init and a first commit, then run specstone '
  'migrate again',
);

/// Refuses a [root] whose work tree holds an uncommitted change (PD12).
///
/// Untracked files count; ignored ones do not. `s05_errors.md` names no code
/// for a `git status` that fails, so that case is `git_work_tree_required`.
void requireCleanWorkTree(Directory root, RunGit runGit) {
  final ProcessResult status;
  try {
    status = runGit(['status', '--porcelain'], workingDirectory: root.path);
  } on ProcessException {
    throw _workTreeRequired();
  }
  if (status.exitCode != 0) throw _workTreeRequired();
  if ((status.stdout as String).trim().isNotEmpty) {
    throw MigrateFault(
      MigrateFaultCode.workingTreeDirty,
      'the repository that holds the docs has uncommitted changes; commit or '
      'stash them, then run specstone migrate again',
    );
  }
}

/// Returns the full sha HEAD points at.
String headSha(Directory root, RunGit runGit) =>
    (runGit(['rev-parse', 'HEAD'], workingDirectory: root.path).stdout
            as String)
        .trim();

/// Returns every commit from [base] to HEAD, oldest first.
List<({String sha, String subject})> commitsSince(
  Directory root,
  String base,
  RunGit runGit,
) {
  final log = runGit([
    'log',
    '--reverse',
    '--format=%h%x09%s',
    '$base..HEAD',
  ], workingDirectory: root.path);
  return [
    for (final line in (log.stdout as String).trim().split('\n'))
      if (line.isNotEmpty)
        () {
          final tab = line.indexOf('\t');
          return (
            sha: line.substring(0, tab),
            subject: line.substring(tab + 1),
          );
        }(),
  ];
}
