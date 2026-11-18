// Builds a branch of this repository and installs the build as the CLI.
//
// Run from the checkout: `dart run tool/install_local.dart [--branch <ref>]`.
// Imports the Version library of `specstone_core` and nothing else outside
// `dart:`; a test compiles the tool against a copy of that library, outside the
// workspace.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/release_version.dart';

const String _usage =
    'usage: dart run tool/install_local.dart [--branch <ref>]';
const String _branchFlag = '--branch';
const String _defaultRef = 'develop';
const String _unchanged = 'the install is unchanged';
const String _rerun = 'run install_local again';
const String _exportFolder = 'export';
const String _shimPath = 'packages/specstone/bin/stn';
const String _versionPath = 'packages/specstone_core/lib/src/version.dart';

/// The `specstoneVersion` line of `version.dart`, up to its quoted value.
///
/// Group 1 is the text before the value and group 2 the closing quote and
/// semicolon; the match ends there, so a line end of any kind stays.
final RegExp _versionLine = RegExp(
  r"^(const String specstoneVersion = ')[^'\r\n]*(';)",
  multiLine: true,
);

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
    await _refuse(refusal);
  }
}

/// Prints [refusal] and sets the exit status to 1.
Future<void> _refuse(_Refusal refusal) async {
  await _say(refusal.message);
  exitCode = 1;
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
  await _requireShim(ref, commit);
  final devVersion = await _devVersionOf(commit);
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
  final interrupt = _Interrupt()..watch();
  Directory? temp;
  _Refusal? failure;
  try {
    try {
      temp = await _createTemp();
      final bundle = await _build(commit, devVersion, temp, interrupt);
      final shim = File('${temp.path}/$_exportFolder/$_shimPath');
      final version = interrupt.isRaised
          ? null
          : await _versionOf(bundle, interrupt);
      if (version != null && !interrupt.isRaised) {
        placing = true;
        await _place(
          bundle,
          install,
          _buildRecord(ref, commit, DateTime.now()),
          shim,
        );
        await _write(
          stdout,
          'installed specstone $version ($ref @ $shortCommit) '
          'in ${install.path}/bin',
        );
      }
    } on _Refusal catch (stepFailure) {
      failure = stepFailure;
    } finally {
      await interrupt.cancel();
    }
    // An interrupt outranks the step it killed, unless the placement had begun:
    // then the install may have changed, and the placement's own outcome
    // stands. A refusal that loses is still printed.
    final refusal = interrupt.isRaised && !placing
        ? _Refusal('interrupted; $_unchanged')
        : failure;
    if (failure != null && failure != refusal) await _say(failure.message);
    if (refusal != null) await _refuse(refusal);
  } finally {
    // After the run's own output, and on every exit once the folder exists.
    if (temp != null) await _deleteTemp(temp);
  }
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

/// Refuses when [commit] holds no `stn` shim, before any temp folder or build.
///
/// A commit older than the shim cannot place it, and an install without it
/// would leave `stn` missing.
Future<void> _requireShim(String ref, String commit) async {
  final result = await _run('git', ['cat-file', '-e', '$commit:$_shimPath']);
  if (result.exitCode != 0) {
    throw _Refusal('the commit of $ref holds no $_shimPath; $_unchanged');
  }
}

/// Returns the dev Version of [commit]: `<MAJOR>.<MINOR+1>.0-dev.<N>`.
///
/// MAJOR and MINOR are the highest Version tag's merged into [commit], and N is
/// the count of merge commits on its first-parent chain after the lowest tag of
/// that MAJOR.MINOR. Refuses when no `v<Version>` tag is merged into it.
Future<String> _devVersionOf(String commit) async {
  final tags = <String, ReleaseVersion>{};
  for (final name in LineSplitter.split(
    await _git(['tag', '--no-column', '--merged', commit]),
  )) {
    final version = name.startsWith('v')
        ? ReleaseVersion.tryParse(name.substring(1))
        : null;
    if (version != null) tags[name] = version;
  }
  if (tags.isEmpty) {
    final shortCommit = await _git(['rev-parse', '--short', commit]);
    throw _Refusal(
      'no tag v<Version> is merged into $shortCommit; $_unchanged',
    );
  }
  final entries = tags.entries.toList();
  final base = entries
      .reduce((a, b) => a.value.compareTo(b.value) >= 0 ? a : b)
      .value;
  final line = entries
      .where(
        (tag) => tag.value.major == base.major && tag.value.minor == base.minor,
      )
      .reduce((a, b) => a.value.compareTo(b.value) <= 0 ? a : b);
  // The full ref, so a branch of the same name cannot move the count.
  final count = await _git([
    'rev-list',
    '--first-parent',
    '--merges',
    '--count',
    'refs/tags/${line.key}..$commit',
  ]);
  return '${base.major}.${BigInt.parse(base.minor) + BigInt.one}.0-dev.$count';
}

/// Sets `specstoneVersion` in the `version.dart` of [export] to [version].
///
/// Only the first such line's quoted value changes. A missing file or line
/// refuses naming the file; an unreadable one refuses with the read error.
Future<void> _setVersion(String export, String version) async {
  final file = File('$export/$_versionPath');
  final missing = _Refusal(
    'no specstoneVersion line in $_versionPath; $_unchanged',
  );
  final String text;
  try {
    text = await file.readAsString();
  } on PathNotFoundException {
    throw missing;
  } on FileSystemException catch (error) {
    throw _Refusal(
      'could not read $_versionPath: ${error.message}; $_unchanged',
    );
  }
  if (!_versionLine.hasMatch(text)) throw missing;
  try {
    await file.writeAsString(
      text.replaceFirstMapped(
        _versionLine,
        (match) => '${match[1]}$version${match[2]}',
      ),
    );
  } on FileSystemException catch (error) {
    throw _Refusal(
      'could not write $_versionPath: ${error.message}; '
      '$_unchanged',
    );
  }
}

/// Exports [commit] into [temp] with `git archive` and builds the CLI there.
///
/// The export sits in `<temp>/export`, so the checkout and its `.git/` stay
/// untouched. Its `specstoneVersion` is set to [version] first. The build
/// output sits beside the export, so deleting [temp] removes both. Returns the
/// folder `dart build cli` fills with `bin/` and `lib/`.
Future<Directory> _build(
  String commit,
  String version,
  Directory temp,
  _Interrupt interrupt,
) async {
  final export = '${temp.path}/$_exportFolder';
  final archive = '$export.tar';
  final output = '${temp.path}/build';
  await Directory(export).create();
  await _git(['archive', '--format=tar', '-o', archive, commit]);
  final extract = await _run('tar', ['-xf', archive, '-C', export]);
  if (extract.exitCode != 0) {
    throw _Refusal('tar -xf failed: ${_failureText(extract)}');
  }
  await _setVersion(export, version);
  await _step(
    'dart pub get',
    ['pub', 'get', '--enforce-lockfile'],
    interrupt,
    workingDirectory: export,
  );
  await _step(
    'dart build cli',
    ['build', 'cli', '-t', 'bin/specstone.dart', '-o', output],
    interrupt,
    workingDirectory: '$export/packages/specstone',
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
/// written. [record] becomes `build.txt` in the copy of `lib/`, and [shim] is
/// copied, its mode kept, into the copy of `bin/`. The aside copies go on
/// every exit path, a stale one of an earlier run included.
Future<void> _place(
  Directory bundle,
  Directory install,
  String record,
  File shim,
) async {
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
    await _placeStep(['cp', '-p', shim.path, '$binAside/stn'], bin, _unchanged);
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

/// Creates the folder that holds the export and the build output.
///
/// A system temp path that is not absolute is refused: it would put the export
/// inside the checkout.
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

/// Deletes [temp]; a failure is printed, never thrown, so it cannot change the
/// run's exit status.
Future<void> _deleteTemp(Directory temp) async {
  try {
    await temp.delete(recursive: true);
  } on FileSystemException catch (error) {
    await _say('could not remove ${temp.path}: ${error.message}');
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
