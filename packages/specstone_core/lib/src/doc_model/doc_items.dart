import 'package:specstone_core/src/doc_model/body_line.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show isThematicBreak, itemHeadingMarker, startsTable;
import 'package:specstone_core/src/doc_model/text_scan.dart';

const _lineFeedChars = 1;

final _quotePrefix = RegExp('^ {0,3}> ?');
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
List<DocItem> itemsOf(List<BodyLine> body) {
  final lines = [for (final line in body) _Line.of(line)];
  final items = <DocItem>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.kind == _Kind.text && _startsTable(lines, i)) {
      i = _addTableRows(items, body, lines, i);
    } else if (line.kind == _Kind.blank ||
        line.kind == _Kind.fence ||
        line.kind == _Kind.rule) {
      i++;
    } else {
      final end = line.kind == _Kind.heading
          ? _headingEnd(lines, i)
          : _paragraphEnd(lines, i);
      items.add(_itemOf(body, lines, i, end));
      i = end + 1;
    }
  }
  return items;
}

enum _Kind { blank, fence, rule, heading, list, text }

/// One body line split into its blockquote depth and the text after it.
final class _Line {
  const new(this.kind, this.quote, this.inner);

  factory of(BodyLine line) {
    var inner = line.text;
    var quote = 0;
    for (
      var mark = _quotePrefix.firstMatch(inner);
      mark != null;
      mark = _quotePrefix.firstMatch(inner)
    ) {
      inner = inner.substring(mark.end);
      quote++;
    }
    return _Line(_kindOf(line, inner), quote, inner);
  }

  static _Kind _kindOf(BodyLine line, String inner) {
    if (line.fenced) return _Kind.fence;
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
  final next = lines[i + 1];
  // A delimiter row such as `- | -` starts like a list item, and `markdown`
  // tries the table before the list.
  return (next.kind == _Kind.text || next.kind == _Kind.list) &&
      next.quote == lines[i].quote &&
      startsTable(lines[i].inner, next.inner);
}

/// Adds one item per row below the delimiter row of the table at [i] to
/// [items] and returns the index of the line after the table.
int _addTableRows(
  List<DocItem> items,
  List<BodyLine> body,
  List<_Line> lines,
  int i,
) {
  var next = i + 2;
  while (next < lines.length &&
      lines[next].kind == _Kind.text &&
      lines[next].quote == lines[i].quote) {
    items.add(_itemOf(body, lines, next, next));
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
