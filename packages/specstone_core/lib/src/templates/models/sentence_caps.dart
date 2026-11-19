/// A language key mapped to a sentence cap, a whole number of 1 or more.
///
/// Every map holds `default`, which a language with no entry of its own takes.
final class SentenceCaps {
  const new(this.entries);

  /// The cap of each language key.
  final Map<String, int> entries;

  /// Returns the cap of [language], else the `default` cap.
  int capFor(String language) =>
      entries[language] ??
      entries[_defaultLanguage] ??
      (throw StateError('a sentence cap map holds no $_defaultLanguage'));

  /// Returns these caps with each entry of [upper] replacing the same entry.
  SentenceCaps mergedWith(Map<String, int>? upper) =>
      upper == null ? this : SentenceCaps({...entries, ...upper});

  /// Returns the JSON object of every language key and its cap.
  Map<String, Object> toJson() => {...entries};

  static const _defaultLanguage = 'default';
}

/// The most words of one sentence when no layer sets `max_sentence_words`.
const builtInSentenceWords = SentenceCaps({'default': 25, 'ko': 17});

/// The most characters of one sentence in a script with no spaces when no
/// layer sets `max_sentence_chars`.
const builtInSentenceChars = SentenceCaps({
  'default': 100,
  'th': 100,
  'ja': 60,
  'zh': 45,
});
