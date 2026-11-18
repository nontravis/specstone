/// The parent DocPath of each doc by child DocPath, and the warning of each doc
/// that has two or more candidate parents.
final class ResolvedParents {
  const new({required this.parents, required this.warnings});

  final Map<String, String> parents;
  final Map<String, String> warnings;
}
