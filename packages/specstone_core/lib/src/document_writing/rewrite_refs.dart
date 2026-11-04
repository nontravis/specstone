import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:specstone_core/src/document_writing/link_destinations.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/document_writing/rewrite_labels.dart';
import 'package:specstone_core/src/document_writing/rewrite_mentions.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show startsWithUtf8Bom;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart'
    show RenderFault;
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

export 'package:specstone_core/src/document_writing/moved_paths.dart'
    show PathMove, movedPath, relativeHref;

/// The byte-order mark as the one character a journal step's text carries.
const _bom = '\uFEFF';

/// A comment that ends a YAML value; `#` opens it only after a space.
const _trailingComment = r'(?<tail>\s+#.*)?';

/// Returns [lfText] with each doc link set to the path [moves] leave its
/// target at, or null when no link changes.
///
/// [docPath] is where the doc sits before the moves. A link is a relative
/// target of any extension, or a folder, that the markdown parser reports,
/// whether it stays under the docs root or leaves it; its new href is the
/// relative path between the moved doc and the moved target, with the `?` or
/// `#` part and a folder's trailing `/` kept. A link whose relative path is
/// unchanged, a web address, another scheme, and a rooted path keep their
/// text.
///
/// Only the text after the frontmatter is read, as the doc model does, so a
/// link-shaped frontmatter value keeps every byte. The parser reports no
/// source positions, so each `](` or `]:` destination is taken as spelled,
/// read alone for the href the parser makes of that spelling, and replaced
/// only when a probe parse, with that span swapped for a unique name, still
/// yields a link to the name. An href in a code span or a fenced block keeps
/// every byte. All proven occurrences change in one pass.
String? rewriteDocLinks(
  String lfText, {
  required String docPath,
  required List<PathMove> moves,
}) => rewriteDocLinksCounted(lfText, docPath: docPath, moves: moves)?.lfText;

/// Returns [rewriteDocLinks]'s text with the number of link destinations it
/// changed, or null when no link changes.
({String lfText, int count})? rewriteDocLinksCounted(
  String lfText, {
  required String docPath,
  required List<PathMove> moves,
}) {
  final body = Doc.parse(lfText).afterFrontmatter;
  if (!body.contains('](') && !body.contains(']:')) return null;
  final edits = <({int start, int end, String text})>[];
  for (final span in destinationsIn(body)) {
    final href = _hrefOfSpelling(
      body.substring(span.start, span.end),
      span.angle,
    );
    final newHref = href == null ? null : _movedHref(href, docPath, moves);
    if (newHref != null && _yieldsLinkAt(body, span.start, span.end)) {
      edits.add((start: span.start, end: span.end, text: newHref));
    }
  }
  if (edits.isEmpty) return null;
  edits.sort((a, b) => b.start.compareTo(a.start));
  var result = body;
  for (final edit in edits) {
    result = result.replaceRange(edit.start, edit.end, edit.text);
  }
  return (
    lfText: lfText.substring(0, lfText.length - body.length) + result,
    count: edits.length,
  );
}

/// Returns [lfText] with each `doc_ref` value in [renamed] set to its new
/// name, or null when no value changes.
///
/// [renamed] maps `(doc type id, old name)` to the new name. Only a key
/// block of a `doc_ref` field in [fields] changes; a value is a block-list
/// item, an inline scalar, or a flow-list item, quoted or not, and a value
/// in the field's `docTypes` is matched by its doc type. A field that names
/// none changes a value only when every renamed doc it names agrees on one
/// new name. Of two blocks with one name only the first counts. Prose,
/// comments, and other fields keep their text.
String? rewriteDocRefs(
  String lfText, {
  required List<MergedField> fields,
  required Map<(String, String), String> renamed,
}) {
  final blocks = Doc.parse(lfText).frontmatter;
  if (blocks == null || renamed.isEmpty) return null;
  var result = lfText;
  final seen = <String>{};
  for (final block in blocks) {
    if (!seen.add(block.name)) continue;
    for (final field in fields) {
      if (field.type != FieldType.docRef || field.id != block.name) continue;
      final text = _renameInBlock(block.text, block.key, field, renamed);
      if (text != block.text) result = withKeyBlock(result, block.name, text);
    }
  }
  return result == lfText ? null : result;
}

