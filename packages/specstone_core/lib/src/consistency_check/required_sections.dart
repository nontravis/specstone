import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/section_fields.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show RequiredWhenLint, WhenField;

/// Whether a section with [whenField] belongs on [doc]: it sets none, or the
/// doc's field holds one of its values; an unset field holds none.
bool appliesTo(IndexedDoc doc, WhenField? whenField) =>
    whenField == null ||
    doc.valuesOf(whenField.field).any(whenField.values.contains);

/// Whether the held section at [index] of [doc] has no non-blank body line.
bool isBlankAt(CheckContext context, IndexedDoc doc, int index) =>
    context.linesOf(doc).sectionCounts[index].lines == 0;

/// Whether the held section [rule] names holds its field with its value.
///
/// False when [doc] holds no such section.
bool requiredWhenMet(
  CheckContext context,
  IndexedDoc doc,
  RequiredWhenLint rule,
) {
  final index = context.heldIndexOf(doc, rule.section);
  if (index == null) return false;
  final fields = readSectionFields(context.itemsIn(doc, index));
  return fields.values[rule.field]?.contains(rule.value) ?? false;
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
