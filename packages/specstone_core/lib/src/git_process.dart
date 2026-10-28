import 'dart:convert';
import 'dart:io';

/// Runs `git` with [arguments] in [workingDirectory].
typedef RunGit = ProcessResult Function(
  List<String> arguments, {
  required String workingDirectory,
});

/// Starts the real `git` program; the only code that does.
ProcessResult runRealGit(
  List<String> arguments, {
  required String workingDirectory,
}) => Process.runSync(
  'git',
  arguments,
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
