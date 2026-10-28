import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Moves a doc to a place among its siblings.
class ReorderCommand extends WriteCommand {
  new() {
    argParser
      ..addOption('to', help: 'The place among the siblings, from 1.')
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'reorder';

  @override
  String get description => 'Move a doc to a place among its siblings.';

  @override
  String get invocation => 'specstone reorder <type>:<name> --to <n> [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    if (rest.isEmpty) {
      return fail(
        missingArgument(
          'reorder',
          'a target',
          'specstone reorder user_story:login/reset_password --to 1',
        ),
        asJson: asJson,
      );
    }
    if (rest.length > 1) {
      usageException('Expected one target, got ${rest.length}.');
    }
    return runWrite(
      (session) => answerReorder(session, rest.first, place: args.option('to')),
      asJson: asJson,
    );
  }
}
