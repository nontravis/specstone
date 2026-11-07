import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/link_places.dart'
    show sourceHrefsOf;
import 'package:specstone_core/src/index_query/link_scan.dart'
    show LinkSource, linkSourcesOf;
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:yaml/yaml.dart';

const _referenceType = 'reference';

/// Id of the doc type whose Concerns lines end with a `see` target.
const architectureTypeId = 'architecture';
const _filesField = 'files';

/// Id of the section whose lines end with a `see` target.
const concernsSectionId = 'concerns';
const _separator = '/';
const _seeMarker = ' see ';
const _notApplicable = 'N/A — ';
const _backtick = '`';
const _trailingPunctuation = '.,;:!?';
const _templatesFolder = '.specstone/templates';
const _referenceKey = 'reference';
const _addKey = 'add';
const _docKey = 'doc';

/// Returns the `listed_file_missing` and `concerns_target_unresolved`
/// findings of a typed [doc].
///
/// A `reference` doc lists files that sit beside it. An `architecture` doc
/// ends each Concerns line with `see <x>`, where `<x>` is a sibling file or a
/// `##` header of the doc, matched as F-05's `format` matches headers.
Iterable<Finding> checkReferenceEntries(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  switch (doc.docTypeId) {
    case _referenceType:
      yield* _missingListedFiles(context, doc);
    case architectureTypeId:
      yield* _unresolvedConcerns(context, doc);
  }
}

/// Returns a `reference_doc_unresolved` finding for each `doc` entry of a
/// project template `reference:` list that names no doc.
///
/// Reads the top-level `<id>.yaml` files of `.specstone/templates/`, in the
/// plain `reference:` list or its `add:` list. The finding sits at the entry's
/// line of the template file and carries no name.
Iterable<Finding> unresolvedTemplateReferences(CheckContext context) sync* {
  final folder = Directory('${context.projectRoot.path}/$_templatesFolder');
  if (!folder.existsSync()) return;
  final files = [
    for (final entity in folder.listSync())
      if (entity is File && isDocTypeFileName(_baseName(entity))) entity,
  ]..sort((a, b) => _baseName(a).compareTo(_baseName(b)));
  final names = {for (final doc in context.index.docs) doc.name};
  for (final file in files) {
    final path = '$_templatesFolder/${_baseName(file)}';
    for (final (:value, :line) in _docEntries(file)) {
      if (names.contains(value)) continue;
      yield Finding(
        kind: FindingKind.referenceDocUnresolved,
        path: path,
        line: line,
        message: 'reference doc $value names no doc',
        keys: {'value': value},
      );
    }
  }
}

Iterable<Finding> _missingListedFiles(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final folder = _folderOf(context, doc);
  for (final (:value, :line, text: _)
      in context.linesOf(doc).entriesOf(_filesField)) {
    if (value is! String || File('$folder/$value').existsSync()) continue;
    yield context.finding(
      doc,
      FindingKind.listedFileMissing,
      line: line,
      message: '$value is not beside the doc',
      keys: {'entry': value},
    );
  }
}

Iterable<Finding> _unresolvedConcerns(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final held = context.contentOf(doc).sections;
  final type = context.typeOf(doc);
  if (type == null) return;
  final headers = {
    for (final section in held)
      headerKey(section.headerLine.trimLeft().substring(2)),
  };
  final anchors = context.contentOf(doc).lineFacts.anchors;
  final sources = _LinkSources(toLf(context.contentOf(doc).text));
  for (var i = 0; i < held.length; i++) {
    if (context.templateSectionAt(doc, i)?.id != concernsSectionId) {
      continue;
    }
    for (final line in context.bodyLinesOf(doc, i)) {
      final see = line.fenced ? null : seeTargetIn(line.text);
      if (see == null) continue;
      final target = see.text;
      final link = sources.linkSpanning(
        line.line,
        start: see.start,
        end: see.start + target.length,
      );
      // The doc's markdown_unparsed already says its links go unchecked (E14).
      if (link case (href: null)) continue;
      final resolves = _seeResolves(
        context,
        doc,
        link?.href ?? target,
        headers,
        anchors,
        isLink: link != null,
      );
      if (resolves) continue;
      yield context.finding(
        doc,
        FindingKind.concernsTargetUnresolved,
        line: line.line,
        message: 'see $target names no section or file',
        keys: {'target': target},
      );
    }
  }
}

/// Returns the text after the last ` see ` of [line], less trailing
/// punctuation and whitespace and one pair of backticks, with the index it
/// starts at in [line]; null for a line that is `N/A — ` or holds no ` see `.
({String text, int start})? seeTargetIn(String line) {
  if (line.contains(_notApplicable)) return null;
  final at = line.lastIndexOf(_seeMarker);
  if (at < 0) return null;
  final after = line.substring(at + _seeMarker.length);
  var start = at + _seeMarker.length + after.length - after.trimLeft().length;
  var text = _withoutTrailingDrops(after.trim());
  if (text.length > 1 &&
      text.startsWith(_backtick) &&
      text.endsWith(_backtick)) {
    text = text.substring(1, text.length - 1);
    start++;
  }
  return text.isEmpty ? null : (text: text, start: start);
}

