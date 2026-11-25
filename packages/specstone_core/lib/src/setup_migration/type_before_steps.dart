import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/document_writing/approval.dart'
    show ApprovalFields, approvalHashOf;
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;
import 'package:specstone_core/src/setup_migration/drop_section_step.dart'
    show keepsDroppedSection;
import 'package:specstone_core/src/setup_migration/record_placement.dart'
    show typeBeforeMoves;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';

/// Returns [type], the merged type after [steps], as it stood before them for
/// the doc [lf], so a doc approved under the older type hashes as it did then.
///
/// Only the carried pack versions ship, so the older type is rebuilt by
/// undoing each step that changes the type: [typeBeforeMoves], then each
/// `rename_field` and `rename_section` from the last, then each section a
/// `drop_section` step removed, put back in the slot whose hash matches the
/// doc's `approved:` value, else after the section [lf] holds before it.
///
/// - [statusesOutside]: the rule [approvalHashOf] hashes the doc by.
MergedDocType typeBeforeSteps(
  MergedDocType type,
  List<MigrationStep> steps, {
  required String lf,
  required bool statusesOutside,
}) {
  var fields = typeBeforeMoves(type, steps).fields;
  var sections = type.sections;
  final dropped = <String>{};
  for (final step in steps.reversed) {
    if (!step.touches(type.id)) continue;
    switch (step) {
      case RenameField(:final from, :final to):
        fields = [
          for (final field in fields)
            if (field.id == to) _fieldNamed(field, from) else field,
        ];
      case RenameSection(:final fromHeader, :final toHeader):
        sections = [
          for (final section in sections)
            if (headerKey(section.header) == headerKey(toHeader))
              section.copyWith(header: fromHeader)
            else
              section,
        ];
      case DropSection() when !keepsDroppedSection(type, step):
        dropped.add(step.sectionId);
        sections = [
          ...sections,
          MergedSection(id: step.sectionId, header: step.sectionHeader),
        ];
      default:
        break;
    }
  }
  final doc = Doc.parse(lf);
  final placed = _placedAsIn(doc, sections, dropped: dropped);
  final byDocOrder = type.copyWith(fields: fields, sections: placed);
  final approved = ApprovalFields.of(doc).approvedValue;
  if (dropped.isEmpty || approved is! String) return byDocOrder;
  for (final candidate in _slotsOf(placed, dropped: dropped)) {
    final before = type.copyWith(fields: fields, sections: candidate);
    if (approvalHashOf(lf, before, statusesOutside: statusesOutside) ==
        approved) {
      return before;
    }
  }
  return byDocOrder;
}

/// Yields [sections] once per slot of each section whose id is in [dropped],
/// every other section kept in order.
Iterable<List<MergedSection>> _slotsOf(
  List<MergedSection> sections, {
  required Set<String> dropped,
}) sync* {
  for (final section in sections) {
    if (!dropped.contains(section.id)) continue;
    final rest = [...sections]..remove(section);
    for (var slot = 0; slot <= rest.length; slot++) {
      yield [...rest]..insert(slot, section);
    }
  }
}

/// Returns [field] under [id], every other property kept.
MergedField _fieldNamed(MergedField field, String id) => MergedField(
  id: id,
  type: field.type,
  list: field.list,
  required: field.required,
  enumValues: field.enumValues,
  docTypes: field.docTypes,
  pointer: field.pointer,
  root: field.root,
  bundleWith: field.bundleWith,
  description: field.description,
  lint: field.lint,
);

/// Returns [sections] with each section whose id is in [dropped] moved to
/// just after the section [doc] holds before it, or first when [doc] holds
/// none before it; one [doc] lacks stays last, where no hash reads it.
List<MergedSection> _placedAsIn(
  Doc doc,
  List<MergedSection> sections, {
  required Set<String> dropped,
}) {
  if (dropped.isEmpty) return sections;
  final placed = [
    for (final section in sections)
      if (!dropped.contains(section.id)) section,
  ];
  final unplaced = {
    for (final section in sections)
      if (dropped.contains(section.id)) headerKey(section.header): section,
  };
  int indexOf(String key) =>
      placed.indexWhere((section) => headerKey(section.header) == key);
  var previous = -1;
  for (final docSection in doc.sections) {
    final key = headerKey(docSection.headerText);
    if (unplaced.remove(key) case final section?) {
      placed.insert(previous + 1, section);
    }
    final index = indexOf(key);
    if (index >= 0) previous = index;
  }
  return [...placed, ...unplaced.values];
}
