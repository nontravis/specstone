import 'package:specstone_core/src/consistency_check/models/code_at.dart';
import 'package:specstone_core/src/index_query/models/indexed_doc.dart';

/// One code catalog: its doc, the doc it hangs under, and its body rows.
final class CatalogDoc {
  const new({required this.doc, required this.owner, required this.rows});

  final IndexedDoc doc;
  final IndexedDoc owner;
  final List<CodeAt> rows;
}
