// Builds a branch of this repository and installs the build as the CLI.
//
// Run from the checkout: `dart run tool/install_local.dart [--branch <ref>]`.
// Only `dart:` libraries, so a test can compile it outside the workspace.
import 'dart:convert';
import 'dart:io';

const String _usage =
    'usage: dart run tool/install_local.dart [--branch <ref>]';
const String _branchFlag = '--branch';
const String _defaultRef = 'develop';

/// A failed check: printed as `install_local: <message>` on stderr, exit 1.
final class _Refusal implements Exception {
  new(this.message);

  final String message;
}

Future<void> main(List<String> args) async {
  try {
    await _installLocal(args);
  } on _Refusal catch (refusal) {
    stderr.writeln('install_local: ${refusal.message}');
    exitCode = 1;
  }
}

Future<void> _installLocal(List<String> args) async {
  if (Platform.isWindows) {
    throw _Refusal(
      'a local build installs on macOS and Linux only; nothing was changed',
    );
  }
  final ref = _refFrom(args);
  await _commitOf(ref);
}

/// Returns the ref to build: `develop`, or the value of `--branch`.
///
/// Any other argument list is a refusal.
String _refFrom(List<String> args) => switch (args) {
  [] => _defaultRef,
  [_branchFlag, final ref] => ref,
  _ => throw _Refusal(_usage),
};

/// Returns the full sha of the commit [ref] names, else refuses naming [ref].
///
/// A ref that starts with `-` refuses without a `git` call: it could read as
/// an option, and no branch, tag, or sha starts with one.
Future<String> _commitOf(String ref) async {
  final missing = 'branch not found: $ref; the install is unchanged';
  if (ref.startsWith('-')) throw _Refusal(missing);
  return _git([
    'rev-parse',
    '--verify',
    '--quiet',
    '$ref^{commit}',
  ], failure: missing);
}

/// Returns the stdout of a `git` call, or refuses with its first error line.
///
/// A [failure] replaces that refusal's text when the call exits non-zero.
Future<String> _git(List<String> args, {String? failure}) async {
  final result = await _run('git', args);
  if (result.exitCode != 0) {
    throw _Refusal(
      failure ?? 'git ${args.join(' ')} failed: ${_failureLine(result)}',
    );
  }
  return (result.stdout as String).trimRight();
}

Future<ProcessResult> _run(String executable, List<String> args) async {
  try {
    return await Process.run(executable, args);
  } on ProcessException catch (error) {
    throw _Refusal('$executable is not available (${error.message})');
  }
}

/// Returns the first non-empty stderr line, else the first stdout line.
String _failureLine(ProcessResult result) {
  for (final stream in [result.stderr, result.stdout]) {
    for (final line in LineSplitter.split(stream as String)) {
      if (line.trim().isNotEmpty) return line.trim();
    }
  }
  return 'exit code ${result.exitCode}';
}
