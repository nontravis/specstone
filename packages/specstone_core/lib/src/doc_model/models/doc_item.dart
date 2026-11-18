/// One item of a section.
///
/// `line` is the first line of the item in the body lines given, the file
/// line when they are the file's. `chars` counts the item's own lines in code
/// points, a surrogate pair once, with the line feeds between them. `text` is
/// the first line after any `>` mark, list marker, or `### `. `heading` is
/// true for a `###` item.
final class DocItem {
  const new({
    required this.line,
    required this.chars,
    required this.text,
    required this.heading,
  });

  final int line;
  final int chars;
  final String text;
  final bool heading;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is DocItem &&
      other.line == line &&
      other.chars == chars &&
      other.text == text &&
      other.heading == heading;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(line, chars, text, heading);
}
