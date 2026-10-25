import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the references of the docs a name addresses.
class RefsCommand extends SpecstoneCommand {
  new() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print JSON instead of text.',
    );
  }

  @override
  String get name => 'refs';

  @override
  String get description => 'Print the references of a doc.';

  @override
  String get invocation => 'specstone refs <name> [--json]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final asJson = args.flag('json');
    final rest = args.rest;
    if (rest.isEmpty) {
      return fail(
        missingArgument('refs', 'a name', 'specstone refs login'),
        asJson: asJson,
      );
    }
    if (rest.length > 1) {
      usageException('Expected one name, got ${rest.length}.');
    }
    return runRead(
      (session) => answerRefs(session.index, rest.first),
      asJson: asJson,
    );
  }
}
