import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/link_places.dart' show LinkPlace;
import 'package:specstone_core/src/rendering/formatter.dart';
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
const _linkOpen = '[';
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
  final facts = context.contentOf(doc).lineFacts;
  for (var i = 0; i < held.length; i++) {
    if (context.templateSectionAt(doc, i)?.id != concernsSectionId) {
      continue;
    }
    for (final line in context.bodyLinesOf(doc, i)) {
      final target = line.fenced ? null : seeTargetIn(line.text)?.text;
      if (target == null) continue;
      final resolves = target.startsWith(_linkOpen)
          ? _linkSeeResolves(context, facts, line.line)
          : _pathSeeResolves(context, doc, target, facts.anchors);
      if (headers.contains(headerKey(target)) || resolves) continue;
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
/// punctuation and one pair of backticks, with the index it starts at in
/// [line]; null for a line that is `N/A — ` or holds no ` see `.
({String text, int start})? seeTargetIn(String line) {
  if (line.contains(_notApplicable)) return null;
  final at = line.lastIndexOf(_seeMarker);
  if (at < 0) return null;
  final after = line.substring(at + _seeMarker.length);
  var start = at + _seeMarker.length + after.length - after.trimLeft().length;
  var text = _withoutTrailingPunctuation(after.trim());
  if (text.length > 1 &&
      text.startsWith(_backtick) &&
      text.endsWith(_backtick)) {
    text = text.substring(1, text.length - 1);
    start++;
  }
  return text.isEmpty ? null : (text: text, start: start);
}

String _withoutTrailingPunctuation(String text) {
  var end = text.length;
  while (end > 0 && _trailingPunctuation.contains(text[end - 1])) {
    end--;
  }
  return text.substring(0, end);
}

/// Whether [target], a `see` target that is no section header, names a file
/// beside [doc] or an anchor of the doc or of that file (R63).
///
/// The target is a bare path or `#anchor`; a target written with link syntax
/// goes to [_linkSeeResolves]. An anchor set that is unknown (null) or a file
/// no doc indexes raises nothing; [anchors] is the set of [doc] itself.
bool _pathSeeResolves(
  CheckContext context,
  IndexedDoc doc,
  String target,
  DocAnchors? anchors,
) {
  if (readLinkTarget(target) case RelativeLink(
    :final segments,
    :final anchor,
  )) {
    final named = _namedAnchor(anchor);
    if (segments.isEmpty) {
      return anchor != null && _anchorHeld(anchors, named);
    }
    final path = relativeFilePathOf(target, doc.docPath);
    return path != null && _fileHolds(context, path, named);
  }
  return false;
}

/// Whether every link the link rule reads on [line] of a doc, reference
/// definitions known, names a file beside the doc or an anchor of the doc or
/// of that file (R63).
///
/// A line with no link place (a web address) resolves nothing; a doc whose
/// markdown did not parse (null anchors) raises nothing.
bool _linkSeeResolves(CheckContext context, LineFacts facts, int line) {
  if (facts.anchors == null) return true;
  bool onLine(LinkPlace place) => place.line == line;
  final fileLinks = [...facts.links, ...facts.fileLinks].where(onLine);
  final selfLinks = facts.selfLinks.where(onLine);
  if (facts.unreadableLinks.any(onLine)) return false;
  if (fileLinks.isEmpty && selfLinks.isEmpty) return false;
  return fileLinks.every(
        (place) =>
            _fileHolds(context, place.target, _namedAnchor(place.anchor)),
      ) &&
      selfLinks.every(
        (place) =>
            place.anchor != null &&
            _anchorHeld(facts.anchors, _namedAnchor(place.anchor)),
      );
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
