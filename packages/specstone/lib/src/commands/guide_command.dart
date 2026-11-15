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
    addOutOption();
  }

  @override
  String get name => 'guide';

  @override
  String get description =>
      "Print a doc type's writing guide, or list the doc types; "
      'with --pattern, a feature pattern, or list them.';

  @override
  String get invocation =>
      'specstone guide [type …] [--json] [--out [<path>]]\n'
      '       specstone guide --pattern [id …] [--json] [--out [<path>]]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final runner = specstoneRunner;
    final asJson = argResults!.flag('json');

    final String? outPath;
    try {
      outPath = outPathOf(argResults!);
    } on IndexFault catch (fault) {
      return fail(fault, asJson: asJson);
    }

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
      return _printPatterns(set, rest, asJson: asJson, outPath: outPath);
    }

    if (rest.isEmpty) {
      return _emit(
        asJson
            ? '${SpecstoneCommand.pretty.convert(set.listJson())}\n'
            : set.listText(),
        outPath,
        asJson: asJson,
      );
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

    return _emit(
      asJson ? _renderJson(docTypes) : _renderGuides(docTypes),
      outPath,
      asJson: asJson,
    );
  }

  int _printPatterns(
    MergedSet set,
    List<String> ids, {
    required bool asJson,
    required String? outPath,
  }) {
    if (ids.isEmpty) {
      final list = set.featurePatternListJson();
      return _emit(
        asJson
            ? '${SpecstoneCommand.pretty.convert(list)}\n'
            : set.featurePatternListText(),
        outPath,
        asJson: asJson,
      );
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

    return _emit(
      asJson ? _renderPatternJson(patterns) : _renderPatterns(patterns),
      outPath,
      asJson: asJson,
    );
  }

  /// Prints [text], or, under `--out`, writes it to [outPath] (bare when null)
  /// and prints the reply that names the file.
  int _emit(String text, String? outPath, {required bool asJson}) {
    final args = argResults!;
    if (!writesOut(args)) {
      specstoneRunner.out.write(text);
      return 0;
    }
    final roots = locateReadRoots(specstoneRunner.workingDirectory);
    try {
      final answer = answerOut(
        command: 'guide',
        text: text,
        outPath: outPath,
        projectRoot: roots?.projectRoot,
        docsRoot: roots?.docsRoot,
        asJson: asJson,
        flags: [if (args.flag('pattern')) 'pattern'],
        args: args.rest,
      );
      return printAnswer(answer, const [], asJson: asJson);
    } on SpecstoneFault catch (fault) {
      return fail(fault, asJson: asJson);
    }
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
