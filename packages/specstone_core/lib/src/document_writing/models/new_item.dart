import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// A doc one write creates, as its feature's records read it: its doc type
/// id, DocPath, Name, and the doc it nests under, indexed or created.
final class NewItem {
  const new({
    required this.docTypeId,
    required this.docPath,
    required this.name,
    required this.parent,
  });

  final String? docTypeId;
  final String docPath;
  final String name;

  /// The doc it nests under; null for a doc with no parent.
  final IndexedDoc? parent;
}
