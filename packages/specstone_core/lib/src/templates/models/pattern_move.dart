/// A move's `from` and `to` path patterns at one nesting depth.
final class PatternMove {
  const new({required this.from, required this.to});

  final String from;
  final String to;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is PatternMove && other.from == from && other.to == to;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(from, to);
}
