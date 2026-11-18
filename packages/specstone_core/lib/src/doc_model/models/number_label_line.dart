/// A number label as written, and the 0-based line of the text it starts on.
final class NumberLabelLine {
  const new({required this.line, required this.written});

  final int line;
  final String written;
}
