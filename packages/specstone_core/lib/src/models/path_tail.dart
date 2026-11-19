/// A `path[:tail]` text split at its first `:`: the path, and the tail, null
/// without a `:`.
final class PathTail {
  const new({required this.path, required this.tail});

  final String path;
  final String? tail;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is PathTail && other.path == path && other.tail == tail;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(path, tail);
}
