import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the doc type list, one doc type's writing guide, or its merged
/// schema.
///
/// A template fault reaches only the commands that resolve templates, `guide`
/// and `format` (INV-11).
class GuideCommand extends SpecstoneCommand {
  new() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print JSON instead of text.',
    );
  }

  @override
  String get name => 'guide';

  @override
  String get description =>
      "Print a doc type's writing guide, or list the doc types.";

  @override
  String get invocation => 'specstone guide [type] [--json]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length > 1) {
      usageException('Expected at most one doc type, got ${rest.length}.');
    }
    final runner = this.runner! as SpecstoneCommandRunner;
    final asJson = argResults!.flag('json');

    final MergedSet set;
    try {
      set = runner.templates.resolve(
        workingDirectory: runner.workingDirectory,
        homeDirectory: runner.homeDirectory,
      );
    } on TemplateFault catch (fault) {
      return fail(fault, asJson: asJson);
    }

    if (rest.isEmpty) {
      runner.out.write(
        asJson
            ? '${SpecstoneCommand.pretty.convert(set.listJson())}\n'
            : set.listText(),
      );
      return 0;
    }

    final type = rest.single;
    final docType = set.lookup(type);
    if (docType == null) {
      final message = 'Could not find a doc type named "$type".';
      if (!asJson) usageException(message);
      return fail(
        TemplateFault(FaultCode.docTypeUnknown, message),
        asJson: true,
      );
    }
    runner.out.write(
      asJson
          ? '${SpecstoneCommand.pretty.convert(docType.toJson())}\n'
          : docType.renderGuide(),
    );
    return 0;
  }
}
