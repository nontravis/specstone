/// One item that holds a repeated run.
final class RepeatItem {
  const new({
    required this.docPath,
    required this.name,
    required this.line,
    required this.item,
  });

  final String docPath;
  final String name;
  final int line;
  final String? item;
}
