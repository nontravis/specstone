import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart'
    show DocTarget, projectFilePathOf, resolveDocLink;
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/models/destination_kind.dart';
import 'package:specstone_core/src/doc_model/models/doc_address.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show markdownExtension;
import 'package:specstone_core/src/doc_model/percent_decode.dart';
import 'package:specstone_core/src/doc_model/records_root.dart'
    show docPathOfProjectPath;
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/key_block_values.dart';
import 'package:specstone_core/src/document_writing/models/counted_rewrite.dart';
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/models/renamed_names.dart';
import 'package:specstone_core/src/document_writing/models/text_edit.dart';
import 'package:specstone_core/src/document_writing/models/typed_name.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/document_writing/restamp_pass.dart';
import 'package:specstone_core/src/document_writing/rewrite_labels.dart';
import 'package:specstone_core/src/document_writing/rewrite_mentions.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/link_places.dart'
    show hrefDestinationsOf, sourceHrefsOf;
import 'package:specstone_core/src/index_query/link_scan.dart' show linkScanOf;
import 'package:specstone_core/src/index_query/models/href_destination.dart';
import 'package:specstone_core/src/index_query/models/href_destinations.dart';
import 'package:specstone_core/src/index_query/models/link_scan.dart';
import 'package:specstone_core/src/index_query/models/link_source.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart'
    show RenderFault;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

export 'package:specstone_core/src/document_writing/moved_paths.dart'
    show movedPath, relativeHref;

/// The [TypedName] of each doc whose Name changes, by the DocPath the doc has
/// before the moves.
typedef RenamedDocs = Map<String, TypedName>;

/// One replacement in a text: the units from `start` up to `end` take `text`.
final class _TextEdit {
  const new({required this.start, required this.end, required this.text});

  final int start;
  final int end;
  final String text;
}

