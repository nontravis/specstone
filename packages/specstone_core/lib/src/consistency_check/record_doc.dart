import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/record_entries.dart'
    show recordStatusLineOf;
import 'package:specstone_core/src/index_query/status_tree.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show RecordStatus;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// A record doc read as a rule needs it: its doc type, its feature, and its
/// lines.
typedef RecordDoc = ({MergedDocType type, IndexedDoc feature, DocLines lines});

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
  return (type: type, feature: feature, lines: lines);
}

/// One `statuses` line of a record: its text, its file line, and what it
/// reads as.
final class StatusLine {
  const new({required this.text, required this.line, required this.parsed});

  /// The line as written.
  final String text;

  /// The 1-based file line.
  final int line;

  /// The item, status, and reason the line reads as; null when it names no
  /// item.
  final ({String item, RecordStatus? status, String? reason})? parsed;

  /// The item the line names, or null.
  String? get item => parsed?.item;
}

/// Returns each string entry of the [statusFieldId] list of [lines], in file
/// order, repeated items included.
List<StatusLine> statusLinesOf(DocLines lines, String statusFieldId) => [
  for (final (:value, :line, text: _) in lines.entriesOf(statusFieldId))
    if (value is String)
      StatusLine(text: value, line: line, parsed: recordStatusLineOf(value)),
];
