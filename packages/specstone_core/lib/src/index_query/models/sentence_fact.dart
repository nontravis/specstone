/// One sentence of an item as `check` counts it: its language and counts, and
/// whether a `###` heading ends it.
///
/// `countsChars` says which counts the language reads; see `SentenceMeasure`.
final class SentenceFact {
  const new({
    required this.language,
    required this.countsChars,
    required this.words,
    required this.chars,
    required this.runs,
    required this.isHeading,
  });

  final String language;
  final bool countsChars;
  final int words;
  final int chars;
  final int runs;
  final bool isHeading;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is SentenceFact &&
      other.language == language &&
      other.countsChars == countsChars &&
      other.words == words &&
      other.chars == chars &&
      other.runs == runs &&
      other.isHeading == isHeading;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode =>
      Object.hash(language, countsChars, words, chars, runs, isHeading);
}
