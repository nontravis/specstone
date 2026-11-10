import 'package:markdown/markdown.dart' show HeaderSyntax;

// The pattern is the one `markdown` matches its ATX headings by, so an upgrade
// that changes it changes every reader with it.
final RegExp _atxHeading = const HeaderSyntax().pattern;

const _space = 0x20;
const _tab = 0x09;
const _pipe = 0x7C;
const _dash = 0x2D;
const _colon = 0x3A;

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

/// Whether the line [header] with [delimiter] below it opens a table.
///
/// Both hold a pipe and [delimiter] is a delimiter row; the edge pipes are
/// optional, as in `markdown`. Both are text with their block quote marks
/// stripped.
bool startsTable(String header, String delimiter) =>
    header.contains('|') &&
    delimiter.contains('|') &&
    isTableDelimiterRow(delimiter);
