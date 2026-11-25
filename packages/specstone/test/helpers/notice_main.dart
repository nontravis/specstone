import 'dart:io';
import 'dart:isolate';

import 'package:specstone/src/console.dart';
import 'package:specstone/src/process_main.dart';
import 'package:specstone/src/update_notice.dart';

/// A [Console] that is a terminal on both outputs and reads no input.
final class _Terminal implements Console {
  @override
  bool get stdinIsTerminal => false;

  @override
  bool get stdoutIsTerminal => true;

  @override
  bool get stderrIsTerminal => true;

  @override
  bool get noColor => false;

  @override
  String? get approveModeVariable => null;

  @override
  Future<String> readAll() async => '';

  @override
  String? readLine() => null;
}

/// The process main of the CLI with the update notice on.
///
/// Arguments: the release URL, the home folder, then the command line. The
/// home holds `.specstone/bin`, where the notice finds its managed binary. A
/// `HANG` variable keeps a port open, standing for work nothing awaits.
Future<void> main(List<String> args) {
  final [url, home, ...command] = args;
  if (Platform.environment['HANG'] != null) ReceivePort();
  return runProcess(
    command,
    updateNotice: UpdateNotice(
      console: _Terminal(),
      environment: const {},
      home: Directory(home),
      executable: '$home/.specstone/bin/specstone',
      latestReleaseUrl: Uri.parse(url),
    ),
  );
}
