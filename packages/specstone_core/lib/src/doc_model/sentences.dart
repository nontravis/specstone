import 'package:specstone_core/src/doc_model/doc.dart' show Doc, blockScan;
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show atxHeadingOf, isTableDelimiterRow, isThematicBreak, startsTable;

const _space = 0x20;
const _terminators = {0x2E, 0x3F, 0x21}; // . ? !

/// The first heading level a sentence is read from; `#` and `##` are the title
/// and the section headers.
const _firstTextHeadingLevel = 3;

final _quotePrefix = RegExp(r'^[ \t]*>[ \t]?');
final _listMarker = RegExp(r'^[ \t]*(?:[-+*]|\d{1,9}[.)])(?:[ \t]+|$)');
final _tableRow = RegExp(r'^ {0,3}\|');
final _unescapedPipe = RegExp(r'(?<!\\)\|');

const _tab = 0x09;
const _lineFeed = 0x0A;
const _carriageReturn = 0x0D;
const _lineSeparator = 0x2028;
const _paragraphSeparator = 0x2029;
const _quoteMark = 0x3E;
const _maxMarkerDigits = 9;

/// Whether [unit] is whitespace as the regex `\s` reads it: the ECMAScript set,
/// which holds the no-break space and the byte order mark.
bool _isWhitespace(int unit) =>
    unit == _space ||
    (unit >= _tab && unit <= _carriageReturn) ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200A) ||
    unit == _lineSeparator ||
    unit == _paragraphSeparator ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000 ||
    unit == 0xFEFF;

/// Returns each of [text]'s runs of whitespace as one space.
///
/// Both sides of "holds" are read in this form: a sentence and the text it is
/// looked for in.
String collapseWhitespace(String text) {
  StringBuffer? out;
  var copied = 0;
  var i = 0;
  while (i < text.length) {
    if (!_isWhitespace(text.codeUnitAt(i))) {
      i++;
      continue;
    }
    var end = i + 1;
    while (end < text.length && _isWhitespace(text.codeUnitAt(end))) {
      end++;
    }
    if (end - i > 1 || text.codeUnitAt(i) != _space) {
      (out ??= StringBuffer())
        ..write(text.substring(copied, i))
        ..writeCharCode(_space);
      copied = end;
    }
    i = end;
  }
  if (out == null) return text;
  return (out..write(text.substring(copied))).toString();
}

/// Returns [lfText] as the text a sentence is looked for in: its block quote
/// marks stripped, then [collapseWhitespace].
///
/// A sentence of a block quote wrapped over `>` lines is read without those
/// marks, so the text it is held in is read without them too. A `>` inside a
/// line stays.
String heldTextOf(String lfText) =>
    collapseWhitespace(_withoutOpeningQuoteMarks(lfText));

/// Returns [text] without the `>` marks, and the blank after each, that sit in
/// the quote marks and list markers a line opens with.
///
/// A line starts at the text's start and after a line feed, a carriage return,
/// or a line or paragraph separator.
String _withoutOpeningQuoteMarks(String text) {
  if (!text.contains('>')) return text;
  final out = StringBuffer();
  var copied = 0;
  var at = 0;
  while (at < text.length) {
    final openingEnd = _skipOpening(text, at, (mark, blankEnd) {
      out.write(text.substring(copied, mark));
      copied = blankEnd;
    });
    at = _nextLineStart(text, openingEnd);
  }
  return (out..write(text.substring(copied))).toString();
}

/// Reads the opening of the line that starts at [start], calling [onQuote]
/// with the index of each `>` and the index after the blank that follows it;
/// returns the index after the opening, [start] when the line has none.
///
/// An opening is one or more of: blanks then a `>` and at most one blank, or
/// blanks then a list marker and at least one blank.
int _skipOpening(
  String text,
  int start,
  void Function(int mark, int blankEnd) onQuote,
) {
  var end = start;
  while (true) {
    final markAt = _skipBlanks(text, end);
    if (markAt >= text.length) return end;
    if (text.codeUnitAt(markAt) == _quoteMark) {
      final afterMark = markAt + 1;
      final blankEnd = afterMark < text.length && _isBlank(text, afterMark)
          ? afterMark + 1
          : afterMark;
      onQuote(markAt, blankEnd);
      end = blankEnd;
      continue;
    }
    final afterMarker = _afterListMarker(text, markAt);
    if (afterMarker == null) return end;
    final afterBlanks = _skipBlanks(text, afterMarker);
    if (afterBlanks == afterMarker) return end;
    end = afterBlanks;
  }
}

bool _isBlank(String text, int at) {
  final unit = text.codeUnitAt(at);
  return unit == _space || unit == _tab;
}

int _skipBlanks(String text, int from) {
  var at = from;
  while (at < text.length && _isBlank(text, at)) {
    at++;
  }
  return at;
}

