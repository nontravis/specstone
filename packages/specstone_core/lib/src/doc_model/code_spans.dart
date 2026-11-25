import 'package:specstone_core/src/doc_model/inline_holders.dart';
import 'package:specstone_core/src/doc_model/models/code_span.dart';

const _backtick = '`';
final RegExp _backtickRun = RegExp('$_backtick+');

/// Returns each code span of [line], in order.
///
/// A backtick that follows an odd run of backslashes is text, as CommonMark
/// reads it, and opens no span.
List<CodeSpan> codeSpansOf(String line) {
  // indexOf, not a RegExp: the regex engine tries every offset of a pattern
  // that opens with one character.
  final spans = <CodeSpan>[];
  var open = line.indexOf('`');
  while (open >= 0) {
    if (isEscaped(line, open)) {
      open = line.indexOf('`', open + 1);
      continue;
    }
    final ticks = _runLengthAt(line, open);
    final close = _closerOf(line, open + ticks, ticks);
    if (close < 0) {
      open = line.indexOf('`', open + ticks);
      continue;
    }
    spans.add(CodeSpan(start: open, end: close + ticks, ticks: ticks));
    open = line.indexOf('`', close + ticks);
  }
  return spans;
}

/// Returns [content], the text between a code span's backtick runs, as
/// CommonMark reads it: one space off each end when both ends hold one and
/// the content is not all spaces.
String codeSpanContentOf(String content) {
  final padded =
      content.length > 1 &&
      content.startsWith(' ') &&
      content.endsWith(' ') &&
      content.trim().isNotEmpty;
  return padded ? content.substring(1, content.length - 1) : content;
}

/// Returns [text] as a code span whose content CommonMark reads as [text]: a
/// backtick run one longer than any inside it, padded with a space each side
/// when an edge would otherwise be lost.
String codeSpanOf(String text) {
  var longest = 0;
  for (final run in _backtickRun.allMatches(text)) {
    if (run.end - run.start > longest) longest = run.end - run.start;
  }
  final fence = _backtick * (longest + 1);
  final isPadded =
      text.startsWith(_backtick) ||
      text.endsWith(_backtick) ||
      codeSpanContentOf(text) != text;
  final pad = isPadded ? ' ' : '';
  return '$fence$pad$text$pad$fence';
}

/// Returns the offset of the first run of exactly [ticks] backticks in [line]
/// at or after [from], or -1.
int _closerOf(String line, int from, int ticks) {
  var at = line.indexOf('`', from);
  while (at >= 0) {
    final run = _runLengthAt(line, at);
    if (run == ticks) return at;
    at = line.indexOf('`', at + run);
  }
  return -1;
}

/// Returns the length of the backtick run that starts at [at] in [line].
int _runLengthAt(String line, int at) {
  var end = at;
  while (end < line.length && line.codeUnitAt(end) == 0x60) {
    end++;
  }
  return end - at;
}
