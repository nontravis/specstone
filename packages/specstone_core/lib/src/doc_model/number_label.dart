import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart'
    show Doc, blockScan, fenceScan, mermaidInfoWord;
import 'package:specstone_core/src/doc_model/models/block_scan.dart';
import 'package:specstone_core/src/doc_model/models/code_span.dart';
import 'package:specstone_core/src/doc_model/models/label_part.dart';
import 'package:specstone_core/src/doc_model/models/number_label_line.dart';
import 'package:specstone_core/src/doc_model/models/prefixed_label_line.dart';
import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart'
    show isCommentLine, lineCommentMarkOf, markdownExtension;

/// How a number label names its doc.
enum LabelShape {
  /// Opens with a feature part: `F-<nn>`, `F-<nn> US-<nn>`, or all three.
  full,

  /// Opens with a story or FR part: `US-<nn> FR-<nn>`, `US-<nn>`, `FR-<nn>`.
  partial,

  /// Doc-tree folder names joined by `/`, one at least a number with no slug.
  folderPath,
}

/// One number label run as written.
///
/// [start] and [end] are offsets into the text that was read: the line for
/// [numberLabelsIn], the whole text for [numberLabelsInMarkdown]. [slug] is the
/// slug of a folder path's last folder.
final class NumberLabel {
  const new({
    required this.start,
    required this.end,
    required this.written,
    required this.shape,
    this.feature,
    this.story,
    this.fr,
    this.slug,
    this.isPartOfPath = false,
  });

  final int start;
  final int end;
  final String written;
  final LabelShape shape;
  final int? feature;
  final int? story;
  final int? fr;
  final String? slug;

  /// Whether a numbered folder that does not follow the label's last part
  /// comes right after it, as `nf01` does after a story folder: the label is
  /// read and reported, but names no doc by its folders.
  final bool isPartOfPath;

  NumberLabel _shiftedBy(int offset) => NumberLabel(
    start: start + offset,
    end: end + offset,
    written: written,
    shape: shape,
    feature: feature,
    story: story,
    fr: fr,
    slug: slug,
    isPartOfPath: isPartOfPath,
  );
}

/// The number labels of [line]: each begins where no letter, digit, or `-`
/// comes before it; `<nn>` placeholders are no label.
///
/// This is the one reader of the label boundary. Every other reader of a
/// label goes through it, [numberLabelsInMarkdown] for a whole text.
///
List<NumberLabel> numberLabelsIn(String line) {
  final labels = <NumberLabel>[];
  var at = 0;
  while (at < line.length) {
    final label = _beginsLabel(line, at) ? _labelAt(line, at) : null;
    if (label == null) {
      at++;
    } else {
      labels.add(label);
      at = label.end;
    }
  }
  return labels;
}

/// The number labels and the capital-prefix label chains of a body, each at
/// its 0-based line, read in one pass.
final class MarkdownLabelLines {
  const new({required this.numbers, required this.prefixed});

  /// The labels of [numberLabelsInMarkdown], as written.
  final List<NumberLabelLine> numbers;

  /// The chains of parts that hold a prefix outside `F-`, `US-`, and `FR-`.
  final List<PrefixedLabelLine> prefixed;
}

/// Returns the labels of [lfText], LF text without frontmatter, as the index
/// stores them.
///
/// A chain is parts joined by single spaces, a part being `<CAPITALS>-<digits>`
/// that begins where [numberLabelsIn] lets a label begin. The project's config
/// says which prefixes count, so each chain keeps every part with the built-in
/// label it lies in. The text read is the text [numberLabelsInMarkdown] reads.
/// [blocks] is the [blockScan] of `lfText.split('\n')` a caller already holds.
/// With [readsMermaid] false, every fenced line is skipped, `mermaid` blocks
/// included.
MarkdownLabelLines labelLinesInMarkdown(
  String lfText, {
  BlockScan? blocks,
  bool readsMermaid = true,
}) {
  final numbers = <NumberLabelLine>[];
  final prefixed = <PrefixedLabelLine>[];
  for (final text in _readableTextsOf(
    lfText,
    blocks: blocks,
    readsMermaid: readsMermaid,
  )) {
    _addLabelsOf(text.text, text.index, numbers, prefixed);
  }
  return MarkdownLabelLines(numbers: numbers, prefixed: prefixed);
}

