/// One code span of a line: the offsets of its first and one past its last
/// backtick, and the length of the backtick run that opens and closes it.
final class CodeSpan {
  const new({required this.start, required this.end, required this.ticks});

  final int start;
  final int end;
  final int ticks;
}
