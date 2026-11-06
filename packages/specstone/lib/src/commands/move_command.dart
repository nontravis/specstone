import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Moves a story into another feature.
class MoveCommand extends WriteCommand {
  new() {
    argParser
      ..addOption('under', help: 'The feature that takes the story.')
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'move';

  @override
  String get description =>
      'Move a story into another feature and rewrite every reference to it.';

  @override
  String get invocation =>
      'specstone move <doc address> --under <doc address> [--json]';

  @override
  Future<int> run() {
    final args = argResults!;
    return runWriteOnTarget(
      'specstone move user_story:login/reset_password --under account',
      (session, target) =>
          answerMove(session, target, under: args.option('under')),
    );
  }
}
