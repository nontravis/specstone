import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Gives a doc a new slug and rewrites every reference to it.
class RenameCommand extends WriteCommand {
  new() {
    argParser
      ..addOption('to', help: 'The new slug.')
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'rename';

  @override
  String get description => 'Rename a doc and rewrite every reference to it.';

  @override
  String get invocation =>
      'specstone rename (<type>:<name> | <path>) --to <slug> [--json]';

  @override
  Future<int> run() {
    final args = argResults!;
    return runWriteOnTarget(
      'specstone rename user_story:login/reset_password '
      '--to recover_account',
      (session, target) =>
          answerRename(session, target, slug: args.option('to')),
    );
  }
}
