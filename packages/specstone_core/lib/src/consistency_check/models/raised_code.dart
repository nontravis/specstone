import 'package:specstone_core/src/index_query/models/indexed_doc.dart';

/// One code an unskipped requirement names: where.
final class RaisedCode {
  const new({required this.doc, required this.code, required this.line});

  final IndexedDoc doc;
  final String code;
  final int line;
}
