import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the docs tree, or the subtree of one doc.
///
/// Without a target it prints every doc; untyped docs follow under their
/// folder.
class StructureCommand extends SpecstoneCommand {
  new() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print JSON instead of text.',
    );
  }

  @override
  String get name => 'structure';

  @override
  String get description => 'Print the docs tree with each doc size.';

  @override
  String get invocation => 'specstone structure [<target>] [--json]';

  @override
  Future<int> run() {
    final rest = argResults!.rest;
    if (rest.length > 1) {
      usageException('Expected at most one target, got ${rest.length}.');
    }
    return runRead(
      (session) => answerStructure(session.index, target: rest.firstOrNull),
      asJson: argResults!.flag('json'),
    );
  }
}
