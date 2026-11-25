import 'dart:io';

import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/models/git_floor.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/setup_migration/models/git_commit.dart';

// `git log` prints these control characters for `%x01` and `%x02`; neither
// appears in a commit message.
const _commitStart = '\x01';
const _fieldSeparator = '\x02';

/// The oldest git whose `add` and `commit` take `--pathspec-from-file`, which
/// a migrate commit passes its paths through.
const _gitFloor = GitFloor(major: 2, minor: 25);

/// Refuses a [root] outside a git work tree with no first commit, or a git
/// older than 2.25.
///
/// Throws `MigrateFault` `git_work_tree_required` when `git` cannot start,
/// `git --version` names a version below 2.25, `git rev-parse
/// --is-inside-work-tree` does not print `true`, or HEAD names no commit. A
/// version line it cannot read passes.
void requireGitWorkTree(Directory root, RunGit runGit) {
  final bool inside;
  final bool hasHead;
  try {
    _requireGitFloor(root, runGit);
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
  } on ProcessException catch (e) {
    throw _gitCannotStartFault(e);
  }
  if (!inside || !hasHead) throw workTreeRequiredFault(migrateCommand);
}

/// Returns the work-tree fault with [error]'s reason added, so a user whose git
/// runs in their shell learns why Specstone could not start it.
MigrateFault _gitCannotStartFault(ProcessException error) {
  final fault = workTreeRequiredFault(migrateCommand);
  return MigrateFault(
    fault.code,
    '${fault.message}; git cannot start: ${error.message}',
  );
}

/// Throws `git_work_tree_required` when `git --version` names a version
/// below [_gitFloor].
void _requireGitFloor(Directory root, RunGit runGit) {
  final printed = runGit(['--version'], workingDirectory: root.path).stdout;
  final version = parseGitVersion('$printed');
  if (version == null || !isGitBelow(version, _gitFloor)) return;
  throw MigrateFault(
    MigrateFaultCode.gitWorkTreeRequired,
    'specstone migrate needs git ${_gitFloor.major}.${_gitFloor.minor} or '
    'later, and this git is ${version.text}; upgrade git, then run specstone '
    'migrate again',
  );
}

/// Refuses a [root] whose work tree holds an uncommitted change.
///
/// Throws `working_tree_dirty` as [isWorkTreeDirty] reads it.
void requireCleanWorkTree(Directory root, RunGit runGit) {
  if (!isWorkTreeDirty(root, runGit)) return;
  throw MigrateFault(
    MigrateFaultCode.workingTreeDirty,
    'the repository that holds the docs has uncommitted changes; commit or '
    'stash them, then run specstone migrate again',
  );
}

/// Returns whether the work tree of [root] holds an uncommitted change.
///
/// Untracked files count, whatever `status.showUntrackedFiles` says; ignored
/// ones do not. No other fault code covers a `git status` that fails, so that
/// case is `git_work_tree_required`.
bool isWorkTreeDirty(Directory root, RunGit runGit) {
  final ProcessResult status;
  try {
    status = runGit([
      'status',
      '--porcelain',
      '--untracked-files=normal',
    ], workingDirectory: root.path);
  } on ProcessException catch (e) {
    throw _gitCannotStartFault(e);
  }
  if (status.exitCode != 0) throw workTreeRequiredFault(migrateCommand);
  return (status.stdout as String).trim().isNotEmpty;
}

/// Returns the full sha HEAD points at.
String headSha(Directory root, RunGit runGit) =>
    (runGit(['rev-parse', 'HEAD'], workingDirectory: root.path).stdout
            as String)
        .trim();

/// Returns every commit from [base] to HEAD, oldest first.
///
/// `subject` is the first paragraph; `message` is the whole text.
List<GitCommit> commitsSince(Directory root, String base, RunGit runGit) {
  final log = runGit([
    'log',
    '--reverse',
    '--format=%x01%h%x02%s%x02%B',
    '$base..HEAD',
  ], workingDirectory: root.path);
  return [
    for (final record in (log.stdout as String).split(_commitStart))
      if (record.trim().isNotEmpty)
        () {
          final fields = record.split(_fieldSeparator);
          return GitCommit(
            sha: fields[0],
            subject: fields[1],
            message: fields[2],
          );
        }(),
  ];
}
