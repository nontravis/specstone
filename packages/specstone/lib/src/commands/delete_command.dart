import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Deletes one or more docs, each with the docs it owns.
class DeleteCommand extends WriteCommand {
  new() {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'List the files the delete removes, and its plan line.',
      )
      ..addFlag(
        'yes',
        negatable: false,
        help:
            'Delete approved docs without the terminal prompt; the agent '
            "runs it after the Owner's ok.",
      )
      ..addOption(
        'plan',
        valueHelp: 'hash',
        help:
            'With --yes: the plan line --dry-run printed; a changed list '
            'refuses.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete docs, each with the docs it owns.';

  @override
  String get invocation =>
      'specstone delete <target> [<target> …] '
      '[--dry-run | --yes --plan <hash>] [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    if (rest.isEmpty) {
      return fail(
        missingArgument(
          'delete',
          'a target',
          'specstone delete user_story:login/reset_password',
        ),
        asJson: asJson,
      );
    }
    final dryRun = args.flag('dry-run');
    final yes = args.flag('yes');
    final planHash = args.option('plan');
    checkPlanFlags(
      yes: yes,
      planHash: planHash,
      planCommand: 'specstone delete',
      dryRun: dryRun,
    );
    if (dryRun) {
      return runWrite(
        (session) => answerDeleteDryRun(session, rest),
        asJson: asJson,
      );
    }
    final runner = specstoneRunner;
    return runWrite(
      (session) => answerDelete(
        session,
        rest,
        confirmation: OwnerConfirmation.of(yes: yes, interactive: interactive),
        readLine: console.readLine,
        prompts: asJson ? runner.err : runner.out,
        planHash: planHash,
      ),
      asJson: asJson,
    );
  }
}
