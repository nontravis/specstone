/// One stored item of a rule-bearing section: its doc's DocPath, its first
/// file line, its item ID when it holds one, and its normalized words.
final class IndexedItemWords {
  const new({
    required this.docPath,
    required this.line,
    required this.itemId,
    required this.words,
  });

  final String docPath;
  final int line;
  final String? itemId;
  final List<String> words;
}
