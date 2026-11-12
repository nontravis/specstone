// Builds a branch of this repository and installs the build as the CLI.
//
// Run from the checkout: `dart run tool/install_local.dart [--branch <ref>]`.
// Only `dart:` libraries, so a test can compile it outside the workspace.
import 'dart:async';
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
  final commit = await _commitOf(_refFrom(args));
  var interrupted = false;
  // The watch keeps the tool alive after Ctrl-C, so the cleanup below runs;
  // Ctrl-C also reaches the child, whose failure ends the run.
  final watch = ProcessSignal.sigint.watch().listen((_) {
    if (!interrupted) stderr.writeln('install_local: interrupted; cleaning up');
    interrupted = true;
  });
  final temp = await Directory.systemTemp.createTemp('install_local_');
  _Refusal? failure;
  _Refusal? cleanup;
  try {
    final bundle = await _build(commit, temp);
    await _versionOf(bundle);
  } on _Refusal catch (stepFailure) {
    failure = stepFailure;
  } finally {
    cleanup = await _cleanUp(temp, watch);
  }
  // An interrupt outranks the step it killed; a cleanup failure is reported
  // only when nothing else failed, so it never displaces the first refusal.
  final refusal = interrupted
      ? _Refusal('interrupted; the install is unchanged')
      : failure ?? cleanup;
  if (cleanup != null && cleanup != refusal) {
    stderr.writeln('install_local: ${cleanup.message}');
  }
  if (refusal != null) throw refusal;
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
  final missing = _Refusal('branch not found: $ref; the install is unchanged');
  if (ref.startsWith('-')) throw missing;
  // `--verify --quiet` exits 1 with no output when the ref names no commit;
  // any other failure, such as 128 outside a repository, is git's own.
  final commit = await _git(
    ['rev-parse', '--verify', '--quiet', '$ref^{commit}'],
    okExits: const {0, 1},
  );
  if (commit.isEmpty) throw missing;
  return commit;
}

/// Adds a detached worktree at [commit] in [temp] and builds the CLI there.
///
/// The build output sits beside the worktree, so deleting [temp] removes both.
/// Returns the folder `dart build cli` fills with `bin/` and `lib/`.
Future<Directory> _build(String commit, Directory temp) async {
  final worktree = '${temp.path}/worktree';
  final output = '${temp.path}/build';
  await _git(['worktree', 'add', '--detach', worktree, commit]);
  await _step('dart pub get', [
    'pub',
    'get',
    '--enforce-lockfile',
  ], workingDirectory: worktree);
  await _step('dart build cli', [
    'build',
    'cli',
    '-t',
    'bin/specstone.dart',
    '-o',
    output,
  ], workingDirectory: '$worktree/packages/specstone');
  return Directory('$output/bundle');
}

/// Returns the version [bundle]'s binary prints for `--version`.
Future<String> _versionOf(Directory bundle) async => (await _step(
  'specstone --version',
  ['--version'],
  workingDirectory: bundle.path,
  executable: '${bundle.path}/bin/specstone',
)).trim();

/// Runs [executable] (`dart`) with [args] and returns its stdout.
///
/// A start failure or an exit status other than 0 refuses with [name] and the
/// step's own error output.
Future<String> _step(
  String name,
  List<String> args, {
  required String workingDirectory,
  String executable = 'dart',
}) async {
  final ProcessResult result;
  try {
    result = await Process.run(
      executable,
      args,
      workingDirectory: workingDirectory,
    );
  } on ProcessException catch (error) {
    throw _Refusal('$name failed: ${error.message}');
  }
  if (result.exitCode != 0) {
    throw _Refusal('$name failed: ${_failureText(result)}');
  }
  return result.stdout as String;
}

/// Removes the worktree and [temp], then stops [watch] whatever happened.
///
/// Returns the refusal a failed removal raised instead of throwing it, so the
/// caller decides which refusal the Owner sees.
Future<_Refusal?> _cleanUp(
  Directory temp,
  StreamSubscription<ProcessSignal> watch,
) async {
  try {
    await _removeTemp(temp);
    return null;
  } on _Refusal catch (refusal) {
    return refusal;
  } finally {
    await watch.cancel();
  }
}

/// Removes the worktree under [temp], then [temp] itself.
///
/// The worktree is absent when `git worktree add` failed. `--force` is needed
/// because the build leaves an untracked `.dart_tool/` in it.
Future<void> _removeTemp(Directory temp) async {
  final worktree = Directory('${temp.path}/worktree');
  try {
    if (worktree.existsSync()) {
      await _git(['worktree', 'remove', '--force', worktree.path]);
    }
  } finally {
    await temp.delete(recursive: true);
  }
}

/// Returns the stdout of a `git` call, or refuses with its first error line.
///
/// An exit status in [okExits] is not a failure.
Future<String> _git(List<String> args, {Set<int> okExits = const {0}}) async {
  final result = await _run('git', args);
  if (!okExits.contains(result.exitCode)) {
    final line = LineSplitter.split(_failureText(result)).first.trim();
    throw _Refusal('git ${args.join(' ')} failed: $line');
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

/// Returns the trimmed stderr, else the trimmed stdout, else the exit status.
String _failureText(ProcessResult result) {
  for (final stream in [result.stderr, result.stdout]) {
    final text = (stream as String).trim();
    if (text.isNotEmpty) return text;
  }
  return 'exit code ${result.exitCode}';
}
