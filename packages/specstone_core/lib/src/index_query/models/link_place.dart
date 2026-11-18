/// A link of a doc: the path it resolves to, the file line it is written on,
/// its destination as written, and its decoded `#anchor`, null with no `#`.
///
/// The target is a docPath for a doc link and a self link, and the path under
/// the docs root for a file link.
final class LinkPlace {
  const new({
    required this.target,
    required this.line,
    required this.shown,
    required this.anchor,
  });

  final String target;
  final int line;
  final String shown;
  final String? anchor;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is LinkPlace &&
      other.target == target &&
      other.line == line &&
      other.shown == shown &&
      other.anchor == anchor;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(target, line, shown, anchor);
}
