import 'dart:convert';

import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart' show utf8Bom;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart'
    show RenderFault;
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// One move of a doc or a folder, as DocPaths.
///
/// A folder ends in `/`, a file does not.
typedef PathMove = ({String from, String to});

/// The byte-order mark as the one character a journal step's text carries.
const _bom = '﻿';

/// A comment that ends a YAML value; `#` opens it only after a space.
const _trailingComment = r'(?<tail>\s+#.*)?';

/// Returns [docPath] after the first of [moves] whose `from` is the path
/// itself or a folder holding it.
String movedPath(String docPath, List<PathMove> moves) {
  for (final move in moves) {
    final holds = move.from.endsWith('/')
        ? docPath.startsWith(move.from)
        : docPath == move.from;
    if (holds) return move.to + docPath.substring(move.from.length);
  }
  return docPath;
}

/// Returns the `/`-separated path from the folder of [fromDocPath] to
/// [toDocPath], with `..` segments up to the common folder.
String relativeHref(String fromDocPath, String toDocPath) {
  final fromFolder = fromDocPath.split('/')..removeLast();
  final to = toDocPath.split('/');
  var common = 0;
  while (common < fromFolder.length &&
      common < to.length - 1 &&
      fromFolder[common] == to[common]) {
    common++;
  }
  return [
    ...List.filled(fromFolder.length - common, '..'),
    ...to.skip(common),
  ].join('/');
}

/// Returns [lfText] with each doc link set to the path [moves] leave its
/// target at, or null when no link changes.
///
/// [docPath] is where the doc sits before the moves. A link is a `.md`
/// target the markdown parser reports and the doc model resolves; its new
/// href is the relative path between the moved doc and the moved target,
/// with the `?` or `#` part kept. A link whose relative path is unchanged,
/// a web address, and a path outside the docs root keep their text.
///
/// The parser reports no source positions, so each `](href` or `]: href`
/// occurrence is replaced only when a probe parse, with that one href
/// swapped for a unique name, still yields a link to the name. An href in a
/// code span or a fenced block keeps every byte. All proven occurrences
/// change in one pass.
String? rewriteDocLinks(
  String lfText, {
  required String docPath,
  required List<PathMove> moves,
}) {
  if (!lfText.contains('](') && !lfText.contains(']:')) return null;
  final edits = <({int start, int end, String text})>[];
  for (final href in _hrefsOf(lfText)) {
    final newHref = _movedHref(href, docPath, moves);
    if (newHref == null) continue;
    final occurrence = RegExp(r'\](?:\(|:)\s*<?' + RegExp.escape(href));
    for (final match in occurrence.allMatches(lfText)) {
      final start = match.end - href.length;
      if (_yieldsLinkAt(lfText, start, match.end)) {
        edits.add((start: start, end: match.end, text: newHref));
      }
    }
  }
  if (edits.isEmpty) return null;
  edits.sort((a, b) => b.start.compareTo(a.start));
  var result = lfText;
  for (final edit in edits) {
    result = result.replaceRange(edit.start, edit.end, edit.text);
  }
  return result;
}

/// Returns [lfText] with each `doc_ref` value in [renamed] set to its new
/// name, or null when no value changes.
///
/// [renamed] maps `(doc type id, old name)` to the new name. Only a key
/// block of a `doc_ref` field in [fields] changes; a value is a block-list
/// item, an inline scalar, or a flow-list item, quoted or not, and a value
/// in the field's `docTypes` is matched by its doc type, any type when the
/// field names none. Prose, comments, and other fields keep their text.
String? rewriteDocRefs(
  String lfText, {
  required List<MergedField> fields,
  required Map<(String, String), String> renamed,
}) {
  final blocks = Doc.parse(lfText).frontmatter;
  if (blocks == null || renamed.isEmpty) return null;
  var result = lfText;
  for (final block in blocks) {
    for (final field in fields) {
      if (field.type != FieldType.docRef || field.id != block.key) continue;
      final text = _renameInBlock(block.text, field, renamed);
      if (text != block.text) result = withKeyBlock(result, block.key, text);
    }
  }
  return result == lfText ? null : result;
}

