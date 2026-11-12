/// One code span of a line: the offsets of its first and one past its last
/// backtick, and the length of the backtick run that opens and closes it.
typedef CodeSpan = ({int start, int end, int ticks});

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
    if (_isEscaped(line, open)) {
      open = line.indexOf('`', open + 1);
      continue;
    }
    final ticks = _runLengthAt(line, open);
    final close = _closerOf(line, open + ticks, ticks);
    if (close < 0) {
      open = line.indexOf('`', open + ticks);
      continue;
    }
    spans.add((start: open, end: close + ticks, ticks: ticks));
    open = line.indexOf('`', close + ticks);
  }
  return spans;
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

/// Whether the character at [at] in [line] follows an odd run of backslashes.
bool _isEscaped(String line, int at) {
  var start = at;
  while (start > 0 && line.codeUnitAt(start - 1) == 0x5C) {
    start--;
  }
  return (at - start).isOdd;
}
