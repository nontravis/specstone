import 'dart:io';

import 'package:specstone/src/command_runner.dart';
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
  final courtesy = CourtesyWrites(stderr);
  final status = await guardOutput(
    () => SpecstoneCommandRunner(
      courtesy: courtesy.writeln,
      updateNotice: updateNotice,
    ).run(args),
    out: stdout,
    err: stderr,
    courtesy: courtesy,
  );
  exit(status);
}
