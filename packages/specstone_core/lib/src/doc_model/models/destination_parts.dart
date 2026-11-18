/// A link destination as written, split as `markdown` reads it: the index
/// where the text of its href's first `?` or `#` starts, else its length,
/// and the index past the text of its href's first `#`, null with none.
final class DestinationParts {
  const new({required this.pathEnd, required this.anchorStart});

  final int pathEnd;
  final int? anchorStart;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is DestinationParts &&
      other.pathEnd == pathEnd &&
      other.anchorStart == anchorStart;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(pathEnd, anchorStart);
}
