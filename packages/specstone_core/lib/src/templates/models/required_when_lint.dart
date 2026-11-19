/// A section that is required while an item of another section holds a value.
final class RequiredWhenLint {
  const new({required this.section, required this.field, required this.value});

  /// The id of the section whose items are read.
  final String section;

  /// The nested item label read in that section.
  final String field;

  /// The field value that makes this section required.
  final String value;

  /// Returns the JSON object of this rule.
  Map<String, Object> toJson() => {
    'section': section,
    'field': field,
    'value': value,
  };
}
