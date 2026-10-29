import 'dart:typed_data';

import 'package:markdown/markdown.dart'
    show
        CodeBlockSyntax,
        FencedCodeBlockSyntax,
        FootnoteDefSyntax,
        HeaderSyntax,
        HorizontalRuleSyntax,
        HtmlBlockSyntax,
        LinkReferenceDefinitionSyntax,
        SetextHeaderSyntax;

/// The inline text of a body and the definitions its links resolve against.
///
/// `text` is the body with every code unit markdown never reads as inline text
/// blanked to a space, line ends and length kept; `leaves` are the inline text
/// ranges in source order; `definitions` maps `linkLabel(label)` to the
/// destination as written, angle brackets dropped, the first definition of a
/// label winning.
typedef LeafText = ({
  String text,
  List<({int start, int end})> leaves,
  Map<String, String> definitions,
});

// The patterns are the ones `markdown` matches its block syntaxes by, so an
// upgrade that changes one changes the scan with it.
final RegExp _htmlStart = const HtmlBlockSyntax().pattern;
final RegExp _setextUnderline = const SetextHeaderSyntax().pattern;
final RegExp _atxHeading = const HeaderSyntax().pattern;
final RegExp _indentedCode = const CodeBlockSyntax().pattern;
final RegExp _fence = const FencedCodeBlockSyntax().pattern;
final RegExp _thematicBreak = const HorizontalRuleSyntax().pattern;
final RegExp _footnote = const FootnoteDefSyntax().pattern;
final RegExp _definitionStart = const LinkReferenceDefinitionSyntax().pattern;

/// `markdown`'s `tablePattern` (`patterns.dart:53`), which `markdown.dart` does
/// not export.
final _tableDelimiter = RegExp(
  r'^[ ]{0,3}\|?([ \t]*:?\-+:?[ \t]*\|[ \t]*)+([ \t]|[ \t]*:?\-+:?[ \t]*)?$',
);

/// `HtmlBlockSyntax`'s end conditions (`html_block_syntax.dart:29-39`), by the
/// start condition they close; null ends the block at the next blank line.
final _htmlEndConditions = <RegExp?>[
  RegExp('</(?:pre|script|style|textarea)>', caseSensitive: false),
  RegExp('-->'),
  RegExp(r'\?>'),
  RegExp('>'),
  RegExp(']]>'),
  null,
  null,
];

final _blankRun = RegExp(r'\s+');
final _hashes = RegExp(r'^#+$');

const _tab = 0x09;
const _lineFeed = 0x0A;
const _verticalTab = 0x0B;
const _formFeed = 0x0C;
const _carriageReturn = 0x0D;
const _space = 0x20;
const _quote = 0x22;
const _apostrophe = 0x27;
const _openParen = 0x28;
const _closeParen = 0x29;
const _colon = 0x3A;
const _lessThan = 0x3C;
const _greaterThan = 0x3E;
const _openBracket = 0x5B;
const _backslash = 0x5C;
const _closeBracket = 0x5D;
const _pipe = 0x7C;

/// Returns the [LeafText] of [lfBody], a doc text with LF line ends.
///
/// The lines are walked once, in the order `markdown` tries its block syntaxes,
/// and only the text it reads as inline text is a leaf: a paragraph or setext
/// heading (the lines up to the block that ends them), an ATX heading's
/// content, and each cell of a table row. Blank lines, fences, HTML blocks,
/// indented code, thematic breaks, setext underlines, table delimiter rows,
/// and each definition (`[label]: dest "title"`, read where a block starts, as
/// `LinkParser.parseDefinition` reads it) are blanked, so an offset in the text
/// is an offset in [lfBody]. Code spans stay: the reader skips them with the
/// other atoms that bind tighter than brackets.
///
/// Every line is visited a fixed number of times: a definition is read forward
/// once, and what it reads is the lines it consumes or the paragraph a failed
/// read leaves behind. A title that finds no closer before the block ends is
/// remembered, so a later definition in the block fails at its opener.
LeafText leafTextOf(String lfBody) {
  final pass = _BlockPass(lfBody.split('\n'))..run();
  final units = Uint16List.fromList(lfBody.codeUnits);
  var kept = 0;
  for (final (:start, :end) in pass.leaves) {
    _blank(units, kept, start);
    kept = end;
  }
  _blank(units, kept, units.length);
  return (
    text: String.fromCharCodes(units),
    leaves: pass.leaves,
    definitions: pass.definitions,
  );
}

