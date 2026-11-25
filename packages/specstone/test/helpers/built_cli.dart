import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package_root.dart';

const _cacheFolderName = 'specstone_test_cli';
const _usedStampName = 'used';
const _lockPollInterval = Duration(milliseconds: 250);
const _staleLockAge = Duration(minutes: 5);
const _unusedBundleAge = Duration(days: 3);

/// Workspace files and package folders the CLI build reads.
const _workspaceBuildFiles = ['pubspec.yaml', 'pubspec.lock'];
const _buildPackages = ['packages/specstone/', 'packages/specstone_core/'];

/// Package folders whose files never reach the built binary.
const _nonBuildFolders = {'test', 'coverage', 'build'};

/// Returns the path of a specstone binary built from the current source.
///
/// Builds once per source state and shares the bundle across test files,
/// isolates, and runs, so callers must copy it before changing any file in it.
/// Fails with the build's stdout and stderr on a non-zero exit.
Future<String> buildSpecstone() async {
  final cache = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}$_cacheFolderName',
  );
  await cache.create(recursive: true);
  final workspace = Directory.fromUri(packageRoot().uri.resolve('../../'));
  final bundle = Directory.fromUri(cache.uri.resolve(sourceKey(workspace)));
  if (!bundle.existsSync()) await _buildOnce(cache, bundle);
  File.fromUri(bundle.uri.resolve(_usedStampName)).writeAsStringSync('');
  final name = Platform.isWindows ? 'specstone.exe' : 'specstone';
  return bundle.uri.resolve('bundle/bin/$name').toFilePath();
}

/// Runs the built binary at [binary] and decodes its output as UTF-8.
///
/// The binary writes UTF-8, while `Process.run` decodes with the Windows ANSI
/// code page by default, which garbles every non-ASCII character.
Future<ProcessResult> runSpecstone(
  String binary,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
}) => Process.run(
  binary,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
  includeParentEnvironment: includeParentEnvironment,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

/// Blocking form of [runSpecstone].
ProcessResult runSpecstoneSync(
  String binary,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
}) => Process.runSync(
  binary,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
  includeParentEnvironment: includeParentEnvironment,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

/// Returns a hex digest of the Dart version and every build input under
/// [workspace]; a change to any input changes the digest.
///
/// The paths in the digest are relative to [workspace], so two checkouts of
/// one source share a key.
String sourceKey(Directory workspace) {
  final root = workspace.uri.path;
  final inputs = [
    for (final name in _workspaceBuildFiles)
      File.fromUri(workspace.uri.resolve(name)),
    for (final package in _buildPackages)
      ..._buildInputs(Directory.fromUri(workspace.uri.resolve(package))),
  ];
  final lines = [
    Platform.version,
    for (final file in inputs) _inputLine(file, root),
  ];
  return sha256.convert(utf8.encode(lines.join('\n'))).toString();
}

String _inputLine(File file, String root) {
  final digest = sha256.convert(file.readAsBytesSync());
  return '${file.uri.path.substring(root.length)} $digest';
}

/// The files of [package] the build may read: all but dot entries and
/// [_nonBuildFolders] at the top, sorted for a stable key.
List<File> _buildInputs(Directory package) {
  final root = package.uri.path;
  bool isInput(File file) {
    final segments = file.uri.path.substring(root.length).split('/');
    return !_nonBuildFolders.contains(segments.first) &&
        !segments.any((segment) => segment.startsWith('.'));
  }

  return package
      .listSync(recursive: true)
      .whereType<File>()
      .where(isInput)
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Builds [bundle] unless another isolate or process holds its lock; then
/// waits until that builder's rename makes [bundle] appear.
Future<void> _buildOnce(Directory cache, Directory bundle) async {
  final lock = File('${bundle.path}.lock');
  while (!bundle.existsSync()) {
    if (!await _tryLock(lock)) {
      await Future<void>.delayed(_lockPollInterval);
      continue;
    }
    try {
      if (!bundle.existsSync()) await _buildInto(cache, bundle);
    } finally {
      await lock.delete();
    }
    _pruneUnused(cache, keep: bundle);
  }
}

/// Takes [lock] by creating it; a lock older than [_staleLockAge] belongs to
/// a builder that died, so it is removed first.
Future<bool> _tryLock(File lock) async {
  try {
    if (DateTime.now().difference(lock.lastModifiedSync()) > _staleLockAge) {
      await lock.delete();
    }
  } on PathNotFoundException {
    // No lock, or another waiter removed the stale one first.
  }
  try {
    await lock.create(exclusive: true);
    return true;
  } on PathExistsException {
    return false;
  }
}

/// Builds into a new folder of [cache], then renames it to [bundle] so that
/// a waiter never sees a half-written bundle.
Future<void> _buildInto(Directory cache, Directory bundle) async {
  final out = await cache.createTemp('build_');
  // `dart compile exe` rejects build hooks and sqlite3 is a hook package.
  // `dart run` relinks the hook library on every call, which fails on Windows
  // while the test runner has that library loaded.
  final build = await Process.run(Platform.resolvedExecutable, [
    'build',
    'cli',
    '-t',
    'bin/specstone.dart',
    '-o',
    out.path,
  ], workingDirectory: packageRoot().path);
  if (build.exitCode != 0) await out.delete(recursive: true);
  expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
  await out.rename(bundle.path);
}

/// Deletes bundles of other source states unused for [_unusedBundleAge].
void _pruneUnused(Directory cache, {required Directory keep}) {
  for (final folder in cache.listSync().whereType<Directory>()) {
    if (folder.path == keep.path) continue;
    final stamp = File.fromUri(folder.uri.resolve(_usedStampName));
    final used = stamp.existsSync() ? stamp : folder;
    final age = DateTime.now().difference(used.statSync().modified);
    if (age > _unusedBundleAge) folder.deleteSync(recursive: true);
  }
}
