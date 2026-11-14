import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc;
import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show holdsLinkSyntax;
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show atxHeadingOf;
import 'package:specstone_core/src/doc_model/name_mentions.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show DestinationKind, ItemId, proseTrimmedPath, readItemIdAt;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show sectionKeyOf;
import 'package:specstone_core/src/index_query/link_scan.dart';

/// A cite candidate of a typed doc's body (doc_model RULE-48): the doc name or
/// path as written, less its `#<section key>`, at its 1-based file `line`,
/// with the section key it names, null when it names none, and the item IDs
/// after it on its line.
///
/// A candidate holds no resolution: `check` and the cite pass judge it when
/// they run (index_query INV-86).
typedef CiteCandidate = ({
  int line,
  String written,
  String? sectionKey,
  List<String> itemIds,
});

/// Returns the cite candidates of [lfText], a typed doc with LF line ends, in
/// file order.
///
/// Each doc mention `docMentionsInFile` reads from the body outside fenced
/// code is a candidate, bar one inside a link or a link reference's
/// destination. The section key is the `#key` after the mention, or, after a
/// path, the header of a code span that follows it, such as `` `## Error
/// envelope` ``. The item IDs are the IDs the reference grammar reads in the
/// line's prose after the candidate, up to the next citation, a link or
/// another candidate, so the nearest citation before an ID owns it
/// (setup_migration `apply_steps_and_pins` E47).
List<CiteCandidate> citeCandidatesOf(String lfText) {
  final mentions = docMentionsInFile(lfText, markdownExtension);
  if (mentions.isEmpty) return const [];
  final body = Doc.parse(lfText).afterFrontmatter;
  final firstLine = _lineFeedsIn(lfText, lfText.length - body.length) + 1;
  final lines = _LineIndex(body);
  final ranges = _linkRangesOf(body, firstLine);
  final kept = <(NameMention, int)>[];
  for (final mention in mentions) {
    final offset = lines.offsetOf(mention.line - firstLine, mention.column);
    if (offset != null && !ranges.covers(offset)) kept.add((mention, offset));
  }
  final boundaries = [...ranges.starts, for (final (_, offset) in kept) offset]
    ..sort();
  return [
    for (final (mention, offset) in kept)
      _candidateOf(
        mention,
        lines.lineOf(mention.line - firstLine),
        nextBoundary: _firstAfter(boundaries, offset),
        lineStart: offset - mention.column,
      ),
  ];
}

CiteCandidate _candidateOf(
  NameMention mention,
  String line, {
  required int? nextBoundary,
  required int lineStart,
}) {
  final spans = codeSpansOf(line);
  var end = mention.column + mention.text.length;
  var key = _nonEmpty(mention.address.sectionKey);
  if (key == null) {
    final keyed = _keyAfter(line, end);
    if (keyed != null) (key, end) = keyed;
  }
  end = _closedBy(spans, mention.column, end) ?? end;
  if (key == null && mention.text.endsWith(markdownExtension)) {
    final header = _headerSpanAfter(line, spans, end);
    if (header != null) (key, end) = header;
  }
  final stop = nextBoundary == null
      ? line.length
      : (nextBoundary - lineStart).clamp(end, line.length);
  return (
    line: mention.line,
    written: mention.address.docPart,
    sectionKey: key,
    itemIds: _itemIdsIn(_proseOf(line, spans, from: end).substring(end, stop)),
  );
}

String? _nonEmpty(String? text) => text == null || text.isEmpty ? null : text;

/// Returns the `#key` of a path written at [end] of [line] and the offset
/// after it, or null when none follows.
(String, int)? _keyAfter(String line, int end) {
  if (end >= line.length || line.codeUnitAt(end) != _hash) return null;
  var stop = end + 1;
  while (stop < line.length && !endsDocPath(line.codeUnitAt(stop))) {
    stop++;
  }
  final key = proseTrimmedPath(line.substring(end + 1, stop));
  return key.isEmpty ? null : (key, end + 1 + key.length);
}

/// Returns the offset after the closing backticks of the code span that holds
/// [column] when a mention that ends at [end] fills it to its closer, else
/// null.
int? _closedBy(List<CodeSpan> spans, int column, int end) {
  for (final (:start, end: spanEnd, :ticks) in spans) {
    if (start < column && column < spanEnd && spanEnd - ticks == end) {
      return spanEnd;
    }
  }
  return null;
}

