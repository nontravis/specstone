import 'package:specstone_core/src/doc_model/doc.dart'
    show Doc, blockScan, isSectionHeaderLine, isTitleLine;

const _space = 0x20;
const _terminators = {0x2E, 0x3F, 0x21}; // . ? !

final _whitespaceRun = RegExp(r'\s+');
final _quotePrefix = RegExp(r'^[ \t]*>[ \t]?');
final _listMarker = RegExp(r'^[ \t]*(?:[-+*]|\d{1,9}[.)])(?:[ \t]+|$)');
final _thematicBreak = RegExp(r'^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$');
final _deepHeading = RegExp(
  r'^ {0,3}#{3,6}(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$',
);
final _tableRow = RegExp(r'^ {0,3}\|');
final _tableDelimiterCell = RegExp(r'^:?-+:?$');
final _unescapedPipe = RegExp(r'(?<!\\)\|');

final _quoteMark = RegExp(r'>[ \t]?');

/// The quote marks and list markers a line opens with, for [heldTextOf].
final _lineOpening = RegExp(
  r'^(?:[ \t]*(?:>[ \t]?|(?:[-+*]|\d{1,9}[.)])[ \t]+))+',
  multiLine: true,
);

/// Returns each of [text]'s runs of whitespace as one space.
///
/// Both sides of "holds" are read in this form: a sentence and the text it is
/// looked for in.
String collapseWhitespace(String text) => text.replaceAll(_whitespaceRun, ' ');

/// Returns [lfText] as the text a sentence is looked for in: its block quote
/// marks stripped, then [collapseWhitespace].
///
/// A sentence of a block quote wrapped over `>` lines is read without those
/// marks, so the text it is held in is read without them too. A `>` inside a
/// line stays.
String heldTextOf(String lfText) => collapseWhitespace(
  lfText.replaceAllMapped(
    _lineOpening,
    (opening) => opening[0]!.replaceAll(_quoteMark, ''),
  ),
);

/// Returns the sentences of [lfText], a doc's LF text, as the text each one is
/// written in, whitespace collapsed.
///
/// A sentence is cut from the text of a paragraph, list item, table cell, or
/// `###` or deeper heading, outside the frontmatter, the `# ` title, the `##`
/// headers, and fenced code, after each `.`, `?`, or `!` that a space or the
/// end of its block follows. List markers, `>` marks, heading marks, and table
/// pipes are no part of it; inline markup is, so the sentence occurs in
/// `heldTextOf` of any doc that holds it.
List<String> sentencesOf(String lfText) {
  final lines = _linesOf(Doc.parse(lfText).afterFrontmatter);
  final scan = blockScan(lines);
  final reader = _BlockReader();
  for (var i = 0; i < lines.length; i++) {
    if (scan.fenced[i]) {
      reader.close();
    } else {
      reader.read(lines[i], continuesParagraph: scan.continuesParagraph[i]);
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

  void close() {
    if (_open.isEmpty) return;
    blocks.add(_open.join(' '));
    _open.clear();
  }

  void read(String line, {required bool continuesParagraph}) {
    final text = _withoutContainers(line, continuesParagraph);
    if (text == null || text.trim().isEmpty) return close();
    if (isTitleLine(text) || isSectionHeaderLine(text)) return close();
    final heading = _deepHeading.firstMatch(text);
    if (heading != null) {
      close();
      return _add(heading[1] ?? '');
    }
    if (_tableRow.hasMatch(text)) {
      close();
      return _readTableRow(text);
    }
    if (!continuesParagraph) close();
    _open.add(text.trim());
  }

  void _add(String block) {
    if (block.trim().isNotEmpty) blocks.add(block.trim());
  }

  void _readTableRow(String row) {
    final cells = [
      for (final cell in _trimPipes(row).split(_unescapedPipe)) cell.trim(),
    ];
    if (cells.every(_tableDelimiterCell.hasMatch)) return;
    cells.forEach(_add);
  }
}

String _trimPipes(String row) {
  var text = row.trim().substring(1);
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
    if (_thematicBreak.hasMatch(text)) return null;
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
