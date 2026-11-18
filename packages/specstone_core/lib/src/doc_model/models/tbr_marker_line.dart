/// A TBR marker's 0-based body line, and the trimmed text after it up to the
/// next marker.
final class TbrMarkerLine {
  const new({required this.line, required this.rest});

  final int line;
  final String rest;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is TbrMarkerLine && other.line == line && other.rest == rest;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(line, rest);
}
