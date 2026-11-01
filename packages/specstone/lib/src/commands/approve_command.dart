import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Walks the drafts and approves each one at the Owner's `y`, or approves the
/// named drafts under `--yes`.
class ApproveCommand extends WriteCommand {
  new() {
    argParser.addFlag(
      'yes',
      negatable: false,
      help:
          'Approve the named drafts without the terminal prompt; the Claude '
          'Code plugin asks the Owner first.',
    );
  }

  @override
  String get name => 'approve';

  @override
  String get description => "Show each draft and approve it at the Owner's y.";

  @override
  String get invocation => 'specstone approve [<name> …] [--yes]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final names = args.rest;
    final yes = args.flag('yes');
    if (yes && names.isEmpty) {
      usageException('--yes needs the names of the drafts it approves.');
    }
    final confirmation = OwnerConfirmation.of(
      yes: yes,
      interactive: interactive,
    );
    try {
      confirmation.refuseIfMissing('approve runs only');
    } on SpecstoneFault catch (fault) {
      return failWrite(fault, asJson: false);
    }
    if (!confirmation.prompts) {
      return runWrite((session) => approveNamed(session, names), asJson: false);
    }
    return runWrite((session) {
      approveDrafts(
        session,
        names: names,
        readLine: console.readLine,
        out: specstoneRunner.out,
      );
      return const ReadAnswer(text: '', json: {});
    }, asJson: false);
  }
}
