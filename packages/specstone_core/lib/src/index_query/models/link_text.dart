import 'package:specstone_core/src/index_query/models/link_place.dart';

/// A doc link or self link whose text reads as an item ID or as a doc
/// address: the text as written, where the link sits, and what it points at.
///
/// `column` is the 0-based offset of the link's first character in its line
/// `line`; `endColumn` the offset after its last character in its line
/// `endLine`, so a reader tests what lies between two links on one line. A
/// link text reads as an item ID when it holds no whitespace and a digit; the
/// reader that knows the target section's prefix judges it. `shown` is the
/// link's destination as written, the `shown` of its [LinkPlace].
final class LinkText {
  const new({
    required this.line,
    required this.column,
    required this.endLine,
    required this.endColumn,
    required this.text,
    required this.target,
    required this.anchor,
    required this.shown,
  });

  final int line;
  final int column;
  final int endLine;
  final int endColumn;
  final String text;
  final String target;
  final String? anchor;
  final String shown;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is LinkText &&
      other.line == line &&
      other.column == column &&
      other.endLine == endLine &&
      other.endColumn == endColumn &&
      other.text == text &&
      other.target == target &&
      other.anchor == anchor &&
      other.shown == shown;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(
    line,
    column,
    endLine,
    endColumn,
    text,
    target,
    anchor,
    shown,
  );
}
