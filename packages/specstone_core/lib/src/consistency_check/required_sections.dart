import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart'
    show heldSectionIndexIn;
import 'package:specstone_core/src/consistency_check/section_fields.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show sectionItemsAt;
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show MergedDocType, MergedSection, RequiredWhenLint, WhenField;

/// Whether a section with [whenField] belongs on [doc]: it sets none, or the
/// doc's field holds one of its values; an unset field holds none.
bool appliesTo(IndexedDoc doc, WhenField? whenField) =>
    whenField == null ||
    doc.valuesOf(whenField.field).any(whenField.values.contains);

/// Whether the held section at [index] of [doc] has no non-blank body line.
bool isBlankAt(CheckContext context, IndexedDoc doc, int index) =>
    isBlankIn(context.contentOf(doc), index);

/// Whether the held section at [index] of [content] has no non-blank body
/// line.
bool isBlankIn(DocContent content, int index) =>
    content.lineFacts.sectionCounts[index].lines == 0;

/// Whether the held section [rule] names holds its field with its value.
///
/// False when [doc] holds no such section.
bool requiredWhenMet(
  CheckContext context,
  IndexedDoc doc,
  RequiredWhenLint rule,
) => requiredWhenMetIn(context.contentOf(doc), context.typeOf(doc), rule);

/// Whether the held section [rule] names in [content], a doc of [type], holds
/// its field with its value.
///
/// False when [content] holds no such section.
bool requiredWhenMetIn(
  DocContent content,
  MergedDocType? type,
  RequiredWhenLint rule,
) {
  final index = heldSectionIndexIn(
    heldTemplatesOf(content.sections, type),
    rule.section,
  );
  if (index == null) return false;
  final fields = readSectionFields(sectionItemsAt(content, index, type));
  return fields.values[rule.field]?.contains(rule.value) ?? false;
}

/// Whether [section] is required on [doc]: it sets `required` and applies, or
/// its `required_when` rule is met.
bool isRequiredOn(
  CheckContext context,
  IndexedDoc doc,
  MergedSection section,
) => isRequiredIn(doc, context.contentOf(doc), context.typeOf(doc), section);

/// Whether [section] is required on [doc], whose text is [content], a doc of
/// [type].
bool isRequiredIn(
  IndexedDoc doc,
  DocContent content,
  MergedDocType? type,
  MergedSection section,
) {
  if (section.required && appliesTo(doc, section.whenField)) return true;
  final rule = section.requiredWhen;
  return rule != null && requiredWhenMetIn(content, type, rule);
}

/// Returns the `required_section_missing` finding of [sectionId] on [doc].
///
/// With no [headerLine] the section is absent and the finding sits at line 1;
/// with one the section is held and blank, and the finding sits at that line.
Finding requiredSectionFinding(
  CheckContext context,
  IndexedDoc doc,
  String sectionId, {
  int? headerLine,
}) => context.finding(
  doc,
  FindingKind.requiredSectionMissing,
  line: headerLine ?? 1,
  message: headerLine == null
      ? 'required section $sectionId is missing'
      : 'required section $sectionId is empty',
  keys: {'section': sectionId},
);
