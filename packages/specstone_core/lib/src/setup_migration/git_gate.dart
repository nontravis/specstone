import 'dart:io';

import 'package:specstone_core/src/git_process.dart';
import 'package:specstone_core/src/setup_migration/migrate_fault.dart';

// `git log` prints these control characters for `%x01` and `%x02`; neither
// appears in a commit message.
const _commitStart = '\x01';
const _fieldSeparator = '\x02';

/// The oldest git whose `add` and `commit` take `--pathspec-from-file`, which
/// a migrate commit passes its paths through.
const ({int major, int minor}) _gitFloor = (major: 2, minor: 25);

/// The version `git --version` prints, as `git version 2.39.3 (Apple Git-145)`
/// or `git version 2.45.1.windows.1` do.
final _gitVersion = RegExp(r'^git version ((\d+)\.(\d+)\S*)');

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
  } on ProcessException {
    throw workTreeRequiredFault();
  }
  if (!inside || !hasHead) throw workTreeRequiredFault();
}

/// Throws `git_work_tree_required` when `git --version` names a version
/// below [_gitFloor].
void _requireGitFloor(Directory root, RunGit runGit) {
  final printed = runGit(['--version'], workingDirectory: root.path).stdout;
  final match = _gitVersion.firstMatch('$printed'.trim());
  if (match == null) return;
  final major = int.parse(match[2]!);
  final minor = int.parse(match[3]!);
  final belowFloor =
      major < _gitFloor.major ||
      (major == _gitFloor.major && minor < _gitFloor.minor);
  if (!belowFloor) return;
  throw MigrateFault(
    MigrateFaultCode.gitWorkTreeRequired,
    'specstone migrate needs git ${_gitFloor.major}.${_gitFloor.minor} or '
    'later, and this git is ${match[1]}; upgrade git, then run specstone '
    'migrate again',
  );
}

/// Returns the fault for a project outside a git work tree with a first
/// commit, or whose `git` cannot run.
MigrateFault workTreeRequiredFault() => MigrateFault(
  MigrateFaultCode.gitWorkTreeRequired,
  'the project is not in a git work tree with a first commit; put the '
  'project under git, git init and a first commit, then run specstone '
  'migrate again',
);

/// Refuses a [root] whose work tree holds an uncommitted change (PD12).
///
/// Untracked files count, whatever `status.showUntrackedFiles` says; ignored
/// ones do not. `s05_errors.md` names no code for a `git status` that fails,
/// so that case is `git_work_tree_required`.
void requireCleanWorkTree(Directory root, RunGit runGit) {
  final ProcessResult status;
  try {
    status = runGit([
      'status',
      '--porcelain',
      '--untracked-files=normal',
    ], workingDirectory: root.path);
  } on ProcessException {
    throw workTreeRequiredFault();
  }
  if (status.exitCode != 0) throw workTreeRequiredFault();
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
///
/// `subject` is the first paragraph; `message` is the whole text.
List<({String sha, String subject, String message})> commitsSince(
  Directory root,
  String base,
  RunGit runGit,
) {
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
          return (sha: fields[0], subject: fields[1], message: fields[2]);
        }(),
  ];
}
