import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Records, at the Owner's `y`, that a docs folder outside the project, or a
/// project reached through a `docs` link, may be written.
class TrustCommand extends WriteCommand {
  @override
  String get name => 'trust';

  @override
  String get description =>
      "Trust, at the Owner's y, the docs folder a docs link leads to, so "
      'writes may follow it.';

  @override
  String get invocation => 'specstone trust';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Expected no argument, got ${argResults!.rest.length}.');
    }
    final runner = specstoneRunner;
    try {
      return runTrust(
        TrustRequest(
          workingDirectory: runner.workingDirectory,
          homeDirectory: runner.homeDirectory,
          confirmation: OwnerConfirmation.of(
            yes: false,
            interactive: interactive,
          ),
          readLine: console.readLine,
          out: runner.out,
        ),
      );
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: false);
    }
  }
}
