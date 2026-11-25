import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/document_writing/clean_draft_judge.dart';
import 'package:specstone_core/src/document_writing/draft_sections.dart'
    show comparableItemTextOf;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show docStructureOf, leadKey;
import 'package:specstone_core/src/index_query/item_facts.dart'
    show leadItemsAt, sectionItemsAt;
import 'package:specstone_core/src/index_query/models/doc_content.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Returns the [findingKeyOf] keys of the `item_over_limit` [findings] whose
/// item the approved copy holds in the same section.
///
/// [draftLf] and [approvedLf] are the LF text of the draft the findings
/// belong to and of its approved copy. Items match after whitespace collapses
/// and each opening `>` mark and the list marker drop, so a rewrap or a
/// renumber does not change an item.
Set<String> heldItemKeysOf({
  required Iterable<Finding> findings,
  required String draftLf,
  required String approvedLf,
  required MergedDocType? type,
}) {
  final draft = docStructureOf(draftLf, type);
  final approved = docStructureOf(approvedLf, type);
  return {
    for (final finding in findings)
      if (finding.kind == FindingKind.itemOverLimit &&
          _isHeld(finding, draft, approved, type))
        findingKeyOf(finding),
  };
}

bool _isHeld(
  Finding finding,
  DocContent draft,
  DocContent approved,
  MergedDocType? type,
) {
  final section = finding.keys['section'];
  if (section is! String) return false;
  final item = _itemsIn(
    draft,
    section,
    type,
  ).where((item) => item.line == finding.line).firstOrNull;
  if (item == null) return false;
  final text = comparableItemTextOf(item);
  return _itemsIn(
    approved,
    section,
    type,
  ).any((held) => comparableItemTextOf(held) == text);
}

Iterable<SectionItem> _itemsIn(
  DocContent content,
  String sectionKey,
  MergedDocType? type,
) sync* {
  if (sectionKey == leadKey) {
    yield* leadItemsAt(content, type);
    return;
  }
  for (final (at, section) in content.sections.indexed) {
    if (section.key == sectionKey) yield* sectionItemsAt(content, at, type);
  }
}
