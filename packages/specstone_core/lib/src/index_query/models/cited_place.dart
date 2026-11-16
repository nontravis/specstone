/// What a cited-by line names: an item or a `###` block, a `##` section, or
/// a whole doc.
enum CitedKind { item, section, doc }

/// A place a link names: the doc at `docPath`, its [CitedKind], and its key
/// there: the item ID or the block's anchor, the section's key, or null for the
/// doc.
final class CitedPlace {
  const new({required this.docPath, required this.kind, required this.key});

  final String docPath;
  final CitedKind kind;
  final String? key;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is CitedPlace &&
      other.docPath == docPath &&
      other.kind == kind &&
      other.key == key;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(docPath, kind, key);
}