void _addLabelsOf(
  String text,
  int index,
  List<NumberLabelLine> numbers,
  List<PrefixedLabelLine> prefixed,
) {
  final labels = _labelsOutsideLinks(text, 0);
  numbers.addAll([
    for (final label in labels)
      NumberLabelLine(line: index, written: label.written),
  ]);
  prefixed.addAll(_prefixedChainsIn(text, index, labels));
}

/// Returns the labels of [lf], a code file of [extension], each at its 0-based
/// line of the file.
///
/// Markdown is read after its frontmatter and outside fenced code, as
/// [labelLinesInMarkdown] reads a body; any other file by its comment lines,
/// each read after its mark, with its code spans and link destinations
/// skipped. [parsed] is the [Doc.parse] of [lf] a caller already holds.
MarkdownLabelLines labelLinesInFile(
  String lf,
  String extension, {
  Doc? parsed,
}) {
  if (extension == markdownExtension) {
    final body = (parsed ?? Doc.parse(lf)).afterFrontmatter;
    final bodyStart = '\n'.allMatches(lf.substring(0, lf.length - body.length));
    return _shiftedLines(
      labelLinesInMarkdown(body, readsMermaid: false),
      bodyStart.length,
    );
  }
  final mark = lineCommentMarkOf(extension);
  final numbers = <NumberLabelLine>[];
  final prefixed = <PrefixedLabelLine>[];
  if (mark != null) {
    final lines = lf.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!isCommentLine(lines[i], extension)) continue;
      final text = lines[i].trimLeft().substring(mark.length);
      _addLabelsOf(
        _outsideCodeSpans([text], const [false], {}, 0),
        i,
        numbers,
        prefixed,
      );
    }
  }
  return MarkdownLabelLines(numbers: numbers, prefixed: prefixed);
}

MarkdownLabelLines _shiftedLines(MarkdownLabelLines labels, int offset) =>
    MarkdownLabelLines(
      numbers: [
        for (final NumberLabelLine(:line, :written) in labels.numbers)
          NumberLabelLine(line: line + offset, written: written),
      ],
      prefixed: [
        for (final PrefixedLabelLine(:line, :parts) in labels.prefixed)
          PrefixedLabelLine(line: line + offset, parts: parts),
      ],
    );

const _spaceUnit = 0x20;

/// The number labels of [lfText], LF text without frontmatter, with offsets
/// into the whole text.
///
/// Prose and `mermaid` blocks are read; fenced code other than `mermaid`,
/// code spans, and link destinations are skipped.
List<NumberLabel> numberLabelsInMarkdown(String lfText) => [
  for (final line in _readableTextsOf(lfText))
    ..._labelsOutsideLinks(line.text, line.start),
];

/// One line [numberLabelsInMarkdown] reads: its 0-based index, its text with
/// every code span blanked, and the offset it starts at in the whole text.
final class _ReadableText {
  const new({required this.index, required this.text, required this.start});

  final int index;
  final String text;
  final int start;
}

List<_ReadableText> _readableTextsOf(
  String lfText, {
  BlockScan? blocks,
  bool readsMermaid = true,
}) {
  final lines = lfText.split('\n');
  final scan = blocks ?? blockScan(lines);
  final readable = readsMermaid
      ? _readableLines(lines)
      : [for (final isFenced in scan.fenced) !isFenced];
  final continues = scan.continuesParagraph;
  final spansOfGroup = <int, List<CodeSpan>>{};
  final texts = <_ReadableText>[];
  var lineStart = 0;
  for (var i = 0; i < lines.length; i++) {
    if (readable[i]) {
      texts.add(
        _ReadableText(
          index: i,
          // A `mermaid` block is fenced: its backticks are no code spans.
          text: scan.fenced[i]
              ? lines[i]
              : _outsideCodeSpans(lines, continues, spansOfGroup, i),
          start: lineStart,
        ),
      );
    }
    lineStart += lines[i].length + 1;
  }
  return texts;
}

