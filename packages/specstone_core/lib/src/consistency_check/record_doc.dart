import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/models/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/models/record_doc.dart';
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart'
    show recordStatusLineOf;
import 'package:specstone_core/src/index_query/status_tree.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

/// Returns [doc] as a [RecordDoc], or null when it is no record, its parent
/// is no feature, or its frontmatter is invalid.
RecordDoc? recordDocOf(CheckContext context, IndexedDoc doc) =>
    recordDocIn(context.index.statusTree, doc, () => context.linesOf(doc));

/// Returns [doc] of [tree] as a [RecordDoc], or null when it is no record,
/// its parent is no feature, or its frontmatter is invalid.
///
/// [linesOf] is read only once [doc] is a record under a feature.
RecordDoc? recordDocIn(
  StatusTree tree,
  IndexedDoc doc,
  DocLines Function() linesOf,
) {
  final type = tree.set.recordDocType;
  if (type == null || doc.docTypeId != type.id) return null;
  final feature = tree.parentOf(doc);
  if (feature == null || feature.docTypeId != featureType) return null;
  final lines = linesOf();
  if (lines.frontmatterErrorLine != null) return null;
  return RecordDoc(type: type, feature: feature, lines: lines);
}

/// Whether [item] is skipped in the target of [record], by its own entry or by
/// a skip that covers it.
///
/// The record entry rule reports a row of such an item, so no other rule
/// judges it.
bool isSkippedIn(CheckContext context, IndexedDoc record, IndexedDoc item) =>
    context.index.itemStatus(item, codeTarget: record.target) ==
    RecordStatus.skipped;

/// One `statuses` line of a record: its text, its file line, and what it
/// reads as.
final class StatusLine {
  const new({
    required this.text,
    required this.line,
    this.item,
    this.status,
    this.reason,
  });

  /// The line as written.
  final String text;

  /// The 1-based file line.
  final int line;

  /// The item the line names; null when it names none.
  final String? item;

  /// The status the line gives; null with none or one that names no
  /// RecordStatus.
  final RecordStatus? status;

  /// The reason of a `skipped` line, as written.
  final String? reason;
}

/// Returns each string entry of the [statusFieldId] list of [lines], in file
/// order, repeated items included.
List<StatusLine> statusLinesOf(DocLines lines, String statusFieldId) => [
  for (final YamlEntry(:value, :line) in lines.entriesOf(statusFieldId))
    if (value is String) _statusLineOf(value, line),
];

StatusLine _statusLineOf(String text, int line) {
  final parsed = recordStatusLineOf(text);
  return StatusLine(
    text: text,
    line: line,
    item: parsed?.item,
    status: parsed?.status,
    reason: parsed?.reason,
  );
}
