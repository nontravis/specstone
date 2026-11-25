import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import 'package_root.dart';

// One build per test isolate; a later caller gets the same bytes.
Future<List<int>>? _built;

/// Returns the path of the `build.ps1` the release compiles `stn.exe` with.
String stnBuildScript() =>
    packageRoot().uri.resolve('shim/windows/build.ps1').toFilePath();

/// Runs `build.ps1` to write `stn.exe` at [outFile], stamped with [version].
Future<ProcessResult> runStnBuild(String outFile, String version) =>
    Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      stnBuildScript(),
      '-OutFile',
      outFile,
      '-Version',
      version,
    ]);

/// Returns the bytes of `stn.exe`, built once per test isolate.
///
/// The build stamps `specstoneVersion` and runs in a temp folder deleted
/// before this returns, so a caller writes the bytes where it needs a file.
/// Fails with the script's stdout and stderr on a non-zero exit.
Future<List<int>> buildStnExe() => _built ??= _build();

Future<List<int>> _build() async {
  final out = await Directory.systemTemp.createTemp('specstone_stn_build_');
  try {
    final exe = '${out.path}${Platform.pathSeparator}stn.exe';
    final build = await runStnBuild(exe, specstoneVersion);
    if (build.exitCode != 0) {
      fail(
        'build.ps1 exited ${build.exitCode}: ${build.stdout}${build.stderr}',
      );
    }
    final bytes = await File(exe).readAsBytes();
    return bytes;
  } finally {
    await out.delete(recursive: true);
  }
}
