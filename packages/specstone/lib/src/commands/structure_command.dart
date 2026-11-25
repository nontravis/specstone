import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the docs tree, or the union of the subtrees of the named docs.
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
    addOutOption();
    addTargetOption();
  }

  @override
  String get name => 'structure';

  @override
  String get description => 'Print the docs tree with each doc size.';

  @override
  String get invocation =>
      'specstone structure [<target> ...] [--target <name>] [--json] '
      '[--out [<path>]]';

  @override
  Future<int> run() {
    final args = argResults!;
    return runRead(
      (session) => answerStructure(
        session.index,
        targets: args.rest,
        codeTarget: targetOf(args),
      ),
      asJson: args.flag('json'),
    );
  }
}
