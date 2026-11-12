import 'package:markdown/markdown.dart' show HeaderSyntax;

// The pattern is the one `markdown` matches its ATX headings by, so an upgrade
// that changes it changes every reader with it.
final RegExp _atxHeading = const HeaderSyntax().pattern;

const _space = 0x20;
const _tab = 0x09;
const _pipe = 0x7C;
const _dash = 0x2D;
const _colon = 0x3A;
const _backslash = 0x5C;

/// The most spaces `markdown` lets precede the leading pipe of a table row.
const _maxIndent = 3;

/// The opening of an item heading, a level 3 ATX heading.
const itemHeadingMarker = '### ';

final RegExp _thematicBreak = RegExp(r'^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$');

/// An ATX heading line: its level, 1 to 6, and its text without the marks.
typedef AtxHeading = ({int level, String text});

/// Returns the heading [line] is, or null when it is no ATX heading.
///
/// The text has no opening `#` run and no closing one, and is trimmed.
AtxHeading? atxHeadingOf(String line) {
  final match = _atxHeading.firstMatch(line);
  if (match == null) return null;
  final marks = match.group(1)!;
  final closing = match.group(2);
  var text = line.substring(line.indexOf(marks) + marks.length).trim();
  if (closing != null) {
    text = text.substring(0, text.length - closing.length).trimRight();
  } else if (text.isNotEmpty && text.replaceAll('#', '').isEmpty) {
    text = ''; // a lone closing run, as in `### ###`
  }
  return (level: marks.length, text: text);
}

/// Whether [line] is a table delimiter row, such as `|---|:-:|`.
///
/// It reads what `markdown`'s `tablePattern` (`patterns.dart`, not exported)
/// matches, so every reader agrees with the renderer on what a table is: up to
/// 3 spaces, an optional pipe, then cells of hyphens with an optional colon
/// at each end, each closed by a pipe, the last one needing none. A one-column
/// row such as `|---` is no delimiter row. The pattern backtracks on a
/// failing row with spaces around many pipes, so this reads the line once,
/// left to right.
bool isTableDelimiterRow(String line) {
  var at = 0;
  while (at < line.length && line.codeUnitAt(at) == _space) {
    at++;
  }
  final hasLeadingPipe =
      at <= _maxIndent && at < line.length && line.codeUnitAt(at) == _pipe;
  at = hasLeadingPipe ? at + 1 : 0;
  var pipes = 0;
  while (true) {
    at = _skipBlanks(line, at);
    at = _skipDelimiterCell(line, at);
    if (at < 0) return false;
    at = _skipBlanks(line, at);
    if (at == line.length) return pipes > 0;
    if (line.codeUnitAt(at) != _pipe) return false;
    pipes++;
    at = _skipBlanks(line, at + 1);
    if (at == line.length) return true;
  }
}

/// Returns the index after the blanks that start at [from].
int _skipBlanks(String line, int from) {
  var at = from;
  while (at < line.length) {
    final unit = line.codeUnitAt(at);
    if (unit != _space && unit != _tab) break;
    at++;
  }
  return at;
}

/// Returns the index after the cell of hyphens, `:-:` for one, that starts at
/// [from], or -1 when none does.
int _skipDelimiterCell(String line, int from) {
  var at = from;
  if (at < line.length && line.codeUnitAt(at) == _colon) at++;
  final start = at;
  while (at < line.length && line.codeUnitAt(at) == _dash) {
    at++;
  }
  if (at == start) return -1;
  if (at < line.length && line.codeUnitAt(at) == _colon) at++;
  return at;
}

/// Whether [line] is a thematic break, such as `---`, `* * *`, or `___`.
bool isThematicBreak(String line) => _thematicBreak.hasMatch(line);

/// The range of one table cell in its row: `start` to `end`, the cell's text
/// without the blanks after it.
typedef CellRange = ({int start, int end});

/// Returns the cells of [header] when it opens a table with [delimiter] below
/// it, else null.
///
/// It follows `markdown`'s `TableSyntax`: [delimiter] is a delimiter row, and
/// [header] has as many cells as [delimiter] has columns; the edge pipes of
/// either are optional. Both are non-blank text with their block quote marks
/// stripped.
List<CellRange>? tableHeadCells(String header, String delimiter) {
  if (!isTableDelimiterRow(delimiter)) return null;
  final cells = tableCellRanges(header);
  return cells.length == tableColumnCount(delimiter) ? cells : null;
}

/// Whether the line [header] with [delimiter] below it opens a table; see
/// [tableHeadCells].
bool startsTable(String header, String delimiter) =>
    tableHeadCells(header, delimiter) != null;

/// Returns the number of columns of the delimiter [row]
/// (`TableSyntax._parseAlignments`).
int tableColumnCount(String row) {
  var columns = 0;
  var started = false;
  var hitDash = false;
  for (var i = 0; i < row.length; i++) {
    final unit = row.codeUnitAt(i);
    if (unit == _space || unit == _tab || (!started && unit == _pipe)) {
      continue;
    }
    started = true;
    if (unit == _pipe) {
      columns++;
      hitDash = false;
    } else {
      hitDash = true;
    }
  }
  return hitDash ? columns + 1 : columns;
}

/// Returns the ranges of the cells of the table [row], split at an unescaped
/// pipe (`TableSyntax._parseRow`).
List<CellRange> tableCellRanges(String row) {
  final cells = <CellRange>[];
  void add(int start, int end) {
    cells.add((
      start: start,
      end: start + row.substring(start, end).trimRight().length,
    ));
  }

  var index = _pastOpeningPipe(row);
  var start = index;
  while (true) {
    if (index >= row.length) {
      add(start, row.length);
      break;
    }
    final unit = row.codeUnitAt(index);
    if (unit == _backslash) {
      if (index == row.length - 1) {
        add(start, row.length);
        break;
      }
      index += 2;
    } else if (unit == _pipe) {
      add(start, index);
      index = _skipBlanks(row, index + 1);
      start = index;
      if (index >= row.length) break;
    } else {
      index++;
    }
  }
  return cells;
}

int _pastOpeningPipe(String row) {
  var index = 0;
  while (index < row.length) {
    final unit = row.codeUnitAt(index);
    if (unit == _pipe) index = _skipBlanks(row, index + 1);
    if (unit != _space && unit != _tab) break;
    index++;
  }
  return index;
}
