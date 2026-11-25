import 'dart:convert';

import 'package:specstone_core/src/consistency_check/item_id_rules.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/doc_model/retired_id_list.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The item IDs a doc has given up, as its `retired_ids` field lists them.
final class RetiredIds {
  const new(this.ids);

  /// The IDs in the order they were retired.
  final Set<String> ids;

  /// Reads the `retired_ids` list of [lfText]; empty when the doc holds none.
  static RetiredIds readFrom(String lfText) =>
      RetiredIds(readRetiredIdList(lfText));

  /// Returns the list with each of [removed] added after the ones held.
  RetiredIds grownBy(Iterable<String> removed) =>
      RetiredIds({...ids, ...removed});

  /// Returns [lfText], the text of the doc at [docPath], with its
  /// `retired_ids` set to this list.
  ///
  /// An empty list leaves [lfText] as it is; a list on disk keeps its style.
  /// Throws [IndexFault] `argument_invalid` for a list on disk that does not
  /// read whole ([isRetiredIdListWhole]), which a write would lose entries of.
  String writeInto(String lfText, {required String docPath}) {
    if (ids.isEmpty) return lfText;
    if (!isRetiredIdListWhole(lfText)) {
      throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '$docPath: its $retiredIdsField is not a YAML list of IDs; fix it by '
        'hand before a write that retires an ID',
      );
    }
    return withKeyBlock(
      lfText,
      retiredIdsField,
      listBlockOf(
        retiredIdsField,
        ids.toList(),
        onDisk: retiredIdsBlockOf(lfText),
      ),
    );
  }
}

/// Returns [after], the text of the doc at [docPath], with each item ID that
/// [before] holds and [after] lacks added to its `retired_ids`; [after]
/// itself when none is lost.
///
/// Throws as [RetiredIds.writeInto] does.
String retireRemovedIds({
  required String docPath,
  required String before,
  required String after,
  required MergedDocType type,
}) {
  final removed = removedItemIds(before: before, after: after, type: type);
  if (removed.isEmpty) return after;
  return RetiredIds.readFrom(after)
      .grownBy(removed)
      .writeInto(after, docPath: docPath);
}

/// Returns each item ID that [before] holds and [after] lacks, in the order
/// [before] holds them.
///
/// Both texts are LF text of a doc of [type]. An edge case or scenario number
/// is no item ID.
Set<String> removedItemIds({
  required String before,
  required String after,
  required MergedDocType type,
}) {
  final kept = _itemIdsOf(after, type);
  return _itemIdsOf(before, type).difference(kept);
}

// An ordered set, so retired IDs keep the order the doc held them in. Only
// item IDs are read, so the placeholder doc path changes no result.
Set<String> _itemIdsOf(String lfText, MergedDocType type) {
  final content = parseIndexedDoc(
    docPath: 'doc.md',
    bytes: utf8.encode(lfText),
    match: MatchedDocType(type),
  ).content;
  return {
    for (final item in idsInDoc(content, type))
      if (item.id case ItemId(:final written)
          when !isPositionalPrefix(item.prefix))
        written,
  };
}
