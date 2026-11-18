import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc.dart' show fencedLines;
import 'package:specstone_core/src/doc_model/models/code_span.dart';

final _htmlComment = RegExp(r'<!--[\s\S]*?-->');

/// Returns [text] with every HTML comment removed, except one whose `<!--`
/// sits in fenced code or an inline code span.
///
/// A comment runs to the first `-->` whatever it holds, so a backtick or a
/// fence line inside a comment never hides it.
String removeHtmlComments(String text) {
  final kept = StringBuffer();
  var from = 0;
  for (final (:start, :end) in commentRangesOf(text)) {
    kept.write(text.substring(from, start));
    from = end;
  }
  return (kept..write(text.substring(from))).toString();
}

/// Returns the offsets of each HTML comment of [text] that
/// [removeHtmlComments] removes, in order.
List<({int start, int end})> commentRangesOf(String text) {
  final code = _codeRanges(text);
  final ranges = <({int start, int end})>[];
  var search = 0;
  while (true) {
    final comment = _htmlComment.allMatches(text, search).firstOrNull;
    if (comment == null) break;
    if (code.any((r) => r.start <= comment.start && comment.start < r.end)) {
      search = comment.start + 1;
      continue;
    }
    ranges.add((start: comment.start, end: comment.end));
    search = comment.end;
  }
  return ranges;
}

/// Returns the offsets of each fenced line and each inline code span of [text].
List<({int start, int end})> _codeRanges(String text) {
  final lines = text.split('\n');
  final fenced = fencedLines([
    for (final line in lines) line.replaceFirst(RegExp(r'\r$'), ''),
  ]);
  final ranges = <({int start, int end})>[];
  var offset = 0;
  for (var i = 0; i < lines.length; i++) {
    if (fenced[i]) {
      ranges.add((start: offset, end: offset + lines[i].length));
    } else {
      for (final CodeSpan(:start, :end) in codeSpansOf(lines[i])) {
        ranges.add((start: offset + start, end: offset + end));
      }
    }
    offset += lines[i].length + 1;
  }
  return ranges;
}
