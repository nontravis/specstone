/// The item and code path of an `item:path[:Symbol]` line; the item is empty
/// for the feature itself.
final class RecordCodeLine {
  const new({required this.item, required this.code});

  final String item;
  final String code;
}
