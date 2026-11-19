/// One skip line of an `out_of_scope` section: the item a doc leaves out of
/// the feature pattern it lists.
///
/// `span` is the code span's text as written, without its backticks.
final class SkipLine {
  const new({
    required this.line,
    required this.pattern,
    required this.item,
    required this.span,
  });

  final int line;
  final String pattern;
  final String item;
  final String span;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is SkipLine &&
      other.line == line &&
      other.pattern == pattern &&
      other.item == item &&
      other.span == span;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(line, pattern, item, span);
}
