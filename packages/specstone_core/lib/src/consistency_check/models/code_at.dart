/// A code span's text and its file line: a catalog row's code, or a code a
/// requirement names.
final class CodeAt {
  const new({required this.code, required this.line});

  final String code;
  final int line;
}
