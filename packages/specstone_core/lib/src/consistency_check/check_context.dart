import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/tree_rules.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// What every rule of one check run reads: the index, per-doc caches, and the
/// warnings the findings have stated.
final class CheckContext {
  new(this._session);

  final ReadSession _session;
  final Map<String, DocContent> _contents = {};
  final Map<String, DocLines> _lines = {};
  final Map<String, String?> _codeTexts = {};
  final List<String> _codeWarnings = [];
  final Set<String> _stated = {};

  /// The index of the session's snapshot.
  DocIndex get index => _session.index;

  /// The project root folder.
  Directory get projectRoot => _session.project.projectRoot;

  /// Returns the content of [doc], read once.
  DocContent contentOf(IndexedDoc doc) =>
      _contents.putIfAbsent(doc.docPath, () => index.contentOf(doc));

  /// Returns the line map of [doc], built on first use.
  DocLines linesOf(IndexedDoc doc) =>
      _lines.putIfAbsent(doc.docPath, () => DocLines.of(contentOf(doc).text));

  /// Returns the text of the code file at [path], read once per run.
  ///
  /// [path] is relative to the project root. Malformed UTF-8 bytes decode to
  /// U+FFFD instead of failing. Returns null for a file that cannot be read,
  /// and adds one warning for it.
  String? codeTextOf(String path) {
    if (_codeTexts.containsKey(path)) return _codeTexts[path];
    String? text;
    try {
      text = const Utf8Decoder(allowMalformed: true)
          .convert(File('${projectRoot.path}/$path').readAsBytesSync());
    } on FileSystemException {
      _codeWarnings.add(
        '$path: cannot read the file; implements Symbols in it are not checked',
      );
    }
    return _codeTexts[path] = text;
  }

  /// How many code files this run has read.
  int get codeFilesRead => _codeTexts.length;

  /// Returns the merged doc type of [doc], or null for an untyped doc.
  MergedDocType? typeOf(IndexedDoc doc) => index.typeOf(doc);

  /// Returns a finding on [doc]; an untyped doc carries no name.
  Finding finding(
    IndexedDoc doc,
    FindingKind kind, {
    required int line,
    required String message,
    Map<String, Object> keys = const {},
  }) => Finding(
    kind: kind,
    path: doc.docPath,
    name: doc.isTyped ? doc.name : null,
    line: line,
    message: message,
    keys: keys,
  );

  /// Returns the template section of [type] that [held] maps to, or null.
  ///
  /// Both headers compare by `headerKey`, as F-05's `format` matches them.
  MergedSection? templateSectionOf(MergedDocType type, IndexedSection held) {
    final key = headerKey(_headerText(held));
    for (final section in type.sections) {
      if (headerKey(section.header) == key) return section;
    }
    return null;
  }

  /// Returns the first held section of [doc] that maps to [sectionId].
  IndexedSection? heldSection(IndexedDoc doc, String sectionId) {
    final type = typeOf(doc);
    if (type == null) return null;
    for (final held in contentOf(doc).sections) {
      if (templateSectionOf(type, held)?.id == sectionId) return held;
    }
    return null;
  }

  /// The first path segment of every doc type `path` (INV-8).
  late final Set<String> checkedFolders = checkedFoldersOf(
    _session.project.set,
  );

  /// Whether [docPath] lies in a checked folder.
  bool isCheckedPath(String docPath) =>
      checkedFolders.contains(docPath.split('/').first);

  /// Whether [doc] lies in a checked folder.
  bool isChecked(IndexedDoc doc) => isCheckedPath(doc.docPath);

  /// Whether the doc type of [doc] names a parent and [doc] has none (INV-13).
  bool hasNoParent(IndexedDoc doc) =>
      typeOf(doc)?.parent != null && doc.parentPath == null;

  /// Every warning of the session, in session order.
  List<String> get sessionWarnings => _session.warnings;

  /// Marks [warning] as printed by a finding.
  void state(String warning) => _stated.add(warning);

  /// The session's warnings that no finding stated, in session order.
  List<String> get unstatedWarnings => [
    for (final warning in _session.warnings)
      if (!_stated.contains(warning)) warning,
    ..._codeWarnings,
  ];
}

String _headerText(IndexedSection section) =>
    section.headerLine.trimLeft().substring(2).trim();
