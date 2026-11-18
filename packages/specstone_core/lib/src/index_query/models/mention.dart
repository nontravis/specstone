import 'package:specstone_core/src/index_query/models/indexed_doc.dart';

/// A doc line that names another doc's file in text or holds a doc-name
/// mention of it: the doc holding the line and its 1-based file line.
final class Mention {
  const new({required this.doc, required this.line});

  final IndexedDoc doc;
  final int line;
}
