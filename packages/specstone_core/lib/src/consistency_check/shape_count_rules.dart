import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/sentences.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Returns the sentence, item-count, and line-floor findings of a typed [doc];
/// an untyped doc has none.
///
/// An item is a top-level list item or a table row; a nested item, a
/// paragraph, a heading, and fenced code are none.
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
    if (limits.isEmpty && count == null) continue;
    final section = _Block(
      context.itemsIn(doc, i),
      text: [
        for (final line in context.bodyLinesOf(doc, i))
          if (!line.fenced) line.text,
      ].join('\n'),
    );
    for (final limit in limits) {
      yield* _sentenceFindings(context, doc, section, headerLine, limit);
    }
    if (count != null) {
      yield* _countFindings(context, doc, section, headerLine, count);
    }
  }
}

Iterable<Finding> _sentenceFindings(
  CheckContext context,
  IndexedDoc doc,
  _Block section,
  int headerLine,
  SentenceLimit limit,
) sync* {
  for (final (:line, :text) in _textsToLimit(section, headerLine, limit)) {
    final actual = sentencesOf(text).length;
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

/// Returns each text [limit] bounds with its file line.
///
/// A section with no item and a limit with no prefix or column bounds its
/// whole text, at the header line.
Iterable<({int line, String text})> _textsToLimit(
  _Block section,
  int headerLine,
  SentenceLimit limit,
) sync* {
  if (limit.column case final column?) {
    for (final row in section.rows) {
      final at = row.header!.indexOf(column);
      if (at < 0 || at >= row.cells!.length) continue;
      yield (line: row.line, text: row.cells![at]);
    }
    return;
  }
  final prefix = limit.linePrefix;
  if (prefix == null && section.items.isEmpty) {
    yield (line: headerLine, text: section.text);
    return;
  }
  for (final item in section.items) {
    if (prefix == null || item.firstLine.startsWith(prefix)) {
      yield (line: item.line, text: item.text);
    }
  }
}

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
        .where((item) => item.firstLine.startsWith(linePrefix))
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

/// A section's top-level items, grouped for the rules.
final class _Block {
  new(List<SectionItem> all, {this.text = ''})
    : _all = [
        for (final item in all)
          if (!item.nested) item,
      ];

  final List<SectionItem> _all;

  /// The section's unfenced text, read when no list item or table row holds
  /// it.
  final String text;

  /// The list items and table rows.
  late final List<SectionItem> items = [
    for (final item in _all)
      if (item.kind == SectionItemKind.listItem ||
          item.kind == SectionItemKind.tableRow)
        item,
  ];

  /// The table rows.
  late final List<SectionItem> rows = [
    for (final item in _all)
      if (item.kind == SectionItemKind.tableRow) item,
  ];

  /// The `###` subsections, each with its heading's file line and the items
  /// under it.
  late final List<({int line, _Block block})> subsections = _subsectionsOf(
    _all,
  );
}

List<({int line, _Block block})> _subsectionsOf(List<SectionItem> all) {
  final subsections = <({int line, List<SectionItem> under})>[];
  for (final item in all) {
    if (item.kind == SectionItemKind.heading) {
      subsections.add((line: item.line, under: []));
    } else if (subsections.isNotEmpty) {
      subsections.last.under.add(item);
    }
  }
  return [
    for (final (:line, :under) in subsections)
      (line: line, block: _Block(under)),
  ];
}
