import 'dart:convert';
import 'dart:io';

/// Runs `git` with [arguments] in [workingDirectory].
typedef RunGit = ProcessResult Function(
  List<String> arguments, {
  required String workingDirectory,
});

/// The config that keeps `git` from taking a bare repository it finds by
/// walking up as the repository of the folder it runs in.
///
/// A committed folder laid out as a git dir would otherwise supply the
/// repository config (`core.fsmonitor`, `core.hooksPath`, filter drivers) and
/// have git run a command from it. A git before 2.38 ignores the key; the
/// migrate gate checks the git dir itself for those.
const _explicitBareRepository = ['-c', 'safe.bareRepository=explicit'];

/// Starts the real `git` program; the only code that does.
ProcessResult runRealGit(
  List<String> arguments, {
  required String workingDirectory,
}) => Process.runSync(
  'git',
  [..._explicitBareRepository, ...arguments],
  workingDirectory: workingDirectory,
  stdoutEncoding: utf8,
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
