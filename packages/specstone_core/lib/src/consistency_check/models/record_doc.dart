import 'package:specstone_core/src/consistency_check/models/doc_lines.dart';
import 'package:specstone_core/src/index_query/models/indexed_doc.dart';
import 'package:specstone_core/src/templates/models/merged_doc_type.dart';

/// A record doc read as a rule needs it: its doc type, its feature, and its
/// lines.
final class RecordDoc {
  const new({required this.type, required this.feature, required this.lines});

  final MergedDocType type;
  final IndexedDoc feature;
  final DocLines lines;
}