/// Returns the journal writes that keep every link and `doc_ref` value true
/// after [moves] and the renames in [renamed].
///
/// The candidates are the docs, typed or untyped, that link to a doc or to
/// any other file or folder under a moved path, that move away from a link's
/// target, that hold a path mention [rewritePathMentions] changes, and, for
/// [renamed], the typed docs whose `doc_ref` values name a renamed doc and
/// the `journey` and `api` docs whose step identities, FR trace cells, or
/// `confirmed` labels do.
/// A doc is chosen from a lenient read, so a non-UTF-8 doc that names nothing
/// renamed never blocks. Each is read from disk before the moves; a step
/// holds its text after the rewrites, in the file's line endings and BOM,
/// at its project path after the moves. Steps are sorted by path. No draft
/// or approved mark is touched.
/// Throws [RenderFault] `output_not_writable` for a candidate that is not
/// UTF-8 text or that is read-only and would change.
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
    if (_linksToMovedFile(index, doc, moves) ||
        _movesAwayFromLink(index, doc, moves) ||
        _mentionsMovedFile(session, doc, moves)) {
      candidates[doc.docPath] = doc;
    }
    if (_namesRenamedDoc(index, doc, renamed) ||
        _namesRenamedLabel(session, doc, renamed)) {
      candidates[doc.docPath] = doc;
    }
  }
  final steps = [
    for (final doc in candidates.values)
      ?_stepFor(session, doc, moves, renamed),
  ]..sort((a, b) => a.path.compareTo(b.path));
  return steps;
}

/// Whether [doc] holds a file link, a link that is no doc link, to a path
/// that [moves] move.
bool _linksToMovedFile(DocIndex index, IndexedDoc doc, List<PathMove> moves) =>
    index
        .contentOf(doc)
        .lineFacts
        .fileLinks
        .any((link) => movedFilePath(link.target, moves) != link.target);

/// Whether [doc] moves and a link it holds takes another shortest path from
/// its new folder; a link that keeps its shortest path still reaches it.
bool _movesAwayFromLink(DocIndex index, IndexedDoc doc, List<PathMove> moves) {
  final movedDoc = movedPath(doc.docPath, moves);
  if (movedDoc == doc.docPath) return false;
  final facts = index.contentOf(doc).lineFacts;
  return [...facts.links, ...facts.fileLinks].any(
    (link) =>
        relativeHref(movedDoc, movedFilePath(link.target, moves)) !=
        relativeHref(doc.docPath, link.target),
  );
}

/// Whether [doc] holds a path mention that [moves] change.
bool _mentionsMovedFile(
  WriteSession session,
  IndexedDoc doc,
  List<PathMove> moves,
) =>
    rewritePathMentions(
      toLf(session.index.contentOf(doc).text),
      docPath: doc.docPath,
      moves: moves,
      exists: (path) => _existsBeforeMoves(session, path),
    ) !=
    null;

/// Whether [path], from the docs root and possibly leaving it, names an
/// indexed doc or a file or folder on disk.
///
/// Planning runs before the moves, so this reads the tree as it stands.
bool _existsBeforeMoves(WriteSession session, String path) =>
    session.index.at(path) != null ||
    FileSystemEntity.typeSync(session.fileOf(path).path) !=
        FileSystemEntityType.notFound;

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
  final mentioned =
      rewritePathMentions(
        linked ?? lfText,
        docPath: doc.docPath,
        moves: moves,
        exists: (path) => _existsBeforeMoves(session, path),
      )?.lfText ??
      linked;
  final fields = session.index.typeOf(doc)?.fields ?? const <MergedField>[];
  final refs =
      rewriteDocRefs(mentioned ?? lfText, fields: fields, renamed: renamed) ??
      mentioned;
  final text =
      rewriteLinkLabels(
        refs ?? lfText,
        docType: session.index.typeOf(doc),
        featureName: session.index.parentOf(doc)?.name,
        newFeatureName: _newParentName(session, doc, renamed),
        renamed: renamed,
      ) ??
      refs;
  if (text == null) return null;
  session.requireWritable(doc.docPath);
  final bom = startsWithUtf8Bom(bytes) ? _bom : '';
  return WriteStep(
    session.projectPathOf(movedPath(doc.docPath, moves)),
    '$bom${LineEnding.of(raw).apply(text)}',
  );
}

/// Returns the Name of [doc]'s parent after the renames in [renamed], null
/// when [doc] has no parent.
String? _newParentName(
  WriteSession session,
  IndexedDoc doc,
  Map<(String, String), String> renamed,
) {
  final parent = session.index.parentOf(doc);
  if (parent == null) return null;
  return renamed[(parent.docTypeId, parent.name)] ?? parent.name;
}

