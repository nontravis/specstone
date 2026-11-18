/// A trace note of an item, and whether it closes the item or its table cell.
final class TraceNote {
  const new({required this.text, required this.closes});

  final String text;
  final bool closes;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is TraceNote && other.text == text && other.closes == closes;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(text, closes);
}