const _backslash = 0x5C;
const _openParen = 0x28;
const _closeParen = 0x29;
const _openBracket = 0x5B;
const _hash = 0x23;
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
/// image description is no link text. A text equal to the old last `/` part of
/// a renamed doc's Name, bare or after its own `<doc type>:` prefix, takes the
/// new last part, only on a link that reaches that doc.
String? rewriteDocLinks(
  String lfText, {
  required String docPath,
  required List<PathMove> moves,
  RenamedNames renamed = const RenamedNames({}),
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
CountedRewrite? rewriteDocLinksCounted(
  String lfText, {
  required String docPath,
  required List<PathMove> moves,
  RenamedNames renamed = const RenamedNames({}),
  RenamedDocs renamedDocs = const {},
}) {
  final body = Doc.parse(lfText).afterFrontmatter;
  if (!_mayHoldLink(body)) return null;
  final scan = linkScanOf(body, firstLine: 1);
  final pathEdits = _placeEdits(
    body,
    scan,
    (href) => _placeOfPath(_movedPath(href, docPath, moves)),
  );
  final edits = [
    ...pathEdits,
    ..._linkTextEdits(body, scan.sources, docPath, renamed, renamedDocs),
  ];
  if (edits.isEmpty) return null;
  return CountedRewrite(
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
  return withLinkPlaces(
    lfBody,
    (href) => switch (readLinkTarget(href)) {
      RelativeLink(:final pathEnd) => _placeOfPath(
        rebasedHref(href.substring(0, pathEnd), fromDocPath, toDocPath),
      ),
      _ => null,
    },
  );
}

/// Where a link destination goes: a new path, a new `#anchor`, or both; a
/// null part keeps what is written.
final class LinkPlace {
  const new({this.path, this.anchor, this.dropsAnchor = false});

  final String? path;
  final String? anchor;

  /// Whether the destination loses its `#` part, which [anchor] then does
  /// not set.
  final bool dropsAnchor;
}

LinkPlace? _placeOfPath(String? path) =>
    path == null ? null : LinkPlace(path: path);

/// Returns [lfBody] with each link destination set where [placeOf] puts its
/// href, other text kept as [rewriteDocLinks] keeps it.
///
/// [textOf] gives an inline or full reference link its new text, from its
/// href and text. A link whose href [unwraps] holds for becomes its text.
String withLinkPlaces(
  String lfBody,
  LinkPlace? Function(String href) placeOf, {
  String? Function(String href, String text)? textOf,
  bool Function(String href)? unwraps,
}) {
  if (!_mayHoldLink(lfBody)) return lfBody;
  final scan = linkScanOf(lfBody, firstLine: 1);
  final linkEdits = textOf == null && unwraps == null
      ? const <_TextEdit>[]
      : _linkEditsOf(lfBody, scan.sources, textOf: textOf, unwraps: unwraps);
  return _withEdits(lfBody, [
    ..._placeEdits(lfBody, scan, placeOf),
    ...linkEdits,
  ]);
}

/// Returns the edits [textOf] and [unwraps] make to the links of [body]
/// whose text starts with `[` (no image), each with its href.
List<_TextEdit> _linkEditsOf(
  String body,
  List<LinkSource> sources, {
  required String? Function(String href, String text)? textOf,
  required bool Function(String href)? unwraps,
}) {
  final hrefs = sourceHrefsOf(body, sources);
  if (hrefs == null) return const [];
  return [
    for (final (index, source) in sources.indexed)
      if ((hrefs[index], source.textEnd) case (final href?, final textEnd?)
          when body.codeUnitAt(source.offset) == _openBracket)
        ?_linkEditOf(
          body,
          source,
          href,
          textEnd: textEnd,
          textOf: textOf,
          unwraps: unwraps,
        ),
  ];
}

/// Returns the edit of [source], whose href is [href] and whose text ends at
/// [textEnd], or null when it keeps its text.
_TextEdit? _linkEditOf(
  String body,
  LinkSource source,
  String href, {
  required int textEnd,
  required String? Function(String href, String text)? textOf,
  required bool Function(String href)? unwraps,
}) {
  final text = body.substring(source.offset + 1, textEnd);
  if (unwraps?.call(href) ?? false) {
    return _TextEdit(
      start: source.offset,
      end: source.end,
      text: textOf?.call(href, text) ?? text,
    );
  }
  if (textOf == null || !_isInlineOrFullReference(body, source, textEnd)) {
    return null;
  }
  return switch (textOf(href, text)) {
    final renamed? => _TextEdit(
      start: source.offset + 1,
      end: textEnd,
      text: renamed,
    ),
    null => null,
  };
}

/// Whether [body] may hold an inline link or a link definition.
bool _mayHoldLink(String body) => body.contains('](') || body.contains(']:');

/// Returns the edits that set each link destination in [body], scanned as
/// [scan], to the place [placeOf] gives its href, when it gives one.
List<_TextEdit> _placeEdits(
  String body,
  LinkScan scan,
  LinkPlace? Function(String href) placeOf,
) {
  final HrefDestinations(:destinations) = hrefDestinationsOf(
    body,
    scan,
    canMove: (href) => placeOf(href) != null,
  );
  return [
    for (final HrefDestination(:start, :end, :href, :kind) in destinations)
      if (placeOf(href) case final place?)
        _TextEdit(
          start: start,
          end: end,
          text: _placed(
            body.substring(start, end),
            kind,
            place,
            isAngle: isAngleBracketed(body, start, kind),
          ),
        ),
  ];
}

/// Returns [written], a [kind] destination as written, set to [place].
String _placed(
  String written,
  DestinationKind kind,
  LinkPlace place, {
  required bool isAngle,
}) {
  final anchored = switch (place.anchor) {
    _ when place.dropsAnchor => _withoutAnchor(written, kind),
    null => written,
    final anchor => switch (destinationPartsOf(written, kind).anchorStart) {
      null => '$written#$anchor',
      final at => written.replaceRange(at, written.length, anchor),
    },
  };
  return switch (place.path) {
    null => anchored,
    final path => destinationWithPath(anchored, kind, path, isAngle: isAngle),
  };
}

/// Returns [written], a [kind] destination as written, without its `#` part;
/// the `#` is written plain, escaped, or as a character reference ending in
/// `;`.
String _withoutAnchor(String written, DestinationKind kind) {
  final at = destinationPartsOf(written, kind).anchorStart;
  if (at == null) return written;
  final hash = written.codeUnitAt(at - 1) == _hash
      ? at - 1
      : written.lastIndexOf('&', at - 1);
  if (hash < 0) return written;
  final escaped = hash > 0 && written.codeUnitAt(hash - 1) == _backslash;
  return written.substring(0, escaped ? hash - 1 : hash);
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
/// or bare on a link that reaches that doc, to the new Name; a text equal to
/// the old last `/` part of such a doc's Name, on a link that reaches it, takes
/// the new last part.
List<_TextEdit> _linkTextEdits(
  String body,
  List<LinkSource> sources,
  String docPath,
  RenamedNames renamed,
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

/// Returns the [TypedName] of the renamed doc that [href], written in the doc
/// at [docPath], reaches, or null when it reaches none.
TypedName? _reachedDoc(String? href, String docPath, RenamedDocs renamedDocs) {
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
/// is the doc it names. A text that is that doc's old last `/` part, bare or
/// after its own `<doc type>:` prefix, counts on a link that reaches it.
_TextEdit? _namedLinkText(
  String body,
  LinkSource source,
  RenamedNames renamed,
  TypedName? Function() reached,
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
    name =
        renamed.newNameFor(address) ?? _newLastSlug(address, renamed, reached);
  } else {
    final key = reached();
    name = key != null && key.name == address.body
        ? renamed.newNameOf(key.typeId, key.name)
        : _newLastSlug(address, renamed, reached);
  }
  if (name == null) return null;
  final prefix = typeId == null ? '' : '$typeId:';
  return _TextEdit(start: start, end: textEnd, text: '$prefix$name');
}

/// Returns the new last `/` part of the renamed doc [reached] gives when
/// [address] is that doc's old last `/` part, bare or after the doc's own
/// `<doc type>:` prefix; null otherwise.
String? _newLastSlug(
  DocAddress address,
  RenamedNames renamed,
  TypedName? Function() reached,
) {
  final key = reached();
  if (key == null || (address.typeId ?? key.typeId) != key.typeId) return null;
  if (_lastSlug(key.name) != address.body) return null;
  final newName = renamed.newNameOf(key.typeId, key.name);
  return newName == null ? null : _lastSlug(newName);
}

String _lastSlug(String name) => name.substring(name.lastIndexOf('/') + 1);

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
String destinationWithPath(
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
bool isAngleBracketed(String body, int start, DestinationKind kind) =>
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
  required RenamedNames renamed,
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

/// The journal steps of one restructure write: the sorted writes of existing
/// docs, and the records it creates.
final class PlannedRewrites {
  const new({required this.rewrites, required this.creates});

  final List<WriteStep> rewrites;
  final List<CreateStep> creates;
}

/// One candidate doc as its rewrite leaves it, laid out, before any stamp.
final class _Rewritten {
  const new({
    required this.docPath,
    required this.bytes,
    required this.lfText,
    required this.laidOut,
  });

  /// Where the doc sits before the moves.
  final String docPath;

  /// The file as the step reads it under the lock.
  final List<int> bytes;
  final String lfText;
  final String laidOut;
}

/// Returns the journal writes that keep every link, `doc_ref`, and doc-name
/// mention true in docs, and [creates] with their rows re-stamped.
///
/// One re-stamp pass ([RestampPass]) then sets each matched `confirmed` or
/// `overrides` entry and Verification matrix row whose block the call
/// rewrites to the block's fingerprint after it; a doc only it changes is
/// written too. A doc whose hash matched its `approved:` value is stamped
/// again after the pass, and its step saves the approved copy when it writes.
/// Draft marks stay untouched. A code file or an agent file is never written:
/// its mentions are listed by `staleMentions`.
///
/// [docEdits] maps a DocPath to one edit of that doc, such as a record's
/// entries or a moved FR's traces; the doc is a candidate, indexed or not, and
/// the edit runs after the other rewrites of its step. [readEdits] maps a
/// DocPath to an edit planned against the doc's text as read, such as an item
/// landing, which runs before the other rewrites. [blocks] gives where a moved
/// block sits after the call. [createdTexts] gives, by DocPath, the text of
/// each doc the call creates, which the re-stamp pass reads as written.
/// [prefilter] parses for links and mentions only the docs whose stored text
/// can name a moved path or an old Name ([docPathsNamingMoves],
/// [docPathsNamingOldNames]); false parses every doc, the same rewrites
/// slower, so a test can compare the two.
/// Throws [RenderFault] `output_not_writable` for a candidate that is not
/// UTF-8 text or that is read-only and would change.
PlannedRewrites planRewrites(
  WriteSession session,
  List<PathMove> moves, {
  RenamedNames renamed = const RenamedNames({}),
  Map<String, TextEdit> docEdits = const {},
  Map<String, TextEdit> readEdits = const {},
  Map<String, String> createdTexts = const {},
  List<CreateStep> creates = const [],
  BlockMoves blocks = const BlockMoves.none(),
  bool prefilter = true,
}) {
  final index = session.index;
  final renamedDocs = _renamedDocsOf(index, moves, renamed);
  final namingMoves = prefilter ? docPathsNamingMoves(index, moves) : null;
  final namingOldNames = prefilter
      ? docPathsNamingOldNames(index, renamed)
      : null;
  final candidates = <String, IndexedDoc>{};
  for (final doc in index.docs) {
    final isMoved = movedPath(doc.docPath, moves) != doc.docPath;
    if (isMoved) {
      for (final linker in index.linkingTo(doc)) {
        candidates[linker.docPath] = linker;
      }
    }
    final mayReachMoves =
        isMoved || (namingMoves?.contains(doc.docPath) ?? true);
    if ((mayReachMoves && _linksToMovedFile(index, doc, moves)) ||
        _movesWithChangedLink(index, doc, moves) ||
        (mayReachMoves && _mentionsMovedFile(session, doc, moves))) {
      candidates[doc.docPath] = doc;
    }
    if (_namesRenamedDoc(index, doc, renamed) ||
        _mentionsRenamedDoc(index, doc, renamed) ||
        _namesRenamedLabel(session, doc, renamed) ||
        ((namingOldNames?.contains(doc.docPath) ?? true) &&
            _textsRenamedDoc(index, doc, moves, renamed, renamedDocs))) {
      candidates[doc.docPath] = doc;
    }
  }
  for (final docPath in {...readEdits.keys, ...docEdits.keys}) {
    candidates.putIfAbsent(
      docPath,
      () => index.at(docPath) ?? _unindexedDoc(session, docPath),
    );
  }
  final rewritten = [
    for (final doc in candidates.values)
      ?_rewrittenOf(
        session,
        doc,
        moves,
        renamed,
        renamedDocs,
        docEdits[doc.docPath],
        readEdits[doc.docPath],
      ),
  ];
  final pass = RestampPass.plan(
    session,
    before: {for (final doc in rewritten) doc.docPath: doc.lfText},
    after: {
      for (final doc in rewritten) doc.docPath: doc.laidOut,
      ...createdTexts,
    },
    moves: moves,
    blocks: blocks,
  );
  final steps = [
    for (final doc in rewritten)
      _stampedStep(session, doc, moves, pass.apply(doc.docPath, doc.laidOut)),
    for (final docPath in pass.onlyRestamped)
      ?_restampedStep(session, docPath, moves, pass),
  ]..sort((a, b) => a.path.compareTo(b.path));
  return PlannedRewrites(
    rewrites: steps,
    creates: [
      for (final create in creates)
        CreateStep(
          create.path,
          pass.apply(
            session.docPathOf(create.path) ?? create.path,
            create.text,
          ),
        ),
    ],
  );
}

/// The marks a link destination may spell a path character with: a percent
/// escape, a backslash escape, and an entity reference.
const _spellingMarks = ['%', r'\', '&'];

/// Returns the DocPath of each doc of [index] whose text may hold a link or a
/// path mention that reaches a path [moves] move, the docs that move left out.
///
/// From a doc that stays, a path into a moved folder or file walks into it by
/// its last segment, so the text holds that segment as written, or a mark
/// that spells one of its characters. A doc outside the set that does not
/// move holds no such link or mention, so the planner never parses it.
Set<String> docPathsNamingMoves(DocIndex index, List<PathMove> moves) {
  final segments = {
    for (final move in moves)
      if (move.from.split('/').where((s) => s.isNotEmpty) case final parts
          when parts.isNotEmpty)
        parts.last,
  };
  if (segments.isEmpty) return const {};
  return {
    for (final needle in [...segments, ..._spellingMarks])
      for (final doc in index.holding(needle)) doc.docPath,
  };
}

/// Returns the DocPath of each doc of [index] whose text holds the old Name of
/// a doc [renamed] renames, as [RenamedNames.anyOldNameIn] reads it.
///
/// An old Name that holds another is left out of the search, since a text
/// that holds it holds the other too.
Set<String> docPathsNamingOldNames(DocIndex index, RenamedNames renamed) {
  final names = renamed.oldNames.toList()
    ..sort((a, b) => a.length.compareTo(b.length));
  final needles = <String>[];
  for (final name in names) {
    if (!needles.any(name.contains)) needles.add(name);
  }
  return {
    for (final needle in needles)
      for (final doc in index.holding(needle)) doc.docPath,
  };
}

/// Returns the docs of [index] whose Name [renamed] changes under [moves], by
/// their DocPath before the moves.
RenamedDocs _renamedDocsOf(
  DocIndex index,
  List<PathMove> moves,
  RenamedNames renamed,
) => {
  for (final doc in index.docs)
    if (doc.docTypeId case final typeId?)
      if (movedPath(doc.docPath, moves) != doc.docPath &&
          renamed.newNameOf(typeId, doc.name) != null)
        doc.docPath: TypedName(typeId: typeId, name: doc.name),
};

/// Whether [doc] holds a file link, a link that is no doc link, to a path
/// that [moves] move.
bool _linksToMovedFile(DocIndex index, IndexedDoc doc, List<PathMove> moves) {
  final projectMoves = projectMovesOf(moves);
  return index.contentOf(doc).lineFacts.fileLinks.any((link) {
    final target = projectFilePathOf(link.target, doc.docPath);
    return movedFilePath(target, projectMoves) != target;
  });
}

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
  RenamedNames renamed,
  RenamedDocs renamedDocs,
) {
  if (renamed.isEmpty) return false;
  final text = toLf(index.contentOf(doc).text);
  // A link text names an old Name, so a doc without one needs no parse.
  if (!renamed.anyOldNameIn(text)) return false;
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

/// Whether [path], from the project root, names an indexed doc or a file or
/// folder on disk.
///
/// Planning runs before the moves, so this reads the tree as it stands.
bool _existsBeforeMoves(WriteSession session, String path) =>
    _isIndexedDoc(session, path) ||
    FileSystemEntity.typeSync(
          [
            session.project.projectRoot.path,
            ...path.split('/'),
          ].join(Platform.pathSeparator),
        ) !=
        FileSystemEntityType.notFound;

/// Whether [projectPath] names a doc of the session's snapshot.
bool _isIndexedDoc(WriteSession session, String projectPath) {
  final docPath = docPathOfProjectPath(projectPath);
  return docPath != null && session.snapshotIndex.at(docPath) != null;
}

/// Returns the doc at [docPath], on disk but not in the session's snapshot, as
/// a step reads it: typed by the matcher, with no parent indexed.
IndexedDoc _unindexedDoc(WriteSession session, String docPath) => IndexedDoc(
  docPath: docPath,
  docTypeId: session.docTypeAt(docPath)?.id,
  name: docPath,
  frontmatter: const {},
  tokens: 0,
);

/// Returns [doc] with [readEdit], then its links, mentions, `doc_ref` values,
/// labels, and [docEdit] rewritten and laid out, or null when its bytes would
/// not change.
_Rewritten? _rewrittenOf(
  WriteSession session,
  IndexedDoc doc,
  List<PathMove> moves,
  RenamedNames renamed,
  RenamedDocs renamedDocs,
  TextEdit? docEdit,
  TextEdit? readEdit,
) {
  final bytes = session.readDocBytes(doc.docPath);
  if (bytes == null) return null;
  final raw = utf8.decode(bytes);
  final lfText = toLf(raw);
  final read = readEdit?.call(lfText);
  final start = read ?? lfText;
  final linked = rewriteDocLinks(
    start,
    docPath: doc.docPath,
    moves: moves,
    renamed: renamed,
    renamedDocs: renamedDocs,
  );
  final mentioned =
      rewritePathMentions(
        linked ?? start,
        docPath: doc.docPath,
        moves: moves,
        exists: (path) => _existsBeforeMoves(session, path),
      )?.lfText ??
      linked;
  final fields = session.index.typeOf(doc)?.fields ?? const <MergedField>[];
  final refs =
      rewriteDocRefs(mentioned ?? start, fields: fields, renamed: renamed) ??
      mentioned;
  final named =
      rewriteNameMentions(refs ?? start, markdownExtension, renamed) ?? refs;
  final text =
      rewriteLinkLabels(
        named ?? start,
        docType: session.index.typeOf(doc),
        featureName: session.index.parentOf(doc)?.name,
        newFeatureName: _newParentName(session, doc, renamed),
        renamed: renamed,
      ) ??
      named;
  final entries = docEdit?.call(text ?? start) ?? text ?? read;
  if (entries == null) return null;
  session.requireWritable(doc.docPath);
  return _Rewritten(
    docPath: doc.docPath,
    bytes: bytes,
    lfText: lfText,
    laidOut: layOutDoc(
      entries,
      session.docTypeAt(movedPath(doc.docPath, moves)),
    ),
  );
}

/// Returns the step that writes the doc at [docPath], which only [pass]
/// changes, or null when the file is gone.
WriteStep? _restampedStep(
  WriteSession session,
  String docPath,
  List<PathMove> moves,
  RestampPass pass,
) {
  final bytes = session.readDocBytes(docPath);
  if (bytes == null) return null;
  session.requireWritable(docPath);
  final lfText = toLf(utf8.decode(bytes));
  final laidOut = layOutDoc(
    lfText,
    session.docTypeAt(movedPath(docPath, moves)),
  );
  return _stampedStep(
    session,
    _Rewritten(
      docPath: docPath,
      bytes: bytes,
      lfText: lfText,
      laidOut: laidOut,
    ),
    moves,
    pass.apply(docPath, laidOut),
  );
}

/// Returns the step that writes [text], [doc] as the re-stamp pass leaves
/// it, at its path after [moves], with the approval hash stamped again when
/// it matched before the call.
WriteStep _stampedStep(
  WriteSession session,
  _Rewritten doc,
  List<PathMove> moves,
  String text,
) {
  final writtenPath = movedPath(doc.docPath, moves);
  final wasApproved = _wasApproved(doc.lfText, session.docTypeAt(doc.docPath));
  // An edit that marked the doc draft, as an item move does, takes no stamp.
  final isRestamped = wasApproved && !Doc.parse(text).isDraft;
  final stamped = isRestamped
      ? withApprovalHash(text, session.docTypeAt(writtenPath))
      : text;
  final step = session.docWriteStep(writtenPath, stamped, doc.bytes);
  return isRestamped ? step.keepingApprovedCopy() : step;
}

/// Whether [lfText], the doc as the step reads it under the lock, is no draft
/// and its `approved:` value is the hash of its content under [docType], so a
/// rewrite of its references re-stamps it (a stale hash stays).
///
/// Read from the bytes the step rewrites, not the index: an edit made after
/// the session opened stays stale.
bool _wasApproved(String lfText, MergedDocType? docType) {
  final fields = ApprovalFields.of(Doc.parse(lfText));
  return !fields.isDraft &&
      fields.approvedValue is String &&
      fields.approvedValue == approvalHashOf(lfText, docType);
}

/// Returns the Name of [doc]'s parent after the renames in [renamed], null
/// when [doc] has no parent.
String? _newParentName(
  WriteSession session,
  IndexedDoc doc,
  RenamedNames renamed,
) {
  final parent = session.index.parentOf(doc);
  if (parent == null) return null;
  return renamed.newNameOf(parent.docTypeId, parent.name) ?? parent.name;
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
  RenamedNames renamed,
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
  RenamedNames renamed,
) =>
    renamed.isNotEmpty &&
    index
        .contentOf(doc)
        .lineFacts
        .nameMentions
        .any((m) => renamed.newNameFor(m.address) != null);

/// Whether [doc] carries a `doc_ref` value that [renamed] renames.
bool _namesRenamedDoc(DocIndex index, IndexedDoc doc, RenamedNames renamed) {
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
String? _newName(MergedField field, String value, RenamedNames renamed) {
  final types = field.docTypes;
  return types == null
      ? renamed.agreedNewNameOf(value)
      : types
            .map((type) => renamed.newNameOf(type, value))
            .nonNulls
            .firstOrNull;
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
  RenamedNames renamed,
) {
  return renameKeyBlockValues(
    text,
    key,
    (value) => _newName(field, value, renamed),
  );
}
