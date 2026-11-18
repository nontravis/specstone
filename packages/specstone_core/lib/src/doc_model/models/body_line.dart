/// One line of a held section's body.
///
/// `line` is its 1-based line in the text read; `fenced` is true for fenced
/// code content and the fence lines.
final class BodyLine {
  const new({required this.text, required this.line, required this.fenced});

  final String text;
  final int line;
  final bool fenced;
}
