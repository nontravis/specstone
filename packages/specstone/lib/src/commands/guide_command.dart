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
  String get invocation => 'specstone guide [type …] [--json]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final runner = specstoneRunner;
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

    final types = rest.toSet().toList();
    final docTypes = <MergedDocType>[];
    final unknown = <String>[];
    for (final type in types) {
      final docType = set.lookup(type);
      if (docType == null) {
        unknown.add(type);
      } else {
        docTypes.add(docType);
      }
    }
    if (unknown.isNotEmpty) {
      final message = _unknownMessage(unknown);
      if (!asJson) usageException(message);
      return fail(
        TemplateFault(FaultCode.docTypeUnknown, message),
        asJson: true,
      );
    }

    runner.out.write(asJson ? _renderJson(docTypes) : _renderGuides(docTypes));
    return 0;
  }

  static String _unknownMessage(List<String> unknown) {
    final quoted = unknown.map((type) => '"$type"').join(', ');
    return unknown.length == 1
        ? 'Could not find a doc type named $quoted.'
        : 'Could not find doc types named $quoted.';
  }

  static String _renderJson(List<MergedDocType> docTypes) {
    final json = docTypes.length == 1
        ? docTypes.single.toJson()
        : [for (final docType in docTypes) docType.toJson()];
    return '${SpecstoneCommand.pretty.convert(json)}\n';
  }

  static String _renderGuides(List<MergedDocType> docTypes) {
    if (docTypes.length == 1) return docTypes.single.renderGuide();
    return [
      for (final docType in docTypes)
        '==> ${docType.id} <==\n${docType.renderGuide()}',
    ].join();
  }
}