/// Blanks [units] from [from] to [to], line ends kept.
void _blank(Uint16List units, int from, int to) {
  for (var i = from; i < to; i++) {
    if (units[i] != _lineFeed) units[i] = _space;
  }
}

/// Returns whether [line] holds nothing but spaces and tabs.
bool _isBlankLine(String line) {
  for (var i = 0; i < line.length; i++) {
    final unit = line.codeUnitAt(i);
    if (unit != _space && unit != _tab) return false;
  }
  return true;
}

/// Returns [text] as a definition label: trimmed, each run of blanks one
/// space, lowercased.
String linkLabel(String text) =>
    text.trim().replaceAll(_blankRun, ' ').toLowerCase();

/// What ends the paragraph a line meets.
enum _Stop {
  /// The line continues the paragraph.
  none,

  /// The line underlines the paragraph as a setext heading.
  setext,

  /// The line starts another block.
  block,
}

/// The walk of the block pass over the lines of a body.
final class _BlockPass {
  new(this._lines)
    : _starts = List.filled(_lines.length, 0),
      _delimiters = List.filled(_lines.length, null),
      _endsBlock = List.filled(_lines.length, null) {
    var offset = 0;
    for (var i = 0; i < _lines.length; i++) {
      _starts[i] = offset;
      offset += _lines[i].length + 1;
    }
  }

  final List<String> _lines;

  /// The body offset of each line.
  final List<int> _starts;

  /// Per line, whether it is a table delimiter row; null until asked.
  final List<bool?> _delimiters;

  /// Per line, whether it ends a block; null until asked.
  final List<bool?> _endsBlock;

  final leaves = <({int start, int end})>[];
  final definitions = <String, String>{};

  /// The first line of the open paragraph, or -1.
  var _paragraph = -1;

  /// Per title closer, the last line of a title read that found no closer
  /// before the block ended. A later title in a line up to it ends at the
  /// same place without the rescan.
  final _noCloser = <int, int>{};

  void run() {
    var i = 0;
    while (i < _lines.length) {
      if (_paragraph >= 0) {
        final stop = _stopAt(i);
        if (stop == _Stop.none) {
          i++;
          continue;
        }
        _closeParagraph(i);
        if (stop == _Stop.setext) {
          i++;
          continue;
        }
      }
      i = _startBlock(i);
    }
    if (_paragraph >= 0) _closeParagraph(_lines.length);
  }

  void _addLeaf(int line, int from, int to) {
    if (from < to) {
      leaves.add((start: _starts[line] + from, end: _starts[line] + to));
    }
  }

  void _closeParagraph(int end) {
    final last = end - 1;
    leaves.add((
      start: _starts[_paragraph],
      end: _starts[last] + _lines[last].length,
    ));
    _paragraph = -1;
  }

  /// Returns what line [i] does to the open paragraph, in the order of
  /// `BlockSyntax.interruptedBy`: a block that can end a paragraph, with the
  /// setext underline between the HTML block and the heading.
  _Stop _stopAt(int i) {
    final line = _lines[i];
    if (_opensFence(line) ||
        _headsTable(i) ||
        _isBlankLine(line) ||
        _endsHtml(line)) {
      return _Stop.block;
    }
    if (_setextUnderline.hasMatch(line)) return _Stop.setext;
    return _atxHeading.hasMatch(line) || _thematicBreak.hasMatch(line)
        ? _Stop.block
        : _Stop.none;
  }

  /// Returns whether line [i] ends a block that is not a paragraph
  /// (`BlockSyntax.isAtBlockEnd`, where no paragraph is open).
  bool _endsBlockAt(int i) => _endsBlock[i] ??= switch (_stopAt(i)) {
    _Stop.block => true,
    _Stop.setext => _thematicBreak.hasMatch(_lines[i]),
    _Stop.none => false,
  };

  bool _opensFence(String line) => _fence.hasMatch(line);

  /// Returns whether an HTML block that starts at [line] can end a paragraph:
  /// only start condition 7 cannot (`HtmlBlockSyntax.canEndBlock`).
  bool _endsHtml(String line) {
    final match = _htmlStart.firstMatch(line);
    return match != null && match.namedGroup('condition_7') == null;
  }

  /// Returns whether line [i] heads a table: the next line is a delimiter row
  /// (`TableSyntax.canParse`).
  bool _headsTable(int i) {
    final next = i + 1;
    if (next >= _lines.length) return false;
    return _delimiters[next] ??= _tableDelimiter.hasMatch(_lines[next]);
  }

