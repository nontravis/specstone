/// One frontmatter list item or scalar with its source line.
///
/// `text` is the item's source text, its span.
final class YamlEntry {
  const new({required this.value, required this.line, required this.text});

  final Object? value;
  final int line;
  final String text;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is YamlEntry &&
      other.value == value &&
      other.line == line &&
      other.text == text;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(value, line, text);
}
