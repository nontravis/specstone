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

/// The first git that refuses a bare repository found by walking up, which
/// `runRealGit` asks for with `safe.bareRepository=explicit`.
const ({int major, int minor}) _gitExplicitBare = (major: 2, minor: 38);

/// The version `git --version` prints, as `git version 2.39.3 (Apple Git-145)`
/// or `git version 2.45.1.windows.1` do.
final _gitVersion = RegExp(r'^git version ((\d+)\.(\d+)\S*)');

/// Refuses a [root] outside a git work tree with no first commit, or a git
/// older than 2.25.
///
/// Throws `MigrateFault` `git_work_tree_required` when `git` cannot start,
/// `git --version` names a version below 2.25, a git before 2.38 reports a git
/// dir that is not the `.git` of its work tree (or of a linked work tree),
/// `git rev-parse --is-inside-work-tree` does not print `true`, or HEAD names
/// no commit. A version line it cannot read passes the floor.
void requireGitWorkTree(Directory root, RunGit runGit) {
  final bool inside;
  final bool hasHead;
  try {
    final version = _requireGitFloor(root, runGit);
    if (version == null || _isBelow(version, _gitExplicitBare)) {
      _requireOwnGitDir(root, runGit);
    }
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

/// Returns the version `git --version` names, or null when the line cannot be
/// read.
///
/// Throws `git_work_tree_required` when that version is below [_gitFloor].
({int major, int minor})? _requireGitFloor(Directory root, RunGit runGit) {
  final printed = runGit(['--version'], workingDirectory: root.path).stdout;
  final match = _gitVersion.firstMatch('$printed'.trim());
  if (match == null) return null;
  final version = (major: int.parse(match[2]!), minor: int.parse(match[3]!));
  if (!_isBelow(version, _gitFloor)) return version;
  throw MigrateFault(
    MigrateFaultCode.gitWorkTreeRequired,
    'specstone migrate needs git ${_gitFloor.major}.${_gitFloor.minor} or '
    'later, and this git is ${match[1]}; upgrade git, then run specstone '
    'migrate again',
  );
}

bool _isBelow(({int major, int minor}) version, ({int major, int minor}) of) =>
    version.major < of.major ||
    (version.major == of.major && version.minor < of.minor);

/// Throws `git_work_tree_required` unless the git dir of [root] is the `.git`
/// of its work tree or lies under a `.git/worktrees/` folder.
///
/// A git before 2.38 takes a committed folder laid out as a git dir as the
/// repository of [root] and runs the commands its config names. `git
/// rev-parse` reads that config without running any of them. A folder that
/// is no repository prints nothing and is left to the checks that follow.
void _requireOwnGitDir(Directory root, RunGit runGit) {
  final result = runGit([
    'rev-parse',
    '--absolute-git-dir',
    '--show-toplevel',
  ], workingDirectory: root.path);
  if (result.exitCode != 0) return;
  final lines = (result.stdout as String).trim().split('\n');
  if (lines.length != 2) throw workTreeRequiredFault();
  final (gitDir, topLevel) = (lines[0].trim(), lines[1].trim());
  if (gitDir == '$topLevel/.git' || _isLinkedWorkTreeDir(gitDir)) return;
  throw workTreeRequiredFault();
}

/// Whether the `/`-separated [gitDir] lies below a `.git/worktrees` folder.
bool _isLinkedWorkTreeDir(String gitDir) {
  final segments = gitDir.split('/');
  for (var i = 0; i < segments.length - 2; i++) {
    if (segments[i] == '.git' && segments[i + 1] == 'worktrees') return true;
  }
  return false;
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
