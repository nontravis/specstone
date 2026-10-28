import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Walks the drafts and approves each one at the Owner's `y`.
class ApproveCommand extends WriteCommand {
  @override
  String get name => 'approve';

  @override
  String get description => "Show each draft and approve it at the Owner's y.";

  @override
  String get invocation => 'specstone approve [<name>]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length > 1) {
      usageException('Expected at most one name, got ${rest.length}.');
    }
    try {
      requireOwnerTerminal(
        interactive: interactive,
        message:
            'approve runs only at an interactive terminal; '
            'ask the Owner to run specstone approve',
      );
    } on SpecstoneFault catch (fault) {
      return failWrite(fault, asJson: false);
    }
    return runWrite((session) {
      approveDrafts(
        session,
        name: rest.firstOrNull,
        readLine: console.readLine,
        out: specstoneRunner.out,
      );
      return const ReadAnswer(text: '', json: {});
    }, asJson: false);
  }
}
