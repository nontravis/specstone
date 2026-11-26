import 'package:args/args.dart';
import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Prints the doc type list, one doc type's writing guide or merged schema,
/// or, with `--pattern`, the feature pattern list or each named feature
/// pattern, or, with `--file-format`, the keys a doc type file and a
/// `pack.yaml` accept.
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
      )
      ..addFlag(
        'file-format',
        negatable: false,
        help: 'Print the keys a doc type file and a pack.yaml accept.',
      );
    addOutOption();
  }

  @override
  String get name => 'guide';

  @override
  String get description =>
      "Print a doc type's writing guide, or list the doc types; "
      'with --pattern, a feature pattern, or list them; '
      'with --file-format, the keys a doc type file accepts.';

  @override
  String get invocation =>
      'specstone guide [type …] [--json] [--out [<path>]]\n'
      '       specstone guide --pattern [id …] [--json] [--out [<path>]]\n'
      '       specstone guide --file-format [--out [<path>]]';

  @override
  void refuseArgs(ArgResults args) {
    if (!args.flag('file-format')) return;
    final refused = [
      if (args.rest.isNotEmpty) 'a doc type',
      if (args.flag('pattern')) '--pattern',
      if (args.flag('json')) '--json',
    ];
    if (refused.isEmpty) return;
    usageException('--file-format does not go with ${refused.join(', ')}.');
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    refuseArgs(args);
    final rest = args.rest;
    final runner = specstoneRunner;
    final asJson = args.flag('json');
    final isPattern = args.flag('pattern');

    if (args.flag('file-format')) {
      runner.out.write(renderFileFormat());
      return 0;
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

    int emit(String text) {
      runner.out.write(text);
      return 0;
    }

    if (isPattern) {
      return _printPatterns(set, rest, asJson: asJson, emit: emit);
    }

    if (rest.isEmpty) {
      return emit(
        asJson
            ? '${SpecstoneCommand.pretty.convert(set.listJson())}\n'
            : set.listText(),
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

    return emit(asJson ? _renderJson(docTypes) : _renderGuides(docTypes));
  }

  int _printPatterns(
    MergedSet set,
    List<String> ids, {
    required bool asJson,
    required int Function(String text) emit,
  }) {
    if (ids.isEmpty) {
      final list = set.featurePatternListJson();
      return emit(
        asJson
            ? '${SpecstoneCommand.pretty.convert(list)}\n'
            : set.featurePatternListText(),
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

    return emit(
      asJson ? _renderPatternJson(patterns) : _renderPatterns(patterns),
    );
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
    final shared = sharedByAll(docTypes);
    final sharedOut = {for (final line in shared) line.id};
    return [
      '==> shared <==\n',
      for (final line in shared) '${line.text}\n',
      for (final docType in docTypes)
        '==> ${docType.id} <==\n${docType.renderGuide(sharedOut: sharedOut)}',
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
