import 'package:specstone_core/src/index_query/models/cited_by.dart';
import 'package:specstone_core/src/index_query/models/cited_place.dart';

/// A place a bundle prints whose `by` lines print right after file line
/// `after` of its doc, or as a part of their own (`CitedByIndex.inline`).
///
/// An item has its `item` ID, and a `###` block its heading's anchor as a
/// link names it, even when the block starts an item; each has the `##`
/// section `sectionKey` that holds it; a
/// section has its `sectionKey` alone, `after` its header's file line; a doc
/// has neither, `after` 0, the line of its naming line. [isBlock] is true for
/// a `###` block, which keeps `CitedKind.item`.
final class CitedItem {
  const new({
    required this.kind,
    required this.item,
    required this.sectionKey,
    required this.after,
    required this.by,
    this.isBlock = false,
  });

  final CitedKind kind;
  final String? item;
  final String? sectionKey;
  final int after;
  final List<CitedBy> by;
  final bool isBlock;
}
