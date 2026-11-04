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
  String get invocation =>
      'specstone reorder (<type>:<name> | <path>) --to <n> [--json]';

  @override
  Future<int> run() {
    final args = argResults!;
    return runWriteOnTarget(
      'specstone reorder user_story:login/reset_password --to 1',
      (session, target) =>
          answerReorder(session, target, place: args.option('to')),
    );
  }
}
