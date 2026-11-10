import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show startsTable;
import 'package:specstone_core/src/rendering/generated_blocks.dart';

const _hardBreakSuffix = '  ';

const _tab = 0x09;
const _lineFeed = 0x0A;
const _space = 0x20;
const _hash = 0x23;
const _closeParen = 0x29;
const _star = 0x2A;
const _plus = 0x2B;
const _dash = 0x2D;
const _dot = 0x2E;
const _digitZero = 0x30;
const _digitNine = 0x39;
const _quoteMarker = 0x3E;

/// The most spaces before a heading's `#` run.
const _maxHeadingIndent = 3;
const _maxHeadingLevel = 6;
const _maxOrderedDigits = 9;

/// Returns [text] with its layout whitespace normalized (rendering INV-32).
///
/// [text] is LF markdown with no frontmatter. Lines inside a fenced code block
/// or a closed generated block of [blockKinds] stay as written. With
/// [underHeading], the line above [text] is a heading line.
String layOutText(
  String text, {
  bool underHeading = false,
  Set<String> blockKinds = const {},
}) {
  if (_isBlankText(text)) return '';
  final hasFinalBreak = text.endsWith('\n');
  final lines = text.split('\n');
  if (hasFinalBreak) lines.removeLast();
  final scan = blockScan(lines);
  final laid = _Layout(
    lines,
    fenced: scan.fenced,
    continues: scan.continuesParagraph,
    blockKinds: blockKinds,
  );
  final out = _insertHeadingGaps(laid.normalized(), laid, underHeading);
  return out.join('\n') + (hasFinalBreak ? '\n' : '');
}

/// Per-line facts of a text that the layout rules read.
final class _Layout {
  new(
    this.lines, {
    required List<bool> fenced,
    required this.continues,
    required Set<String> blockKinds,
  }) : protected = _protectedLines(lines, fenced, blockKinds),
       isTable = List.filled(lines.length, false),
       isDelimiter = List.filled(lines.length, false) {
    _markTables();
  }

  final List<String> lines;

  /// Per line, whether it is the next line of the paragraph above it (GFM).
  final List<bool> continues;
  final List<bool> protected;
  final List<bool> isTable;
  final List<bool> isDelimiter;

  bool isBlank(int i) => !protected[i] && _isBlankLine(lines[i]);

  bool isHeading(int i) => !protected[i] && _isHeadingLine(lines[i]);

  /// Lines with every rule except heading gaps applied.
  List<String> normalized() => [
    for (var i = 0; i < lines.length; i++) _normalizeLine(i),
  ];

  String _normalizeLine(int i) {
    if (protected[i]) return lines[i];
    if (isTable[i]) return _layOutRow(lines[i], isDelimiter: isDelimiter[i]);
    final trimmed = _trimEnd(lines[i]);
    return _isHardBreak(i) ? '$trimmed$_hardBreakSuffix' : trimmed;
  }

  bool _isHardBreak(int i) =>
      lines[i].endsWith(_hardBreakSuffix) &&
      i + 1 < lines.length &&
      _continuesParagraph(i + 1);

  /// Whether line [i] is the next line of the paragraph above it, neither a
  /// table row nor a generated block line.
  bool _continuesParagraph(int i) =>
      continues[i] && !protected[i] && !isTable[i];

  void _markTables() {
    var i = 0;
    while (i + 1 < lines.length) {
      if (!_startsTable(i)) {
        i++;
        continue;
      }
      isTable[i] = isTable[i + 1] = isDelimiter[i + 1] = true;
      i += 2;
      while (i < lines.length && _isRowLine(i)) {
        isTable[i++] = true;
      }
    }
  }

  // The delimiter row may start like a list item, as `- | -` does; `markdown`
  // tries the table before the list.
  bool _startsTable(int i) =>
      _isRowLine(i) && !protected[i + 1] && startsTable(lines[i], lines[i + 1]);

  bool _isRowLine(int i) =>
      !protected[i] &&
      !isBlank(i) &&
      !isHeading(i) &&
      !_isQuote(lines[i]) &&
      !_isListItemLine(lines[i]);
}

List<bool> _protectedLines(
  List<String> lines,
  List<bool> fenced,
  Set<String> blockKinds,
) {
  final blocks = generatedBlockLines(lines, blockKinds);
  return [for (var i = 0; i < lines.length; i++) fenced[i] || blocks[i]];
}

/// Puts exactly one blank line between each heading and the next text line.
List<String> _insertHeadingGaps(
  List<String> lines,
  _Layout laid,
  bool underHeading,
) {
  final out = <String>[];
  var needsGap = underHeading;
  var i = 0;
  while (i < lines.length) {
    if (needsGap && laid.isBlank(i)) {
      final start = i;
      while (i < lines.length && laid.isBlank(i)) {
        i++;
      }
      if (i < lines.length) {
        out.add('');
      } else {
        out.addAll(lines.sublist(start));
      }
      needsGap = false;
      continue;
    }
    if (needsGap) out.add('');
    needsGap = laid.isHeading(i);
    out.add(lines[i++]);
  }
  return out;
}

