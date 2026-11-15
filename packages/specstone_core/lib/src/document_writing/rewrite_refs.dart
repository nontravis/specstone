import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart'
    show DocTarget, resolveDocLink;
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show markdownExtension;
import 'package:specstone_core/src/doc_model/percent_decode.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/key_block_values.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/document_writing/rewrite_labels.dart';
import 'package:specstone_core/src/document_writing/rewrite_mentions.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/link_places.dart'
    show hrefDestinationsOf, sourceHrefsOf;
import 'package:specstone_core/src/index_query/link_scan.dart'
    show LinkScan, LinkSource, linkScanOf;
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart'
    show RenderFault;
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

export 'package:specstone_core/src/document_writing/moved_paths.dart'
    show PathMove, movedPath, relativeHref;

/// Rewrites the LF text of a doc; null when nothing changes.
typedef TextEdit = String? Function(String lfText);

/// The `(doc type id, old name)` key in a `renamed` map of each doc whose Name
/// changes, by the DocPath the doc has before the moves.
typedef RenamedDocs = Map<String, (String, String)>;

/// One replacement in a text: the units from `start` up to `end` take `text`.
typedef _TextEdit = ({int start, int end, String text});

const _backslash = 0x5C;
const _openParen = 0x28;
const _closeParen = 0x29;
const _openBracket = 0x5B;
const _lessThan = 0x3C;
const _encodedOpenParen = '%28';
const _encodedCloseParen = '%29';

/// Returns [lfText] with each doc link set to the path [moves] leave its
/// target at, or null when no link changes.
///
/// [docPath] is where the doc sits before the moves. A link is a relative
/// target of any extension, or a folder, that the markdown parser reports,
/// whether it stays under the docs root or leaves it; its new path is the
/// relative path between the moved doc and the moved target, a folder's
/// trailing `/` kept. A link whose relative path is unchanged, a web address,
/// another scheme, and a rooted path keep their text.
///
/// Only the text after the frontmatter is read, as the doc model does, so a
/// link-shaped frontmatter value keeps every byte. Each inline link's and
/// each definition's destination as written moves by the href the parser
/// gives it (see [hrefDestinationsOf]), so an href in a code span or a fenced
/// block keeps every byte; only the path it is written with changes, its `?`
/// or `#` part kept as written (see [destinationPartsOf]). All of them change
/// in one pass.
///
/// [renamed] maps `(doc type id, old name)` to the new name. A link text equal
/// to a renamed doc's old Name takes the new Name: after its `<doc type>:`
/// prefix, the prefix kept, on any link; bare, only on a link that reaches
/// that doc, which [renamedDocs] names by its DocPath before the moves. Only
/// the text of an inline link and of a full reference link changes: a shortcut
/// or collapsed link's text is its label, which a definition names, and an
/// image description is no link text.
String? rewriteDocLinks(
  String lfText, {
  required String docPath,
  required List<PathMove> moves,
  Map<(String, String), String> renamed = const {},
  RenamedDocs renamedDocs = const {},
}) => rewriteDocLinksCounted(
  lfText,
  docPath: docPath,
  moves: moves,
  renamed: renamed,
  renamedDocs: renamedDocs,
)?.lfText;

/// Returns [rewriteDocLinks]'s text with the number of link destinations it
/// changed, or null when no link changes.
({String lfText, int count})? rewriteDocLinksCounted(
  String lfText, {
  required String docPath,
  required List<PathMove> moves,
  Map<(String, String), String> renamed = const {},
  RenamedDocs renamedDocs = const {},
}) {
  final body = Doc.parse(lfText).afterFrontmatter;
  if (!_mayHoldLink(body)) return null;
  final scan = linkScanOf(body, firstLine: 1);
  final pathEdits = _pathEdits(
    body,
    scan,
    (href) => _movedPath(href, docPath, moves),
  );
  final edits = [
    ...pathEdits,
    ..._linkTextEdits(body, scan.sources, docPath, renamed, renamedDocs),
  ];
  if (edits.isEmpty) return null;
  return (
    lfText:
        lfText.substring(0, lfText.length - body.length) +
        _withEdits(body, edits),
    count: pathEdits.length,
  );
}