String _withoutTrailingDrops(String text) {
  var end = text.length;
  while (end > 0 && _isTrailingDrop(text[end - 1])) {
    end--;
  }
  return text.substring(0, end);
}

bool _isTrailingDrop(String char) =>
    _trailingPunctuation.contains(char) || char.trim().isEmpty;

/// Whether [text], a `see` target or the href of the link that spans it,
/// names a `##` section of [doc], a file at the path relative to it, the
/// doc itself included, or an anchor of the doc or of that file (R63).
///
/// A link, [isLink], names no section, as the link rule reads it (R71). Text
/// after a path makes it no path (E11). An anchor set that is unknown (null)
/// or a file no doc indexes raises nothing for the anchor; [anchors] is the
/// set of [doc] itself.
bool _seeResolves(
  CheckContext context,
  IndexedDoc doc,
  String text,
  Set<String> headers,
  DocAnchors? anchors, {
  required bool isLink,
}) {
  if (!isLink && headers.contains(headerKey(text))) return true;
  if (readLinkTarget(text) case RelativeLink(:final segments, :final anchor)) {
    final named = _namedAnchor(anchor);
    if (segments.isEmpty) {
      return anchor != null && _anchorHeld(anchors, named);
    }
    final path = relativeFilePathOf(text, doc.docPath);
    return path != null && _fileHolds(context, path, named);
  }
  return false;
}

/// The link sources of a doc's body, read on first use by the link scan the
/// link rule places its links from.
final class _LinkSources {
  new(this._text);

  final String _text;

  late final String _body = Doc.parse(_text).afterFrontmatter;

  late final List<LinkSource> _all = linkSourcesOf(
    _body,
    firstLine:
        '\n'
            .allMatches(_text.substring(0, _text.length - _body.length))
            .length +
        1,
  );

  /// The href `markdown` gives each of [_all], by index; null when none is
  /// known (see [sourceHrefsOf]).
  late final List<String>? _hrefs = sourceHrefsOf(_body, _all);

  /// Returns the one link that spans column [start] to column [end] of file
  /// line [line], as the link rule reads it, with the href `markdown` gives
  /// it, null when that is unknown; null when no link with a destination
  /// spans them.
  ({String? href})? linkSpanning(
    int line, {
    required int start,
    required int end,
  }) {
    for (final (index, source) in _all.indexed) {
      if (source.line != line || !_spans(source, start, end)) continue;
      return source.shown == null ? null : (href: _hrefs?[index]);
    }
    return null;
  }

  /// Whether [source] starts at column [start] of its line and ends at column
  /// [end] of it or on a later line, which takes in the rest of its line.
  bool _spans(LinkSource source, int start, int end) {
    final lineStart = source.offset == 0
        ? 0
        : _body.lastIndexOf('\n', source.offset - 1) + 1;
    if (source.offset - lineStart != start) return false;
    final lineEnd = _body.indexOf('\n', source.offset);
    return source.end - lineStart == end ||
        (lineEnd >= 0 && source.end > lineEnd);
  }
}

String? _namedAnchor(String? anchor) =>
    anchor == null || anchor.isEmpty ? null : anchor;

bool _anchorHeld(DocAnchors? anchors, String? named) =>
    named == null || _holds(anchors, named);

/// Whether the file at [path] under the docs root exists and, when it is an
/// indexed doc, holds the anchor [named].
bool _fileHolds(CheckContext context, String path, String? named) {
  if (!File('${context.docsRoot.path}/$path').existsSync()) return false;
  final file = context.index.at(path);
  return named == null ||
      file == null ||
      _holds(context.contentOf(file).lineFacts.anchors, named);
}

bool _holds(DocAnchors? anchors, String anchor) =>
    anchors == null || anchors.holds(anchor);

/// Returns each string `doc` value of the reference entries of [file], with
/// its 1-based line.
Iterable<({String value, int line})> _docEntries(File file) sync* {
  final YamlNode root;
  try {
    root = loadYamlNode(file.readAsStringSync());
  } on YamlException {
    return;
  } on FileSystemException {
    return;
  }
  if (root is! YamlMap) return;
  var list = root.nodes[_referenceKey];
  if (list is YamlMap) list = list.nodes[_addKey];
  if (list is! YamlList) return;
  for (final item in list.nodes) {
    if (item is! YamlMap) continue;
    final value = item[_docKey];
    if (value is String) {
      yield (value: value, line: item.span.start.line + 1);
    }
  }
}

String _folderOf(CheckContext context, IndexedDoc doc) {
  final at = doc.docPath.lastIndexOf(_separator);
  final folder = at < 0 ? '' : doc.docPath.substring(0, at);
  return folder.isEmpty
      ? context.docsRoot.path
      : '${context.docsRoot.path}/$folder';
}

String _baseName(File file) =>
    file.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
