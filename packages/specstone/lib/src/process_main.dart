import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/console.dart';
import 'package:specstone/src/output_guard.dart';
import 'package:specstone/src/update_notice.dart';

/// Runs [args] as the specstone process and ends it with the command's exit
/// status once stdout and stderr have flushed.
///
/// The process ends whatever is still pending, so an abandoned release
/// request, a name lookup included, never holds it open after the output.
Future<Never> runProcess(
  List<String> args, {
  UpdateNotice? updateNotice,
}) async {
  final watch = Stopwatch()..start();
  final courtesy = CourtesyWrites(stderr);
  final status = await guardOutput(
    () async {
      final status = await SpecstoneCommandRunner(
        console: SystemConsole(),
        courtesy: courtesy.writeln,
        updateNotice: updateNotice,
      ).run(args);
      // Trace branch only; written here since guardOutput then closes stderr.
      if (Platform.environment['SPECSTONE_TRACE_PHASES'] == '1') {
        final ms = (watch.elapsedMicroseconds / 1000).toStringAsFixed(1);
        stderr.writeln('trace main: $ms ms');
      }
      return status;
    },
    out: stdout,
    err: stderr,
    courtesy: courtesy,
  );
  exit(status);
}
