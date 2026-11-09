import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/setup_migration/migrate_fault.dart';

/// Runs `git` with [arguments] in [workingDirectory].
///
/// [environment] adds variables to the process environment, such as
/// `GIT_INDEX_FILE`.
typedef RunGit = ProcessResult Function(
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String>? environment,
});

/// The config that keeps `git` from taking a bare repository it finds by
/// walking up as the repository of the folder it runs in.
///
/// A committed folder laid out as a git dir would otherwise supply the
/// repository config (`core.fsmonitor`, `core.hooksPath`, filter drivers) and
/// have git run a command from it. A git before 2.38 ignores the key; see
/// [guardedGit].
const _explicitBareRepository = ['-c', 'safe.bareRepository=explicit'];

/// The first git that honours `safe.bareRepository`.
const ({int major, int minor}) _gitExplicitBare = (major: 2, minor: 38);

/// The version `git --version` prints, as `git version 2.39.3 (Apple Git-145)`
/// or `git version 2.45.1.windows.1` do.
final _gitVersion = RegExp(r'^git version ((\d+)\.(\d+)\S*)');

/// Returns the version a `git --version` line names, or null when it names
/// none; `text` is the full version, such as `2.39.3`.
({String text, int major, int minor})? parseGitVersion(String printed) {
  final match = _gitVersion.firstMatch(printed.trim());
  if (match == null) return null;
  return (
    text: match[1]!,
    major: int.parse(match[2]!),
    minor: int.parse(match[3]!),
  );
}

/// Whether [version] is older than [floor].
bool isGitBelow(
  ({String text, int major, int minor}) version,
  ({int major, int minor}) floor,
) =>
    version.major < floor.major ||
    (version.major == floor.major && version.minor < floor.minor);

/// Starts the real `git` program, run through [guardedGit]; the only code that
/// does.
ProcessResult runRealGit(
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String>? environment,
}) => _realGit(
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
);

final RunGit _realGit = guardedGit(_startGit);

/// Starts the real `git` program like [runRealGit], with the refusal of the
/// git dir check closing on `specstone migrate`, the command it refuses.
ProcessResult runMigrateGit(
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String>? environment,
}) => _migrateGit(
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
);

final RunGit _migrateGit = guardedGit(_startGit, command: migrateCommand);

ProcessResult _startGit(
  List<String> arguments, {
  required String workingDirectory,
  Map<String, String>? environment,
}) => Process.runSync(
  'git',
  [..._explicitBareRepository, ...arguments],
  workingDirectory: workingDirectory,
  environment: environment,
  stdoutEncoding: utf8,
);

/// The command a refusal tells the user to run again, when `migrate` is the one
/// that refused.
const migrateCommand = 'specstone migrate';

/// What a refusal tells the user to run again when no command name is known.
const _anyCommand = 'the command';

/// Returns a [RunGit] that starts git through [start] and, on a git before
/// 2.38, first checks that the repository git finds in the folder is that
/// folder's own.
///
/// A git before 2.38 ignores `safe.bareRepository` and takes a committed
/// folder laid out as a git dir as the repository of the folder it runs in,
/// then runs the commands its config names. `git rev-parse` reads that config
/// without running any of them, so each verb is preceded by one that prints
/// the git dir and the top level. The git dir must be the `.git` of that top
/// level, lie under a `.git/worktrees/` folder (a linked work tree), or under
/// a `.git/modules/` folder (a submodule). A folder in no repository prints
/// nothing and is left to the verb, which fails on its own; one in a bare
/// repository prints a git dir and no top level, and is refused.
///
/// Throws `MigrateFault` `git_work_tree_required` when the check refuses; its
/// text closes on `then run [command] again`, and [command] is `the command`
/// unless the caller names its own. `--version` runs unchecked, since it reads
/// no repository. A version line it cannot read counts as a git before 2.38.
RunGit guardedGit(RunGit start, {String command = _anyCommand}) {
  bool? checksGitDir;
  return (arguments, {required workingDirectory, environment}) {
    if (arguments.first != '--version') {
      checksGitDir ??= _isBefore238(start, workingDirectory, environment);
      if (checksGitDir!) {
        _requireOwnGitDir(start, workingDirectory, environment, command);
      }
    }
    return start(
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  };
}

bool _isBefore238(
  RunGit start,
  String workingDirectory,
  Map<String, String>? environment,
) {
  final printed = start(
    ['--version'],
    workingDirectory: workingDirectory,
    environment: environment,
  ).stdout;
  final version = parseGitVersion('$printed');
  return version == null || isGitBelow(version, _gitExplicitBare);
}

void _requireOwnGitDir(
  RunGit start,
  String workingDirectory,
  Map<String, String>? environment,
  String command,
) {
  final result = start(
    ['rev-parse', '--absolute-git-dir', '--show-toplevel'],
    workingDirectory: workingDirectory,
    environment: environment,
  );
  final printed = (result.stdout as String).trim();
  if (result.exitCode != 0) {
    if (printed.isEmpty) return;
    throw workTreeRequiredFault(command);
  }
  final lines = printed.split('\n');
  if (lines.length != 2) throw workTreeRequiredFault(command);
  final (gitDir, topLevel) = (lines[0].trim(), lines[1].trim());
  if (gitDir == '$topLevel/.git' || _isNestedGitDir(gitDir)) return;
  throw workTreeRequiredFault(command);
}

/// Whether the `/`-separated [gitDir] lies below a `.git/worktrees` or
/// `.git/modules` folder.
bool _isNestedGitDir(String gitDir) {
  final segments = gitDir.split('/');
  for (var i = 0; i < segments.length - 2; i++) {
    if (segments[i] == '.git' &&
        (segments[i + 1] == 'worktrees' || segments[i + 1] == 'modules')) {
      return true;
    }
  }
  return false;
}

/// Returns the fault for a project outside a git work tree with a first
/// commit, or whose `git` cannot run; it tells the user to run [command]
/// again.
MigrateFault workTreeRequiredFault(String command) => MigrateFault(
  MigrateFaultCode.gitWorkTreeRequired,
  'the project is not in a git work tree with a first commit; put the '
  'project under git, git init and a first commit, then run $command again',
);

/// A `git add` or `git commit` that exited non-zero.
final class GitCommandFailed implements Exception {
  const new(this.verb, this.line);

  /// The git verb that failed: `add` or `commit`.
  final String verb;

  /// The decisive line of git's stderr: its first line that starts `fatal:` or
  /// `error:`, else its last non-empty line.
  final String line;

  @override
  String toString() => 'git $verb failed: $line';
}
