/// The non-blank line count and code point count of a held section's body.
final class SectionCounts {
  const new({required this.lines, required this.chars});

  final int lines;
  final int chars;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is SectionCounts && other.lines == lines && other.chars == chars;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(lines, chars);
}
