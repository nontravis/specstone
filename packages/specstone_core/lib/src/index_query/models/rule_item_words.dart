/// One item of a rule-bearing section: its first file line, its item ID when
/// it holds one, and its normalized words (see `normalizedWordsOf`).
final class RuleItemWords {
  const new({required this.line, required this.itemId, required this.words});

  final int line;
  final String? itemId;
  final List<String> words;
}
