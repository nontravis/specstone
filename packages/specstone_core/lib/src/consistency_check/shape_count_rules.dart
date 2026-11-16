import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Returns the sentence, item-count, line-floor, and subsection-cap findings
/// of a typed [doc]; an untyped doc has none.
///
/// An item is a top-level list item, table row, paragraph, or `###` heading
/// with the paragraph under it; a nested item and fenced code are none. A
/// sentence count is the stored fact of its item.
Iterable<Finding> checkShapeCounts(CheckContext context, IndexedDoc doc) sync* {
  if (context.typeOf(doc) == null) return;
  final lines = context.linesOf(doc);
  final held = context.contentOf(doc).sections;
  for (var i = 0; i < held.length; i++) {
    final template = context.templateSectionAt(doc, i);
    if (template == null) continue;
    final headerLine = lines.sectionLines[i];
    final minLines = template.minLines;
    final actualLines = lines.sectionCounts[i].lines;
    if (minLines != null && actualLines < minLines) {
      yield context.finding(
        doc,
        FindingKind.linesUnderLimit,
        line: headerLine,
        message:
            'section ${template.id} has $actualLines lines; the floor is '
            '$minLines',
        keys: {
          'section': template.id,
          'limit': minLines,
          'actual': actualLines,
        },
      );
    }
    final limits = template.maxSentences ?? const <SentenceLimit>[];
    final count = template.itemCount;
    final maxSubsections = template.maxSubsections;
    if (limits.isEmpty && count == null && maxSubsections == null) continue;
    final section = _Block(_heldItemsIn(context, doc, i));
    if (maxSubsections != null) {
      yield* _subsectionLimitFindings(
        context,
        doc,
        template.id,
        section,
        headerLine,
        maxSubsections,
      );
    }
    for (final limit in limits) {
      yield* _sentenceFindings(context, doc, section, limit);
    }
    if (count != null) {
      yield* _countFindings(context, doc, section, headerLine, count);
    }
  }
}

Iterable<Finding> _subsectionLimitFindings(
  CheckContext context,
  IndexedDoc doc,
  String sectionId,
  _Block section,
  int headerLine,
  int limit,
) sync* {
  final actual = section.subsections.length;
  if (actual <= limit) return;
  yield context.finding(
    doc,
    FindingKind.subsectionsOverLimit,
    line: headerLine,
    message: 'section $sectionId has $actual subsections; the limit is $limit',
    keys: {'section': sectionId, 'limit': limit, 'actual': actual},
  );
}

/// Returns the items of the held section at [index] of [doc], each with the
/// readability facts the index stores for it.
///
/// The items and the stored facts read the same section by one item rule, so
/// they pair by position; a section whose two counts differ is a fault in the
/// index.
List<_Held> _heldItemsIn(CheckContext context, IndexedDoc doc, int index) {
  final items = context.itemsIn(doc, index);
  final content = context.contentOf(doc);
  final facts = content.itemFacts.sectionItems[index];
  if (items.length != facts.length) {
    throw StateError(
      '${doc.docPath} section ${content.sections[index].key} holds '
      '${items.length} items but the index stores ${facts.length}',
    );
  }
  return [
    for (var k = 0; k < items.length; k++)
      (item: items[k], facts: facts[k].readability),
  ];
}

Iterable<Finding> _sentenceFindings(
  CheckContext context,
  IndexedDoc doc,
  _Block section,
  SentenceLimit limit,
) sync* {
  for (final (:line, :actual) in _countsToLimit(section, limit)) {
    if (actual <= limit.count) continue;
    yield context.finding(
      doc,
      FindingKind.sentencesOverLimit,
      line: line,
      message: 'holds $actual sentences; the limit is ${limit.count}',
      keys: {'limit': limit.count, 'actual': actual},
    );
  }
}

