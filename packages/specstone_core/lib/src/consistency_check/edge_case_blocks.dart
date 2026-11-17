import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show SectionItem, SectionItemKind;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show itemKeyOfHead;

const _edgeCasesSection = 'edge_cases';

/// Returns the edge cases of the requirement [fr], each ID as written mapped
/// to its block.
///
/// A block runs from the item's first line to the line before the next item
/// that is not nested, nested items included, its trailing blank lines left
/// off. The first of a repeated ID wins; an item with no readable ID keys no
/// block. Empty when [fr] holds no `edge_cases` section.
Map<String, String> edgeCaseBlocksOf(CheckContext context, IndexedDoc fr) {
  final at = context.heldIndexOf(fr, _edgeCasesSection);
  final section = at == null ? null : context.templateSectionAt(fr, at);
  if (at == null || section == null) return const {};
  final body = context.bodyLinesOf(fr, at);
  final tops = [
    for (final item in context.itemsIn(fr, at))
      if (!item.nested) item,
  ];
  final blocks = <String, String>{};
  for (final (i, item) in tops.indexed) {
    final key = itemKeyOfHead(
      item.head,
      isHeading: item.kind == SectionItemKind.heading,
      prefixId: section.prefixId,
      isAcceptanceCriteria: false,
    );
    if (key == null || blocks.containsKey(key)) continue;
    final end = i + 1 < tops.length ? tops[i + 1].line : null;
    blocks[key] = _blockText(body, item, end);
  }
  return blocks;
}

String _blockText(List<BodyLine> body, SectionItem item, int? endLine) => [
  for (final line in body)
    if (line.line >= item.line && (endLine == null || line.line < endLine))
      line.text,
].join('\n').trimRight();