  /// Starts the block at line [i], where no paragraph is open, in the order
  /// `markdown` tries its syntaxes, and returns the line after it.
  int _startBlock(int i) {
    final line = _lines[i];
    final fence = _fenceMark(line);
    if (fence != null) return _skipFence(i, fence.marker);
    if (_headsTable(i)) {
      final end = _readTable(i);
      if (end != null) return end;
    }
    if (_isBlankLine(line)) return i + 1;
    if (_htmlStart.hasMatch(line)) return _skipHtml(i);
    if (_atxHeading.hasMatch(line)) {
      _readHeading(i);
      return i + 1;
    }
    if (_indentedCode.hasMatch(line)) return _skipIndentedCode(i);
    if (_thematicBreak.hasMatch(line)) return i + 1;
    if (_definitionStart.hasMatch(line) && !_footnote.hasMatch(line)) {
      final next = _readDefinition(i);
      if (next != null) return next;
    }
    _paragraph = i;
    return i + 1;
  }

  ({String marker, String info})? _fenceMark(String line) {
    final match = _fence.firstMatch(line);
    if (match == null) return null;
    final backtick = match.namedGroup('backtick');
    return backtick == null
        ? (
            marker: match.namedGroup('tilde')!,
            info: match.namedGroup('tildeInfo')!,
          )
        : (marker: backtick, info: match.namedGroup('backtickInfo')!);
  }

  /// Returns the line after the fence that opens at line [i] with [marker]: a
  /// fence of the same marker, at least as long and with no info, closes it
  /// (`FencedCodeBlockSyntax.parseChildLines`).
  int _skipFence(int i, String marker) {
    for (var j = i + 1; j < _lines.length; j++) {
      final close = _fenceMark(_lines[j]);
      if (close != null &&
          close.marker.startsWith(marker) &&
          close.info.trim().isEmpty) {
        return j + 1;
      }
    }
    return _lines.length;
  }

  /// Returns the line after the HTML block that starts at line [i], which
  /// takes in each HTML block that starts on the line right after it
  /// (`HtmlBlockSyntax.parseChildLines`).
  int _skipHtml(int i) {
    var next = _skipHtmlBlock(i);
    while (next < _lines.length && _htmlStart.hasMatch(_lines[next])) {
      next = _skipHtmlBlock(next);
    }
    return next;
  }

  int _skipHtmlBlock(int i) {
    final match = _htmlStart.firstMatch(_lines[i])!;
    var condition = 0;
    while (match.namedGroup('condition_${condition + 1}') == null) {
      condition++;
    }
    final end = _htmlEndConditions[condition];
    if (end == null) {
      var j = i + 1;
      while (j < _lines.length && !_isBlankLine(_lines[j])) {
        j++;
      }
      return j;
    }
    for (var j = i; j < _lines.length; j++) {
      if (end.hasMatch(_lines[j])) return j + 1;
    }
    return _lines.length;
  }

  /// Returns the line after the indented code that starts at line [i]
  /// (`CodeBlockSyntax.parseChildLines`): blank lines belong to it only when
  /// an indented line follows them.
  int _skipIndentedCode(int i) {
    var j = i + 1;
    while (j < _lines.length) {
      if (_isBlankLine(_lines[j])) {
        var next = j + 1;
        while (next < _lines.length && _isBlankLine(_lines[next])) {
          next++;
        }
        if (next == _lines.length || !_indentedCode.hasMatch(_lines[next])) {
          break;
        }
        j = next;
      } else if (_indentedCode.hasMatch(_lines[j])) {
        j++;
      } else {
        break;
      }
    }
    return j;
  }

  /// Adds the content of the ATX heading at line [i] as a leaf
  /// (`HeaderSyntax.parse`).
  void _readHeading(int i) {
    final line = _lines[i];
    final match = _atxHeading.firstMatch(line)!;
    final matched = match[0]!;
    final open = match[1]!;
    final close = match[2];
    final contentStart = matched.indexOf(open) + open.length;
    final contentEnd = close == null ? line.length : matched.lastIndexOf(close);
    if (contentEnd <= contentStart) return;
    final content = line.substring(contentStart, contentEnd);
    final trimmed = content.trim();
    if (close == null && _hashes.hasMatch(trimmed)) return;
    final lead = content.length - content.trimLeft().length;
    _addLeaf(i, contentStart + lead, contentStart + lead + trimmed.length);
  }

