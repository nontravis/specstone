import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart'
    show readLocked;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/get_docs.dart'
    show wholeDocBaseOf;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Texts

/// One doc a write reads, its text as the edits so far leave it.
final class LockedDocText {
  new({
    required this.doc,
    required this.docType,
    required this.bytes,
    required this.held,
  }) : text = held;

  final IndexedDoc doc;
  final MergedDocType docType;

  /// The file's bytes as read under the lock.
  final List<int> bytes;

  /// The doc's text as read, with LF line ends.
  final String held;

  /// The doc's text after the edits applied so far, with LF line ends.
  String text;

  /// Whether an edit changed [text] from [held].
  bool get isChanged => text != held;
}

/// The docs of one write, each read once under the write lock and held in
/// memory until one journal writes every changed one.
final class LockedDocTexts {
  new(this._session);

  final WriteSession _session;
  final _byPath = <String, LockedDocText>{};

  /// Returns the text of [doc], read from disk on its first use.
  LockedDocText of(IndexedDoc doc) => _byPath.putIfAbsent(doc.docPath, () {
    final docType =
        _session.index.typeOf(doc) ??
        (throw StateError('${doc.docPath} is typed but its type is gone'));
    final locked = readLocked(_session, doc, MatchedDocType(docType));
    return LockedDocText(
      doc: doc,
      docType: docType,
      bytes: locked.bytes,
      held: locked.lfText,
    );
  });

  /// The docs whose text an edit changed, in DocPath order.
  List<LockedDocText> get changed => [
    for (final text in _byPath.values)
      if (text.isChanged) text,
  ]..sort((a, b) => a.doc.docPath.compareTo(b.doc.docPath));
}

// MARK: - Writing

/// One changed doc as written: its text laid out and the base `get` prints
/// for it after the write.
final class WrittenDoc {
  const new({required this.text, required this.laidOut, required this.base});

  final LockedDocText text;
  final String laidOut;

  /// The whole-doc `base` `get` prints for the doc as written.
  final String base;

  IndexedDoc get doc => text.doc;
}

/// Lays out each changed doc of [texts] and writes them all through one
/// journal, or writes none; returns them in DocPath order.
///
/// Trust is checked before each path, so a project whose roots wait refuses
/// with the trust text first. A run that changed no doc writes no journal.
List<WrittenDoc> writeChangedDocs(WriteSession session, LockedDocTexts texts) {
  final changed = texts.changed;
  final laidOut = [
    for (final text in changed)
      layOutDoc(text.text, session.docTypeAt(text.doc.docPath)),
  ];
  final steps = [
    for (final (at, text) in changed.indexed)
      _stepOf(session, text, laidOut[at]),
  ];
  if (steps.isNotEmpty) MoveJournal(steps).run(session.journalTarget);
  return [
    for (final (at, text) in changed.indexed)
      WrittenDoc(
        text: text,
        laidOut: laidOut[at],
        base: _baseOf(session, text, laidOut[at]),
      ),
  ];
}

WriteStep _stepOf(WriteSession session, LockedDocText text, String laidOut) {
  final docPath = text.doc.docPath;
  session.journalTarget.requireTrusted();
  session.requireWritable(docPath);
  return session.docWriteStep(docPath, laidOut, text.bytes);
}

/// Returns the whole-doc `base` `get` prints for [text]'s doc holding
/// [laidOut].
String _baseOf(WriteSession session, LockedDocText text, String laidOut) {
  final after = parseIndexedDoc(
    docPath: text.doc.docPath,
    bytes: utf8.encode(laidOut),
    match: MatchedDocType(text.docType),
  );
  return wholeDocBaseOf(after.content);
}