/// Returns [lfBody], text written in the doc at [fromDocPath], with each
/// relative link's path set to reach from [toDocPath] the file or folder it
/// reaches from [fromDocPath] (see [rebasedHref]); a link with an empty
/// path, such as `#rules`, takes the path of [fromDocPath] itself.
///
/// A link keeps its `?` and `#` part, and every other text stays, as
/// [rewriteDocLinks] keeps it: a web address, another scheme, a rooted path,
/// and an href in a code span or a fenced block.
String rebaseDocLinks(
  String lfBody, {
  required String fromDocPath,
  required String toDocPath,
}) {
  if (!_mayHoldLink(lfBody)) return lfBody;
  String? newPathOf(String href) => switch (readLinkTarget(href)) {
    RelativeLink(:final pathEnd) => rebasedHref(
      href.substring(0, pathEnd),
      fromDocPath,
      toDocPath,
    ),
    _ => null,
  };
  final scan = linkScanOf(lfBody, firstLine: 1);
  return _withEdits(lfBody, _pathEdits(lfBody, scan, newPathOf));
}

/// Whether [body] may hold an inline link or a link definition.
bool _mayHoldLink(String body) => body.contains('](') || body.contains(']:');

/// Returns the edits that set the path of each link destination in [body],
/// scanned as [scan], to the one [newPathOf] gives its href, when it gives
/// one.
List<_TextEdit> _pathEdits(
  String body,
  LinkScan scan,
  String? Function(String href) newPathOf,
) {
  final (:destinations, linksRead: _) = hrefDestinationsOf(
    body,
    scan,
    canMove: (href) => newPathOf(href) != null,
  );
  return [
    for (final (:start, :end, :href, :kind) in destinations)
      if (newPathOf(href) case final newPath?)
        (
          start: start,
          end: end,
          text: _withPath(
            body.substring(start, end),
            kind,
            newPath,
            isAngle: _isAngleBracketed(body, start, kind),
          ),
        ),
  ];
}

/// Returns [body] with each of [edits], which never overlap, applied.
String _withEdits(String body, List<_TextEdit> edits) {
  final rightFirst = [...edits]..sort((a, b) => b.start.compareTo(a.start));
  var result = body;
  for (final edit in rightFirst) {
    result = result.replaceRange(edit.start, edit.end, edit.text);
  }
  return result;
}

/// Returns the edits that set the text of each inline or full reference link
/// in [body] equal to a renamed doc's old Name, after its `<doc type>:` prefix
/// or bare on a link that reaches that doc, to the new Name.
List<_TextEdit> _linkTextEdits(
  String body,
  List<LinkSource> sources,
  String docPath,
  Map<(String, String), String> renamed,
  RenamedDocs renamedDocs,
) {
  if (renamed.isEmpty) return const [];
  late final hrefs = sourceHrefsOf(body, sources);
  return [
    for (final (index, source) in sources.indexed)
      ?_namedLinkText(
        body,
        source,
        renamed,
        () => _reachedDoc(hrefs?[index], docPath, renamedDocs),
      ),
  ];
}

/// Returns the key of the renamed doc that [href], written in the doc at
/// [docPath], reaches, or null when it reaches none.
(String, String)? _reachedDoc(
  String? href,
  String docPath,
  RenamedDocs renamedDocs,
) {
  if (href == null) return null;
  return switch (resolveDocLink(href, docPath)) {
    DocTarget(:final docPath) => renamedDocs[docPath],
    _ => null,
  };
}

/// Returns the edit of [source]'s text, or null when [source] is no link whose
/// text is a renamed doc's old Name.
///
/// A bare Name counts only when [reached], the renamed doc the link reaches,
/// is the doc it names.
_TextEdit? _namedLinkText(
  String body,
  LinkSource source,
  Map<(String, String), String> renamed,
  (String, String)? Function() reached,
) {
  final textEnd = source.textEnd;
  if (textEnd == null || body.codeUnitAt(source.offset) != _openBracket) {
    return null;
  }
  if (!_isInlineOrFullReference(body, source, textEnd)) return null;
  final start = source.offset + 1;
  final address = readDocAddress(body.substring(start, textEnd));
  if (address.sectionKey != null) return null;
  final typeId = address.typeId;
  final String? name;
  if (typeId != null) {
    name = renamedNameOf(address, renamed);
  } else {
    final key = reached();
    name = key != null && key.$2 == address.body ? renamed[key] : null;
  }
  if (name == null) return null;
  final prefix = typeId == null ? '' : '$typeId:';
  return (start: start, end: textEnd, text: '$prefix$name');
}

