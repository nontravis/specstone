/// A condition on one nested field of an item: the field holds exactly a value.
final class ItemFieldWhen {
  const new({required this.field, required this.value});

  /// The label of the nested item that is read.
  final String field;

  /// The text that nested item must hold, compared exactly.
  final String value;

  /// Returns whether [fields] holds [field] with exactly [value].
  bool isMetBy(Map<String, String> fields) => fields[field] == value;

  /// Returns the JSON object of this condition.
  Map<String, Object> toJson() => {'field': field, 'value': value};
}
