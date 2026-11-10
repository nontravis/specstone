import 'package:specstone_core/src/doc_model/doc.dart' show Doc, blockScan;
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show atxHeadingOf, isTableDelimiterRow, isThematicBreak, startsTable;

const _space = 0x20;
const _terminators = {0x2E, 0x3F, 0x21}; // . ? !

/// The first heading level a sentence is read from; `#` and `##` are the title
/// and the section headers.
const _firstTextHeadingLevel = 3;

final _whitespaceRun = RegExp(r'\s+');
final _quotePrefix = RegExp(r'^[ \t]*>[ \t]?');
final _listMarker = RegExp(r'^[ \t]*(?:[-+*]|\d{1,9}[.)])(?:[ \t]+|$)');
final _tableRow = RegExp(r'^ {0,3}\|');
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

  void close() {
    if (_open.isEmpty) return;
    blocks.add(_open.join(' '));
    _open.clear();
  }

  /// Whether the rows being read belong to a table whose header had no edge
  /// pipe.
  var _inTable = false;

  /// Reads [text], a line without its containers or null for a thematic
  /// break, with [below] the next line's text.
  void read(
    String? text, {
    required String? below,
    required bool continuesParagraph,
  }) {
    if (text == null || text.trim().isEmpty) {
      _inTable = false;
      return close();
    }
    final heading = atxHeadingOf(text);
    if (heading != null) {
      _inTable = false;
      close();
      if (heading.level >= _firstTextHeadingLevel) _add(heading.text);
      return;
    }
    if (_tableRow.hasMatch(text) || _inTable) {
      close();
      return _readTableRow(text);
    }
    if (below != null && startsTable(text, below)) {
      close();
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
