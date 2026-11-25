import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/models/see_target.dart';
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/consistency_check/outside_docs.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/models/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/link_places.dart'
    show sourceHrefsOf;
import 'package:specstone_core/src/index_query/link_scan.dart'
    show linkSourcesOf;
import 'package:specstone_core/src/index_query/models/link_source.dart';
import 'package:specstone_core/src/portable_path.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/line_ending.dart' show toLf;
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/layer_source.dart'
    show projectTemplatesFolder;
import 'package:yaml/yaml.dart';

/// Ids of the doc types whose `files` entries name files beside the doc.
const _filesListingTypes = {'reference', 'competitor'};

/// Id of the doc type whose Concerns lines end with a `see` target.
const architectureTypeId = 'architecture';
const _filesField = 'files';

/// Id of the section whose lines end with a `see` target.
const concernsSectionId = 'concerns';
const _seeMarker = ' see ';
const _backtick = '`';
const _trailingPunctuation = '.,;:!?';
const _referenceKey = 'reference';
const _addKey = 'add';
const _docKey = 'doc';

/// Returns the `listed_file_missing` and `concerns_target_unresolved`
/// findings of a typed [doc].
///
/// A `reference` or `competitor` doc lists files that sit beside it. An
/// `architecture` doc, or one of a type built on it, ends each Concerns line
/// with `see <x>`, where `<x>` is a sibling file or a `##` header of the doc,
/// matched as the doc formatter matches headers.
Iterable<Finding> checkReferenceEntries(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (context.typeOf(doc)?.buildsOn(architectureTypeId) ?? false) {
    yield* _unresolvedConcerns(context, doc);
  }
  if (_filesListingTypes.contains(doc.docTypeId)) {
    yield* _missingListedFiles(context, doc);
  }
}

/// Returns a `reference_doc_unresolved` finding for each `doc` entry of a
/// project template `reference:` list that names no doc.
///
/// Reads the top-level `<id>.yaml` files of `.specstone/templates/`, in the
/// plain `reference:` list or its `add:` list. The finding sits at the entry's
/// line of the template file and carries no name.
Iterable<Finding> unresolvedTemplateReferences(CheckContext context) sync* {
  final folder = Directory(
    '${context.projectRoot.path}/$projectTemplatesFolder',
  );
  if (!folder.existsSync()) return;
  final files = [
    for (final entity in folder.listSync())
      if (entity is File && isDocTypeFileName(_baseName(entity))) entity,
  ]..sort((a, b) => _baseName(a).compareTo(_baseName(b)));
  final names = {for (final doc in context.index.docs) doc.name};
  for (final file in files) {
    final path = '$projectTemplatesFolder/${_baseName(file)}';
    for (final _DocEntry(:value, :line) in _docEntries(file)) {
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
  for (final YamlEntry(:value, :line)
      in context.linesOf(doc).entriesOf(_filesField)) {
    if (value is! String || _namesFileBeside(folder, value)) continue;
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
      // The doc's markdown_unparsed already says its links go unchecked.
      if (link case _SpanningLink(href: null)) continue;
      final outside = _outsideSeePath(
        context,
        doc,
        link?.href ?? target,
        headers,
        isLink: link != null,
      );
      if (outside != null) {
        // A reported link is the link rule's own; a bare path is reported here.
        if (link == null) {
          yield _outsideSeeFinding(context, doc, line.line, target, outside);
        }
        continue;
      }
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
        keys: {'value': target},
      );
    }
  }
}

Finding _outsideSeeFinding(
  CheckContext context,
  IndexedDoc doc,
  int line,
  String target,
  String path,
) => context.finding(
  doc,
  FindingKind.linkOutsideDocs,
  line: line,
  message:
      'links $path, outside the docs; move the file into the docs or drop '
      'the link',
  keys: {'value': target, 'targetPath': path},
);

/// Returns the project path [text], a `see` target or the href of the link that
/// spans it, names when that file lies outside the checked folders; null
/// otherwise.
///
/// A bare target that names a `##` header of the doc is that header, never a
/// file. The anchor is not read.
String? _outsideSeePath(
  CheckContext context,
  IndexedDoc doc,
  String text,
  Set<String> headers, {
  required bool isLink,
}) {
  if (!isLink && headers.contains(headerKey(text))) return null;
  final path = relativeFilePathOf(text, doc.docPath);
  if (path == null) return null;
  return outsideDocsPathOf(context, projectFilePathOf(path, doc.docPath));
}

/// Returns the text after the last ` see ` of [line], less trailing
/// punctuation and whitespace and one pair of backticks, with the index it
/// starts at in [line]; null for a line that holds no ` see `.
SeeTarget? seeTargetIn(String line) {
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
  return text.isEmpty ? null : SeeTarget(text: text, start: start);
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
/// doc itself included, or an anchor of the doc or of that file.
///
/// A link, [isLink], names no section, as the link rule reads it. Text
/// after a path makes it no path. An anchor set that is unknown (null)
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
    return path != null && _fileHolds(context, doc, path, named);
  }
  return false;
}

/// The href `markdown` gives a link that spans a `see` target; null when it
/// gives none or that is unknown.
final class _SpanningLink {
  const new({required this.href});

  final String? href;
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
  late final List<String?>? _hrefs = sourceHrefsOf(_body, _all);

  /// Returns the one link that spans column [start] to column [end] of file
  /// line [line], as the link rule reads it, with the href `markdown` gives
  /// it, null when it gives none or that is unknown; null when no link with a
  /// destination spans them.
  _SpanningLink? linkSpanning(
    int line, {
    required int start,
    required int end,
  }) {
    for (final (index, source) in _all.indexed) {
      if (source.line != line || !_spans(source, start, end)) continue;
      return source.shown == null ? null : _SpanningLink(href: _hrefs?[index]);
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

/// Whether the file at [path] under the root [doc] is read from exists and,
/// when it is an indexed doc of either root, holds the anchor [named].
bool _fileHolds(
  CheckContext context,
  IndexedDoc doc,
  String path,
  String? named,
) {
  final root = rootOfDocPath(
    doc.docPath,
    docsRoot: context.docsRoot,
    projectRoot: context.projectRoot,
  );
  if (!_namesFileBeside(root.path, path)) return false;
  final docPath = docPathOfProjectPath(projectFilePathOf(path, doc.docPath));
  final file = docPath == null ? null : context.index.at(docPath);
  return named == null ||
      file == null ||
      _holds(context.contentOf(file).lineFacts.anchors, named);
}

/// Whether [path], `/`-separated, is a file under [folder]; a path that is no
/// [isPortablePath] is none, so no OS finds a file there.
bool _namesFileBeside(String folder, String path) =>
    isPortablePath(path) && File('$folder/$path').existsSync();

bool _holds(DocAnchors? anchors, String anchor) =>
    anchors == null || anchors.holds(anchor);

/// One `doc` value of a template reference entry, and its 1-based line.
final class _DocEntry {
  const new({required this.value, required this.line});

  final String value;
  final int line;
}

/// Returns each string `doc` value of the reference entries of [file], with
/// its 1-based line.
Iterable<_DocEntry> _docEntries(File file) sync* {
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
      yield _DocEntry(value: value, line: item.span.start.line + 1);
    }
  }
}

String _folderOf(CheckContext context, IndexedDoc doc) => fileOfDocPath(
  doc.docPath,
  docsRoot: context.docsRoot,
  projectRoot: context.projectRoot,
).parent.path;

String _baseName(File file) =>
    file.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
