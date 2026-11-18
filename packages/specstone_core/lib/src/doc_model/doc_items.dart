import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show
        isThematicBreak,
        itemHeadingMarker,
        startsTable,
        tableCellRanges,
        tableHeadCells;
import 'package:specstone_core/src/doc_model/models/body_line.dart';
import 'package:specstone_core/src/doc_model/models/doc_item.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:specstone_core/src/doc_model/text_scan.dart';

const _lineFeedChars = 1;

/// A `###` with no text, which `atxHeadingOf` reads as an empty heading.
const _bareHeading = '###';
const _quoteMark = 0x3E;
const _space = 0x20;
const _maxMarkIndent = 3;
final _listMarker = RegExp(r'^\s*(?:[-*+]|\d+[.)])(?:\s+|$)');

/// Whether [line], unfenced, opens a heading item as [sectionItemsOf] reads
/// it: after any `>` marks, a `### ` heading or a bare `###`.
///
/// The one line that ends a heading item's `###` block, for every reader.
bool opensHeadingItem(String line) => headingItemTextOf(line) != null;

/// Returns the text of the heading item [line], unfenced, opens, as
/// [sectionItemsOf] reads it after any `>` marks and the `### `; null when it
/// opens none.
///
/// The one reader every caller names a heading item from.
String? headingItemTextOf(String line) {
  final read = _Line.of(BodyLine(text: line, line: 0, fenced: false));
  return read.kind == _Kind.heading ? read.itemText : null;
}

/// Returns the items of a section's [body] lines in order.
///
/// An item is a list item without its nested items, a nested item alone, a
/// table row below the delimiter row, a paragraph, or a `###` heading with
/// the paragraph right under it and never its bullets, inside a blockquote
/// as anywhere else. A quoted paragraph right under a heading, at the
/// heading's quote depth or deeper, is that paragraph. A fenced code block, a
/// thematic break, and a table's header and delimiter rows are no item; a
/// fenced line belongs to no item. A list item ends at a blank line or a
/// fence, and the text after it is its own item. A line scan, no markdown
/// parse.
List<SectionItem> sectionItemsOf(List<BodyLine> body) {
  final lines = _linesOf(body);
  final headers = <int, List<String>>{};
  final items = <SectionItem>[];
  for (final span in _spansOf(body, lines)) {
    final first = lines[span.start];
    final kind = switch (span.item.heading) {
      true => SectionItemKind.heading,
      false when span.headerAt != null => SectionItemKind.tableRow,
      false when first.kind == _Kind.list => SectionItemKind.listItem,
      _ => SectionItemKind.paragraph,
    };
    final headerAt = span.headerAt;
    items.add(
      SectionItem(
        line: span.item.line,
        kind: kind,
        nested:
            kind != SectionItemKind.tableRow &&
            first.inner.startsWith(RegExp(r'\s')),
        head: span.item.text,
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
      ),
    );
  }
  return items;
}

List<String> _cellTexts(String row, List<TextRange> ranges) => [
  for (final cell in ranges) row.substring(cell.start, cell.end).trim(),
];

List<_Line> _linesOf(List<BodyLine> body) => [
  for (final line in body) _Line.of(line),
];

/// One item's place in the body lines: its first and last line index, and the
/// index of its table's header line when it is a table row.
final class _ItemSpan {
  const new({
    required this.item,
    required this.start,
    required this.end,
    required this.headerAt,
  });

  final DocItem item;
  final int start;
  final int end;
  final int? headerAt;
}

List<_ItemSpan> _spansOf(List<BodyLine> body, List<_Line> lines) {
  final spans = <_ItemSpan>[];
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
      spans.add(
        _ItemSpan(
          item: _itemOf(body, lines, i, end),
          start: i,
          end: end,
          headerAt: null,
        ),
      );
      i = end + 1;
    }
  }
  return spans;
}

/// Returns the index after the header, the delimiter row, and the first
/// [rows] body rows of the first table of [body], read as [sectionItemsOf]
/// reads a table, or null when none starts.
int? firstTableOf(List<BodyLine> body, int rows) {
  final lines = _linesOf(body);
  for (var at = 0; at < lines.length; at++) {
    if (!_startsTable(lines, at)) continue;
    var end = at + 2;
    while (end < at + 2 + rows &&
        end < lines.length &&
        lines[end].kind == _Kind.text &&
        lines[end].quote == lines[at].quote) {
      end++;
    }
    return end;
  }
  return null;
}

enum _Kind { blank, fence, rule, heading, list, text }

/// The count of `>` marks at the start of a line, and the index after the last.
final class _QuoteMarks {
  const new({required this.quote, required this.end});

  final int quote;
  final int end;
}

/// One body line split into its blockquote depth and the text after it.
final class _Line {
  const new(this.kind, this.quote, this.inner);

  /// Reads [line]; a fenced line is code, so it holds no `>` mark.
  factory of(BodyLine line) {
    if (line.fenced) return _Line(_Kind.fence, 0, line.text);
    final _QuoteMarks(:quote, :end) = _quoteMarksOf(line.text);
    final inner = end == 0 ? line.text : line.text.substring(end);
    return _Line(_kindOf(inner), quote, inner);
  }

  /// Returns the count of `>` marks at the start of [text], each after up to
  /// 3 spaces and before one optional space, and the index after the last.
  static _QuoteMarks _quoteMarksOf(String text) {
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
    return _QuoteMarks(quote: quote, end: end);
  }

  static _Kind _kindOf(String inner) {
    if (inner.trim().isEmpty) return _Kind.blank;
    if (isThematicBreak(inner)) return _Kind.rule;
    if (inner.startsWith(itemHeadingMarker) || inner == _bareHeading) {
      return _Kind.heading;
    }
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
    _Kind.heading =>
      inner.length < itemHeadingMarker.length
          ? ''
          : inner.substring(itemHeadingMarker.length),
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
  List<_ItemSpan> spans,
  List<BodyLine> body,
  List<_Line> lines,
  int i,
) {
  var next = i + 2;
  while (next < lines.length &&
      lines[next].kind == _Kind.text &&
      lines[next].quote == lines[i].quote) {
    spans.add(
      _ItemSpan(
        item: _itemOf(body, lines, next, next),
        start: next,
        end: next,
        headerAt: i,
      ),
    );
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
      lines[next].quote >= lines[i].quote &&
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
  return DocItem(
    line: body[start].line,
    chars: chars,
    text: lines[start].itemText,
    heading: lines[start].kind == _Kind.heading,
  );
}
