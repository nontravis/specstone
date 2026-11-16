/// One link to an item, section, or doc, from the citing doc's `name` and
/// `docType`: the ID of its item whose lines hold the link, null when none
/// does, and the trimmed `line` that holds the link.
final class CitedBy {
  const new({
    required this.name,
    required this.docType,
    required this.byItem,
    required this.line,
  });

  final String name;
  final String docType;
  final String? byItem;
  final String line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is CitedBy &&
      other.name == name &&
      other.docType == docType &&
      other.byItem == byItem &&
      other.line == line;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(name, docType, byItem, line);
}
