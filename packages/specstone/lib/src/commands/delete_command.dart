import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Deletes a doc with everything under it.
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
  String get description => 'Delete a doc and everything under it.';

  @override
  String get invocation => 'specstone delete <type>:<name> [--json]';

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
    if (rest.length > 1) {
      usageException('Expected one target, got ${rest.length}.');
    }
    final runner = specstoneRunner;
    return runWrite(
      (session) => answerDelete(
        session,
        rest.first,
        interactive: interactive,
        readLine: console.readLine,
        prompts: asJson ? runner.err : runner.out,
      ),
      asJson: asJson,
    );
  }
}
