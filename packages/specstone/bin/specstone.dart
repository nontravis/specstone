import 'dart:io';

import 'package:specstone/src/command_runner.dart';

Future<void> main(List<String> args) async {
  exitCode = await SpecstoneCommandRunner().run(args);
}