/// Whether a `journey` or `api` [doc] holds a step identity, FR trace cell,
/// or `confirmed` label that [renamed] renames.
///
/// Reads the file leniently, as the index does, so a doc that names no
/// renamed doc is never read strictly and never refuses the rename.
bool _namesRenamedLabel(
  WriteSession session,
  IndexedDoc doc,
  Map<(String, String), String> renamed,
) {
  if (renamed.isEmpty || !carriesLinkLabels(doc.docTypeId)) return false;
  final String text;
  try {
    text = utf8.decode(
      session.fileOf(doc.docPath).readAsBytesSync(),
      allowMalformed: true,
    );
  } on FileSystemException {
    return false;
  }
  return rewriteLinkLabels(
        toLf(text),
        docType: session.index.typeOf(doc),
        featureName: session.index.parentOf(doc)?.name,
        newFeatureName: _newParentName(session, doc, renamed),
        renamed: renamed,
      ) !=
      null;
}

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
///
/// A field with no `docTypes` takes the rename only when every renamed doc
/// called [value] agrees on the new name; two different names leave it.
String? _newName(
  MergedField field,
  String value,
  Map<(String, String), String> renamed,
) {
  final types = field.docTypes;
  if (types == null) {
    final names = {
      for (final e in renamed.entries)
        if (e.key.$2 == value) e.value,
    };
    return names.length == 1 ? names.single : null;
  }
  return types.map((type) => renamed[(type, value)]).nonNulls.firstOrNull;
}

/// Returns the hrefs of every link and image the markdown parser finds in
/// [lfText].
///
/// Returns none when the parser fails on it, so no span of it proves a link.
Set<String> _hrefsOf(String lfText) {
  final nodes = parseMarkdown(lfText);
  if (nodes == null) return const {};
  final hrefs = <String>{};
  void visit(List<Node> nodes) {
    for (final node in nodes) {
      if (node is! Element) continue;
      final href = switch (node.tag) {
        'a' => node.attributes['href'] ?? '',
        'img' => node.attributes['src'],
        _ => null,
      };
      if (href != null) hrefs.add(href);
      final children = node.children;
      if (children != null) visit(children);
    }
  }

  visit(nodes);
  return hrefs;
}

/// Returns the href the markdown parser makes of [raw] alone, or null when it
/// does not make exactly one link of it.
String? _hrefOfSpelling(String raw, bool angle) {
  final hrefs = _hrefsOf(angle ? '[x](<$raw>)' : '[x]($raw)');
  return hrefs.length == 1 ? hrefs.single : null;
}

/// Whether swapping `[start, end)` of [lfText] for a unique name yields a
/// link to that name, which proves the span is a link's href.
bool _yieldsLinkAt(String lfText, int start, int end) {
  final probe = 'specstone-probe-$start.md';
  return _hrefsOf(lfText.replaceRange(start, end, probe)).contains(probe);
}

/// Returns [href] after [moves], or null when the link keeps its text.
///
/// The target is any relative file, or a folder, under or outside the docs
/// root. A folder link keeps its trailing `/`.
String? _movedHref(String href, String docPath, List<PathMove> moves) {
  final cut = href.indexOf(RegExp('[?#]'));
  final path = cut < 0 ? href : href.substring(0, cut);
  // Re-encoding the decoded path would turn an escape that is not UTF-8 into
  // U+FFFD, so the link keeps the bytes the author wrote.
  if (!percentDecodesCleanly(path)) return null;
  final after = movedRelativePath(path, docPath, moves);
  if (after == null) return null;
  final slash = path.endsWith('/') ? '/' : '';
  final encoded = after.split('/').map(Uri.encodeComponent).join('/');
  return cut < 0 ? '$encoded$slash' : '$encoded$slash${href.substring(cut)}';
}

/// Returns the key block [text] of [field] with each renamed value replaced.
///
/// [key] is the key as spelled in the block, quotes included.
String _renameInBlock(
  String text,
  String key,
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
        ? line.startsWith(key)
              ? keyRest.firstMatch(line.substring(key.length))
              : null
        : RegExp(r'^(\s*-\s+)(.*)$').firstMatch(line);
    if (match == null) continue;
    final head = i == keyLine ? key + match[1]! : match[1]!;
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
  final flow = RegExp(r'^\[(?<items>[^\]]*)\](?<tail>\s*(?:#.*)?)$');
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
