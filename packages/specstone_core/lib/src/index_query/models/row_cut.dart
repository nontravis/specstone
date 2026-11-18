/// A body cut to its first table's leading rows, and the number of lines the
/// cut prints.
final class RowCut {
  const new({required this.body, required this.lineCount});

  final String body;
  final int lineCount;
}
