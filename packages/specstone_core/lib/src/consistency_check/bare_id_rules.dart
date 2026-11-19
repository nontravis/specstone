import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/bare_id_owner.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/bare_item_id.dart';

/// Returns an `item_mention_missing` finding for each bare item ID of the
/// typed [doc] whose owner doc lacks that item.
///
/// A run after a code-span cite is `cite_unlinked`'s, and a run after a link
/// to no doc has no owner. The facts are the stored ones, so no doc text is
/// read.
Iterable<Finding> checkBareItemIds(CheckContext context, IndexedDoc doc) sync* {
  for (final id in context.contentOf(doc).lineFacts.bareItemIds) {
    if (id.citation is CiteCitation) continue;
    final owner = ownerDocOf(
      context.index,
      id,
      holderDocPath: doc.docPath,
      ownDoc: doc,
    );
    if (owner == null || _holds(context.contentOf(owner.doc), id.id)) continue;
    yield context.finding(
      doc,
      FindingKind.itemMentionMissing,
      line: id.line,
      message: 'bare ID ${id.id} is no item of ${owner.doc.docPath}',
      keys: {'item': id.id, 'target': owner.doc.docPath},
    );
  }
}

bool _holds(DocContent content, String itemId) => content.itemFacts.sectionItems
    .any((items) => items.any((item) => item.id == itemId));
