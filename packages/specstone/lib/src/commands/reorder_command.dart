import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Moves a doc to a place among its siblings.
class ReorderCommand extends WriteCommand {
  new() {
    addTargetOption();
    argParser
      ..addOption('to', help: 'The place among the siblings, from 1.')
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Run every check and print what the reorder would do; write '
            'nothing.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'reorder';

  @override
  String get description => 'Move a doc to a place among its siblings.';

  @override
  String get invocation =>
      'specstone reorder <doc address> --to <n> '
      '[--dry-run] [--target <name>] [--json]';

  @override
  Future<int> run() {
    final args = argResults!;
    return runWriteOnTarget(
      'specstone reorder user_story:login/reset_password --to 1',
      (session, target) => answerReorder(
        session,
        target,
        place: args.option('to'),
        codeTarget: targetOf(args),
        dryRun: args.flag('dry-run'),
      ),
    );
  }
}
