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
const String _unchanged = 'the install is unchanged';
const String _rerun = 'run install_local again';

/// The text of `git rev-parse` for one commit: a full sha-1 or sha-256 name.
final RegExp _objectName = RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$');

/// A failed check: printed as `install_local: <message>` on stderr, exit 1.
final class _Refusal implements Exception {
  new(this.message);

  final String message;
}

/// The signals that stop a run, and the build step a signal can still reach.
///
/// A signal goes on to the running build step only: git calls and the
/// placement finish, so no install is left half made.
final class _Interrupt {
  static const List<ProcessSignal> _signals = [
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
    ProcessSignal.sighup,
  ];

  final List<StreamSubscription<ProcessSignal>> _watches = [];
  ProcessSignal? _received;
  Process? _step;

  /// Whether a signal has arrived.
  bool get isRaised => _received != null;

  /// Starts watching the signals; the tool then outlives them, so its cleanup
  /// runs.
  void watch() {
    for (final signal in _signals) {
      _watches.add(signal.watch().listen(_raise));
    }
  }

  /// Stops watching, so a later signal ends the tool as it would have.
  Future<void> cancel() =>
      Future.wait([for (final watch in _watches) watch.cancel()]);

  /// Passes a signal already received, or the next one, on to [step].
  void attach(Process step) {
    _step = step;
    final received = _received;
    if (received != null) step.kill(received);
  }

  void detach() => _step = null;

  Future<void> _raise(ProcessSignal signal) async {
    final isFirst = !isRaised;
    _received ??= signal;
    _step?.kill(signal);
    if (isFirst) await _say('interrupted; cleaning up');
  }
}

Future<void> main(List<String> args) async {
  try {
    await _installLocal(args);
  } on _Refusal catch (refusal) {
    await _say(refusal.message);
    exitCode = 1;
  }
}

/// Prints `install_local: <message>` on stderr.
Future<void> _say(String message) => _write(stderr, 'install_local: $message');

/// Writes [line] to [sink], and drops it when nobody reads the sink.
///
/// A closed terminal must not stop the tool before it has cleaned up.
Future<void> _write(IOSink sink, String line) async {
  try {
    sink.writeln(line);
    await sink.flush();
  } on IOException {
    // Nowhere to print.
  }
}

Future<void> _installLocal(List<String> args) async {
  if (Platform.isWindows) {
    throw _Refusal(
      'a local build installs on macOS and Linux only; nothing was changed',
    );
  }
  final ref = _refFrom(args);
  final commit = await _commitOf(ref);
  final home = _homeFrom(Platform.environment);
  if (home == null) {
    throw _Refusal(
      'no home folder: HOME and USERPROFILE are unset, empty, or not an '
      'absolute path; $_unchanged',
    );
  }
  final install = Directory('${home.path}/.specstone');
  final shortCommit = await _git(['rev-parse', '--short', commit]);
  var placing = false;
  var installed = false;
  final interrupt = _Interrupt()..watch();
  Directory? temp;
  _Refusal? failure;
  _Refusal? cleanup;
  try {
    temp = await _createTemp();
    final bundle = await _build(commit, temp, interrupt);
    final version = interrupt.isRaised
        ? null
        : await _versionOf(bundle, interrupt);
    if (version != null && !interrupt.isRaised) {
      placing = true;
      await _place(bundle, install, _buildRecord(ref, commit, DateTime.now()));
      await _write(
        stdout,
        'installed specstone $version ($ref @ $shortCommit) '
        'in ${install.path}/bin',
      );
      installed = true;
    }
  } on _Refusal catch (stepFailure) {
    failure = stepFailure;
  } finally {
    final leftover = await _cleanUp(temp, interrupt);
    // The install landed, so a failed cleanup says so beside its own text.
    cleanup = leftover != null && installed
        ? _Refusal('the install is in place, but ${leftover.message}')
        : leftover;
  }
  // An interrupt outranks the step it killed, unless the placement had begun:
  // then the install may have changed, and the placement's own outcome stands.
  // A cleanup failure is reported only when nothing else failed, so it never
  // displaces the first refusal. A refusal that loses is still printed.
  final refusal = interrupt.isRaised && !placing
      ? _Refusal('interrupted; $_unchanged')
      : failure ?? cleanup;
  if (failure != null && failure != refusal) await _say(failure.message);
  if (cleanup != null && cleanup != refusal) await _say(cleanup.message);
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
  final missing = _Refusal('branch not found: $ref; $_unchanged');
  if (ref.startsWith('-')) throw missing;
  // `--verify --quiet` exits 1 when the ref names no commit; any other
  // failure, such as 128 outside a repository, is git's own. Only one full
  // object name is a commit: a range or a `^ref` prints another shape, some
  // with exit 0.
  final commit = await _git(
    ['rev-parse', '--verify', '--quiet', '$ref^{commit}'],
    okExits: const {0, 1},
  );
  if (!_objectName.hasMatch(commit)) throw missing;
  return commit;
}

