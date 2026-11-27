import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/label_rules.dart'
    show numberLabelRunsOf;
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc;
import 'package:specstone_core/src/doc_model/models/doc_address.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart';
import 'package:specstone_core/src/doc_model/number_label.dart'
    show
        MarkdownLabelLines,
        builtInLabelPrefixes,
        labelLinesInFile,
        numberLabelsIn;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show readDocAddress;
import 'package:specstone_core/src/document_writing/agent_file_walk.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/label_place.dart';
import 'package:specstone_core/src/index_query/models/prefixed_label_place.dart';
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/setup_migration/project_files.dart'
    show isSingularLayoutPath, singularLayoutPathsOf;
import 'package:specstone_core/src/templates/code_target.dart';

const _codeField = 'code';
const _separator = '/';
const _byteOrderMark = '﻿';

/// Returns a `doc_cited_in_code` finding for each mention of a doc and each
/// number label run in the code files of the targets of [work].
///
/// A code file is each file under the `code:` roots of a target's docs; a
/// target with no `code:` entry lists its whole code root but the docs root,
/// hidden folders, and nested checkouts. An agent file is never read, and a
/// file with no comment mark or markdown extension is not read at all. A
/// mention counts only when it resolves to a doc in the index, so a layout
/// template or an item ID never does; a one-slug span and the layout path of a
/// singular doc type are no mention. A number label run is the set
/// `numberLabelRunsOf` gives, read in the same text, after the file's
/// mentions. A file that is not UTF-8 or cannot be read is a warning, not a
/// finding. A file unchanged since an earlier run, whose stored texts name no
/// doc and read as no label now, is not read.
Iterable<Finding> docNamesInCode(
  CheckContext context,
  ImplementedWork work,
) sync* {
  final reader = _DocMentionReader(context);
  for (final target in work.targets) {
    for (final file in _codeFilesOf(context, work, target)) {
      yield* reader.mentionsIn(target, file);
    }
  }
}

/// Returns the code files of [target], as paths from its code root, sorted by
/// code point, each once.
List<String> _codeFilesOf(
  CheckContext context,
  ImplementedWork work,
  CodeTarget target,
) => mentionScanFiles(
  context.codeRootOf(target),
  _codeEntriesOf(context, work, target),
  docsRoot: context.docsRoot,
  nestedRoots: context.nestedRootsOf(target),
  onUnlistable: (folder) => context.warn(
    '$folder: cannot list the folder; files under it are not checked for '
    'doc names',
  ),
);

/// Returns the `code:` entries of the docs of [target].
Set<String> _codeEntriesOf(
  CheckContext context,
  ImplementedWork work,
  CodeTarget target,
) => {
  for (final doc in context.index.docs)
    if (work.targetOf(doc) == target &&
        context.typeHoldsField(context.typeOf(doc), _codeField))
      for (final YamlEntry(:value)
          in context.linesOf(doc).entriesOf(_codeField))
        if (value is String) value,
};

