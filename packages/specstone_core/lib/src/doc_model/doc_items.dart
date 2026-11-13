import 'package:specstone_core/src/doc_model/body_line.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show
        CellRange,
        isThematicBreak,
        itemHeadingMarker,
        startsTable,
        tableCellRanges,
        tableHeadCells;
import 'package:specstone_core/src/doc_model/text_scan.dart';

const _lineFeedChars = 1;

const _quoteMark = 0x3E;
const _space = 0x20;
const _maxMarkIndent = 3;
final _listMarker = RegExp(r'^\s*(?:[-*+]|\d+[.)])(?:\s+|$)');

/// One item of a section.
///
/// `line` is the first line of the item in the body lines given, the file
/// line when they are the file's. `chars` counts the item's own lines in code
/// points, a surrogate pair once, with the line feeds between them. `text` is
/// the first line after any `>` mark, list marker, or `### `. `heading` is
/// true for a `###` item.
typedef DocItem = ({int line, int chars, String text, bool heading});

/// Returns the items of a section's [body] lines in order.
///
/// An item is a list item without its nested items, a nested item alone, a
/// table row below the delimiter row, a paragraph, or a `###` heading with
/// the paragraph right under it and never its bullets, inside a blockquote
/// as anywhere else. A fenced code block, a thematic break, and a table's
/// header and delimiter rows are no item. A list item ends at a blank line or
/// a fence, and the text after it is its own item. A line scan, no markdown
/// parse.
List<DocItem> itemsOf(List<BodyLine> body) => [
  for (final span in _spansOf(body, _linesOf(body))) span.item,
];

/// What a [TopLevelItem] is.
enum TopLevelKind { listItem, tableRow, heading }

/// One top-level item of a section: a list item or table row that opens at
/// the first column (after any `>` marks), or a `###` heading.
///
/// `line` is its first file line; `firstLine` its first line after any `>`
/// marks; `text` its own lines as written, nested items aside. A table row
/// carries its table's `header` cells and its own `cells`, both trimmed;
/// every other kind carries null for both.
typedef TopLevelItem = ({
  int line,
  TopLevelKind kind,
  String firstLine,
  String text,
  List<String>? header,
  List<String>? cells,
});

/// Returns the top-level items of a section's [body] lines in order, read as
/// [itemsOf] reads them.
///
/// A paragraph and a nested item are none, and a fenced line belongs to no
/// item. A nested item's lines are no part of its parent's text.
List<TopLevelItem> topLevelItemsOf(List<BodyLine> body) {
  final lines = _linesOf(body);
  final headers = <int, List<String>>{};
  final items = <TopLevelItem>[];
  for (final span in _spansOf(body, lines)) {
    final first = lines[span.start];
    final kind = switch (span.item.heading) {
      true => TopLevelKind.heading,
      false when span.headerAt != null => TopLevelKind.tableRow,
      false when first.kind == _Kind.list => TopLevelKind.listItem,
      _ => null,
    };
    if (kind == null) continue;
    if (kind != TopLevelKind.tableRow &&
        first.inner.startsWith(RegExp(r'\s'))) {
      continue;
    }
    final headerAt = span.headerAt;
    items.add((
      line: span.item.line,
      kind: kind,
      firstLine: first.inner,
      text: [for (var k = span.start; k <= span.end; k++) body[k].text]
          .join('\n'),
      header: headerAt == null
          ? null
          : headers.putIfAbsent(headerAt, () {
              final head = lines[headerAt].inner;
              return _cellTexts(
                head,
                tableHeadCells(head, lines[headerAt + 1].inner)!,
              );
            }),
      cells: headerAt == null
          ? null
          : _cellTexts(first.inner, tableCellRanges(first.inner)),
    ));
  }
  return items;
}

List<String> _cellTexts(String row, List<CellRange> ranges) => [
  for (final cell in ranges) row.substring(cell.start, cell.end).trim(),
];

List<_Line> _linesOf(List<BodyLine> body) => [
  for (final line in body) _Line.of(line),
];

/// One item's place in the body lines: its first and last line index, and the
/// index of its table's header line when it is a table row.
typedef _Span = ({DocItem item, int start, int end, int? headerAt});

List<_Span> _spansOf(List<BodyLine> body, List<_Line> lines) {
  final spans = <_Span>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (_startsTable(lines, i)) {
      i = _addTableRows(spans, body, lines, i);
    } else if (line.kind == _Kind.blank ||
        line.kind == _Kind.fence ||
        line.kind == _Kind.rule) {
      i++;
    } else {
      final end = line.kind == _Kind.heading
          ? _headingEnd(lines, i)
          : _paragraphEnd(lines, i);
      spans.add((
        item: _itemOf(body, lines, i, end),
        start: i,
        end: end,
        headerAt: null,
      ));
      i = end + 1;
    }
  }
  return spans;
}

