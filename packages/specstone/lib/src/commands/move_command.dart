import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Moves one or more stories into another feature.
class MoveCommand extends WriteCommand {
  new() {
    argParser
      ..addOption(
        'under',
        help:
            'The feature that takes the stories: <doc type>:<name>, '
            'a bare name, or a path.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'move';

  @override
  String get description =>
      'Move stories into another feature and rewrite every reference to them.';

  @override
  String get invocation =>
      'specstone move <doc address> … --under <doc address> [--json]';

  @override
  Future<int> run() {
    final args = argResults!;
    final asJson = args.flag('json');
    if (args.rest.isEmpty) {
      return Future.value(
        fail(
          missingArgument(
            name,
            'a target',
            'specstone move user_story:login/reset_password --under account',
          ),
          asJson: asJson,
        ),
      );
    }
    return runWrite(
      (session) => answerMove(session, args.rest, under: args.option('under')),
      asJson: asJson,
    );
  }
}