/// Returns the section key of the header the code span right after [end]
/// holds, such as `## Error envelope`, and the offset after that span.
(String, int)? _headerSpanAfter(String line, List<CodeSpan> spans, int end) {
  var at = end;
  while (at < line.length && line.codeUnitAt(at) == _space) {
    at++;
  }
  for (final (:start, end: spanEnd, :ticks) in spans) {
    if (start != at) continue;
    final heading = atxHeadingOf(
      line.substring(start + ticks, spanEnd - ticks),
    );
    final key = heading == null ? '' : sectionKeyOf(heading.text);
    return key.isEmpty ? null : (key, spanEnd);
  }
  return null;
}

/// Returns [line] with each code span that starts at [from] or later blanked,
/// so an ID in a code span is no item ID.
String _proseOf(String line, List<CodeSpan> spans, {required int from}) {
  var prose = line;
  for (final (:start, :end, ticks: _) in spans) {
    if (start < from) continue;
    prose = prose.replaceRange(start, end, ' ' * (end - start));
  }
  return prose;
}

/// A prefix of an item ID in prose: capital-led words joined by `-`, then an
/// optional `-`, before a digit; the grammar reads the digits.
final _idPrefix = RegExp(
  r'(?<![\p{L}\p{N}])[A-Z][A-Za-z]*(?:-[A-Z][A-Za-z]*)*-?(?=\d)',
  unicode: true,
);

List<String> _itemIdsIn(String prose) {
  final ids = <String>[];
  for (final match in _idPrefix.allMatches(prose)) {
    final id = readItemIdAt(prose, match.start, match.group(0)!);
    if (id is ItemId && !ids.contains(id.written)) ids.add(id.written);
  }
  return ids;
}

/// The offset of the first element of the sorted [offsets] after [offset].
int? _firstAfter(List<int> offsets, int offset) {
  var low = 0;
  var high = offsets.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (offsets[mid] > offset) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low < offsets.length ? offsets[low] : null;
}

/// The body ranges a link or a link reference's destination takes.
final class _LinkRanges {
  new(List<BodyRange> ranges)
    : starts = [for (final r in ranges) r.start]..sort(),
      _sorted = [...ranges]..sort((a, b) => a.start - b.start) {
    var furthest = 0;
    for (final range in _sorted) {
      if (range.end > furthest) furthest = range.end;
      _furthestEnd.add(furthest);
    }
  }

  /// The start of each range, sorted.
  final List<int> starts;

  final List<BodyRange> _sorted;
  final _furthestEnd = <int>[];

  /// Whether a range holds [offset].
  bool covers(int offset) {
    var low = 0;
    var high = _sorted.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_sorted[mid].start > offset) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low > 0 && _furthestEnd[low - 1] > offset;
  }
}

_LinkRanges _linkRangesOf(String body, int firstLine) {
  if (!holdsLinkSyntax(body)) return _LinkRanges(const []);
  final scan = linkScanOf(body, firstLine: firstLine);
  return _LinkRanges([
    for (final (:offset, :end, line: _, shown: _, angle: _, textEnd: _)
        in scan.sources)
      (start: offset, end: end),
    for (final (:start, :end, link: _, :kind) in scan.destinations)
      if (kind == DestinationKind.definition) (start: start, end: end),
  ]);
}

/// The lines of a body, by index, and where each starts.
final class _LineIndex {
  new(this._body) {
    _starts.add(0);
    for (var i = 0; i < _body.length; i++) {
      if (_body.codeUnitAt(i) == _lineFeed) _starts.add(i + 1);
    }
  }

  final String _body;
  final _starts = <int>[];

  /// Returns the body offset of [column] on the line at [index], or null when
  /// the body has no such line.
  int? offsetOf(int index, int column) =>
      index < 0 || index >= _starts.length ? null : _starts[index] + column;

  /// Returns the line at [index], without its line feed.
  String lineOf(int index) {
    final end = index + 1 < _starts.length
        ? _starts[index + 1] - 1
        : _body.length;
    return _body.substring(_starts[index], end);
  }
}

int _lineFeedsIn(String text, int to) {
  var count = 0;
  for (var i = 0; i < to; i++) {
    if (text.codeUnitAt(i) == _lineFeed) count++;
  }
  return count;
}

const _hash = 0x23;
const _space = 0x20;
const _lineFeed = 0x0A;
