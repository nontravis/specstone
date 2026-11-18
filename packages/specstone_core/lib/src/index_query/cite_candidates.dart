import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show Doc;
import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show holdsLinkSyntax;
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show atxHeadingOf;
import 'package:specstone_core/src/doc_model/models/code_span.dart';
import 'package:specstone_core/src/doc_model/models/destination_kind.dart';
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/models/name_mention.dart';
import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:specstone_core/src/doc_model/name_mentions.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show itemIdRunAt, proseTrimmedPath;
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show sectionKeyOf;
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:specstone_core/src/index_query/matrix_rows.dart'
    show MatrixLine, TestRow;

/// A cite candidate of a typed doc's body: the doc name or
/// path as written, less its `#<section key>`, at its 1-based file `line`,
/// with the section key it names, null when it names none, and the item IDs
/// of the run right after it.
///
/// A candidate holds no resolution: `check` and the cite pass judge it when
/// they run.
typedef CiteCandidate = ({
  int line,
  String written,
  String? sectionKey,
  List<String> itemIds,
});

/// One item ID of a cite form: its 0-based column on the form's line and the
/// ID as written.
typedef CiteItemAt = ({int column, String itemId});

/// A cite candidate with its place on its line, which the cite pass rewrites.
///
/// `start` and `end` are the 0-based columns the doc part spans, its code
/// span's backticks, `#key`, and header span included; `runAt` is the column
/// of the first ID of its run, a lettered one included, or `end` when the run
/// is empty; `items` holds each item ID it owns, repeats included.
typedef CiteForm = ({
  CiteCandidate candidate,
  int start,
  int end,
  int runAt,
  List<CiteItemAt> items,
});

/// Returns the cite candidates of [lfText], a typed doc with LF line ends, in
/// file order.
///
/// Each doc mention `nameMentionsInFile` reads from the body outside fenced
/// code, no lone-word span among them, is a candidate, bar one inside a link
/// or a link reference's destination, and one inside a code span it does not
/// fill, such as a path in quoted CLI output. The section key is the `#key`
/// after the mention, or, after a path, the header of a code span that follows
/// it, such as
/// `` `## Error envelope` ``. The item IDs are the run the reference grammar
/// reads right after the candidate on its line (`itemIdRunAt`): an ID outside
/// the run is no item of the candidate. An item ID is a token of one of
/// [idPrefixes], the merged set's item ID prefixes (`itemIdPrefixesOf`).
///
/// A mention on a 1-based file line of [skipLines] is no candidate.
List<CiteCandidate> citeCandidatesOf(
  String lfText, {
  required Set<String> idPrefixes,
  Set<int> skipLines = const {},
}) => [
  for (final form in citeFormsOf(
    lfText,
    idPrefixes: idPrefixes,
    skipLines: skipLines,
  ))
    form.candidate,
];

/// Returns the file lines of the test rows of [lines], the matrix lines of a
/// record: the lines whose code span holds a test literal, no cite candidate.
///
/// A skip row and a line that is no row stay out: their text can cite.
Set<int> testRowLinesOf(List<MatrixLine> lines) => {
  for (final line in lines)
    if (line is TestRow) line.line,
};

/// Returns the cite candidates of [lfText] as [citeCandidatesOf] reads them,
/// each with its place on its line.
List<CiteForm> citeFormsOf(
  String lfText, {
  required Set<String> idPrefixes,
  Set<int> skipLines = const {},
}) {
  final mentions = nameMentionsInFile(lfText, markdownExtension);
  if (mentions.isEmpty) return const [];
  final body = Doc.parse(lfText).afterFrontmatter;
  final firstLine = _lineFeedsIn(lfText, lfText.length - body.length) + 1;
  final lines = _LineIndex(body);
  final ranges = _linkRangesOf(body, firstLine);
  final kept = <_Kept>[];
  for (final mention in mentions) {
    if (skipLines.contains(mention.line)) continue;
    final offset = lines.offsetOf(mention.line - firstLine, mention.column);
    if (offset == null || ranges.covers(offset)) continue;
    final line = lines.lineOf(mention.line - firstLine);
    final spans = codeSpansOf(line);
    final extent = _extentOf(mention, line, spans);
    if (_isInSpan(spans, mention, extent.end)) continue;
    kept.add((
      mention: mention,
      offset: offset,
      line: line,
      spans: spans,
      extent: extent,
    ));
  }
  return [for (final it in kept) _formOf(it, idPrefixes: idPrefixes)];
}

