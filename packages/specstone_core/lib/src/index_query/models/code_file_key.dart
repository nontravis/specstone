/// The identity of one code file in the index's `code_files` table: the code
/// root it is read from and its `normalCodeEntry` path below that root.
final class CodeFileKey {
  const new({required this.root, required this.path});

  /// The code root folder's path, as the run reads files from it.
  final String root;

  final String path;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is CodeFileKey && other.root == root && other.path == path;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(root, path);
}
