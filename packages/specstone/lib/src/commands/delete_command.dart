import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Deletes one or more docs, each with the docs it owns.
class DeleteCommand extends WriteCommand {
  new() {
    argParser
      ..addFlag(
        'yes',
        negatable: false,
        help:
            'Delete approved docs without the terminal prompt; the Claude '
            'Code plugin asks the Owner first.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete docs, each with the docs it owns.';

  @override
  String get invocation =>
      'specstone delete <target> [<target> …] [--yes] [--json]';

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
    final runner = specstoneRunner;
    return runWrite(
      (session) => answerDelete(
        session,
        rest,
        confirmation: OwnerConfirmation.of(
          yes: args.flag('yes'),
          interactive: interactive,
        ),
        readLine: console.readLine,
        prompts: asJson ? runner.err : runner.out,
      ),
      asJson: asJson,
    );
  }
}
