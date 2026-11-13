import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// A record doc read as a rule needs it: its doc type, its feature, and its
/// lines.
typedef RecordDoc = ({MergedDocType type, IndexedDoc feature, DocLines lines});

/// Returns [doc] as a [RecordDoc], or null when it is no record, its parent
/// is no feature, or its frontmatter is invalid.
RecordDoc? recordDocOf(CheckContext context, IndexedDoc doc) {
  final type = context.set.recordDocType;
  if (type == null || doc.docTypeId != type.id) return null;
  final feature = context.index.parentOf(doc);
  if (feature == null || feature.docTypeId != featureType) return null;
  final lines = context.linesOf(doc);
  if (lines.frontmatterErrorLine != null) return null;
  return (type: type, feature: feature, lines: lines);
}