  /// Adds the cells of the table headed by line [i] as leaves and returns the
  /// line after it, or null when the head row has more or fewer cells than the
  /// delimiter row has columns (`TableSyntax.parse`).
  int? _readTable(int i) {
    final columns = _columnCount(_lines[i + 1]);
    final head = _cellsOf(_lines[i]);
    if (head.length != columns) return null;
    _addCells(i, head, columns);
    var j = i + 2;
    while (j < _lines.length && !_endsBlockAt(j)) {
      _addCells(j, _cellsOf(_lines[j]), columns);
      j++;
    }
    return j;
  }

  void _addCells(int line, List<({int start, int end})> cells, int columns) {
    for (var c = 0; c < cells.length && c < columns; c++) {
      _addLeaf(line, cells[c].start, cells[c].end);
    }
  }

  /// Returns the number of columns of the delimiter [row]
  /// (`TableSyntax._parseAlignments`).
  int _columnCount(String row) {
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

  /// Returns the line ranges of the cells of the table [row], split at an
  /// unescaped pipe (`TableSyntax._parseRow`).
  List<({int start, int end})> _cellsOf(String row) {
    final cells = <({int start, int end})>[];
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
        index = _pastBlanks(row, index + 1);
        start = index;
        if (index >= row.length) break;
      } else {
        index++;
      }
    }
    return cells;
  }

  int _pastBlanks(String row, int from) {
    var index = from;
    while (index < row.length) {
      final unit = row.codeUnitAt(index);
      if (unit != _space && unit != _tab) break;
      index++;
    }
    return index;
  }

  int _pastOpeningPipe(String row) {
    var index = 0;
    while (index < row.length) {
      final unit = row.codeUnitAt(index);
      if (unit == _pipe) index = _pastBlanks(row, index + 1);
      if (unit != _space && unit != _tab) break;
      index++;
    }
    return index;
  }

  /// Reads the definition that starts at line [first] as
  /// `LinkParser.parseDefinition` does and returns the line after it, or null
  /// when `markdown` reads none and the line starts a paragraph.
  ///
  /// The text it reads is the lines up to the next block end, joined with line
  /// feeds; they are read from the cursor on, so a read costs the lines it
  /// passes.
  int? _readDefinition(int first) {
    final cursor = _Cursor(_lines, _endsBlockAt, first)
      ..skipBlanks(lineFeeds: true);
    if (cursor.unit != _openBracket || !cursor.hasUnitAfter) return null;
    cursor.advance();
    final labelStart = cursor.mark;
    var budget = 999;
    while (true) {
      if (budget-- < 0) return null;
      final unit = cursor.unit;
      if (unit == _backslash) {
        cursor.advance();
      } else if (unit == _openBracket) {
        return null;
      } else if (unit == _closeBracket) {
        break;
      }
      cursor.advance();
      if (cursor.isDone) return null;
    }
    final label = cursor.textFrom(labelStart);
    if (label.trim().isEmpty) return null;
    cursor.advance();
    if (cursor.isDone || cursor.unit != _colon) return null;
    cursor
      ..advance()
      ..skipBlanks(lineFeeds: true);
    if (cursor.isDone) return null;
    final String destination;
    if (cursor.unit == _lessThan) {
      cursor.advance();
      final start = cursor.mark;
      while (true) {
        final unit = cursor.unit;
        if (unit == _backslash) {
          cursor.advance();
        } else if (unit == _lineFeed ||
            unit == _carriageReturn ||
            unit == _formFeed) {
          return null;
        } else if (unit == _greaterThan) {
          break;
        }
        cursor.advance();
        if (cursor.isDone) return null;
      }
      destination = cursor.textFrom(start);
      cursor.advance();
    } else {
      final start = cursor.mark;
      var parens = 0;
      while (true) {
        final unit = cursor.unit;
        if (unit == _backslash) {
          cursor.advance();
        } else if (unit == _space ||
            unit == _lineFeed ||
            unit == _carriageReturn ||
            unit == _formFeed) {
          break;
        } else if (unit == _openParen) {
          parens++;
        } else if (unit == _closeParen) {
          parens--;
          if (parens == 0) {
            cursor.advance();
            break;
          }
        }
        cursor.advance();
        if (cursor.isDone) break;
      }
      destination = cursor.textFrom(start);
    }
    var blanks = cursor.skipBlanks();
    if (!cursor.isDone) {
      final multiline = cursor.unit == _lineFeed;
      blanks += cursor.skipBlanks(lineFeeds: true);
      if (!cursor.isDone) {
        if (blanks == 0) return null;
        final hasTitle = _skipTitle(cursor);
        if (!hasTitle && !multiline) return null;
        if (hasTitle) {
          cursor.skipBlanks();
          if (!cursor.isDone && cursor.unit != _lineFeed && !multiline) {
            return null;
          }
        }
      }
    }
    final next = cursor.isRestBlank ? cursor.line + 1 : cursor.line;
    if (next <= first) return null;
    definitions.putIfAbsent(linkLabel(label), () => destination);
    return next;
  }

  /// Skips the title at the cursor and returns whether there is one
  /// (`LinkParser._parseTitle`).
  bool _skipTitle(_Cursor cursor) {
    final opener = cursor.unit;
    if (opener != _quote && opener != _apostrophe && opener != _openParen) {
      return false;
    }
    final closer = opener == _openParen ? _closeParen : opener;
    cursor.advance();
    if (cursor.isDone) return false;
    final failedTo = _noCloser[closer];
    if (failedTo != null && failedTo >= cursor.line) {
      cursor.moveToEnd(failedTo);
      return false;
    }
    while (true) {
      final unit = cursor.unit;
      if (unit == _backslash) {
        cursor.advance();
      } else if (unit == closer) {
        break;
      }
      cursor.advance();
      if (cursor.isDone) {
        _noCloser[closer] = cursor.line;
        return false;
      }
    }
    cursor.advance();
    return true;
  }
}

