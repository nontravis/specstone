import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Moves stories, FRs, nfs, features, items, or scenarios under a new parent.
class MoveCommand extends WriteCommand {
  new() {
    addTargetOption();
    argParser
      ..addOption(
        'under',
        help:
            'The feature that takes user_story or feature targets, the story '
            'that takes fr, nf, or scenario targets, or the doc that takes '
            'item targets: <doc type>:<name>, a bare name, or a path.',
      )
      ..addFlag(
        'top',
        negatable: false,
        help:
            'Move feature targets among the top features, in place of '
            '--under.',
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
      'Move stories and features under a feature, FRs and nfs under a '
      'story, features among the top features, items '
      '(<doc address>#<item ID>) into another doc, or scenarios '
      '(<story address>#S<N>) into another story, '
      'and rewrite every reference to them.';

  @override
  String get invocation =>
      'specstone move <doc address> … (--under <doc address> | --top) '
      '[--dry-run] [--target <name>] [--json]';

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
        top: args.flag('top'),
        codeTarget: targetOf(args),
        dryRun: args.flag('dry-run'),
      ),
      asJson: asJson,
    );
  }
}
