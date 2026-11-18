import 'package:specstone_core/src/index_query/models/indexed_doc.dart';

/// A path written in a doc's text and the doc it names: the 1-based file line,
/// the path as written, less any `#anchor` or closing sentence mark, and the
/// doc.
final class WrittenPath {
  const new({required this.line, required this.written, required this.named});

  final int line;
  final String written;
  final IndexedDoc named;
}