/// A reading position in the lines of a definition, which are the lines from
/// its first one up to the next block end, joined with line feeds.
///
/// The cursor holds a line and a column; the column at a line's length is the
/// line feed that joins it to the next line. The next line joins the text when
/// the cursor first needs it, so a read costs only the lines it passes.
final class _Cursor {
  new(this._lines, this._endsBlock, this.line) : _joined = line;

  final List<String> _lines;
  final bool Function(int line) _endsBlock;

  int line;
  int col = 0;

  /// The last line that joined the text.
  int _joined;

  /// The line that ended the text, or -1 while none is known.
  var _stop = -1;

  bool get _hasNextLine {
    final next = line + 1;
    if (next <= _joined) return true;
    if (next >= _lines.length || next == _stop) return false;
    if (_endsBlock(next)) {
      _stop = next;
      return false;
    }
    _joined = next;
    return true;
  }

  /// The code unit at the cursor, or -1 at the end of the text.
  int get unit {
    final text = _lines[line];
    if (col < text.length) return text.codeUnitAt(col);
    return _hasNextLine ? _lineFeed : -1;
  }

  bool get isDone => col >= _lines[line].length && !_hasNextLine;

  /// Whether a code unit follows the one at the cursor.
  bool get hasUnitAfter => col + 1 < _lines[line].length || _hasNextLine;

  /// Whether the rest of the cursor's line holds nothing but whitespace.
  bool get isRestBlank => _lines[line].substring(col).trim().isEmpty;

  (int, int) get mark => (line, col);

  void advance() {
    if (col < _lines[line].length) {
      col++;
    } else if (_hasNextLine) {
      line++;
      col = 0;
    }
  }

  /// Moves to the end of the text, which ends on [lastLine].
  void moveToEnd(int lastLine) {
    line = lastLine;
    col = _lines[lastLine].length;
    _joined = lastLine;
    _stop = lastLine + 1 < _lines.length ? lastLine + 1 : -1;
  }

  /// Moves past the whitespace `LinkParser.moveThroughWhitespace` skips, line
  /// feeds only when [lineFeeds], and returns how many code units it passed.
  int skipBlanks({bool lineFeeds = false}) {
    var count = 0;
    while (!isDone) {
      final current = unit;
      if (current != _space &&
          current != _tab &&
          current != _verticalTab &&
          current != _carriageReturn &&
          current != _formFeed &&
          !(lineFeeds && current == _lineFeed)) {
        break;
      }
      count++;
      advance();
    }
    return count;
  }

  /// Returns the text from [start] to the cursor.
  String textFrom((int, int) start) {
    final (startLine, startCol) = start;
    if (startLine == line) return _lines[line].substring(startCol, col);
    final text = StringBuffer(_lines[startLine].substring(startCol));
    for (var i = startLine + 1; i < line; i++) {
      text
        ..write('\n')
        ..write(_lines[i]);
    }
    text
      ..write('\n')
      ..write(_lines[line].substring(0, col));
    return text.toString();
  }
}