/// Returns the index after the list marker at [at], `-`, `+`, `*`, or one to
/// nine digits then `.` or `)`; null when none starts there.
int? _afterListMarker(String text, int at) {
  final unit = text.codeUnitAt(at);
  if (unit == 0x2D || unit == 0x2B || unit == 0x2A) return at + 1;
  var digits = 0;
  while (at + digits < text.length &&
      text.codeUnitAt(at + digits) >= 0x30 &&
      text.codeUnitAt(at + digits) <= 0x39) {
    digits++;
  }
  if (digits == 0 || digits > _maxMarkerDigits) return null;
  final end = at + digits;
  if (end >= text.length) return null;
  final terminator = text.codeUnitAt(end);
  return terminator == 0x2E || terminator == 0x29 ? end + 1 : null;
}

/// Returns the index where the next line starts after [from], or the text's
/// length when none does.
int _nextLineStart(String text, int from) {
  for (var i = from; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == _lineFeed ||
        unit == _carriageReturn ||
        unit == _lineSeparator ||
        unit == _paragraphSeparator) {
      return i + 1;
    }
  }
  return text.length;
}

/// Returns the sentences of [lfText], a doc's LF text, whitespace collapsed.
///
/// They come from paragraphs, list items, table cells, and `###` or deeper
/// headings, outside the frontmatter, the title, the `##` headers, and fenced
/// code. Inline markup stays, so each sentence occurs in `heldTextOf` of any
/// doc that holds it.
List<String> sentencesOf(String lfText) {
  final lines = _linesOf(Doc.parse(lfText).afterFrontmatter);
  final scan = blockScan(lines);
  final reader = _BlockReader();
  String? textAt(int i) => i < lines.length && !scan.fenced[i]
      ? _withoutContainers(lines[i], scan.continuesParagraph[i])
      : null;
  for (var i = 0; i < lines.length; i++) {
    if (scan.fenced[i]) {
      reader.close();
    } else {
      reader.read(
        textAt(i),
        below: textAt(i + 1),
        continuesParagraph: scan.continuesParagraph[i],
      );
    }
  }
  reader.close();
  return [for (final block in reader.blocks) ..._cut(block)];
}

List<String> _linesOf(String lfText) {
  final lines = lfText.isEmpty ? <String>[] : lfText.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// Collects the text blocks of a doc, line by line.
final class _BlockReader {
  /// The blocks closed so far, in doc order.
  final blocks = <String>[];

  final _open = <String>[];

  /// Whether the rows being read belong to a table whose header had no edge
  /// pipe.
  var _inTable = false;

  /// Ends the open block and any table: every other block starts anew.
  void close() {
    _closeBlock();
    _inTable = false;
  }

  void _closeBlock() {
    if (_open.isEmpty) return;
    blocks.add(_open.join(' '));
    _open.clear();
  }

  /// Reads [text], a line without its containers or null for a thematic
  /// break, with [below] the next line's text.
  void read(
    String? text, {
    required String? below,
    required bool continuesParagraph,
  }) {
    if (text == null || text.trim().isEmpty) return close();
    final heading = atxHeadingOf(text);
    if (heading != null) {
      close();
      if (heading.level >= _firstTextHeadingLevel) _add(heading.text);
      return;
    }
    if (_tableRow.hasMatch(text) || _inTable) {
      _closeBlock();
      return _readTableRow(text);
    }
    if (below != null && startsTable(text, below)) {
      _closeBlock();
      _inTable = true;
      return _readTableRow(text);
    }
    if (!continuesParagraph) close();
    _open.add(text.trim());
  }

  void _add(String block) {
    if (block.trim().isNotEmpty) blocks.add(block.trim());
  }

  void _readTableRow(String row) {
    if (isTableDelimiterRow(row)) return;
    _trimPipes(row).split(_unescapedPipe).forEach(_add);
  }
}

String _trimPipes(String row) {
  var text = row.trim();
  if (text.startsWith('|')) text = text.substring(1);
  if (text.endsWith('|') && !text.endsWith(r'\|')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// Returns [line] past the block quote marks it opens with, and past its list
/// marker unless it continues a paragraph, or null for a thematic break.
String? _withoutContainers(String line, bool continuesParagraph) {
  var text = line;
  while (true) {
    if (isThematicBreak(text)) return null;
    final prefix =
        _quotePrefix.matchAsPrefix(text) ??
        (continuesParagraph ? null : _listMarker.matchAsPrefix(text));
    if (prefix == null) return text;
    text = text.substring(prefix.end);
  }
}

/// Returns the sentences of [block], cut after each `.`, `?`, or `!` a space or
/// the end of the block follows.
List<String> _cut(String block) {
  final text = collapseWhitespace(block).trim();
  final sentences = <String>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    if (!_terminators.contains(text.codeUnitAt(i))) continue;
    final end = i + 1;
    if (end < text.length && text.codeUnitAt(end) != _space) continue;
    sentences.add(text.substring(start, end).trim());
    start = end;
  }
  sentences.add(text.substring(start).trim());
  return [
    for (final sentence in sentences)
      if (sentence.isNotEmpty) sentence,
  ];
}
