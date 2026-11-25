import 'dart:convert';

import 'package:specstone_core/src/document_writing/approval.dart'
    show approvalHashOf;
import 'package:specstone_core/src/document_writing/models/new_item.dart';
import 'package:specstone_core/src/document_writing/models/planned_lines.dart';
import 'package:specstone_core/src/document_writing/models/record_edit.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/rewrite_records.dart'
    show readRecord;
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show IndexedDoc, frType, storyType;
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

/// Returns an edit for each record outside [inUnit], the DocPaths of the
/// unit's files, that holds an entry or a matrix row of a story or FR of the
/// unit, sorted by DocPath.
///
/// A record's entries and rows name the stories and FRs of its feature
/// relative to it, as [recordItemsOf] gives them; the records of a feature in
/// the unit are in the unit and leave with it.
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
/// `entries` lists each item [rewrite] drops or renames, whether in an entry
/// line or a matrix row. Throws a
/// `RenderFault` `output_not_writable` for a record that is read-only or
/// whose field block is not valid YAML, so a dry run refuses it as the run
/// does.
RecordEdit? recordEditOf(
  WriteSession session,
  String docPath,
  MergedDocType recordType,
  String? Function(String item) rewrite,
) {
  final changed = <String>{};
  return _editOf(
    session,
    docPath,
    (lfText) => rewriteRecordItems(lfText, recordType, (item) {
      final next = rewrite(item);
      if (next != item) changed.add(item);
      return next;
    }),
    changed.toList,
  );
}

/// Returns the edit of each record that [created] add `planned` lines to, as
/// [plannedLinesOf] gives them, read from disk now.
///
/// Throws a `RenderFault` `output_not_writable` as [recordEditOf] does.
List<RecordEdit> plannedLineEditsOf(
  WriteSession session,
  List<NewItem> created,
) => [
  for (final lines in plannedLinesOf(session, created))
    ?_editOf(session, lines.docPath, lines.edit, () => lines.items),
];

/// Returns the `planned` lines [created] add to each record of the feature of
/// each story and FR among them, sorted by record DocPath.
///
/// A story's feature is its parent; an FR's is its story's parent, a story
/// [created] holds included, so a feature [created] holds has no record yet.
/// No line goes to a record that holds one of the item or whose skip covers
/// it. Each line sits in tree order, the items of [created] after those the
/// index holds, in [created] order. The edit marks the record draft only when
/// its lines move the record's approval hash, as a `statuses` field write does,
/// and throws a `RenderFault` `output_not_writable` as [recordEditOf] does.
List<PlannedLines> plannedLinesOf(WriteSession session, List<NewItem> created) {
  final index = session.index;
  final recordType = index.set.recordDocType;
  if (recordType == null) return const [];
  final features = <String, IndexedDoc>{};
  final items = <String, List<String>>{};
  for (final doc in created) {
    final feature = _featureOf(index, doc, created);
    if (feature == null) continue;
    features[feature.docPath] = feature;
    (items[feature.docPath] ??= []).add(
      doc.name.substring(feature.name.length + 1),
    );
  }
  return [
    for (final record in index.docs)
      if (record.docTypeId == recordType.id)
        if (index.parentOf(record) case final feature?)
          if (items[feature.docPath] case final added?)
            ?_plannedLinesIn(
              session,
              recordType,
              record.docPath,
              features[feature.docPath]!,
              added,
            ),
  ]..sort((a, b) => a.docPath.compareTo(b.docPath));
}

/// Returns the feature whose records take [doc]'s `planned` line; null for a
/// doc that is no story or FR, or whose feature is unknown.
IndexedDoc? _featureOf(DocIndex index, NewItem doc, List<NewItem> created) {
  final parent = doc.parent;
  if (parent == null) return null;
  return switch (doc.docTypeId) {
    storyType => parent,
    frType =>
      index.parentOf(parent) ??
          created
              .where((story) => story.docPath == parent.docPath)
              .firstOrNull
              ?.parent,
    _ => null,
  };
}

/// Returns the `planned` lines of [items], named relative to [feature], that
/// the record at [recordDocPath] takes; null when its skips cover them all.
PlannedLines? _plannedLinesIn(
  WriteSession session,
  MergedDocType recordType,
  String recordDocPath,
  IndexedDoc feature,
  List<String> items,
) {
  final index = session.index;
  final taken = [
    for (final item in items)
      if (!index.statusTree.recordSkipsItem(recordDocPath, item)) item,
  ];
  if (taken.isEmpty) return null;
  final order = _inTreeOrder(
    recordItemsOf(feature, index.childrenOf).keys.toList(),
    taken,
  );
  String hashOf(String lfText) => approvalHashOf(lfText, recordType);
  return PlannedLines(
    docPath: recordDocPath,
    items: taken,
    edit: (lfText) {
      var text = lfText;
      for (final item in taken) {
        text =
            readRecord(
              recordDocPath,
              () => withStatusLineInOrder(
                text,
                recordType,
                '$item:${RecordStatus.planned.wire}',
                order: order,
              ),
            ) ??
            text;
      }
      if (text == lfText) return null;
      return hashOf(text) == hashOf(lfText)
          ? text
          : markDraft(text, recordType);
    },
  );
}

/// Returns [order], a feature's items in tree order, with each of [items]
/// added in turn: a story after the last item, an FR after the last item of
/// its story.
List<String> _inTreeOrder(List<String> order, List<String> items) {
  final ordered = [...order];
  for (final item in items) {
    final story = item.contains('/') ? item.split('/').first : null;
    final last = story == null
        ? ordered.length - 1
        : ordered.lastIndexWhere(
            (it) => it == story || it.startsWith('$story/'),
          );
    ordered.insert(last + 1, item);
  }
  return ordered;
}

/// Returns the edit of the record at [docPath] that [edit] makes to its LF
/// text, null for no text change, listing [entries] once it ran; null when the
/// file is gone.
RecordEdit? _editOf(
  WriteSession session,
  String docPath,
  String? Function(String lfText) edit,
  List<String> Function() entries,
) {
  final bytes = session.readDocBytes(docPath);
  if (bytes == null) return null;
  final lfText = readRecord(docPath, () => edit(toLf(utf8.decode(bytes))));
  if (lfText == null) return null;
  session.requireWritable(docPath);
  return RecordEdit(
    docPath: docPath,
    bytes: bytes,
    entries: entries(),
    lfText: lfText,
  );
}

/// Returns the write of [record] as a draft, laid out for its doc type, in the
/// line ends and byte-order mark it had.
WriteStep recordStepOf(WriteSession session, RecordEdit record) =>
    _stepOf(session, record, marksDraft: true);

/// Returns the write of [record], a planned-line edit whose text already holds
/// its draft state, laid out for its doc type, in the line ends and
/// byte-order mark it had.
WriteStep plannedLineStepOf(WriteSession session, RecordEdit record) =>
    _stepOf(session, record, marksDraft: false);

WriteStep _stepOf(
  WriteSession session,
  RecordEdit record, {
  required bool marksDraft,
}) {
  final docType = _typeOf(session, record);
  return session.docWriteStep(
    record.docPath,
    layOutDoc(
      marksDraft ? markDraft(record.lfText, docType) : record.lfText,
      docType,
    ),
    record.bytes,
  );
}

MergedDocType _typeOf(WriteSession session, RecordEdit record) =>
    session.docTypeAt(record.docPath) ??
    (throw StateError('${record.docPath} is typed but its type is gone'));
