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
      'specstone rename <type>:<name> --to <slug> [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    if (rest.isEmpty) {
      return fail(
        missingArgument(
          'rename',
          'a target',
          'specstone rename user_story:login/reset_password '
              '--to recover_account',
        ),
        asJson: asJson,
      );
    }
    if (rest.length > 1) {
      usageException('Expected one target, got ${rest.length}.');
    }
    return runWrite(
      (session) => answerRename(session, rest.first, slug: args.option('to')),
      asJson: asJson,
    );
  }
}
