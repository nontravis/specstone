import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the docs a name addresses, or one section of each.
class GetCommand extends SpecstoneCommand {
  new() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print JSON instead of text.',
    );
  }

  @override
  String get name => 'get';

  @override
  String get description => 'Print the docs a name addresses, or a section.';

  @override
  String get invocation => 'specstone get <name>[#<section key>] [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    if (rest.isEmpty) {
      return fail(
        missingArgument('get', 'a name', 'specstone get login'),
        asJson: asJson,
      );
    }
    if (rest.length > 1) {
      usageException('Expected one name, got ${rest.length}.');
    }
    return runRead(
      (session) => answerGet(session.index, rest.first),
      asJson: asJson,
    );
  }
}
