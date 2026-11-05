import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';

final _heading = RegExp(r'^ {0,3}#{1,6}(?: .*)?$');
final _listItem = RegExp(r'^[ \t]*(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)');
final _spaceTabEnd = RegExp(r'[ \t]+$');
final _spaceTabStart = RegExp(r'^[ \t]+');
final _blankLine = RegExp(r'^[ \t]*$');
final _blankText = RegExp(r'^[ \t\n]*$');
final _delimiterCell = RegExp(r'^:?-+:?$');
const _hardBreakSuffix = '  ';

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

  bool isHeading(int i) =>
      !protected[i] && _heading.hasMatch(_trimEnd(lines[i]));

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

  bool _isDelimiterRow(int i) =>
      _hasPipe(lines[i]) &&
      _splitCells(_trim(lines[i])).every(_delimiterCell.hasMatch);

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

  bool _startsTable(int i) =>
      _isRowLine(i) &&
      _hasPipe(lines[i]) &&
      _isRowLine(i + 1) &&
      _isDelimiterRow(i + 1) &&
      _splitCells(_trim(lines[i])).length ==
          _splitCells(_trim(lines[i + 1])).length;

  bool _isRowLine(int i) =>
      !protected[i] &&
      !isBlank(i) &&
      !isHeading(i) &&
      !_isQuote(lines[i]) &&
      !_listItem.hasMatch(lines[i]);
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

bool _hasPipe(String line) => line.contains('|');

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
String _trimEnd(String text) => text.replaceFirst(_spaceTabEnd, '');

String _trim(String text) => _trimEnd(text).replaceFirst(_spaceTabStart, '');

bool _isBlankLine(String line) => _blankLine.hasMatch(line);

bool _isBlankText(String text) => _blankText.hasMatch(text);

bool _isQuote(String line) =>
    line.replaceFirst(_spaceTabStart, '').startsWith('>');