/// Writes one table row with 1 space inside each cell edge.
///
/// Outer pipes stay as the row has them; a delimiter cell becomes `---` with
/// its `:` marks.
String _layOutRow(String line, {required bool isDelimiter}) {
  final content = _trim(line);
  final indent = line.substring(0, line.indexOf(content));
  final hasLead = content.startsWith('|');
  final rest = hasLead ? content.substring(1) : content;
  final hasTrail = _endsWithUnescapedPipe(rest);
  final cells = _splitCells(content);
  final cellTexts = [
    for (final cell in cells)
      if (isDelimiter) _delimiter(cell) else cell,
  ];
  final joined = cellTexts.join(isDelimiter ? '|' : ' | ');
  final row = isDelimiter
      ? '${hasLead ? '|' : ''}$joined${hasTrail ? '|' : ''}'
      : '${hasLead ? '| ' : ''}$joined${hasTrail ? ' |' : ''}';
  return _trimEnd('$indent$row');
}

String _delimiter(String cell) =>
    '${cell.startsWith(':') ? ':' : ''}---${cell.endsWith(':') ? ':' : ''}';

bool _endsWithUnescapedPipe(String text) {
  if (!text.endsWith('|')) return false;
  var slashes = 0;
  for (var i = text.length - 2; i >= 0 && text[i] == r'\'; i--) {
    slashes++;
  }
  return slashes.isEven;
}

/// Splits a trimmed row into trimmed cells at unescaped pipes (GFM).
List<String> _splitCells(String content) {
  var inner = content.startsWith('|') ? content.substring(1) : content;
  if (_endsWithUnescapedPipe(inner)) {
    inner = inner.substring(0, inner.length - 1);
  }
  final cells = <String>[];
  final cell = StringBuffer();
  for (var i = 0; i < inner.length; i++) {
    final char = inner[i];
    if (char == r'\' && i + 1 < inner.length) {
      cell
        ..write(char)
        ..write(inner[++i]);
    } else if (char == '|') {
      cells.add(_trim(cell.toString()));
      cell.clear();
    } else {
      cell.write(char);
    }
  }
  return [...cells, _trim(cell.toString())];
}

// Dart's trim also strips NBSP and other Unicode spaces; INV-32 allows only
// spaces and tabs to change.
String _trimEnd(String text) {
  final end = _contentEnd(text);
  return end == text.length ? text : text.substring(0, end);
}

String _trim(String text) {
  final start = _contentStart(text);
  final end = _contentEnd(text);
  if (start == 0 && end == text.length) return text;
  return start >= end ? '' : text.substring(start, end);
}

/// The index after the last character that is not a space or a tab.
int _contentEnd(String text) {
  var end = text.length;
  while (end > 0 && _isSpaceOrTab(text.codeUnitAt(end - 1))) {
    end--;
  }
  return end;
}

/// The index of the first character that is not a space or a tab.
int _contentStart(String text) {
  var start = 0;
  while (start < text.length && _isSpaceOrTab(text.codeUnitAt(start))) {
    start++;
  }
  return start;
}

bool _isSpaceOrTab(int unit) => unit == _space || unit == _tab;

bool _isBlankLine(String line) => _contentStart(line) == line.length;

bool _isBlankText(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (!_isSpaceOrTab(unit) && unit != _lineFeed) return false;
  }
  return true;
}

bool _isQuote(String line) {
  final start = _contentStart(line);
  return start < line.length && line.codeUnitAt(start) == _quoteMarker;
}

/// Whether [line], its trailing spaces and tabs aside, is up to 3 spaces, 1 to
/// 6 `#`, then the end or a space.
bool _isHeadingLine(String line) {
  final end = _contentEnd(line);
  var i = 0;
  while (i < end && i < _maxHeadingIndent && line.codeUnitAt(i) == _space) {
    i++;
  }
  final hashes = i;
  while (i < end && line.codeUnitAt(i) == _hash) {
    i++;
  }
  final level = i - hashes;
  if (level < 1 || level > _maxHeadingLevel) return false;
  return i == end || line.codeUnitAt(i) == _space;
}

/// Whether [line] starts, after any spaces and tabs, with a bullet or a 1 to 9
/// digit ordered marker, then a space, a tab, or the end.
bool _isListItemLine(String line) {
  var i = _contentStart(line);
  if (i >= line.length) return false;
  final first = line.codeUnitAt(i);
  if (first == _dash || first == _star || first == _plus) {
    i++;
  } else {
    final digits = i;
    while (i < line.length && _isDigit(line.codeUnitAt(i))) {
      i++;
    }
    final count = i - digits;
    if (count < 1 || count > _maxOrderedDigits || i >= line.length) {
      return false;
    }
    final delimiter = line.codeUnitAt(i);
    if (delimiter != _dot && delimiter != _closeParen) return false;
    i++;
  }
  return i == line.length || _isSpaceOrTab(line.codeUnitAt(i));
}

bool _isDigit(int unit) => unit >= _digitZero && unit <= _digitNine;
