import 'package:specstone_core/src/doc_model/doc.dart' show fenceScan;

/// How a number label names its doc.
enum LabelShape {
  /// Opens with a feature part: `F-<nn>`, `F-<nn> US-<nn>`, or all three.
  full,

  /// Opens with a story or FR part: `US-<nn> FR-<nn>`, `US-<nn>`, `FR-<nn>`.
  partial,

  /// Doc-tree folder names joined by `/`, one at least a number with no slug.
  folderPath,
}

/// One number label run as written, with the item ID that follows it, if any.
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
    this.itemId,
  });

  final int start;
  final int end;
  final String written;
  final LabelShape shape;
  final int? feature;
  final int? story;
  final int? fr;
  final String? slug;
  final String? itemId;

  NumberLabel _shiftedBy(int offset) => NumberLabel(
    start: start + offset,
    end: end + offset,
    written: written,
    shape: shape,
    feature: feature,
    story: story,
    fr: fr,
    slug: slug,
    itemId: itemId,
  );
}

/// The number labels of [line]: each begins where no letter, digit, or `-`
/// comes before it (R83); `<nn>` placeholders are no label (R81).
///
/// This is the one reader of the label boundary. Every other reader of a
/// label goes through it, [numberLabelsInMarkdown] for a whole text.
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

/// The number labels of [lfText], LF text without frontmatter, with offsets
/// into the whole text.
///
/// Prose, code spans, and `mermaid` blocks are read; other fenced code and
/// link destinations are skipped (R82).
List<NumberLabel> numberLabelsInMarkdown(String lfText) {
  final lines = lfText.split('\n');
  final readable = _readableLines(lines);
  final labels = <NumberLabel>[];
  var lineStart = 0;
  for (var i = 0; i < lines.length; i++) {
    if (readable[i]) labels.addAll(_labelsOutsideLinks(lines[i], lineStart));
    lineStart += lines[i].length + 1;
  }
  return labels;
}

// MARK: - Label reader

/// The value a number too long for an int reads as: beyond every doc.
const _beyondAnyDoc = 9007199254740991;

const _dashPrefixes = ['F-', 'US-', 'FR-'];
const _featureRank = 0;
const _storyRank = 1;
const _frRank = 2;

/// One part of a label: its rank (feature, story, FR), number, and end.
typedef _Part = ({int rank, int number, String? slug, int end});

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
  for (var rank = 0; rank < _dashPrefixes.length; rank++) {
    final prefix = _dashPrefixes[rank];
    if (!line.startsWith(prefix, at)) continue;
    final digits = at + prefix.length;
    final end = _digitsEnd(line, digits);
    if (end == digits) return null;
    final number = _numberOf(line.substring(digits, end));
    return (rank: rank, number: number, slug: null, end: end);
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
  );
}

/// Reads a folder name `f<digits>`, `us<digits>`, or `fr<digits>`, with an
/// optional `_<slug>`, at [at].
_Part? _folderAt(String line, int at) {
  final (rank, prefixLength) = line.startsWith('fr', at)
      ? (_frRank, 2)
      : line.startsWith('us', at)
      ? (_storyRank, 2)
      : line.startsWith('f', at)
      ? (_featureRank, 1)
      : (-1, 0);
  if (rank < 0) return null;
  final digits = at + prefixLength;
  final digitsEnd = _digitsEnd(line, digits);
  if (digitsEnd == digits) return null;
  if (digitsEnd < line.length && _isAsciiLetter(line.codeUnitAt(digitsEnd))) {
    return null;
  }
  final slugEnd = _slugEnd(line, digitsEnd);
  return (
    rank: rank,
    number: _numberOf(line.substring(digits, digitsEnd)),
    slug: slugEnd == null ? null : line.substring(digitsEnd + 1, slugEnd),
    end: slugEnd ?? digitsEnd,
  );
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
}) => NumberLabel(
  start: start,
  end: end,
  written: line.substring(start, end),
  shape: shape,
  feature: numbers[_featureRank],
  story: numbers[_storyRank],
  fr: numbers[_frRank],
  slug: slug,
  itemId: _itemIdAfter(line, end),
);

/// Returns the item ID that follows a label ending at [end] after one space:
/// upper-case letters, an optional `-` and letters, then digits, such as
/// `INV-6`, `E05`, or `NFR-P03`. A label is no item ID.
String? _itemIdAfter(String line, int end) {
  if (!line.startsWith(' ', end)) return null;
  final start = end + 1;
  if (_dashPartAt(line, start) != null) return null;
  var cursor = _upperEnd(line, start);
  if (cursor == start) return null;
  if (line.startsWith('-', cursor)) cursor = _upperEnd(line, cursor + 1);
  final digitsEnd = _digitsEnd(line, cursor);
  return digitsEnd == cursor ? null : line.substring(start, digitsEnd);
}

int _numberOf(String digits) => int.tryParse(digits) ?? _beyondAnyDoc;

int _digitsEnd(String text, int from) {
  var end = from;
  while (end < text.length && _isDigit(text.codeUnitAt(end))) {
    end++;
  }
  return end;
}

int _upperEnd(String text, int from) {
  var end = from;
  while (end < text.length && _isUpper(text.codeUnitAt(end))) {
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

// MARK: - Markdown reader

/// Returns, per line, whether it holds text to read: prose, and the lines of
/// a `mermaid` block between its fences.
List<bool> _readableLines(List<String> lines) {
  final scan = fenceScan(lines);
  final readable = <bool>[];
  var inMermaid = false;
  for (var i = 0; i < lines.length; i++) {
    final opened = scan.opens[i];
    if (opened != null) inMermaid = opened == 'mermaid';
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

typedef _Span = ({int start, int end});

/// Returns the link destinations of [line]: each `](...)` target and the
/// target of a reference definition.
List<_Span> _destinationsIn(String line) {
  final spans = <_Span>[?_definitionTarget(line)];
  var open = line.indexOf('](');
  while (open >= 0) {
    final start = open + 2;
    final end = _inlineTargetEnd(line, start);
    spans.add((start: start, end: end));
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
_Span? _definitionTarget(String line) {
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
  return (start: start, end: end);
}

bool _isBlank(int unit) => unit == 0x20 || unit == 0x09;