/// A mention that is a candidate, with the line and code spans it sits on, and
/// its body offset.
typedef _Kept = ({
  NameMention mention,
  int offset,
  String line,
  List<CodeSpan> spans,
  ({String? key, int end}) extent,
});

/// Returns the `#key` and the end column of [mention]'s doc part on [line],
/// its closing backticks and a header span right after a path included.
({String? key, int end}) _extentOf(
  NameMention mention,
  String line,
  List<CodeSpan> spans,
) {
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
  return (key: key, end: end);
}

/// Whether [mention], whose doc part ends at [end], sits inside a code span it
/// does not fill, where no link can stand.
bool _isInSpan(List<CodeSpan> spans, NameMention mention, int end) {
  final holder = _spanHolding(spans, mention.column);
  return holder != null && !_fills(holder, mention.column, end);
}

bool _fills(CodeSpan holder, int column, int end) =>
    holder.start + holder.ticks == column && holder.end <= end;

CiteForm _formOf(_Kept kept, {required Set<String> idPrefixes}) {
  final (:mention, :line, :spans, extent: (:key, :end), offset: _) = kept;
  final run = itemIdRunAt(line, end, prefixes: idPrefixes);
  final items = [
    for (final item in run)
      if (item.id is ItemId) (column: item.at, itemId: item.id.written),
  ];
  final holder = _spanHolding(spans, mention.column);
  return (
    candidate: (
      line: mention.line,
      written: mention.address.docPart,
      sectionKey: key,
      itemIds: [
        ...{for (final item in items) item.itemId},
      ],
    ),
    start: holder?.start ?? mention.column,
    end: end,
    runAt: run.firstOrNull?.at ?? end,
    items: items,
  );
}

/// The code span of [spans] whose text holds [column], or null.
CodeSpan? _spanHolding(List<CodeSpan> spans, int column) {
  for (final span in spans) {
    if (span.start < column && column < span.end) return span;
  }
  return null;
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
  for (final CodeSpan(:start, end: spanEnd, :ticks) in spans) {
    if (start < column && column < spanEnd && spanEnd - ticks == end) {
      return spanEnd;
    }
  }
  return null;
}

/// Returns the offset after the section header span right after the path that
/// ends at [end] of [line], or null when none follows.
int? headerSpanEndAfter(String line, List<CodeSpan> spans, int end) =>
    _headerSpanAfter(line, spans, end)?.$2;

/// Returns the section key of the header the code span right after [end]
/// holds, such as `## Error envelope`, and the offset after that span.
(String, int)? _headerSpanAfter(String line, List<CodeSpan> spans, int end) {
  var at = end;
  while (at < line.length && line.codeUnitAt(at) == _space) {
    at++;
  }
  for (final CodeSpan(:start, end: spanEnd, :ticks) in spans) {
    if (start != at) continue;
    final heading = atxHeadingOf(
      line.substring(start + ticks, spanEnd - ticks),
    );
    final key = heading == null ? '' : sectionKeyOf(heading.text);
    return key.isEmpty ? null : (key, spanEnd);
  }
  return null;
}

/// The body ranges a link or a link reference's destination takes.
final class _LinkRanges {
  new(List<TextRange> ranges)
    : _sorted = [...ranges]..sort((a, b) => a.start - b.start) {
    var furthest = 0;
    for (final range in _sorted) {
      if (range.end > furthest) furthest = range.end;
      _furthestEnd.add(furthest);
    }
  }

  final List<TextRange> _sorted;
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
    for (final source in scan.sources)
      TextRange(start: source.offset, end: source.end),
    for (final (:start, :end, link: _, :kind) in scan.destinations)
      if (kind == DestinationKind.definition) TextRange(start: start, end: end),
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
