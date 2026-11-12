/// One code base the shared PRD drives: its name and its code root.
///
/// The name is null for the one unnamed target a `code_root:`-only config
/// gives. `codeRoot` is the config's value as written, relative to the project
/// root and `/`-separated, `.` for the project root itself.
final class CodeTarget {
  const new(this.name, {required this.codeRoot});

  /// The target's name under `targets:`, one slug; null for the unnamed
  /// target of a `code_root:`-only config.
  final String? name;

  /// The folder this target's code paths are written from, as written in the
  /// config.
  final String codeRoot;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is CodeTarget && other.name == name && other.codeRoot == codeRoot;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(name, codeRoot);

  @override
  String toString() => 'CodeTarget($name, $codeRoot)';
}