/// Adds a detached worktree at [commit] in [temp] and builds the CLI there.
///
/// The build output sits beside the worktree, so deleting [temp] removes both.
/// Returns the folder `dart build cli` fills with `bin/` and `lib/`.
Future<Directory> _build(
  String commit,
  Directory temp,
  _Interrupt interrupt,
) async {
  final worktree = '${temp.path}/worktree';
  final output = '${temp.path}/build';
  await _git(['worktree', 'add', '--detach', worktree, commit]);
  await _step(
    'dart pub get',
    ['pub', 'get', '--enforce-lockfile'],
    interrupt,
    workingDirectory: worktree,
  );
  await _step(
    'dart build cli',
    ['build', 'cli', '-t', 'bin/specstone.dart', '-o', output],
    interrupt,
    workingDirectory: '$worktree/packages/specstone',
  );
  return Directory('$output/bundle');
}

/// Returns the folder in `HOME`, else `USERPROFILE`, of [env].
///
/// An empty value counts as unset; null means no home, which a value that is
/// not an absolute path is too, since the install would land beside the
/// checkout or a dash-led name would read as an option. Follows `homeFrom` of
/// the CLI package, which this script cannot import, except for that check.
Directory? _homeFrom(Map<String, String> env) {
  for (final key in const ['HOME', 'USERPROFILE']) {
    final value = env[key];
    if (value == null || value.isEmpty) continue;
    final home = Directory(value);
    return home.isAbsolute ? home : null;
  }
  return null;
}

/// Returns the lines of `build.txt`: the ref, the full commit, and the UTC
/// time of the build.
String _buildRecord(String ref, String commit, DateTime builtAt) =>
    'ref: $ref\n'
    'commit: $commit\n'
    'built: ${builtAt.toUtc().toIso8601String()}\n';

/// Returns the version [bundle]'s binary prints for `--version`.
Future<String> _versionOf(Directory bundle, _Interrupt interrupt) async =>
    (await _step(
      'specstone --version',
      ['--version'],
      interrupt,
      workingDirectory: bundle.path,
      executable: '${bundle.path}/bin/specstone',
    )).trim();

/// Replaces `lib/` then `bin/` of [install] with those of [bundle].
///
/// Each folder is copied aside first and moved in, as `install.sh` does, so a
/// failed copy leaves the old install as it was and no existing file is
/// written. [record] becomes `build.txt` in the copy of `lib/`. The aside
/// copies go on every exit path, a stale one of an earlier run included.
Future<void> _place(Directory bundle, Directory install, String record) async {
  final lib = '${install.path}/lib';
  final bin = '${install.path}/bin';
  final libAside = '${install.path}/.lib.new';
  final binAside = '${install.path}/.bin.new';
  try {
    await _placeStep(['mkdir', '-p', install.path], install.path, _unchanged);
    await _placeStep(
      ['rm', '-rf', libAside, binAside],
      install.path,
      _unchanged,
    );
    await _placeStep(
      ['cp', '-R', '${bundle.path}/lib', libAside],
      lib,
      _unchanged,
    );
    try {
      await File('$libAside/build.txt').writeAsString(record);
    } on FileSystemException catch (error) {
      throw _Refusal('could not place $lib: ${error.message}; $_unchanged');
    }
    await _placeStep(
      ['cp', '-R', '${bundle.path}/bin', binAside],
      bin,
      _unchanged,
    );
    await _placeStep(['rm', '-rf', lib], lib, _rerun);
    await _placeStep(['mv', libAside, lib], lib, _rerun);
    await _placeStep(['rm', '-rf', bin], bin, _rerun);
    await _placeStep(['mv', binAside, bin], bin, _rerun);
  } finally {
    await _removeAsides([libAside, binAside]);
  }
}

/// Runs [command]; a failure refuses naming [folder] and ending with [outcome].
Future<void> _placeStep(
  List<String> command,
  String folder,
  String outcome,
) async {
  final reason = await _failureOf(command);
  if (reason != null) {
    throw _Refusal('could not place $folder: $reason; $outcome');
  }
}

