import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Deletes one or more docs with everything under them.
class DeleteCommand extends WriteCommand {
  new() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print JSON instead of text.',
    );
  }

  @override
  String get name => 'delete';

  @override
  String get description => 'Delete docs and everything under them.';

  @override
  String get invocation => 'specstone delete <target> [<target> …] [--json]';

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
        interactive: interactive,
        readLine: console.readLine,
        prompts: asJson ? runner.err : runner.out,
      ),
      asJson: asJson,
    );
  }
}
