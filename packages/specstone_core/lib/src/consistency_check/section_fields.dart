import 'package:specstone_core/src/doc_model/models/section_item.dart';

final _fieldItem = RegExp(r'^\*\*(.+?)\:\*\*\s*(.*)$');

/// A `**<field>:** <text>` head read by [readFieldHead].
final class FieldHead {
  const new({required this.name, required this.value});

  final String name;

  /// The text after the label, trimmed.
  final String value;
}

/// Reads [head], an item's first line after its marker, as a field head; null
/// when it opens with no `**<field>:**` label.
FieldHead? readFieldHead(String head) {
  final match = _fieldItem.firstMatch(head);
  if (match == null) return null;
  return FieldHead(name: match.group(1)!, value: match.group(2)!.trim());
}

/// Reads [items]: the nested field items under each top-level item, keyed by
/// the item's line, and every field value the section holds, by field.
///
/// A nested item is one whose line opens indented; a field item is a nested
/// item whose text opens `- **<field>:** <text>`. A `###` heading or a
/// top-level paragraph belongs to no item, so it closes the one open above it.
SectionFields readSectionFields(List<SectionItem> items) {
  final fieldsByItem = <int, Map<String, String>>{};
  final values = <String, Set<String>>{};
  var itemLine = -1;
  for (final item in items) {
    final field = readFieldHead(item.head);
    if (item.kind == SectionItemKind.heading ||
        (item.kind == SectionItemKind.paragraph && !item.nested)) {
      itemLine = -1;
    } else if (item.nested) {
      if (itemLine >= 0 && field != null) {
        fieldsByItem[itemLine]!.putIfAbsent(field.name, () => field.value);
        values.update(
          field.name,
          (held) => held..add(field.value),
          ifAbsent: () => {field.value},
        );
      }
    } else {
      itemLine = item.line;
      fieldsByItem[itemLine] = {};
    }
  }
  return SectionFields(fieldsByItem: fieldsByItem, values: values);
}

/// The field items [readSectionFields] reads from one section.
final class SectionFields {
  const new({required this.fieldsByItem, required this.values});

  final Map<int, Map<String, String>> fieldsByItem;
  final Map<String, Set<String>> values;
}