/// Whether [source], whose text ends at [textEnd], is an inline or full
/// reference link, so its text is no label.
///
/// A shortcut link ends right after its `]`, and a collapsed one after `[]`.
bool _isInlineOrFullReference(String body, LinkSource source, int textEnd) =>
    source.end > textEnd + 1 && !body.startsWith('[]', textEnd + 1);

/// Returns [written], a [kind] destination as written, with [path] in place
/// of the path it is written with, its `?` or `#` part kept (see
/// [destinationPartsOf]).
///
/// A destination inside angle brackets, [isAngle], keeps the path's parens as
/// written. A bare one, inline or of a definition, ends at the first `)` no
/// `(` before it opened. There the path's parens are written `%28` and `%29`,
/// which decode the same, and each `)` of the kept part that a `(` of the old
/// path opened takes a `\`, so the link and its href stay.
String _withPath(
  String written,
  DestinationKind kind,
  String path, {
  required bool isAngle,
}) {
  final pathEnd = destinationPartsOf(written, kind).pathEnd;
  final kept = written.substring(pathEnd);
  if (isAngle) return '$path$kept';
  final balanced = path
      .replaceAll('(', _encodedOpenParen)
      .replaceAll(')', _encodedCloseParen);
  final opened = _parensOpenedIn(written.substring(0, pathEnd));
  return '$balanced${_closersEscaped(kept, opened)}';
}

/// Returns whether the [kind] destination of [body] that starts at [start]
/// is inside angle brackets; a definition's range leaves them out, and a bare
/// destination never follows a `<`.
bool _isAngleBracketed(String body, int start, DestinationKind kind) =>
    switch (kind) {
      DestinationKind.angleInline => true,
      DestinationKind.inline => false,
      DestinationKind.definition =>
        start > 0 && body.codeUnitAt(start - 1) == _lessThan,
    };

/// Returns how many parens [text], part of a bare destination, leaves open;
/// a backslash takes the unit after it out of the count, as `markdown` reads.
int _parensOpenedIn(String text) {
  var open = 0;
  for (var i = 0; i < text.length; i++) {
    switch (text.codeUnitAt(i)) {
      case _backslash:
        i++;
      case _openParen:
        open++;
      case _closeParen:
        open--;
    }
  }
  return open;
}

/// Returns [text] with a `\` before each `)` that closes one of [opened]
/// parens opened before it.
String _closersEscaped(String text, int opened) {
  if (opened == 0) return text;
  final out = StringBuffer();
  var open = 0;
  var unclosed = opened;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == _backslash && i + 1 < text.length) {
      out.write(text.substring(i, i + 2));
      i++;
      continue;
    }
    if (unit == _openParen) open++;
    if (unit == _closeParen) {
      if (open > 0) {
        open--;
      } else if (unclosed > 0) {
        unclosed--;
        out.writeCharCode(_backslash);
      }
    }
    out.writeCharCode(unit);
  }
  return out.toString();
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

