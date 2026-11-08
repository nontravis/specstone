import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart' show isReadOnly;
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart' show docsFolderName;
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show markdownExtension, readsNameMentions;
import 'package:specstone_core/src/doc_model/percent_decode.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/key_block_values.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/document_writing/rewrite_labels.dart';
import 'package:specstone_core/src/document_writing/rewrite_mentions.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/code_root_files.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/link_places.dart'
    show hrefDestinationsOf;
import 'package:specstone_core/src/index_query/link_scan.dart' show linkScanOf;
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show startsWithUtf8Bom;
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart'
    show RenderFault, RenderFaultCode;
import 'package:specstone_core/src/setup_migration/agent_targets.dart'
    show codeEntriesOnDisk;
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

export 'package:specstone_core/src/document_writing/moved_paths.dart'
    show PathMove, movedPath, relativeHref;

/// The byte-order mark as the one character a journal step's text carries.
const _bom = '\uFEFF';

const _backslash = 0x5C;
const _openParen = 0x28;
const _closeParen = 0x29;
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
  final (:destinations, linksRead: _) = hrefDestinationsOf(
    body,
    linkScanOf(body, firstLine: 1),
    canMove: (href) => _movedPath(href, docPath, moves) != null,
  );
  final edits = [
    for (final (:start, :end, :href, :kind) in destinations)
      if (_movedPath(href, docPath, moves) case final newPath?)
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

/// Returns the journal writes that keep every link and `doc_ref` true.
///
/// Candidates are docs that link under a moved path, move and hold a link or
/// path mention a rewrite changes, or, for [renamed], name a renamed doc; a
/// lenient read keeps a non-UTF-8 doc naming nothing renamed from blocking.
/// Steps hold the rewritten text, sorted by path, with draft marks untouched;
/// a doc whose hash matched its `approved:` value is re-stamped.
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
        _movesWithChangedLink(index, doc, moves) ||
        _mentionsMovedFile(session, doc, moves)) {
      candidates[doc.docPath] = doc;
    }
    if (_namesRenamedDoc(index, doc, renamed) ||
        _mentionsRenamedDoc(index, doc, renamed) ||
        _namesRenamedLabel(session, doc, renamed)) {
      candidates[doc.docPath] = doc;
    }
  }
  final steps = [
    for (final doc in candidates.values)
      ?_stepFor(session, doc, moves, renamed),
    ..._codeFileSteps(session, renamed),
  ]..sort((a, b) => a.path.compareTo(b.path));
  return steps;
}

/// Returns the writes of the code files under the `code:` roots that hold a
/// doc-name mention of a doc in [renamed].
///
/// A markdown file is read as a doc is, any other file by its comment lines;
/// a file that is no UTF-8 text, cannot be read, or sits in the docs folder
/// is left out. A code file is never stamped and never marked draft.
List<WriteStep> _codeFileSteps(
  WriteSession session,
  Map<(String, String), String> renamed,
) {
  if (renamed.isEmpty) return const [];
  final project = session.project;
  final paths = codeRootFiles(
    project.codeRoot,
    codeEntriesOnDisk(project.projectRoot, project.set),
  );
  return [for (final path in paths) ?_codeFileStep(session, path, renamed)];
}

WriteStep? _codeFileStep(
  WriteSession session,
  String codePath,
  Map<(String, String), String> renamed,
) {
  final extension = _extensionOf(codePath);
  if (!readsNameMentions(extension)) return null;
  final project = session.project;
  final file = File(
    '${project.codeRoot.path}${Platform.pathSeparator}'
    '${codePath.split('/').join(Platform.pathSeparator)}',
  );
  final projectPath = _projectPathOf(project.projectRoot, file);
  if (projectPath.startsWith('$docsFolderName/')) return null;
  final String raw;
  final List<int> bytes;
  try {
    bytes = file.readAsBytesSync();
    raw = utf8.decode(bytes);
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
  final text = rewriteNameMentions(raw, extension, renamed);
  if (text == null) return null;
  if (isReadOnly(file)) {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write $projectPath: read-only',
    );
  }
  final bom = startsWithUtf8Bom(bytes) ? _bom : '';
  return WriteStep(projectPath, '$bom$text');
}

/// Returns the extension of [path], a `.` and the letters after its last
/// one, or an empty string for a name with none.
String _extensionOf(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot);
}

/// Returns [file] as a path from [projectRoot], `/`-separated, with `..` for
/// each folder it leaves.
String _projectPathOf(Directory projectRoot, File file) {
  final from = _segmentsOf(projectRoot.path);
  final to = _segmentsOf(file.path);
  var shared = 0;
  while (shared < from.length &&
      shared < to.length &&
      from[shared] == to[shared]) {
    shared++;
  }
  return [
    for (var i = shared; i < from.length; i++) '..',
    ...to.skip(shared),
  ].join('/');
}

List<String> _segmentsOf(String path) =>
    path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).toList();

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
  if (text == null) return null;
  session.requireWritable(doc.docPath);
  final bom = startsWithUtf8Bom(bytes) ? _bom : '';
  final writtenPath = movedPath(doc.docPath, moves);
  final writtenType = session.docTypeAt(writtenPath);
  final laidOut = layOutDoc(text, writtenType);
  final stamped = _wasApproved(doc)
      ? withApprovalHash(laidOut, writtenType)
      : laidOut;
  return WriteStep(
    session.projectPathOf(writtenPath),
    '$bom${LineEnding.of(raw).apply(stamped)}',
  );
}

/// Whether [doc] is no draft and its `approved:` value is the hash of its
/// content, so a rewrite of its references re-stamps it (a stale hash stays).
bool _wasApproved(IndexedDoc doc) {
  final fields = ApprovalFields.ofIndexed(doc);
  return !fields.isDraft &&
      fields.approvedValue is String &&
      fields.approvedValue == doc.approvalHash;
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
