import 'package:specstone/src/commands/write_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Creates a doc from stdin, or from its doc type's skeleton.
class NewCommand extends WriteCommand {
  new() {
    argParser
      ..addOption('parent', help: 'The name of the parent doc.')
      ..addOption('slug', help: 'The slug of the new doc.')
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.');
  }

  @override
  String get name => 'new';

  @override
  String get description => 'Create a doc, from stdin or the skeleton.';

  @override
  String get invocation =>
      'specstone new <doc type> [--parent <name>] [--slug <slug>] [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    if (rest.isEmpty) {
      return fail(
        missingArgument(
          'new',
          'a doc type',
          'specstone new user_story --parent login --slug reset_password',
        ),
        asJson: asJson,
      );
    }
    if (rest.length > 1) {
      usageException('Expected one doc type, got ${rest.length}.');
    }
    final text = console.stdinIsTerminal ? '' : await console.readAll();
    return runWrite(
      (session) => answerNew(
        session,
        docTypeId: rest.first,
        parent: args.option('parent'),
        slug: args.option('slug'),
        text: text,
      ),
      asJson: asJson,
    );
  }
}