/// Returns the sorted journal writes that keep every link, `doc_ref`, and
/// doc-name mention true in docs.
///
/// A doc whose hash matched its `approved:` value is re-stamped. Draft marks
/// stay untouched. A code file or an agent file is never written: its
/// mentions are listed by `staleMentions`.
///
/// [recordEdits] maps the DocPath of a record to the edit of its entries; the
/// record is a candidate, indexed or not, and the edit joins the other
/// rewrites of its step.
/// Throws [RenderFault] `output_not_writable` for a candidate that is not
/// UTF-8 text or that is read-only and would change.
List<WriteStep> planRewrites(
  WriteSession session,
  List<PathMove> moves, {
  Map<(String, String), String> renamed = const {},
  Map<String, TextEdit> recordEdits = const {},
}) {
  final index = session.index;
  final renamedDocs = _renamedDocsOf(index, moves, renamed);
  final candidates = <String, IndexedDoc>{};
  for (final doc in index.docs) {
    if (movedPath(doc.docPath, moves) != doc.docPath) {
      for (final linker in index.linkingTo(doc)) {
        candidates[linker.docPath] = linker;
      }
    }
    if (_linksToMovedFile(index, doc, moves) ||
        _movesWithChangedLink(index, doc, moves) ||
        _mentionsMovedFile(session, doc, moves)) {
      candidates[doc.docPath] = doc;
    }
    if (_namesRenamedDoc(index, doc, renamed) ||
        _mentionsRenamedDoc(index, doc, renamed) ||
        _namesRenamedLabel(session, doc, renamed) ||
        _textsRenamedDoc(index, doc, moves, renamed, renamedDocs)) {
      candidates[doc.docPath] = doc;
    }
  }
  for (final docPath in recordEdits.keys) {
    candidates.putIfAbsent(
      docPath,
      () => index.at(docPath) ?? _unindexedDoc(session, docPath),
    );
  }
  final steps = [
    for (final doc in candidates.values)
      ?_stepFor(
        session,
        doc,
        moves,
        renamed,
        renamedDocs,
        recordEdits[doc.docPath],
      ),
  ]..sort((a, b) => a.path.compareTo(b.path));
  return steps;
}

/// Returns the docs of [index] whose Name [renamed] changes under [moves], by
/// their DocPath before the moves.
RenamedDocs _renamedDocsOf(
  DocIndex index,
  List<PathMove> moves,
  Map<(String, String), String> renamed,
) => {
  for (final doc in index.docs)
    if (doc.docTypeId case final typeId?)
      if (movedPath(doc.docPath, moves) != doc.docPath &&
          renamed.containsKey((typeId, doc.name)))
        doc.docPath: (typeId, doc.name),
};

/// Whether [doc] holds a file link, a link that is no doc link, to a path
/// that [moves] move.
bool _linksToMovedFile(DocIndex index, IndexedDoc doc, List<PathMove> moves) =>
    index
        .contentOf(doc)
        .lineFacts
        .fileLinks
        .any((link) => movedFilePath(link.target, moves) != link.target);

/// Whether [doc] moves and [rewriteDocLinks] changes a link it holds, a link
/// to itself or to a target that stays included.
bool _movesWithChangedLink(
  DocIndex index,
  IndexedDoc doc,
  List<PathMove> moves,
) =>
    movedPath(doc.docPath, moves) != doc.docPath &&
    rewriteDocLinks(
          toLf(index.contentOf(doc).text),
          docPath: doc.docPath,
          moves: moves,
        ) !=
        null;