/// Deletes [asides]; a failure is printed, never thrown, so it cannot displace
/// the refusal that ended the placement.
Future<void> _removeAsides(List<String> asides) async {
  final reason = await _failureOf(['rm', '-rf', ...asides]);
  if (reason != null) {
    await _say('could not remove ${asides.join(' and ')}: $reason');
  }
}

/// Runs [command] and returns why it failed, or null when it exited 0.
Future<String?> _failureOf(List<String> command) async {
  try {
    final result = await _run(command.first, command.sublist(1));
    return result.exitCode == 0 ? null : _failureText(result);
  } on _Refusal catch (refusal) {
    return refusal.message;
  }
}

/// Runs [executable] (`dart`) with [args] and returns its stdout.
///
/// [interrupt] passes a signal on to the running child. A start failure or an
/// exit status other than 0 refuses with [name] and the step's own error
/// output.
Future<String> _step(
  String name,
  List<String> args,
  _Interrupt interrupt, {
  required String workingDirectory,
  String executable = 'dart',
}) async {
  final Process process;
  try {
    process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
    );
  } on ProcessException catch (error) {
    throw _Refusal('$name failed: ${error.message}');
  }
  process.stdin.close().ignore();
  interrupt.attach(process);
  final ProcessResult result;
  try {
    result = await _finish(process);
  } finally {
    interrupt.detach();
  }
  if (result.exitCode != 0) {
    throw _Refusal('$name failed: ${_failureText(result)}');
  }
  return result.stdout as String;
}

/// Collects the output of [process] until it exits.
Future<ProcessResult> _finish(Process process) async {
  const decoder = Utf8Decoder(allowMalformed: true);
  final (output, errors, status) = await (
    process.stdout.transform(decoder).join(),
    process.stderr.transform(decoder).join(),
    process.exitCode,
  ).wait;
  return ProcessResult(process.pid, status, output, errors);
}

/// Creates the folder that holds the worktree and the build output.
///
/// A system temp path that is not absolute is refused: it would put the
/// worktree inside the checkout. The path has its symlinks resolved, as git
/// records a worktree's path: git finds the entry of a worktree whose folder is
/// gone only by that path.
Future<Directory> _createTemp() async {
  final system = Directory.systemTemp;
  if (!system.isAbsolute) {
    throw _Refusal(
      'the temp folder ${system.path} is not an absolute path; $_unchanged',
    );
  }
  try {
    final base = await system.resolveSymbolicLinks();
    return await Directory(base).createTemp('install_local_');
  } on FileSystemException catch (error) {
    throw _Refusal(
      'could not create a temp folder: ${error.message}; $_unchanged',
    );
  }
}

/// Removes the worktree and [temp], if made, then stops [interrupt]'s watches
/// whatever happened.
///
/// Returns the refusal a failed removal raised instead of throwing it, so the
/// caller decides which refusal the Owner sees.
Future<_Refusal?> _cleanUp(Directory? temp, _Interrupt interrupt) async {
  try {
    if (temp != null) await _removeTemp(temp);
    return null;
  } on _Refusal catch (refusal) {
    return refusal;
  } finally {
    await interrupt.cancel();
  }
}

/// Removes the worktree under [temp], then [temp] itself.
///
/// The worktree is absent when `git worktree add` failed. `--force` is needed
/// because the build leaves an untracked `.dart_tool/` in it. When the removal
/// fails, [temp] still goes and the removal runs once more: git then drops the
/// entry of a worktree whose folder is gone, and no other. The refusal holds
/// each failure, a delete of [temp] that fails included.
Future<void> _removeTemp(Directory temp) async {
  final removal = ['worktree', 'remove', '--force', '${temp.path}/worktree'];
  final failures = <String>[];
  var isEntryLeft = false;
  if (Directory('${temp.path}/worktree').existsSync()) {
    try {
      await _git(removal);
    } on _Refusal catch (refusal) {
      failures.add(refusal.message);
      isEntryLeft = true;
    }
  }
  try {
    await temp.delete(recursive: true);
  } on FileSystemException catch (error) {
    failures.add('could not remove ${temp.path}: ${error.message}');
  }
  if (isEntryLeft) {
    try {
      await _git(removal);
    } on _Refusal catch (refusal) {
      failures.add(refusal.message);
    }
  }
  if (failures.isNotEmpty) throw _Refusal(failures.join('; '));
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
