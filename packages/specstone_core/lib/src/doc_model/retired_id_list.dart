import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/templates/models/merged_field.dart'
    show retiredIdsField;

/// Returns the `retired_ids` block of [lfText]'s frontmatter, or null.
KeyBlock? retiredIdsBlockOf(String lfText) =>
    _retiredIdsBlockIn(Doc.parse(lfText));

KeyBlock? _retiredIdsBlockIn(Doc doc) =>
    doc.frontmatter?.where((b) => b.name == retiredIdsField).firstOrNull;

/// Whether the `retired_ids` block of [lfText] is absent or reads whole as a
/// YAML list of strings, so a write that grows it loses no entry.
bool isRetiredIdListWhole(String lfText) {
  final block = retiredIdsBlockOf(lfText);
  if (block == null) return true;
  return listEntriesOf(block)?.every((entry) => entry is String) ?? false;
}

/// Reads the `retired_ids` entries of [lfText], in file order; empty when the
/// doc holds none.
Set<String> readRetiredIdList(String lfText) => retiredIdsIn(Doc.parse(lfText));

/// Reads the `retired_ids` entries of the parsed [doc], as
/// [readRetiredIdList] reads them.
Set<String> retiredIdsIn(Doc doc) {
  final block = _retiredIdsBlockIn(doc);
  final entries = block == null ? null : listEntriesOf(block);
  return {
    for (final entry in entries ?? const <Object?>[])
      if (entry is String) entry,
  };
}