/// Returns line [index] of [lines] with every code span of the paragraph it
/// sits in blanked to spaces, so no label begins inside one.
///
/// The spans are read once per paragraph over its lines joined by line
/// feeds, so a span the paragraph wraps over two lines blanks its part on
/// each. A backtick leaves a label's start open, and so does a space, so the
/// blanks move no boundary.
String _outsideCodeSpans(
  List<String> lines,
  List<bool> continues,
  Map<int, List<CodeSpan>> spansOfGroup,
  int index,
) {
  var first = index;
  while (first > 0 && continues[first]) {
    first--;
  }
  var last = index;
  while (last + 1 < lines.length && continues[last + 1]) {
    last++;
  }
  final spans = spansOfGroup.putIfAbsent(
    first,
    () => codeSpansOf(lines.sublist(first, last + 1).join('\n')),
  );
  var lineStart = 0;
  for (var i = first; i < index; i++) {
    lineStart += lines[i].length + 1;
  }
  final line = lines[index];
  if (spans.isEmpty) return line;
  final lineEnd = lineStart + line.length;
  final units = line.codeUnits.toList();
  for (final span in spans) {
    final from = span.start > lineStart ? span.start : lineStart;
    final to = span.end < lineEnd ? span.end : lineEnd;
    for (var at = from; at < to; at++) {
      units[at - lineStart] = _spaceUnit;
    }
  }
  return String.fromCharCodes(units);
}

// MARK: - Label reader

/// The value a number too long for an int reads as: beyond every doc.
const _beyondAnyDoc = 9007199254740991;

/// The prefixes of the built-in dash labels, by rank: feature, story, FR.
const builtInLabelPrefixes = ['F-', 'US-', 'FR-'];
const _featureRank = 0;
const _storyRank = 1;
const _frRank = 2;

/// One part of a label: its rank (feature, story, FR), number, and end.
final class _Part {
  const new({
    required this.rank,
    required this.number,
    required this.slug,
    required this.end,
  });

  final int rank;
  final int number;
  final String? slug;
  final int end;
}

/// The rank of a folder prefix, -1 for none, and its length.
final class _FolderPrefix {
  const new({required this.rank, required this.length});

  final int rank;
  final int length;
}

NumberLabel? _labelAt(String line, int at) =>
    _dashRunAt(line, at) ?? _folderRunAt(line, at);

/// Whether a label may begin at [at] (> 0): no letter, digit, or `-` before.
bool _beginsLabel(String line, int at) {
  if (at == 0) return true;
  final before = line.codeUnitAt(at - 1);
  if (before < _asciiLimit) {
    return before != _dash && !_isDigit(before) && !_isAsciiLetter(before);
  }
  final width = _isLowSurrogate(before) && at >= 2 ? 2 : 1;
  return !_wordChar.hasMatch(line.substring(at - width, at));
}

// A character-class test on the one character before a label, since a letter
// outside ASCII has no code-unit test.
final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

NumberLabel? _dashRunAt(String line, int at) {
  final first = _dashPartAt(line, at);
  if (first == null) return null;
  final numbers = <int?>[null, null, null];
  numbers[first.rank] = first.number;
  var last = first;
  while (line.startsWith(' ', last.end)) {
    final next = _dashPartAt(line, last.end + 1);
    if (next == null || next.rank != last.rank + 1) break;
    numbers[next.rank] = next.number;
    last = next;
  }
  return _labelOf(
    line,
    at,
    last.end,
    shape: first.rank == _featureRank ? LabelShape.full : LabelShape.partial,
    numbers: numbers,
  );
}

_Part? _dashPartAt(String line, int at) {
  for (var rank = 0; rank < builtInLabelPrefixes.length; rank++) {
    final prefix = builtInLabelPrefixes[rank];
    if (!line.startsWith(prefix, at)) continue;
    final digits = at + prefix.length;
    final end = _digitsEnd(line, digits);
    if (end == digits) return null;
    final number = _numberOf(line.substring(digits, end));
    return _Part(rank: rank, number: number, slug: null, end: end);
  }
  return null;
}

NumberLabel? _folderRunAt(String line, int at) {
  final parts = <_Part>[];
  var cursor = at;
  while (true) {
    final part = _folderAt(line, cursor);
    if (part == null) break;
    if (parts.isNotEmpty && part.rank <= parts.last.rank) break;
    parts.add(part);
    cursor = part.end;
    if (!line.startsWith('/', cursor)) break;
    cursor++;
  }
  if (parts.length < 2 || parts.every((part) => part.slug != null)) {
    return null;
  }
  final numbers = <int?>[null, null, null];
  for (final part in parts) {
    numbers[part.rank] = part.number;
  }
  return _labelOf(
    line,
    at,
    parts.last.end,
    shape: LabelShape.folderPath,
    numbers: numbers,
    slug: parts.last.slug,
    isPartOfPath: _numberedFolderFollows(line, parts.last.end),
  );
}

final _numberedFolder = RegExp(
  r'(?:nf|us|fr|f)\d+(?:_[a-z0-9_]+)?(?![A-Za-z0-9])',
);