/// Reads the mentions of docs in code files, against one index.
final class _DocMentionReader {
  new(this._context)
    : _index = _context.index,
      _docsFolder = _context.docsRoot.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
      ),
      _names = {for (final doc in _context.index.docs) doc.name},
      _layoutPaths = singularLayoutPathsOf(
        _context.index.set,
        twinNames: _context.index.twinNames,
      ),
      _paths = ProjectPathReader(
        projectRoot: _context.projectRoot,
        docsRoot: _context.docsRoot,
      );

  final CheckContext _context;
  final DocIndex _index;
  final String _docsFolder;
  final Set<String> _names;
  final Set<String> _layoutPaths;
  final ProjectPathReader _paths;

  Iterable<Finding> mentionsIn(CodeTarget target, String codePath) sync* {
    final extension = extensionOfCodePath(codePath);
    if (!readsNameMentions(extension)) return;
    final projectPath = _projectPathOf(target, codePath);
    if (projectPath == null || isAgentFile(projectPath)) return;
    final root = _context.codeRootOf(target);
    final cache = _context.codeFiles;
    final listed = _context.numberLabelPrefixes.toSet();
    // A file whose stored texts name no doc and read as no label holds no
    // finding: it is not read.
    if (cache.mentionTextsOf(root, codePath) case final texts?) {
      if (!texts.any(
        (text) =>
            _isCited(text, readDocAddress(text)) || _readsAsLabel(text, listed),
      )) {
        return;
      }
    }
    final text = _readText(target, codePath, projectPath);
    if (text == null) return;
    final lf = toLf(text);
    final parsed = extension == markdownExtension ? Doc.parse(lf) : null;
    final mentions = nameMentionsInFile(lf, extension, parsed: parsed);
    final labels = labelLinesInFile(lf, extension, parsed: parsed);
    cache.putMentionTexts(root, codePath, [
      ...{
        for (final mention in mentions) mention.text,
        ..._labelTextsOf(labels),
      },
    ]);
    for (final mention in mentions) {
      if (_isCited(mention.text, mention.address)) {
        yield _finding(projectPath, mention.line, mention.text);
      }
    }
    for (final LabelPlace(:line, :written) in _runsOf(labels, listed)) {
      yield _finding(projectPath, line, written);
    }
  }

  /// The number label runs of [labels], at their 1-based lines.
  List<LabelPlace> _runsOf(MarkdownLabelLines labels, Set<String> listed) =>
      numberLabelRunsOf(
        numberLabels: [
          for (final label in labels.numbers)
            LabelPlace(line: label.line + 1, written: label.written),
        ],
        prefixedLabels: [
          for (final chain in labels.prefixed)
            PrefixedLabelPlace(line: chain.line + 1, parts: chain.parts),
        ],
        listed: listed,
      );

  /// The written text of each label candidate of [labels], whatever the config
  /// lists.
  Iterable<String> _labelTextsOf(MarkdownLabelLines labels) => [
    for (final label in labels.numbers) label.written,
    for (final chain in labels.prefixed)
      for (final part in chain.parts) part.written,
  ];

  /// Whether a stored [text] is a built-in label or a part with a prefix of
  /// [listed].
  bool _readsAsLabel(String text, Set<String> listed) {
    final dash = text.indexOf('-');
    if (dash > 0) {
      final prefix = text.substring(0, dash + 1);
      if (builtInLabelPrefixes.contains(prefix) || listed.contains(prefix)) {
        return true;
      }
    }
    return numberLabelsIn(text).any((label) => label.written == text);
  }

  String? _projectPathOf(CodeTarget target, String codePath) {
    try {
      return _paths.projectPathOf(codePath, _context.codeRootOf(target));
    } on FileSystemException {
      return null;
    }
  }

  String? _readText(CodeTarget target, String codePath, String projectPath) {
    final bytes = _context.readCodeBytes(target, codePath);
    if (bytes == null) {
      _context.warn(
        '$projectPath: cannot read the file; doc names in it are not checked',
      );
      return null;
    }
    try {
      final text = utf8.decode(bytes);
      return text.startsWith(_byteOrderMark) ? text.substring(1) : text;
    } on FormatException {
      _context.warn('$projectPath: not UTF-8; doc names in it are not checked');
      return null;
    }
  }

  /// Whether a mention of [text], read as [address], names a doc: a path read
  /// from the docs root or the project root, or a Name some doc carries.
  bool _isCited(String text, DocAddress address) {
    if (address.isName) return _namesDoc(address);
    return !isSingularLayoutPath(text, _layoutPaths) &&
        _docAtPath(text) != null;
  }

  bool _namesDoc(DocAddress address) => switch (address.typeId) {
    final typeId? => _index.ofTypeNamed(typeId, address.body).isNotEmpty,
    null => _names.contains(address.body),
  };

  IndexedDoc? _docAtPath(String path) {
    if (_index.at(path) case final doc?) return doc;
    final prefix = '$_docsFolder$_separator';
    return path.startsWith(prefix)
        ? _index.at(path.substring(prefix.length))
        : null;
  }

  Finding _finding(String projectPath, int line, String mention) => Finding(
    kind: FindingKind.docCitedInCode,
    path: projectPath,
    line: line,
    message: '$mention names a doc; the doc names the code, never the reverse',
    keys: {'mention': mention},
  );
}
