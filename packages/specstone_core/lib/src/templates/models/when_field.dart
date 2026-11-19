/// The doc field and values that bind a section's `required`.
final class WhenField {
  const new({required this.field, required this.values});

  final String field;
  final List<String> values;
}
