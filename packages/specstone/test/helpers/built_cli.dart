import 'dart:io';

import 'package:test/test.dart';

import 'package_root.dart';

/// Builds specstone into a new temp folder and returns the path of the binary.
///
/// Call it from `setUpAll`; the folder is deleted at tear-down. Fails with the
/// build's stdout and stderr on a non-zero exit.
Future<String> buildSpecstone() async {
  final out = await Directory.systemTemp.createTemp('specstone_build_');
  addTearDown(() => out.delete(recursive: true));
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
  expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
  final name = Platform.isWindows ? 'specstone.exe' : 'specstone';
  return out.uri.resolve('bundle/bin/$name').toFilePath();
}