/// Returns the sentence count of each item or cell [limit] bounds, with its
/// file line.
///
/// A `###` heading's sentence adds none to the count.
Iterable<({int line, int actual})> _countsToLimit(
  _Block section,
  SentenceLimit limit,
) sync* {
  if (limit.column case final column?) {
    for (final (:item, :facts) in section.rows) {
      final at = item.header!.indexOf(column);
      if (at < 0 || at >= facts.cells.length) continue;
      yield (line: item.line, actual: _sentenceCountOf(facts.cells[at]));
    }
    return;
  }
  final prefix = limit.linePrefix;
  for (final (:item, :facts) in section.readable) {
    if (prefix == null || item.firstLine.startsWith(prefix)) {
      yield (
        line: item.line,
        actual: _sentenceCountOf(facts.cells.expand((cell) => cell)),
      );
    }
  }
}

int _sentenceCountOf(Iterable<SentenceFact> sentences) =>
    sentences.where((sentence) => !sentence.isHeading).length;

Iterable<Finding> _countFindings(
  CheckContext context,
  IndexedDoc doc,
  _Block section,
  int headerLine,
  ItemCountLint lint,
) sync* {
  if (!lint.perSubsection) {
    yield* _countIn(context, doc, section, headerLine, lint);
    return;
  }
  for (final (:line, :block) in section.subsections) {
    yield* _countIn(context, doc, block, line, lint);
  }
}

Iterable<Finding> _countIn(
  CheckContext context,
  IndexedDoc doc,
  _Block block,
  int line,
  ItemCountLint lint,
) sync* {
  final actual = block.items.length;
  final min = lint.min;
  final max = lint.max;
  final (bound, message) = switch ((min, max)) {
    (final min?, _) when actual < min => (
      min,
      'holds $actual items; the fewest is $min',
    ),
    (_, final max?) when actual > max => (
      max,
      'holds $actual items; the most is $max',
    ),
    _ => (null, ''),
  };
  if (bound != null) {
    yield context.finding(
      doc,
      FindingKind.itemCountOutOfRange,
      line: line,
      message: message,
      keys: {'limit': bound, 'actual': actual},
    );
  }
  for (final (:linePrefix, :count) in lint.prefixes) {
    final held = block.items
        .where((held) => held.item.firstLine.startsWith(linePrefix))
        .length;
    if (held == count) continue;
    yield context.finding(
      doc,
      FindingKind.prefixCountMismatch,
      line: line,
      message: 'holds $held items opening with $linePrefix; it needs $count',
      keys: {'line_prefix': linePrefix, 'limit': count, 'actual': held},
    );
  }
}

/// An item and the readability facts stored for it.
typedef _Held = ({SectionItem item, ReadabilityFacts facts});

/// A section's top-level items, grouped for the rules.
final class _Block {
  new(List<_Held> all)
    : readable = [
        for (final held in all)
          if (!held.item.nested) held,
      ];

  /// Every top-level item a sentence limit reads.
  final List<_Held> readable;

  /// The list items, table rows, and paragraphs an item count counts.
  late final List<_Held> items = [
    for (final held in readable)
      if (held.item.kind != SectionItemKind.heading) held,
  ];

  /// The table rows.
  late final List<_Held> rows = [
    for (final held in readable)
      if (held.item.kind == SectionItemKind.tableRow) held,
  ];

  /// The `###` subsections, each with its heading's file line and the items
  /// under it.
  late final List<({int line, _Block block})> subsections = _subsectionsOf(
    readable,
  );
}

List<({int line, _Block block})> _subsectionsOf(List<_Held> all) {
  final subsections = <({int line, List<_Held> under})>[];
  for (final held in all) {
    if (held.item.kind == SectionItemKind.heading) {
      subsections.add((line: held.item.line, under: []));
    } else if (subsections.isNotEmpty) {
      subsections.last.under.add(held);
    }
  }
  return [
    for (final (:line, :under) in subsections)
      (line: line, block: _Block(under)),
  ];
}
