/// One item ID of a cite form: its 0-based column on the form's line and the
/// ID as written.
final class CiteItemAt {
  const new({required this.column, required this.itemId});

  final int column;
  final String itemId;
}
