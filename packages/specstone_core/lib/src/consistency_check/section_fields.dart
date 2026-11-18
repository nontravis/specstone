import 'package:specstone_core/src/doc_model/models/section_item.dart';

final _fieldItem = RegExp(r'^\*\*(.+?)\:\*\*\s*(.*)$');

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
    final match = _fieldItem.firstMatch(item.head);
    if (item.kind == SectionItemKind.heading ||
        (item.kind == SectionItemKind.paragraph && !item.nested)) {
      itemLine = -1;
    } else if (item.nested) {
      if (itemLine >= 0 && match != null) {
        final value = match.group(2)!.trim();
        fieldsByItem[itemLine]!.putIfAbsent(match.group(1)!, () => value);
        values.update(
          match.group(1)!,
          (held) => held..add(value),
          ifAbsent: () => {value},
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