/// Returns the journal writes that keep every link and `doc_ref` value true
/// after [moves] and the renames in [renamed].
///
/// The candidates are the docs, typed or untyped, that link to a doc under a
/// moved path, and, for [renamed], the typed docs whose `doc_ref` values
/// name a renamed doc. Each is read from disk before the moves; a step
/// holds its text after the rewrites, in the file's line endings and BOM,
/// at its project path after the moves. Steps are sorted by path. No draft
/// or approved mark is touched.
/// Throws [RenderFault] `output_not_writable` for a candidate that is not
/// UTF-8 text.
List<WriteStep> planRewrites(
  WriteSession session,
  List<PathMove> moves, {
  Map<(String, String), String> renamed = const {},
}) {
  final index = session.index;
  final candidates = <String, IndexedDoc>{};
  for (final doc in index.docs) {
    if (movedPath(doc.docPath, moves) != doc.docPath) {
      for (final linker in index.linkingTo(doc)) {
        candidates[linker.docPath] = linker;
      }
    }
    if (_namesRenamedDoc(index, doc, renamed)) candidates[doc.docPath] = doc;
  }
  final steps = [
    for (final doc in candidates.values)
      ?_stepFor(session, doc, moves, renamed),
  ]..sort((a, b) => a.path.compareTo(b.path));
  return steps;
}

WriteStep? _stepFor(
  WriteSession session,
  IndexedDoc doc,
  List<PathMove> moves,
  Map<(String, String), String> renamed,
) {
  final bytes = session.readDocBytes(doc.docPath);
  if (bytes == null) return null;
  final raw = utf8.decode(bytes);
  final lfText = toLf(raw);
  final linked = rewriteDocLinks(lfText, docPath: doc.docPath, moves: moves);
  final fields = session.index.typeOf(doc)?.fields ?? const <MergedField>[];
  final text =
      rewriteDocRefs(linked ?? lfText, fields: fields, renamed: renamed) ??
      linked;
  if (text == null) return null;
  final bom = _startsWithBom(bytes) ? _bom : '';
  return WriteStep(
    session.projectPathOf(movedPath(doc.docPath, moves)),
    '$bom${LineEnding.of(raw).apply(text)}',
  );
}

bool _startsWithBom(List<int> bytes) =>
    bytes.length >= utf8Bom.length &&
    utf8Bom.indexed.every((e) => bytes[e.$1] == e.$2);

/// Whether [doc] carries a `doc_ref` value that [renamed] renames.
bool _namesRenamedDoc(
  DocIndex index,
  IndexedDoc doc,
  Map<(String, String), String> renamed,
) {
  if (renamed.isEmpty) return false;
  for (final field in index.typeOf(doc)?.fields ?? const <MergedField>[]) {
    if (field.type != FieldType.docRef) continue;
    final value = doc.frontmatter[field.id];
    final values = value is List ? value : [value];
    if (values.any((v) => v is String && _newName(field, v, renamed) != null)) {
      return true;
    }
  }
  return false;
}

/// Returns the new name of [value] in [field], or null when it is not renamed.
String? _newName(
  MergedField field,
  String value,
  Map<(String, String), String> renamed,
) {
  final types = field.docTypes;
  if (types == null) {
    return renamed.entries.where((e) => e.key.$2 == value).firstOrNull?.value;
  }
  return types.map((type) => renamed[(type, value)]).nonNulls.firstOrNull;
}

