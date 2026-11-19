import 'package:specstone_core/src/templates/models/item_field_when.dart';

/// A nested `- **<field>:** <text>` item every top-level item must hold.
final class ItemFieldLint {
  const new({
    required this.field,
    this.values,
    this.when,
    this.optional = false,
    this.defaultFrom,
  });

  /// The nested item's label; the merge key.
  final String field;

  /// The texts the nested item may hold; any text when null.
  final List<String>? values;

  /// The condition under which the item must hold this field; always when null.
  final ItemFieldWhen? when;

  /// Whether an item may leave this field out.
  final bool optional;

  /// The id of the section whose items supply this field's default; none when
  /// null.
  final String? defaultFrom;

  /// Returns whether an item with these nested [fields] must hold this field.
  bool appliesTo(Map<String, String> fields) => when?.isMetBy(fields) ?? true;

  /// Returns the JSON object of this item field, `values`, `when`, `optional`,
  /// and `default_from` only when set.
  Map<String, Object> toJson() => {
    'field': field,
    'values': ?values,
    'when': ?when?.toJson(),
    if (optional) 'optional': true,
    'default_from': ?defaultFrom,
  };
}