/// Whether [doc] holds a link whose text [rewriteDocLinks] sets to the new
/// Name of a doc in [renamed].
bool _textsRenamedDoc(
  DocIndex index,
  IndexedDoc doc,
  List<PathMove> moves,
  Map<(String, String), String> renamed,
  RenamedDocs renamedDocs,
) {
  if (renamed.isEmpty) return false;
  final text = toLf(index.contentOf(doc).text);
  // A link text names an old Name, so a doc without one needs no parse.
  if (!renamed.keys.any((key) => text.contains(key.$2))) return false;
  return rewriteDocLinks(
        text,
        docPath: doc.docPath,
        moves: moves,
        renamed: renamed,
        renamedDocs: renamedDocs,
      ) !=
      null;
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

/// Returns the doc at [docPath], on disk but not in the session's snapshot, as
/// a step reads it: typed by the matcher, with no parent indexed.
IndexedDoc _unindexedDoc(WriteSession session, String docPath) => IndexedDoc(
  docPath: docPath,
  docTypeId: session.docTypeAt(docPath)?.id,
  name: docPath,
  frontmatter: const {},
  tokens: 0,
);

WriteStep? _stepFor(
  WriteSession session,
  IndexedDoc doc,
  List<PathMove> moves,
  Map<(String, String), String> renamed,
  RenamedDocs renamedDocs,
  TextEdit? recordEdit,
) {
  final bytes = session.readDocBytes(doc.docPath);
  if (bytes == null) return null;
  final raw = utf8.decode(bytes);
  final lfText = toLf(raw);
  final linked = rewriteDocLinks(
    lfText,
    docPath: doc.docPath,
    moves: moves,
    renamed: renamed,
    renamedDocs: renamedDocs,
  );
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
  final named =
      rewriteNameMentions(refs ?? lfText, markdownExtension, renamed) ?? refs;
  final text =
      rewriteLinkLabels(
        named ?? lfText,
        docType: session.index.typeOf(doc),
        featureName: session.index.parentOf(doc)?.name,
        newFeatureName: _newParentName(session, doc, renamed),
        renamed: renamed,
      ) ??
      named;
  final entries = recordEdit?.call(text ?? lfText) ?? text;
  if (entries == null) return null;
  session.requireWritable(doc.docPath);
  final writtenPath = movedPath(doc.docPath, moves);
  final writtenType = session.docTypeAt(writtenPath);
  final laidOut = layOutDoc(entries, writtenType);
  final statusesOutside = session.project.statusesOutsideApproval;
  final wasApproved = _wasApproved(
    lfText,
    session.docTypeAt(doc.docPath),
    statusesOutside: statusesOutside,
  );
  final stamped = wasApproved
      ? withApprovalHash(laidOut, writtenType, statusesOutside: statusesOutside)
      : laidOut;
  return session.docWriteStep(writtenPath, stamped, bytes);
}

/// Whether [lfText], the doc as the step reads it under the lock, is no draft
/// and its `approved:` value is the hash of its content under [docType], so a
/// rewrite of its references re-stamps it (a stale hash stays).
///
/// Read from the bytes the step rewrites, not the index: an edit made after
/// the session opened stays stale.
bool _wasApproved(
  String lfText,
  MergedDocType? docType, {
  required bool statusesOutside,
}) {
  final fields = ApprovalFields.of(Doc.parse(lfText));
  return !fields.isDraft &&
      fields.approvedValue is String &&
      fields.approvedValue ==
          approvalHashOf(lfText, docType, statusesOutside: statusesOutside);
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

/// Whether [doc], of a type that [carriesLinkLabels], holds a step identity,
/// FR trace cell, `traced_from` entry, `confirmed` label, or `overrides`
/// entry that [renamed] renames.
///
/// Reads the file leniently, as the index does, so a doc that names no
/// renamed doc is never read strictly and never refuses the rename.
bool _namesRenamedLabel(
  WriteSession session,
  IndexedDoc doc,
  Map<(String, String), String> renamed,
) {
  if (renamed.isEmpty || !carriesLinkLabels(session.docTypeAt(doc.docPath))) {
    return false;
  }
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

/// Whether [doc] holds a doc-name mention of a doc that [renamed] renames.
bool _mentionsRenamedDoc(
  DocIndex index,
  IndexedDoc doc,
  Map<(String, String), String> renamed,
) =>
    renamed.isNotEmpty &&
    index
        .contentOf(doc)
        .lineFacts
        .nameMentions
        .any((m) => renamedNameOf(m.address, renamed) != null);

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

/// Returns the path part of [href] after [moves], encoded, or null when the
/// link keeps its text.
///
/// The target is any relative file, or a folder, under or outside the docs
/// root. A folder link keeps its trailing `/`.
String? _movedPath(String href, String docPath, List<PathMove> moves) {
  if (readLinkTarget(href) case RelativeLink(:final pathEnd)) {
    return _movedRelativePath(href.substring(0, pathEnd), docPath, moves);
  }
  return null;
}

String? _movedRelativePath(String path, String docPath, List<PathMove> moves) {
  // Re-encoding the decoded path would turn an escape that is not UTF-8 into
  // U+FFFD, so the link keeps the bytes the author wrote.
  if (!percentDecodesCleanly(path)) return null;
  final after = movedRelativePath(path, docPath, moves);
  if (after == null) return null;
  final slash = path.endsWith('/') ? '/' : '';
  return '${after.split('/').map(Uri.encodeComponent).join('/')}$slash';
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
  return renameKeyBlockValues(
    text,
    key,
    (value) => _newName(field, value, renamed),
  );
}