/// Returns the hrefs of every link the markdown parser finds in [lfText].
Set<String> _hrefsOf(String lfText) {
  final hrefs = <String>{};
  void visit(List<Node> nodes) {
    for (final node in nodes) {
      if (node is! Element) continue;
      if (node.tag == 'a') hrefs.add(node.attributes['href'] ?? '');
      final children = node.children;
      if (children != null) visit(children);
    }
  }

  visit(Document(extensionSet: ExtensionSet.gitHubFlavored).parse(lfText));
  return hrefs;
}

/// Whether swapping `[start, end)` of [lfText] for a unique name yields a
/// link to that name, which proves the span is a link's href.
bool _yieldsLinkAt(String lfText, int start, int end) {
  final probe = 'specstone-probe-$start.md';
  return _hrefsOf(lfText.replaceRange(start, end, probe)).contains(probe);
}

/// Returns [href] after [moves], or null when the link keeps its text.
String? _movedHref(String href, String docPath, List<PathMove> moves) {
  final target = resolveDocLink(href, docPath);
  if (target is! DocTarget || !target.docPath.endsWith('.md')) return null;
  final cut = href.indexOf(RegExp('[?#]'));
  if (cut == 0) return null;
  final before = relativeHref(docPath, target.docPath);
  final after = relativeHref(
    movedPath(docPath, moves),
    movedPath(target.docPath, moves),
  );
  if (before == after) return null;
  final encoded = after.split('/').map(Uri.encodeComponent).join('/');
  return cut < 0 ? encoded : '$encoded${href.substring(cut)}';
}

/// Returns the key block [text] of [field] with each renamed value replaced.
String _renameInBlock(
  String text,
  MergedField field,
  Map<(String, String), String> renamed,
) {
  final lines = text.split('\n');
  final keyLine = lines.indexWhere((line) => !_isTrivia(line));
  final keyRest = RegExp(r'^(\s*:\s*)(.*)$');
  for (var i = keyLine; i >= 0 && i < lines.length; i++) {
    final line = lines[i];
    if (_isTrivia(line)) continue;
    final match = i == keyLine
        ? line.startsWith(field.id)
              ? keyRest.firstMatch(line.substring(field.id.length))
              : null
        : RegExp(r'^(\s*-\s+)(.*)$').firstMatch(line);
    if (match == null) continue;
    final head = i == keyLine ? field.id + match[1]! : match[1]!;
    lines[i] = head + _renameValues(match[2]!, field, renamed);
  }
  return lines.join('\n');
}

bool _isTrivia(String line) =>
    line.trim().isEmpty || line.trimLeft().startsWith('#');

/// Returns [region], the text after `key:` or `- `, with renamed values set.
String _renameValues(
  String region,
  MergedField field,
  Map<(String, String), String> renamed,
) {
  final flow = RegExp(r'^\[(?<items>.*)\](?<tail>\s*(?:#.*)?)$');
  final flowMatch = flow.firstMatch(region);
  if (flowMatch != null) {
    final items = flowMatch.namedGroup('items')!.split(',').map((item) {
      final token = item.trim();
      final renamedToken = _renameToken(token, field, renamed);
      return item.replaceFirst(token, renamedToken);
    });
    return '[${items.join(',')}]${flowMatch.namedGroup('tail')}';
  }
  final scalar = RegExp(
    '^(?<token>"[^"]*"|\'[^\']*\'|\\S.*?)$_trailingComment\\s*\$',
  ).firstMatch(region);
  if (scalar == null) return region;
  final token = scalar.namedGroup('token')!;
  return _renameToken(token, field, renamed) + region.substring(token.length);
}

/// Returns [token], a scalar as written with its quotes, renamed if needed.
String _renameToken(
  String token,
  MergedField field,
  Map<(String, String), String> renamed,
) {
  final quote =
      token.length >= 2 &&
          (token.startsWith('"') || token.startsWith("'")) &&
          token.endsWith(token[0])
      ? token[0]
      : '';
  final value = quote.isEmpty ? token : token.substring(1, token.length - 1);
  final name = _newName(field, value, renamed);
  return name == null ? token : '$quote$name$quote';
}
