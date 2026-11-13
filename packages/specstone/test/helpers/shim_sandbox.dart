import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'script_sandbox.dart';

/// The loop guard variable the `stn` shim sets before a hand-off.
const stnGuardVariable = 'SPECSTONE_STN_GUARD';

/// The environment variable whose value is the fake `specstone`'s exit status.
const fakeExitVariable = 'FAKE_EXIT';

/// Creates a [ShimSandbox] under a new temp folder.
///
/// The folder is deleted by `addTearDown`. The sandbox's
/// `<home>/.specstone/bin/` holds a copy of the repo's `stn` shim and a fake
/// `specstone` that records its argv, stdin, `PATH`, and the guard's value to
/// a log and exits with the status in `FAKE_EXIT` (0 when unset).
Future<ShimSandbox> createShimSandbox() async {
  final root = await Directory.systemTemp.createTemp('specstone_shim_');
  addTearDown(() => root.delete(recursive: true));
  final sandbox = ShimSandbox(root: root);
  return sandbox._fill();
}

/// A temp home holding the installed shim, a fake `specstone`, and runs of it.
final class ShimSandbox {
  new({required this.root}) : home = Directory('${root.path}/home');

  static final bool _windows = Platform.isWindows;

  static const _lenientUtf8 = Utf8Decoder(allowMalformed: true);

  final Directory root;

  /// The temp home the shim is installed under.
  final Directory home;

  /// The folder holding the installed `stn` and the fake `specstone`.
  Directory get bin => Directory('${home.path}/.specstone/bin');

  /// The folder holding the run logs.
  Directory get logs => Directory('${root.path}/logs');

  /// Returns the log lines of [name], or none when it wrote no log.
  List<String> logOf(String name) {
    final file = File('${logs.path}/$name.log');
    return file.existsSync() ? file.readAsLinesSync() : const [];
  }

  /// Writes another tool's recording `stn` in [folder], exiting with [exit].
  ///
  /// The other `stn` records to the `other` log, so `logOf('other')` shows
  /// whether and how it ran.
  void otherStn(String folder, {int exit = 0}) {
    if (_windows) {
      throw UnimplementedError('Task 2 adds the Windows branch');
    }
    _writeRecorder(File('$folder/stn'), 'other', '$exit');
  }

  /// Runs the installed shim with exactly [path] as `PATH` and none of the
  /// parent environment, plus [extra].
  ///
  /// [stdinText], when given, is piped into the shim. The run fails after
  /// [timeout], so a walk that loops fails the test instead of hanging it.
  Future<ProcessResult> runStn(
    List<String> args, {
    required String path,
    Map<String, String> extra = const {},
    String? stdinText,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_windows) {
      throw UnimplementedError('Task 2 adds the Windows branch');
    }
    final process = await Process.start(
      '/bin/sh',
      ['${bin.path}/stn', ...args],
      environment: {
        'HOME': home.path,
        'PATH': path,
        'STUB_LOG_DIR': logs.path,
        ...extra,
      },
      includeParentEnvironment: false,
      workingDirectory: root.path,
    );
    final stdout = process.stdout.transform(_lenientUtf8).join();
    final stderr = process.stderr.transform(_lenientUtf8).join();
    if (stdinText != null) process.stdin.write(stdinText);
    // A target that never reads stdin closes the pipe early; that is fine.
    await process.stdin.close().catchError((Object _) {});
    final code = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill();
        throw TimeoutException('stn did not exit within $timeout', timeout);
      },
    );
    return ProcessResult(process.pid, code, await stdout, await stderr);
  }

  Future<ShimSandbox> _fill() async {
    await bin.create(recursive: true);
    await logs.create();
    final shim = _windows
        ? File('${repoRoot().path}/packages/specstone/bin/stn.cmd')
        : File('${repoRoot().path}/packages/specstone/bin/stn');
    if (!shim.existsSync()) {
      throw StateError('no shim at ${shim.path}');
    }
    final installed = await shim.copy('${bin.path}/stn');
    if (!_windows) _makeExecutable(installed);
    _writeRecorder(File('${bin.path}/specstone'), 'specstone');
    return this;
  }

  /// Writes an executable `/bin/sh` [file] that records its argv, stdin,
  /// `PATH`, and the guard's value to the log [name], then runs [exit], a
  /// literal or a shell expression such as `'${FAKE_EXIT:-0}'`.
  void _writeRecorder(File file, String name, [String? exit]) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync('''
#!/bin/sh
log="\$STUB_LOG_DIR/$name.log"
printf 'argv\\n' >> "\$log"
for a in "\$@"; do printf '%s\\n' "\$a" >> "\$log"; done
printf 'stdin\\n%s\\n' "\$(cat 2>/dev/null)" >> "\$log"
printf 'path\\n%s\\n' "\$PATH" >> "\$log"
printf 'guard\\n%s\\n' "\${$stnGuardVariable:-unset}" >> "\$log"
exit ${exit ?? '\${$fakeExitVariable:-0}'}
''');
    if (!_windows) _makeExecutable(file);
  }

  static void _makeExecutable(File file) {
    final result = Process.runSync('chmod', ['755', file.path]);
    if (result.exitCode != 0) {
      throw StateError('chmod ${file.path} failed: ${result.stderr}');
    }
  }
}
