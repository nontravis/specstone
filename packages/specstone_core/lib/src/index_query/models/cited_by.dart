/// One citer of an item, section, or doc: the citing doc's `docPath`, `name`,
/// and `docType`, the ID of its item whose lines hold the link (null when none
/// does), and `bySection`, the key of the section of the linking line, the
/// lead's key before the first section.
final class CitedBy {
  const new({
    required this.docPath,
    required this.name,
    required this.docType,
    required this.byItem,
    required this.bySection,
  });

  final String docPath;
  final String name;
  final String docType;
  final String? byItem;
  final String bySection;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is CitedBy &&
      other.docPath == docPath &&
      other.name == name &&
      other.docType == docType &&
      other.byItem == byItem &&
      other.bySection == bySection;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(docPath, name, docType, byItem, bySection);
}
