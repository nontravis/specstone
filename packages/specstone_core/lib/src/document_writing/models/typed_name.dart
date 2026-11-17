/// A doc's Name with the id of its doc type.
final class TypedName {
  const new({required this.typeId, required this.name});

  final String typeId;
  final String name;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is TypedName && other.typeId == typeId && other.name == name;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(typeId, name);
}
