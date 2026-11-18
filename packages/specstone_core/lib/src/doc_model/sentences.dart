import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc, blockScan;
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show atxHeadingOf, isTableDelimiterRow, isThematicBreak, startsTable;
import 'package:specstone_core/src/doc_model/models/text_block.dart';

const _space = 0x20;

/// The marks `.`, `?`, and `!`, which end a sentence before a space or the end
/// of the text.
const spacedTerminators = {0x2E, 0x3F, 0x21};

/// The first heading level a sentence is read from; `#` and `##` are the title
/// and the section headers.
const _firstTextHeadingLevel = 3;

final _quotePrefix = RegExp(r'^[ \t]*>[ \t]?');
final _listMarker = RegExp(r'^[ \t]*(?:[-+*]|\d{1,9}[.)])(?:[ \t]+|$)');
final _unescapedPipe = RegExp(r'(?<!\\)\|');

const _tab = 0x09;
const _carriageReturn = 0x0D;
const _lineSeparator = 0x2028;
const _paragraphSeparator = 0x2029;

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

/// Returns the sentences of [lfText], a doc's LF text, whitespace collapsed.
///
/// They come from paragraphs, list items, table cells, and `###` or deeper
/// headings, outside the frontmatter, the title, the `##` headers, and fenced
/// code. Inline markup stays in each sentence.
List<String> sentencesOf(String lfText) => [
  for (final block in textBlocksOf(lfText)) ..._cut(block.text),
];

/// Returns the text blocks of [lfText], a doc's LF text, in doc order: its
/// paragraphs, list items, table cells, and `###` or deeper headings, read past
/// block quote and list markers, outside the frontmatter, the title, the `##`
/// headers, and fenced code.
List<TextBlock> textBlocksOf(String lfText) {
  final lines = _linesOf(Doc.parse(lfText).afterFrontmatter);
  final scan = blockScan(lines);
  final reader = _BlockReader();
  _Stripped? textAt(int i) => i < lines.length && !scan.fenced[i]
      ? _withoutContainers(lines[i], scan.continuesParagraph[i])
      : null;
  // The delimiter row below a header keeps a list marker: `- | -` is one, and
  // `markdown` tries the table before the list.
  _Stripped? delimiterAt(int i) => i < lines.length && !scan.fenced[i]
      ? _withoutContainers(lines[i], true)
      : null;
  for (var i = 0; i < lines.length; i++) {
    if (scan.fenced[i]) {
      reader.close();
    } else {
      reader.read(
        textAt(i),
        below: delimiterAt(i + 1),
        continuesParagraph: scan.continuesParagraph[i],
      );
    }
  }
  reader.close();
  return reader.blocks;
}

List<String> _linesOf(String lfText) {
  final lines = lfText.isEmpty ? <String>[] : lfText.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// Collects the text blocks of a doc, line by line.
final class _BlockReader {
  /// The blocks closed so far, in doc order.
  final blocks = <TextBlock>[];

  final _open = <String>[];

  /// Whether the lines being read are the rows of a table that started.
  var _inTable = false;

  /// Ends the open block and any table: every other block starts anew.
  void close() {
    _closeBlock();
    _inTable = false;
  }

  void _closeBlock() {
    if (_open.isEmpty) return;
    blocks.add(TextBlock(text: _open.join(' '), isHeading: false));
    _open.clear();
  }

  /// The block quote depth of the table being read.
  var _tableQuotes = 0;

  /// Whether the next line is the delimiter row of the table just started,
  /// which holds no text.
  var _delimiterNext = false;

  /// Reads [line], a line without its containers or null for a thematic
  /// break, with [below] the next line.
  void read(
    _Stripped? line, {
    required _Stripped? below,
    required bool continuesParagraph,
  }) {
    if (_delimiterNext) {
      _delimiterNext = false;
      return;
    }
    if (line == null || line.text.trim().isEmpty) return close();
    final text = line.text;
    final heading = atxHeadingOf(text);
    if (heading != null) {
      close();
      if (heading.level >= _firstTextHeadingLevel) {
        _add(heading.text, isHeading: true);
      }
      return;
    }
    if (_inTable) {
      if (line.quotes == _tableQuotes && !line.isListItem) {
        _closeBlock();
        return _readTableRow(text);
      }
      close();
    }
    // A header such as `- a | b` starts like a list item, and `markdown` tries
    // the table before the list; its marker is part of the first cell.
    if (below != null &&
        below.quotes == line.quotes &&
        startsTable(line.written, below.text)) {
      _closeBlock();
      _inTable = true;
      _delimiterNext = true;
      _tableQuotes = line.quotes;
      return _readTableRow(line.written);
    }
    if (!continuesParagraph) close();
    _open.add(text.trim());
  }

  void _add(String block, {bool isHeading = false}) {
    if (block.trim().isNotEmpty) {
      blocks.add(TextBlock(text: block.trim(), isHeading: isHeading));
    }
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

/// A line read past its containers: its `text`, the count of block quote
/// marks it opened with, whether a list marker opened it, and the line as
/// `written`, past the block quote marks only.
final class _Stripped {
  const new({
    required this.text,
    required this.quotes,
    required this.isListItem,
    required this.written,
  });

  final String text;
  final int quotes;
  final bool isListItem;
  final String written;
}

/// Returns [line] past the block quote marks it opens with, and past its list
/// marker unless it continues a paragraph, or null for a thematic break.
_Stripped? _withoutContainers(String line, bool continuesParagraph) {
  var text = line;
  var quotes = 0;
  var isListItem = false;
  String? written;
  while (true) {
    if (isThematicBreak(text)) return null;
    final quote = _quotePrefix.matchAsPrefix(text);
    final marker = quote == null && !continuesParagraph
        ? _listMarker.matchAsPrefix(text)
        : null;
    final prefix = quote ?? marker;
    if (prefix == null) {
      return _Stripped(
        text: text,
        quotes: quotes,
        isListItem: isListItem,
        written: written ?? text,
      );
    }
    if (quote != null) {
      quotes++;
    } else {
      written ??= text;
      isListItem = true;
    }
    text = text.substring(prefix.end);
  }
}

/// Returns the sentences of [block], cut after each `.`, `?`, or `!` a space or
/// the end of the block follows and no code span holds.
///
/// The marks of a code span are blanked before the cut, so a sentence never
/// ends inside one; the span's own text stays in each sentence as written.
List<String> _cut(String block) {
  final text = collapseWhitespace(block).trim();
  final cuttable = _outsideCodeSpans(text);
  final sentences = <String>[];
  var start = 0;
  for (var i = 0; i < cuttable.length; i++) {
    if (!spacedTerminators.contains(cuttable.codeUnitAt(i))) continue;
    final end = i + 1;
    if (end < cuttable.length && cuttable.codeUnitAt(end) != _space) continue;
    sentences.add(text.substring(start, end).trim());
    start = end;
  }
  sentences.add(text.substring(start).trim());
  return [
    for (final sentence in sentences)
      if (sentence.isNotEmpty) sentence,
  ];
}

/// Returns [text] with every code span's marks and backticks blanked, the
/// same length as [text], so only the marks outside a span cut a sentence.
String _outsideCodeSpans(String text) {
  final spans = codeSpansOf(text);
  if (spans.isEmpty) return text;
  final units = text.codeUnits.toList();
  for (final span in spans) {
    for (var at = span.start; at < span.end; at++) {
      units[at] = _space;
    }
  }
  return String.fromCharCodes(units);
}
