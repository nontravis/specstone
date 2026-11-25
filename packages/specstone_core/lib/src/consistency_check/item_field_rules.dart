import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/required_sections.dart';
import 'package:specstone_core/src/consistency_check/section_fields.dart';
import 'package:specstone_core/src/doc_model/default_enforcer.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Returns the item-field and conditional-section findings of a typed [doc];
/// an untyped doc has none.
///
/// Each top-level list item or table row of a section whose template sets
/// `item_fields` holds a nested `- **<field>:** <text>` item per entry, its
/// text one of the entry's `values` when it gives them; a top-level paragraph
/// holds none. An item may lack the field when the entry is `optional`, or
/// when its `default_from` section names a default enforcer for the doc; a
/// field the item holds still needs that text. An entry with a `when` applies
/// only to an item that meets it; an item that does not meet it and holds the
/// field gives `item_field_unneeded`. A section whose template sets
/// `required_when` is required exactly while an item of the named section
/// holds the named field value: missing or blank and met gives
/// `required_section_missing`, held and unmet gives `section_unneeded`.
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
  final held = context.contentOf(doc).sections;
  final defaults = <String, bool>{};
  bool hasDefault(String sectionId) => defaults.putIfAbsent(
    sectionId,
    () => _hasDefaultEnforcer(context, doc, sectionId),
  );
  for (var i = 0; i < held.length; i++) {
    final entries = entriesBySection[context.templateSectionAt(doc, i)?.id];
    if (entries == null) continue;
    final section = readSectionFields(context.itemsIn(doc, i));
    for (final MapEntry(:key, :value) in section.fieldsByItem.entries) {
      yield* _fieldFindings(context, doc, key, value, entries, hasDefault);
    }
  }
  for (final (template, rule) in rules) {
    final met = requiredWhenMet(context, doc, rule);
    final heldAt = context.heldIndexOf(doc, template.id);
    if (heldAt case final index?) {
      if (!met) {
        yield context.finding(
          doc,
          FindingKind.sectionUnneeded,
          line: context.linesOf(doc).sectionLines[index],
          message: 'section ${template.id} is not needed',
          keys: {'section': template.id},
        );
      } else if (isBlankAt(context, doc, index)) {
        yield requiredSectionFinding(
          context,
          doc,
          template.id,
          headerLine: context.linesOf(doc).sectionLines[index],
        );
      }
    } else if (met) {
      yield requiredSectionFinding(context, doc, template.id);
    }
  }
}

Iterable<Finding> _fieldFindings(
  CheckContext context,
  IndexedDoc doc,
  int itemLine,
  Map<String, String> fields,
  List<ItemFieldLint> entries,
  bool Function(String sectionId) hasDefault,
) sync* {
  for (final entry in entries) {
    final text = fields[entry.field];
    if (!entry.appliesTo(fields)) {
      if (text == null) continue;
      yield context.finding(
        doc,
        FindingKind.itemFieldUnneeded,
        line: itemLine,
        message: 'the item holds a ${entry.field} field it does not need',
        keys: {'field': entry.field},
      );
      continue;
    }
    if (text == null && _isFreed(entry, hasDefault)) continue;
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

bool _isFreed(ItemFieldLint entry, bool Function(String) hasDefault) {
  if (entry.optional) return true;
  final source = entry.defaultFrom;
  return source != null && hasDefault(source);
}

/// Returns whether the doc, or its nearest ancestor of the same doc type and
/// target, names a default enforcer in its [sectionId] table.
bool _hasDefaultEnforcer(
  CheckContext context,
  IndexedDoc doc,
  String sectionId,
) {
  final chain = [_entityRowsIn(context, doc, sectionId)];
  for (final path in ancestorTwinPaths(doc.docPath)) {
    final twin = context.index.at(path);
    if (twin == null ||
        twin.docTypeId != doc.docTypeId ||
        twin.target != doc.target) {
      continue;
    }
    chain.add(_entityRowsIn(context, twin, sectionId));
  }
  return defaultEnforcerOf(chain) != null;
}

List<EntityRow> _entityRowsIn(
  CheckContext context,
  IndexedDoc doc,
  String sectionId,
) {
  final section = context.heldSection(doc, sectionId);
  return section == null ? const [] : entityRowsOf(section.body.split('\n'));
}
