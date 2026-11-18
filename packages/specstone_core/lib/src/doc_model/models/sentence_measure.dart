/// What the check counts in one sentence.
///
/// `language` is the key of its cap map. A sentence that `countsChars` has
/// `chars` and `runs` and no `words`; any other has `words` alone. `runs`
/// holds the other-script runs and code spans, which `weightedChars` weighs.
final class SentenceMeasure {
  const new({
    required this.language,
    required this.countsChars,
    required this.words,
    required this.chars,
    required this.runs,
  });

  final String language;
  final bool countsChars;
  final int words;
  final int chars;
  final int runs;
}
