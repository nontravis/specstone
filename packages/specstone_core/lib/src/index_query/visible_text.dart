import 'dart:math';

import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show holdsLinkSyntax, parseMarkdownTreeByBlock;
import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:specstone_core/src/doc_model/text_scan.dart';
import 'package:specstone_core/src/index_query/link_blocks.dart'
    show leafTextOf;
import 'package:specstone_core/src/index_query/link_places.dart'
    show parserReadSourcesOf;
import 'package:specstone_core/src/index_query/link_scan.dart'
    show LinkSource, linkSourcesOf;

/// The text of a body a reader never sees: the markup of each inline link,
/// reference link, and image the markdown parser reads, and each link
/// reference definition it reads.
///
/// A link or image hides what lies outside its text: the `[` or `![` before
/// it, and everything from its `]` on. A definition hides its whole span.
final class HiddenText {
  const new _(this._text, this._firstLine, this._lineStarts, this._ranges);

  /// Reads what [lfBody], a doc text with LF line ends whose first line is file
  /// line [firstLine], hides.
  ///
  /// A body the parser fails on, or that holds no link syntax, hides nothing.
  /// The scan places the parser's links, as `linkPlacesOf` does, so a link the
  /// parser reads and the scan cannot place hides nothing.
  factory of(String lfBody, {required int firstLine}) {
    if (!holdsLinkSyntax(lfBody)) return none;
    final tree = parseMarkdownTreeByBlock(lfBody);
    if (tree == null) return none;
    final sources = parserReadSourcesOf(
      linkSourcesOf(lfBody, firstLine: firstLine),
      tree,
    );
    final ranges = [
      for (final source in sources) ..._markupOf(lfBody, source),
      ...leafTextOf(lfBody).definitionSpans,
    ];
    return HiddenText._(
      lfBody,
      firstLine,
      _lineStartsOf(lfBody),
      _merged(ranges),
    );
  }

  /// The text that hides nothing.
  static const none = HiddenText._('', 0, [], []);

  final String _text;
  final int _firstLine;

  /// The offset of each line's first code unit.
  final List<int> _lineStarts;

  /// The hidden ranges, sorted and disjoint.
  final List<TextRange> _ranges;

  /// Returns the code points that file lines [firstLine] to [lastLine], both
  /// included, hide, with the line feeds that join those lines.
  int codePointsOn(int firstLine, int lastLine) {
    final first = max(firstLine - _firstLine, 0);
    final last = lastLine - _firstLine;
    if (_ranges.isEmpty || last < first || first >= _lineStarts.length) {
      return 0;
    }
    final from = _lineStarts[first];
    final to = last + 1 < _lineStarts.length
        ? _lineStarts[last + 1] - 1
        : _text.length;
    var count = 0;
    for (var i = _firstEndingAfter(from); i < _ranges.length; i++) {
      final range = _ranges[i];
      if (range.start >= to) break;
      final clipped = _text.substring(
        max(range.start, from),
        min(range.end, to),
      );
      count += clipped.length - scanText(clipped).pairs;
    }
    return count;
  }

  /// Returns the index of the first range that ends after [offset].
  int _firstEndingAfter(int offset) {
    var low = 0;
    var high = _ranges.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_ranges[middle].end > offset) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low;
  }
}

const _bang = 0x21;
const _lineFeed = 0x0A;

/// Returns the ranges [source] hides: its opener, and its text's closer to its
/// end; an autolink and a bare URL have no bracketed text and hide none.
List<TextRange> _markupOf(String body, LinkSource source) {
  final textEnd = source.textEnd;
  if (textEnd == null) return const [];
  final opener = body.codeUnitAt(source.offset) == _bang ? 2 : 1;
  return [
    TextRange(start: source.offset, end: source.offset + opener),
    TextRange(start: textEnd, end: source.end),
  ];
}

List<int> _lineStartsOf(String body) => [
  0,
  for (var i = 0; i < body.length; i++)
    if (body.codeUnitAt(i) == _lineFeed) i + 1,
];

/// Returns [ranges] as sorted, disjoint ranges, an overlap joined.
List<TextRange> _merged(List<TextRange> ranges) {
  ranges.sort((a, b) => a.start - b.start);
  final merged = <TextRange>[];
  for (final range in ranges) {
    final last = merged.isEmpty ? null : merged.last;
    if (last == null || range.start > last.end) {
      merged.add(range);
    } else if (range.end > last.end) {
      merged.last = TextRange(start: last.start, end: range.end);
    }
  }
  return merged;
}
