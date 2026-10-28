import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/banned_words.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/tree_rules.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One line of a held section's body.
///
/// `line` is the 1-based file line; `fenced` is true for fenced code content
/// and the fence lines.
typedef BodyLine = ({String text, int line, bool fenced});

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
  final Map<String, RegExp> _bannedPatterns = {};
  final Map<MergedDocType, Map<String, MergedSection>> _sectionsByHeader =
      Map.identity();
  final Map<String, ({List<MergedSection?> templates, Map<String, int> first})>
  _heldTemplates = {};

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

  /// Returns the pattern of the banned [word], built once per run.
  RegExp bannedPatternOf(String word) =>
      _bannedPatterns.putIfAbsent(word, () => bannedWordPattern(word));

  /// Returns the template section the held section [index] of [doc] maps to,
  /// or null.
  ///
  /// Both headers compare by `headerKey`, as F-05's `format` matches them.
  MergedSection? templateSectionAt(IndexedDoc doc, int index) =>
      _heldTemplatesOf(doc).templates[index];

  /// Returns the first held section of [doc] that maps to [sectionId].
  IndexedSection? heldSection(IndexedDoc doc, String sectionId) {
    final index = _heldIndex(doc, sectionId);
    return index == null ? null : contentOf(doc).sections[index];
  }

  int? _heldIndex(IndexedDoc doc, String sectionId) =>
      _heldTemplatesOf(doc).first[sectionId];

  /// Maps each held section of [doc] to its template section, built once.
  ({List<MergedSection?> templates, Map<String, int> first}) _heldTemplatesOf(
    IndexedDoc doc,
  ) => _heldTemplates.putIfAbsent(doc.docPath, () {
    final held = contentOf(doc).sections;
    final type = typeOf(doc);
    final byHeader = type == null ? null : _sectionsByHeaderOf(type);
    final templates = [
      for (final section in held) byHeader?[headerKey(_headerText(section))],
    ];
    final first = <String, int>{};
    for (final (i, template) in templates.indexed) {
      if (template != null) first.putIfAbsent(template.id, () => i);
    }
    return (templates: templates, first: first);
  });

  /// Maps each header key of [type] to its first template section.
  Map<String, MergedSection> _sectionsByHeaderOf(MergedDocType type) =>
      _sectionsByHeader.putIfAbsent(type, () {
        final byHeader = <String, MergedSection>{};
        for (final section in type.sections) {
          byHeader.putIfAbsent(headerKey(section.header), () => section);
        }
        return byHeader;
      });

  /// Returns the body lines of the held section at [index] of [doc].
  List<BodyLine> bodyLinesOf(IndexedDoc doc, int index) {
    final lines = linesOf(doc);
    final first = lines.sectionLines[index] + 1;
    final body = contentOf(doc).sections[index].body.split('\n');
    return [
      for (var k = 0; k < body.length; k++)
        (text: body[k], line: first + k, fenced: lines.isFenced(first + k)),
    ];
  }

  /// Whether [type] declares the field [fieldId].
  ///
  /// A rule that reads a named field runs only when this holds (INV-2).
  bool typeHoldsField(MergedDocType? type, String fieldId) =>
      type != null && type.fields.any((field) => field.id == fieldId);

  /// Whether the merged doc type [typeId] declares the section [sectionId].
  ///
  /// A rule that reads a named section runs only when this holds (INV-2).
  bool typeHoldsSection(String typeId, String sectionId) =>
      _session.project.set.docTypes.any(
        (type) =>
            type.id == typeId &&
            type.sections.any((section) => section.id == sectionId),
      );

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
  /// line to the next `###` line outside fenced code, or the section end. The
  /// first block of a repeated number wins.
  Map<String, String> scenarioBlocksOf(IndexedDoc story) =>
      _scenarioBlocks.putIfAbsent(story.docPath, () {
        final index = _heldIndex(story, _acceptanceSection);
        if (index == null) return const {};
        final blocks = <String, String>{};
        for (final (:key, :lines) in _blocksOf(
          bodyLinesOf(story, index),
          _scenarioHeading,
          (match) => 'S${match.group(1)}',
        )) {
          blocks.putIfAbsent(key, () => _blockText(lines));
        }
        return blocks;
      });

  /// Whether the merged set holds a `project` doc type.
  bool get hasProject =>
      _session.project.set.docTypes.any((type) => type.id == _projectType);

  late final Set<String> _roleNames = {
    for (final doc in _projectDocs)
      if (_heldIndex(doc, _rolesSection) case final index?)
        for (final line in bodyLinesOf(doc, index))
          if (!line.fenced)
            if (_roleEntry.firstMatch(line.text) case final entry?)
              entry.group(1)!,
  };

  /// Returns the Role names of every `project` doc.
  ///
  /// A name is the text in backticks that opens a `roles` section entry.
  Set<String> roleNames() => _roleNames;

  late final Set<String> _projectHeadingIds = {
    for (final doc in _projectDocs)
      for (final (i, line) in linesOf(doc).lines.indexed)
        if (!linesOf(doc).isFenced(i + 1))
          if (_nfrHeading.firstMatch(line) case final heading?)
            heading.group(1)!,
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
      for (var i = 0; i < contentOf(doc).sections.length; i++) {
        for (final (:key, :lines) in _blocksOf(
          bodyLinesOf(doc, i),
          _nfrHeading,
          (match) => match.group(1)!,
        )) {
          final statement = lines
              .where((line) => !line.fenced)
              .map((line) => line.text.trim())
              .where((text) => text.startsWith(_statementPrefix))
              .firstOrNull;
          statements.putIfAbsent(
            key,
            () => (path: doc.docPath, text: statement ?? ''),
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
    final rows = <({String cell, int line})>[];
    for (var i = 0; i < held.length; i++) {
      if (templateSectionAt(api, i)?.id != _frTraceSection) continue;
      var sawHeader = false;
      for (final line in bodyLinesOf(api, i)) {
        final text = line.text.trim();
        if (line.fenced || !text.startsWith('|')) continue;
        final cell = _firstCell(text);
        if (!sawHeader) {
          sawHeader = true;
          continue;
        }
        if (_separatorCell.hasMatch(cell)) continue;
        rows.add((cell: _unquoted(cell), line: line.line));
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

String _blockText(List<BodyLine> lines) =>
    lines.map((line) => line.text).join('\n').trimRight();

/// Splits [body] into the `###` blocks whose heading matches [heading].
///
/// A block runs from its heading line to the next `###` line outside fenced
/// code, or the end of [body]. [keyOf] names a block from its heading match.
List<({String key, List<BodyLine> lines})> _blocksOf(
  List<BodyLine> body,
  RegExp heading,
  String Function(Match heading) keyOf,
) {
  final blocks = <({String key, List<BodyLine> lines})>[];
  String? key;
  var lines = <BodyLine>[];
  void close() {
    if (key case final closed?) blocks.add((key: closed, lines: lines));
  }

  for (final line in body) {
    if (line.fenced || !_subHeading.hasMatch(line.text)) {
      lines.add(line);
      continue;
    }
    close();
    final match = heading.firstMatch(line.text);
    key = match == null ? null : keyOf(match);
    lines = [line];
  }
  close();
  return blocks;
}
