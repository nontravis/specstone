import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the doc type list, one doc type's writing guide or merged schema,
/// or, with `--pattern`, the feature pattern list or each named feature
/// pattern.
///
/// A template fault reaches only the commands that resolve templates, `guide`
/// and `format`.
class GuideCommand extends SpecstoneCommand {
  new() {
    argParser
      ..addFlag('json', negatable: false, help: 'Print JSON instead of text.')
      ..addFlag(
        'pattern',
        negatable: false,
        help: 'Read feature patterns in place of doc types.',
      );
  }

  @override
  String get name => 'guide';

  @override
  String get description =>
      "Print a doc type's writing guide, or list the doc types; "
      'with --pattern, a feature pattern, or list them.';

  @override
  String get invocation =>
      'specstone guide [type …] [--json]\n'
      '       specstone guide --pattern [id …] [--json]';

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

    if (argResults!.flag('pattern')) {
      return _printPatterns(set, rest, asJson: asJson);
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
      final message = _unknownMessage('doc type', unknown);
      if (!asJson) usageException(message);
      return fail(
        TemplateFault(FaultCode.docTypeUnknown, message),
        asJson: true,
      );
    }

    runner.out.write(asJson ? _renderJson(docTypes) : _renderGuides(docTypes));
    return 0;
  }

  int _printPatterns(MergedSet set, List<String> ids, {required bool asJson}) {
    final out = specstoneRunner.out;
    if (ids.isEmpty) {
      final list = set.featurePatternListJson();
      out.write(
        asJson
            ? '${SpecstoneCommand.pretty.convert(list)}\n'
            : set.featurePatternListText(),
      );
      return 0;
    }

    final patterns = <FeaturePattern>[];
    final unknown = <String>[];
    for (final id in ids.toSet()) {
      final pattern = set.featurePattern(id);
      if (pattern == null) {
        unknown.add(id);
      } else {
        patterns.add(pattern);
      }
    }
    if (unknown.isNotEmpty) {
      return fail(
        TemplateFault(
          FaultCode.featurePatternUnknown,
          _unknownMessage('feature pattern', unknown),
        ),
        asJson: asJson,
      );
    }

    out.write(
      asJson ? _renderPatternJson(patterns) : _renderPatterns(patterns),
    );
    return 0;
  }

  /// Names each of [unknown] after [noun], in the singular form for one.
  static String _unknownMessage(String noun, List<String> unknown) {
    final quoted = unknown.map((id) => '"$id"').join(', ');
    return unknown.length == 1
        ? 'Could not find a $noun named $quoted.'
        : 'Could not find ${noun}s named $quoted.';
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

  static String _renderPatternJson(List<FeaturePattern> patterns) {
    final json = patterns.length == 1
        ? patterns.single.toJson()
        : [for (final pattern in patterns) pattern.toJson()];
    return '${SpecstoneCommand.pretty.convert(json)}\n';
  }

  static String _renderPatterns(List<FeaturePattern> patterns) {
    if (patterns.length == 1) return patterns.single.renderBody();
    return [
      for (final pattern in patterns)
        '==> ${pattern.id} <==\n${pattern.renderBody()}',
    ].join();
  }
}
