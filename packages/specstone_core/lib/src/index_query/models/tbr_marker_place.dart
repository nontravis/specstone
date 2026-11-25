/// A TBR marker at its file line, with the line's text after it.
final class TbrMarkerPlace {
  const new({required this.line, required this.rest});

  final int line;
  final String rest;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is TbrMarkerPlace && other.line == line && other.rest == rest;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(line, rest);
}
