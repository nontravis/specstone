import 'dart:convert';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// A record that loses or changes entries: its DocPath, its bytes as read, the
/// items whose entries change, and its text after the change.
typedef RecordEdit = ({
  String docPath,
  List<int> bytes,
  List<String> entries,
  String lfText,
});

/// Returns an edit for each record outside [inUnit], the DocPaths of the
/// unit's files, that holds an entry of a story or FR of the unit, sorted by
/// DocPath.
///
/// A record's entries name the stories and FRs of its feature relative to it,
/// as [recordItemsOf] gives them; the records of a feature in the unit are in
/// the unit and leave with it.
List<RecordEdit> recordEditsOf(WriteSession session, Set<String> inUnit) {
  final index = session.index;
  final recordType = index.set.recordDocType;
  if (recordType == null) return const [];
  final edits = <RecordEdit>[];
  for (final record in index.docs) {
    if (record.docTypeId != recordType.id || inUnit.contains(record.docPath)) {
      continue;
    }
    final feature = index.parentOf(record);
    if (feature == null) continue;
    final lost = {
      for (final MapEntry(:key, :value) in recordItemsOf(
        feature,
        index.childrenOf,
      ).entries)
        if (inUnit.contains(value.docPath)) key,
    };
    if (lost.isEmpty) continue;
    final edit = recordEditOf(
      session,
      record.docPath,
      recordType,
      (item) => lost.contains(item) ? null : item,
    );
    if (edit != null) edits.add(edit);
  }
  return edits..sort((a, b) => a.docPath.compareTo(b.docPath));
}

/// Returns the edit of the record at [docPath] that [rewrite] sets out, as
/// [rewriteRecordItems] reads it, or null when the file is gone or no line
/// changes.
///
/// `entries` lists each item [rewrite] drops or renames. Throws a
/// `RenderFault` `output_not_writable` for a record that is read-only, so a
/// dry run refuses it as the run does.
RecordEdit? recordEditOf(
  WriteSession session,
  String docPath,
  MergedDocType recordType,
  String? Function(String item) rewrite,
) {
  final bytes = session.readDocBytes(docPath);
  if (bytes == null) return null;
  final changed = <String>{};
  final lfText = rewriteRecordItems(toLf(utf8.decode(bytes)), recordType, (
    item,
  ) {
    final next = rewrite(item);
    if (next != item) changed.add(item);
    return next;
  });
  if (lfText == null) return null;
  session.requireWritable(docPath);
  return (
    docPath: docPath,
    bytes: bytes,
    entries: changed.toList(),
    lfText: lfText,
  );
}

/// Returns the write of [record] as a draft, laid out for its doc type, in the
/// line ends and byte-order mark it had.
WriteStep recordStepOf(WriteSession session, RecordEdit record) {
  final docType =
      session.docTypeAt(record.docPath) ??
      (throw StateError('${record.docPath} is typed but its type is gone'));
  return session.docWriteStep(
    record.docPath,
    layOutDoc(markDraft(record.lfText, docType), docType),
    record.bytes,
  );
}
