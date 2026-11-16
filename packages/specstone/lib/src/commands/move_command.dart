import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Moves stories into another feature, or FRs into another story.
class MoveCommand extends WriteCommand {
  new() {
    argParser
      ..addOption(
        'under',
        help:
            'The feature that takes user_story targets, or the story that '
            'takes fr targets: <doc type>:<name>, a bare name, or a path.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Run every check and print what the move would do; write nothing.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'move';

  @override
  String get description =>
      'Move stories into a feature, or FRs into a story, '
      'and rewrite every reference to them.';

  @override
  String get invocation =>
      'specstone move <doc address> … --under <doc address> '
      '[--dry-run] [--json]';

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
      (session) => answerMove(
        session,
        args.rest,
        under: args.option('under'),
        dryRun: args.flag('dry-run'),
      ),
      asJson: asJson,
    );
  }
}
