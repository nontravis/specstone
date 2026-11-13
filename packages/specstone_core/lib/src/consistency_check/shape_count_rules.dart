import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show isThematicBreak, itemHeadingMarker, tableCellRanges, tableHeadCells;
import 'package:specstone_core/src/doc_model/sentences.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

final _listMarker = RegExp(r'^(?:[-*+]|\d{1,9}[.)])(?:[ \t]+|$)');
final _listMarkerIndented = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])(?:[ \t]+|$)');

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
    final section = _Block(context.bodyLinesOf(doc, i));
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
    for (final table in section.tables) {
      final at = table.header.indexOf(column);
      if (at < 0) continue;
      for (final row in table.rows) {
        final cells = tableCellRanges(row.text);
        if (at >= cells.length) continue;
        yield (
          line: row.line,
          text: row.text.substring(cells[at].start, cells[at].end).trim(),
        );
      }
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

/// One item: its first file line and raw text, and all its own lines.
typedef _Item = ({int line, String firstLine, String text});

/// One table: its header cells and its body rows.
typedef _Table = ({List<String> header, List<BodyLine> rows});

/// A run of consecutive body lines, read for items, tables, and subsections
/// on first use.
final class _Block {
  new(this._lines);

  final List<BodyLine> _lines;

  late final List<_Table> tables = _tablesIn(_lines);

  late final List<_Item> items = _itemsIn(_lines, tables);

  /// The unfenced lines, joined.
  late final String text = [
    for (final line in _lines)
      if (!line.fenced) line.text,
  ].join('\n');

  /// The `###` subsections, each with the heading's file line and the block
  /// under it.
  late final List<({int line, _Block block})> subsections = _subsectionsIn(
    _lines,
  );
}

List<({int line, _Block block})> _subsectionsIn(List<BodyLine> lines) {
  final starts = [
    for (var k = 0; k < lines.length; k++)
      if (!lines[k].fenced && lines[k].text.startsWith(itemHeadingMarker)) k,
  ];
  return [
    for (var s = 0; s < starts.length; s++)
      (
        line: lines[starts[s]].line,
        block: _Block(
          lines.sublist(
            starts[s] + 1,
            s + 1 < starts.length ? starts[s + 1] : lines.length,
          ),
        ),
      ),
  ];
}

/// Returns the top-level list items of [lines], each whole: its wrapped
/// lines included, its nested items aside.
List<_Item> _itemsIn(List<BodyLine> lines, List<_Table> tables) {
  if (lines.isEmpty) return const [];
  final rowLines = {
    for (final table in tables)
      for (final row in table.rows) row.line,
  };
  final items = <_Item>[];
  var k = 0;
  while (k < lines.length) {
    final text = lines[k].text;
    if (lines[k].fenced || !_listMarker.hasMatch(text)) {
      k++;
      continue;
    }
    final base = _indentOf(text);
    var end = k + 1;
    while (end < lines.length && _continuesItem(lines[end], base, rowLines)) {
      end++;
    }
    items.add((
      line: lines[k].line,
      firstLine: text,
      text: _itemText(lines, k, end),
    ));
    k = end;
  }
  return items;
}

/// Returns the own lines of the item from [k] to [end], a nested item's lines
/// dropped.
String _itemText(List<BodyLine> lines, int k, int end) {
  final own = StringBuffer(lines[k].text);
  int? nestedIndent;
  for (var j = k + 1; j < end; j++) {
    final text = lines[j].text;
    if (lines[j].fenced) continue;
    final indent = _indentOf(text);
    final marker = _listMarkerIndented.hasMatch(text) ? indent : null;
    if (marker != null && marker > _indentOf(lines[k].text)) {
      nestedIndent = marker;
      continue;
    }
    if (nestedIndent != null) {
      if (indent < nestedIndent) {
        nestedIndent = null;
      } else {
        continue;
      }
    }
    own.write('\n$text');
  }
  return own.toString();
}

/// Whether [line] stays in the item that opened at [base] indent columns: a
/// blank line, a fence, a heading, a thematic break, a table row, and a
/// same-or-shallower list marker each end it.
bool _continuesItem(BodyLine line, int base, Set<int> rowLines) {
  if (line.fenced || rowLines.contains(line.line)) return false;
  final text = line.text;
  if (text.trim().isEmpty) return false;
  if (text.startsWith(itemHeadingMarker) || isThematicBreak(text)) return false;
  return !_listMarkerIndented.hasMatch(text) || _indentOf(text) > base;
}

int _indentOf(String text) {
  var at = 0;
  while (at < text.length &&
      (text.codeUnitAt(at) == 0x20 || text.codeUnitAt(at) == 0x09)) {
    at++;
  }
  return at;
}

List<_Table> _tablesIn(List<BodyLine> lines) {
  final tables = <_Table>[];
  var k = 0;
  while (k + 1 < lines.length) {
    final head = lines[k];
    final cells = head.fenced || lines[k + 1].fenced
        ? null
        : tableHeadCells(head.text, lines[k + 1].text);
    if (cells == null) {
      k++;
      continue;
    }
    var end = k + 2;
    while (end < lines.length && _isRow(lines[end])) {
      end++;
    }
    tables.add((
      header: [
        for (final cell in cells)
          head.text.substring(cell.start, cell.end).trim(),
      ],
      rows: lines.sublist(k + 2, end),
    ));
    k = end;
  }
  return tables;
}

bool _isRow(BodyLine line) =>
    !line.fenced &&
    line.text.trim().isNotEmpty &&
    !line.text.startsWith(itemHeadingMarker) &&
    !_listMarkerIndented.hasMatch(line.text) &&
    !isThematicBreak(line.text);
