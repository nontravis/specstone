import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// Which way a link ties a piece of an ancestor spec doc to the target subtree.
enum PieceDirection {
  /// A doc of the target subtree links to the piece.
  outbound,

  /// The piece links to a doc of the target subtree.
  inbound,
}

/// A piece of an ancestor spec doc that links to or from the target subtree,
/// cut from the stored text.
///
/// [first] and [last] are the 1-based file lines the piece itself holds; a
/// table row's [text] also holds its table's header and separator rows above
/// them.
final class AncestorPiece {
  const new({
    required this.doc,
    required this.sectionKey,
    this.itemId,
    this.heading,
    required this.direction,
    required this.first,
    required this.last,
    required this.text,
  });

  final IndexedDoc doc;

  /// The key of the `##` section that holds the piece.
  final String sectionKey;

  /// The ID of the item the piece is, or whose `###` block it is; null for a
  /// section, a `###` block that starts no item, a table row, a bullet, and a
  /// paragraph.
  final String? itemId;

  /// The anchor of the `###` block the piece is when it starts no item, else
  /// null.
  final String? heading;

  final PieceDirection direction;
  final int first;
  final int last;

  /// The piece's lines, without line endings.
  final String text;
}
