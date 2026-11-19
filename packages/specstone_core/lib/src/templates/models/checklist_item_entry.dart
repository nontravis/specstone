/// One checklist item as one layer writes it.
///
/// `text` is null for an entry that only disables an item.
final class ChecklistItemEntry {
  const new({required this.id, required this.text, required this.disabled});

  final String id;
  final String? text;
  final bool disabled;
}
