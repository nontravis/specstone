import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/upgrade_command.dart';
import 'package:specstone/src/process_main.dart';

/// The process main of the CLI whose `upgrade` reads its URLs from the
/// environment, so a test can watch what the install script does with the
/// process's own output.
///
/// `UPGRADE_SCRIPT_BASE`, `UPGRADE_RELEASE_URL`, `UPGRADE_EXECUTABLE`, and
/// `UPGRADE_VERSION` stand for the arguments of `UpgradeCommand`; with the
/// first one unset, or any other command, it is the CLI as it ships.
Future<Never> main(List<String> args) async {
  final env = Platform.environment;
  final scriptBase = env['UPGRADE_SCRIPT_BASE'];
  if (args.firstOrNull != 'upgrade' || scriptBase == null) {
    return runProcess(args);
  }
  final status = await SpecstoneCommandRunner(
    upgrade: UpgradeCommand(
      scriptBase: Uri.parse(scriptBase),
      latestReleaseUrl: Uri.parse(env['UPGRADE_RELEASE_URL']!),
      executable: env['UPGRADE_EXECUTABLE'],
      runningVersion: env['UPGRADE_VERSION'],
    ),
  ).run(args);
  await stdout.flush();
  await stderr.flush();
  exit(status);
}
