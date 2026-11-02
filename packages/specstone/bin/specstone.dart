import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/output_guard.dart';

Future<void> main(List<String> args) async {
  exitCode = await guardOutput(
    () => SpecstoneCommandRunner().run(args),
    out: stdout,
    err: stderr,
  );
}