enum _Kind { blank, fence, rule, heading, list, text }

/// One body line split into its blockquote depth and the text after it.
final class _Line {
  const new(this.kind, this.quote, this.inner);

  /// Reads [line]; a fenced line is code, so it holds no `>` mark.
  factory of(BodyLine line) {
    if (line.fenced) return _Line(_Kind.fence, 0, line.text);
    final (:quote, :end) = _quoteMarksOf(line.text);
    final inner = end == 0 ? line.text : line.text.substring(end);
    return _Line(_kindOf(inner), quote, inner);
  }

  /// Returns the count of `>` marks at the start of [text], each after up to
  /// 3 spaces and before one optional space, and the index after the last.
  static ({int quote, int end}) _quoteMarksOf(String text) {
    var quote = 0;
    var end = 0;
    while (true) {
      var at = end;
      while (at < text.length &&
          at - end < _maxMarkIndent &&
          text.codeUnitAt(at) == _space) {
        at++;
      }
      if (at >= text.length || text.codeUnitAt(at) != _quoteMark) break;
      at++;
      if (at < text.length && text.codeUnitAt(at) == _space) at++;
      end = at;
      quote++;
    }
    return (quote: quote, end: end);
  }

  static _Kind _kindOf(String inner) {
    if (inner.trim().isEmpty) return _Kind.blank;
    if (isThematicBreak(inner)) return _Kind.rule;
    if (inner.startsWith(itemHeadingMarker)) return _Kind.heading;
    final marker = _listMarker.firstMatch(inner);
    if (marker == null) return _Kind.text;
    return isThematicBreak(inner.substring(marker.end))
        ? _Kind.rule
        : _Kind.list;
  }

  final _Kind kind;

  /// The count of `>` marks before the text.
  final int quote;
  final String inner;

  /// Whether the line is text, or opens like a list item, that a table row
  /// may be.
  bool get isTableCandidate => kind == _Kind.text || kind == _Kind.list;

  /// The first line of an item that starts here, marker stripped.
  String get itemText => switch (kind) {
    _Kind.heading => inner.substring(itemHeadingMarker.length),
    _Kind.list => inner.substring(_listMarker.firstMatch(inner)!.end),
    _ => inner.trimLeft(),
  };
}

/// Whether line [i] is a table header, the delimiter row under it.
bool _startsTable(List<_Line> lines, int i) {
  if (i + 1 >= lines.length) return false;
  final line = lines[i];
  final next = lines[i + 1];
  // A header or delimiter row such as `- a | b` or `- | -` starts like a list
  // item, and `markdown` tries the table before the list.
  return line.isTableCandidate &&
      next.isTableCandidate &&
      next.quote == line.quote &&
      startsTable(line.inner, next.inner);
}

/// Adds one span per row below the delimiter row of the table at [i] to
/// [spans] and returns the index of the line after the table.
int _addTableRows(
  List<_Span> spans,
  List<BodyLine> body,
  List<_Line> lines,
  int i,
) {
  var next = i + 2;
  while (next < lines.length &&
      lines[next].kind == _Kind.text &&
      lines[next].quote == lines[i].quote) {
    spans.add((
      item: _itemOf(body, lines, next, next),
      start: next,
      end: next,
      headerAt: i,
    ));
    next++;
  }
  return next;
}

/// Returns the last line of the paragraph or list item that starts at [i].
int _paragraphEnd(List<_Line> lines, int i) {
  var end = i;
  while (end + 1 < lines.length) {
    final next = lines[end + 1];
    if (next.kind != _Kind.text ||
        next.quote != lines[i].quote ||
        _startsTable(lines, end + 1)) {
      break;
    }
    end++;
  }
  return end;
}

/// Returns the last line of the heading at [i], its paragraph included.
int _headingEnd(List<_Line> lines, int i) {
  var next = i + 1;
  while (next < lines.length && lines[next].kind == _Kind.blank) {
    next++;
  }
  final isParagraph =
      next < lines.length &&
      lines[next].kind == _Kind.text &&
      lines[next].quote == lines[i].quote &&
      !_startsTable(lines, next);
  return isParagraph ? _paragraphEnd(lines, next) : i;
}

DocItem _itemOf(List<BodyLine> body, List<_Line> lines, int start, int end) {
  var chars = 0;
  for (var k = start; k <= end; k++) {
    final text = body[k].text;
    chars += text.length - scanText(text).pairs;
    if (k > start) chars += _lineFeedChars;
  }
  return (
    line: body[start].line,
    chars: chars,
    text: lines[start].itemText,
    heading: lines[start].kind == _Kind.heading,
  );
}
