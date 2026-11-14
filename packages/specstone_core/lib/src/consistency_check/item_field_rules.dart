import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show SectionItem, SectionItemKind;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

final _fieldItem = RegExp(r'^\*\*(.+?)\:\*\*\s*(.*)$');

/// Returns the item-field and conditional-section findings of a typed [doc];
/// an untyped doc has none.
///
/// Each top-level item of a section whose template sets `item_fields` holds a
/// nested `- **<field>:** <text>` item per entry, its text one of the entry's
/// `values` when it gives them. A section whose template sets `required_when`
/// is required exactly while an item of the named section holds the named
/// field value: missing and met gives `required_section_missing`, held and
/// unmet gives `section_unneeded`.
Iterable<Finding> checkItemFields(CheckContext context, IndexedDoc doc) sync* {
  final type = context.typeOf(doc);
  if (type == null) return;
  final entriesBySection = <String, List<ItemFieldLint>>{};
  final rules = <(MergedSection, RequiredWhenLint)>[];
  for (final template in type.sections) {
    if (template.itemFields case final entries?) {
      entriesBySection[template.id] = entries;
    }
    if (template.requiredWhen case final rule?) rules.add((template, rule));
  }
  if (entriesBySection.isEmpty && rules.isEmpty) return;
  final watched = {
    ...entriesBySection.keys,
    for (final (_, rule) in rules) rule.section,
  };
  final valuesBySection = <String, Map<String, Set<String>>>{};
  final held = context.contentOf(doc).sections;
  for (var i = 0; i < held.length; i++) {
    final template = context.templateSectionAt(doc, i);
    if (template == null || !watched.contains(template.id)) continue;
    final (:fieldsByItem, :values) = _readSection(context.itemsIn(doc, i));
    valuesBySection[template.id] = values;
    final entries = entriesBySection[template.id];
    if (entries == null) continue;
    for (final MapEntry(:key, :value) in fieldsByItem.entries) {
      yield* _fieldFindings(context, doc, key, value, entries);
    }
  }
  for (final (template, rule) in rules) {
    final met =
        valuesBySection[rule.section]?[rule.field]?.contains(rule.value) ??
        false;
    final heldAt = context.heldIndexOf(doc, template.id);
    if (heldAt case final index?) {
      if (met) continue;
      yield context.finding(
        doc,
        FindingKind.sectionUnneeded,
        line: context.linesOf(doc).sectionLines[index],
        message: 'section ${template.id} is not needed',
        keys: {'section': template.id},
      );
    } else if (met) {
      yield context.finding(
        doc,
        FindingKind.requiredSectionMissing,
        line: 1,
        message: 'required section ${template.id} is missing',
        keys: {'section': template.id},
      );
    }
  }
}

Iterable<Finding> _fieldFindings(
  CheckContext context,
  IndexedDoc doc,
  int itemLine,
  Map<String, String> fields,
  List<ItemFieldLint> entries,
) sync* {
  for (final entry in entries) {
    final text = fields[entry.field];
    final holds =
        text != null &&
        text.isNotEmpty &&
        (entry.values == null || entry.values!.contains(text));
    if (holds) continue;
    yield context.finding(
      doc,
      FindingKind.itemFieldMissing,
      line: itemLine,
      message: entry.values == null
          ? 'the item holds no ${entry.field} field'
          : 'the item holds no ${entry.field} field of '
                '${entry.values!.join(', ')}',
      keys: {'field': entry.field},
    );
  }
}

/// Reads [items]: the nested field items under each top-level item, keyed by
/// the item's line, and every field value the section holds, by field.
///
/// A nested item is one whose line opens indented; a field item is a nested
/// item whose text opens `- **<field>:** <text>`. A `###` heading belongs to
/// no item, so it closes the one open above it.
({Map<int, Map<String, String>> fieldsByItem, Map<String, Set<String>> values})
_readSection(List<SectionItem> items) {
  final fieldsByItem = <int, Map<String, String>>{};
  final values = <String, Set<String>>{};
  var itemLine = -1;
  for (final item in items) {
    final match = _fieldItem.firstMatch(item.head);
    if (item.kind == SectionItemKind.heading) {
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
  return (fieldsByItem: fieldsByItem, values: values);
}