/// Whether a numbered folder (`nf`, `f`, `us`, or `fr` and digits) comes
/// after a `/` at [end]; an item ID or scenario segment, such as `e09`, is
/// none.
bool _numberedFolderFollows(String line, int end) =>
    line.startsWith('/', end) &&
    _numberedFolder.matchAsPrefix(line, end + 1) != null;

/// Reads a folder name `f<digits>`, `us<digits>`, or `fr<digits>`, with an
/// optional `_<slug>`, at [at].
_Part? _folderAt(String line, int at) {
  final _FolderPrefix(:rank, length: prefixLength) = _folderPrefixAt(line, at);
  if (rank < 0) return null;
  final digits = at + prefixLength;
  final digitsEnd = _digitsEnd(line, digits);
  if (digitsEnd == digits) return null;
  if (digitsEnd < line.length && _isAsciiLetter(line.codeUnitAt(digitsEnd))) {
    return null;
  }
  final slugEnd = _slugEnd(line, digitsEnd);
  return _Part(
    rank: rank,
    number: _numberOf(line.substring(digits, digitsEnd)),
    slug: slugEnd == null ? null : line.substring(digitsEnd + 1, slugEnd),
    end: slugEnd ?? digitsEnd,
  );
}

/// Returns the rank and length of the folder prefix at [at], or rank -1.
_FolderPrefix _folderPrefixAt(String line, int at) {
  if (line.startsWith('fr', at)) {
    return const _FolderPrefix(rank: _frRank, length: 2);
  }
  if (line.startsWith('us', at)) {
    return const _FolderPrefix(rank: _storyRank, length: 2);
  }
  return line.startsWith('f', at)
      ? const _FolderPrefix(rank: _featureRank, length: 1)
      : const _FolderPrefix(rank: -1, length: 0);
}

/// Returns the end of the `_<slug>` that starts at [at], or null without one.
int? _slugEnd(String line, int at) {
  if (!line.startsWith('_', at)) return null;
  var end = at + 1;
  while (end < line.length && _isSlugChar(line.codeUnitAt(end))) {
    end++;
  }
  return end == at + 1 ? null : end;
}

NumberLabel _labelOf(
  String line,
  int start,
  int end, {
  required LabelShape shape,
  required List<int?> numbers,
  String? slug,
  bool isPartOfPath = false,
}) => NumberLabel(
  start: start,
  end: end,
  written: line.substring(start, end),
  shape: shape,
  feature: numbers[_featureRank],
  story: numbers[_storyRank],
  fr: numbers[_frRank],
  slug: slug,
  isPartOfPath: isPartOfPath,
);

int _numberOf(String digits) => int.tryParse(digits) ?? _beyondAnyDoc;

int _digitsEnd(String text, int from) {
  var end = from;
  while (end < text.length && _isDigit(text.codeUnitAt(end))) {
    end++;
  }
  return end;
}

const _asciiLimit = 0x80;
const _dash = 0x2D;

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;
bool _isUpper(int unit) => unit >= 0x41 && unit <= 0x5A;
bool _isLower(int unit) => unit >= 0x61 && unit <= 0x7A;
bool _isAsciiLetter(int unit) => _isUpper(unit) || _isLower(unit);
bool _isSlugChar(int unit) => _isLower(unit) || _isDigit(unit) || unit == 0x5F;
bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

// MARK: - Prefixed label reader

/// One `<CAPITALS>-<digits>` part: its prefix, such as `FO-`, and its span.
final class _PrefixedPart {
  const new({required this.prefix, required this.start, required this.end});

  final String prefix;
  final int start;
  final int end;
}

/// Returns the chains of [line] with a part outside the built-in prefixes,
/// none starting inside a link destination, each part with the label of
/// [labels], the built-in ones of [line], it lies in.
List<PrefixedLabelLine> _prefixedChainsIn(
  String line,
  int index,
  List<NumberLabel> labels,
) {
  final chains = [
    for (final chain in _prefixedChainsOf(line))
      if (chain.any((part) => !builtInLabelPrefixes.contains(part.prefix)))
        chain,
  ];
  if (chains.isEmpty) return const [];
  final destinations = _destinationsIn(line);
  return [
    for (final chain in chains)
      if (!destinations.any(
        (d) => chain.first.start >= d.start && chain.first.start < d.end,
      ))
        PrefixedLabelLine(
          line: index,
          parts: [for (final part in chain) _labelPartOf(line, part, labels)],
        ),
  ];
}

