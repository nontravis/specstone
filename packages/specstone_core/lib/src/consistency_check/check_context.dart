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
  final Map<String, Map<String, String>> _scenarioBlocks = {};

  /// The index of the session's snapshot.
  DocIndex get index => _session.index;

  /// The project root folder.
  Directory get projectRoot => _session.project.projectRoot;

  /// The docs root folder, `<project root>/docs/`.
  Directory get docsRoot => _session.project.docsRoot;

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

  /// Adds [warning], which no finding states.
  void warn(String warning) => _codeWarnings.add(warning);

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

  /// Whether the merged set holds a `gnfr` doc type.
  bool get hasGnfr =>
      _session.project.set.docTypes.any((type) => type.id == _gnfrType);

  /// Returns the `### Scenario <N>` blocks of [story], keyed `S<N>`.
  ///
  /// Reads the `acceptance_criteria` section. A block runs from its heading
  /// line to the next `###` line or the section end. The first block of a
  /// repeated number wins.
  Map<String, String> scenarioBlocksOf(IndexedDoc story) =>
      _scenarioBlocks.putIfAbsent(story.docPath, () {
        final section = heldSection(story, _acceptanceSection);
        if (section == null) return const {};
        final blocks = <String, String>{};
        for (final (:key, :text) in _blocksOf(
          section.body,
          _scenarioHeading,
          (match) => 'S${match.group(1)}',
        )) {
          blocks.putIfAbsent(key, () => text);
        }
        return blocks;
      });

  /// Whether the merged set holds a `project` doc type.
  bool get hasProject =>
      _session.project.set.docTypes.any((type) => type.id == _projectType);

  late final Set<String> _roleNames = {
    for (final doc in _projectDocs)
      for (final line in (heldSection(doc, _rolesSection)?.body ?? '').split(
        '\n',
      ))
        if (_roleEntry.firstMatch(line) case final entry?) entry.group(1)!,
  };

  /// Returns the Role names of every `project` doc.
  ///
  /// A name is the text in backticks that opens a `roles` section entry.
  Set<String> roleNames() => _roleNames;

  late final Set<String> _projectHeadingIds = {
    for (final doc in _projectDocs)
      for (final line in linesOf(doc).lines)
        if (_nfrHeading.firstMatch(line) case final heading?) heading.group(1)!,
  };

  /// Returns the ID of each `###` heading with a ` — ` of every `project` doc.
  Set<String> projectHeadingIds() => _projectHeadingIds;

  Iterable<IndexedDoc> get _projectDocs =>
      index.docs.where((doc) => doc.docTypeId == _projectType);

  /// Maps each NFR id of the `gnfr` docs to its DocPath and Statement line.
  ///
  /// The text is empty when the block has no `- **Statement:**` line.
  late final Map<String, ({String path, String text})> _nfrStatements =
      _readNfrStatements();

  /// Returns the NFR ids of the `gnfr` docs with their Statement lines.
  Map<String, ({String path, String text})> nfrStatements() => _nfrStatements;

  Map<String, ({String path, String text})> _readNfrStatements() {
    final statements = <String, ({String path, String text})>{};
    for (final doc in index.docs) {
      if (doc.docTypeId != _gnfrType) continue;
      for (final section in contentOf(doc).sections) {
        for (final (:key, :text) in _blocksOf(
          section.body,
          _nfrHeading,
          (match) => match.group(1)!,
        )) {
          final line = text
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.startsWith(_statementPrefix))
              .firstOrNull;
          statements.putIfAbsent(
            key,
            () => (path: doc.docPath, text: line ?? ''),
          );
        }
      }
    }
    return statements;
  }

  /// Whether the merged set holds an `architecture` doc type.
  bool get hasArchitecture =>
      _session.project.set.docTypes.any((type) => type.id == _architectureType);

  late final Map<String, IndexedDoc> _frsByName = {
    for (final doc in index.docs)
      if (doc.docTypeId == _frType) doc.name: doc,
  };

  /// Returns the doc of type `fr` named [name], or null.
  IndexedDoc? frNamed(String name) => _frsByName[name];

  final Map<String, List<({String cell, int line})>> _frTraceRows = {};

  /// Returns the FR cell and file line of each row of the `fr_trace` table
  /// of [api].
  ///
  /// A cell is the row's first cell, trimmed, with one pair of backticks
  /// dropped. The header row and the separator row are skipped.
  List<({String cell, int line})> frTraceRowsOf(IndexedDoc api) =>
      _frTraceRows.putIfAbsent(api.docPath, () => _readFrTraceRows(api));

  List<({String cell, int line})> _readFrTraceRows(IndexedDoc api) {
    final held = contentOf(api).sections;
    final type = typeOf(api);
    if (type == null) return const [];
    final headerLines = linesOf(api).sectionLines;
    final rows = <({String cell, int line})>[];
    for (var i = 0; i < held.length; i++) {
      if (templateSectionOf(type, held[i])?.id != _frTraceSection) continue;
      final bodyLines = held[i].body.split('\n');
      var sawHeader = false;
      for (var k = 0; k < bodyLines.length; k++) {
        final text = bodyLines[k].trim();
        if (!text.startsWith('|')) continue;
        final cell = _firstCell(text);
        if (!sawHeader) {
          sawHeader = true;
          continue;
        }
        if (_separatorCell.hasMatch(cell)) continue;
        rows.add((cell: _unquoted(cell), line: headerLines[i] + 1 + k));
      }
    }
    return rows;
  }

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

String _firstCell(String row) {
  final inner = row.substring(1);
  final end = inner.indexOf('|');
  return (end < 0 ? inner : inner.substring(0, end)).trim();
}

String _unquoted(String cell) =>
    cell.length > 1 && cell.startsWith('`') && cell.endsWith('`')
    ? cell.substring(1, cell.length - 1)
    : cell;

String _headerText(IndexedSection section) =>
    section.headerLine.trimLeft().substring(2).trim();

const _gnfrType = 'gnfr';
const _projectType = 'project';
const _rolesSection = 'roles';
final _roleEntry = RegExp('^- `([^`]+)` — ');
const _acceptanceSection = 'acceptance_criteria';
const _architectureType = 'architecture';
const _frType = 'fr';
const _frTraceSection = 'fr_trace';
final _separatorCell = RegExp(r'^:?-+:?$');
const _statementPrefix = '- **Statement:**';
final _scenarioHeading = RegExp('^### Scenario ([0-9]+)(?![0-9])');
final _nfrHeading = RegExp(r'^### (\S+) — ');
final _subHeading = RegExp('^###(?!#)');

/// Splits [body] into the `###` blocks whose heading matches [heading].
///
/// A block runs from its heading line to the next `###` line, trailing blank
/// lines dropped. [keyOf] names a block from its heading match.
List<({String key, String text})> _blocksOf(
  String body,
  RegExp heading,
  String Function(Match heading) keyOf,
) {
  final blocks = <({String key, String text})>[];
  String? key;
  var lines = <String>[];
  for (final line in '$body\n###'.split('\n')) {
    if (!_subHeading.hasMatch(line)) {
      lines.add(line);
      continue;
    }
    if (key case final closed?) {
      blocks.add((key: closed, text: lines.join('\n').trimRight()));
    }
    final match = heading.firstMatch(line);
    key = match == null ? null : keyOf(match);
    lines = [line];
  }
  return blocks;
}
