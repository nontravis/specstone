/// One merged checklist item.
///
/// `origin` is the id of the feature pattern whose layers last wrote the
/// item's text, so two patterns that share an item agree on all three fields.
final class ChecklistItem {
  const new({required this.id, required this.text, required this.origin});

  final String id;
  final String text;
  final String origin;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is ChecklistItem &&
      other.id == id &&
      other.text == text &&
      other.origin == origin;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(id, text, origin);
}
