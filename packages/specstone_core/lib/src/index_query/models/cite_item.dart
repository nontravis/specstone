/// One item a cite names: its ID as written, and the key and heading anchor
/// of the `##` section that holds it.
final class CiteItem {
  const new({
    required this.itemId,
    required this.sectionKey,
    required this.anchor,
  });

  final String itemId;
  final String sectionKey;
  final String anchor;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is CiteItem &&
      other.itemId == itemId &&
      other.sectionKey == sectionKey &&
      other.anchor == anchor;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(itemId, sectionKey, anchor);
}