LabelPart _labelPartOf(
  String line,
  _PrefixedPart part,
  List<NumberLabel> labels,
) {
  final owner = labels
      .where((label) => label.start <= part.start && part.end <= label.end)
      .firstOrNull;
  return LabelPart(
    prefix: part.prefix,
    written: line.substring(part.start, part.end),
    ownerWritten: owner?.written,
    ownerStart: owner?.start,
  );
}

List<List<_PrefixedPart>> _prefixedChainsOf(String line) {
  final chains = <List<_PrefixedPart>>[];
  var at = 0;
  while (at < line.length) {
    final first = _isUpper(line.codeUnitAt(at)) && _beginsLabel(line, at)
        ? _prefixedPartAt(line, at)
        : null;
    if (first == null) {
      at++;
      continue;
    }
    final chain = [first];
    while (line.startsWith(' ', chain.last.end)) {
      final next = _prefixedPartAt(line, chain.last.end + 1);
      if (next == null) break;
      chain.add(next);
    }
    chains.add(chain);
    at = chain.last.end;
  }
  return chains;
}

_PrefixedPart? _prefixedPartAt(String line, int at) {
  var dash = at;
  while (dash < line.length && _isUpper(line.codeUnitAt(dash))) {
    dash++;
  }
  if (dash == at || !line.startsWith('-', dash)) return null;
  final digits = dash + 1;
  final end = _digitsEnd(line, digits);
  if (end == digits) return null;
  return _PrefixedPart(prefix: line.substring(at, digits), start: at, end: end);
}

// MARK: - Markdown reader

/// Returns, per line, whether it holds text to read: prose, and the lines of
/// a `mermaid` block between its fences.
List<bool> _readableLines(List<String> lines) {
  final scan = fenceScan(lines);
  final readable = <bool>[];
  var inMermaid = false;
  for (var i = 0; i < lines.length; i++) {
    final opened = scan.opens[i];
    if (opened != null) inMermaid = opened == mermaidInfoWord;
    if (!scan.fenced[i]) inMermaid = false;
    final isDelimiter = opened != null || scan.closes[i];
    readable.add(!scan.fenced[i] || (inMermaid && !isDelimiter));
  }
  return readable;
}

/// Returns the labels of [line] that lie outside a link destination, their
/// offsets shifted by [lineStart].
List<NumberLabel> _labelsOutsideLinks(String line, int lineStart) {
  final labels = numberLabelsIn(line);
  if (labels.isEmpty) return labels;
  final destinations = _destinationsIn(line);
  return [
    for (final label in labels)
      if (!destinations.any(
        (d) => label.start >= d.start && label.start < d.end,
      ))
        label._shiftedBy(lineStart),
  ];
}

/// Returns the link destinations of [line]: each `](...)` target and the
/// target of a reference definition.
List<TextRange> _destinationsIn(String line) {
  final spans = <TextRange>[?_definitionTarget(line)];
  var open = line.indexOf('](');
  while (open >= 0) {
    final start = open + 2;
    final end = _inlineTargetEnd(line, start);
    spans.add(TextRange(start: start, end: end));
    open = line.indexOf('](', end);
  }
  return spans;
}

/// Returns the end of the inline target that starts at [start]: past a `<...>`
/// target, else at the `)` that balances the opening one.
int _inlineTargetEnd(String line, int start) {
  if (line.startsWith('<', start)) {
    final close = line.indexOf('>', start);
    return close < 0 ? line.length : close;
  }
  var depth = 1;
  for (var i = start; i < line.length; i++) {
    final unit = line.codeUnitAt(i);
    if (unit == 0x28) depth++;
    if (unit == 0x29 && --depth == 0) return i;
  }
  return line.length;
}

/// Returns the target of a reference definition `[x]: target`, or null.
TextRange? _definitionTarget(String line) {
  var at = 0;
  while (at < line.length && at < 3 && line.startsWith(' ', at)) {
    at++;
  }
  if (!line.startsWith('[', at)) return null;
  final close = line.indexOf(']:', at);
  if (close < 0) return null;
  var start = close + 2;
  while (start < line.length && _isBlank(line.codeUnitAt(start))) {
    start++;
  }
  var end = start;
  while (end < line.length && !_isBlank(line.codeUnitAt(end))) {
    end++;
  }
  return TextRange(start: start, end: end);
}

bool _isBlank(int unit) => unit == 0x20 || unit == 0x09;
