import 'dart:async';
import 'dart:io';

/// The operating system family the browser lookup targets.
enum HostOs {
  macos,
  linux,
  windows;

  /// Returns the running OS; any OS other than macOS and Windows is [linux].
  static HostOs get current {
    if (Platform.isMacOS) return macos;
    if (Platform.isWindows) return windows;
    return linux;
  }
}

/// Runs [executable] with [arguments]; returns its exit code.
///
/// Returns `-1` when [timeout] elapsed and the process was killed.
typedef RunProcess = Future<int> Function(
  String executable,
  List<String> arguments, {
  required Duration timeout,
});

/// The machine facts the browser lookup and the pdf print depend on.
///
/// Tests pass fakes; [BrowserHost.system] reads the real machine.
final class BrowserHost {
  new({
    required this.environment,
    required this.os,
    required this.isRunnable,
    required this.runProcess,
  });

  /// Returns the host of the running process.
  factory system() => BrowserHost(
    environment: Platform.environment,
    os: HostOs.current,
    isRunnable: _isRunnableFile,
    runProcess: _runProcess,
  );

  /// The process environment variables.
  final Map<String, String> environment;

  /// The OS whose install paths the lookup tries.
  final HostOs os;

  /// Whether the file at the path exists and can be run.
  final bool Function(String path) isRunnable;

  /// Runs a program and waits for it, killing it at the timeout.
  final RunProcess runProcess;
}

/// An executable bit for owner, group, or other in `FileStat.mode`.
const _anyExecuteBit = 0x49;

bool _isRunnableFile(String path) {
  final stat = FileStat.statSync(path);
  if (stat.type != FileSystemEntityType.file) return false;
  return Platform.isWindows || stat.mode & _anyExecuteBit != 0;
}

Future<int> _runProcess(
  String executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  final process = await Process.start(executable, arguments);
  // Unread output would fill the pipe buffer and stall the process.
  unawaited(process.stdout.drain<void>());
  unawaited(process.stderr.drain<void>());
  return process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
}
