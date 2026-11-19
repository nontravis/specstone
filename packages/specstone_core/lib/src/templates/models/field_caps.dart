/// The sentence caps of one prose field, each key set or null.
///
/// A key an upper layer writes replaces the lower key whole; a key it leaves
/// out stays. The two maps are written as a pair in one layer file.
final class FieldCaps {
  const new({this.maxSentences, this.maxSentenceWords, this.maxSentenceChars});

  /// The most sentences the field's value may hold.
  final int? maxSentences;

  /// The most words of one sentence, by language key.
  final Map<String, int>? maxSentenceWords;

  /// The most characters of one sentence in a script with no spaces, by
  /// language key.
  final Map<String, int>? maxSentenceChars;

  /// Whether the caps limit the length of a sentence.
  bool get capsLength => maxSentenceWords != null || maxSentenceChars != null;

  /// Returns these caps with each key [upper] writes replacing the same key.
  FieldCaps mergedWith(FieldCaps upper) => FieldCaps(
    maxSentences: upper.maxSentences ?? maxSentences,
    maxSentenceWords: upper.maxSentenceWords ?? maxSentenceWords,
    maxSentenceChars: upper.maxSentenceChars ?? maxSentenceChars,
  );

  /// Returns the JSON object of the keys set.
  Map<String, Object> toJson() => {
    'maxSentences': ?maxSentences,
    'maxSentenceWords': ?maxSentenceWords,
    'maxSentenceChars': ?maxSentenceChars,
  };
}
