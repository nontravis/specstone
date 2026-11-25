import 'package:specstone_core/src/templates/models/pattern_entry.dart';
import 'package:specstone_core/src/templates/models/sentence_caps.dart';

/// The most characters one item may hold when no layer sets `max_item_chars`.
const defaultMaxItemChars = 600;

/// The doc-level lint settings of a merged doc type.
///
/// A null limit or word list means no layer defines it.
final class MergedLint {
  const new({
    this.maxChars,
    this.maxLines,
    this.maxItemChars,
    this.bannedWords,
    this.allowedWords,
    this.bannedPatterns,
    this.requiredFieldGroups,
    this.maxSentenceWords,
    this.maxSentenceChars,
    this.traceNoteLast,
    this.titleNoNumber,
  });

  /// The doc-level character limit.
  final int? maxChars;

  /// The doc-level line ceiling.
  final int? maxLines;

  /// The most characters one item may hold, when a layer sets it.
  final int? maxItemChars;

  /// The most characters one item may hold: [maxItemChars], else the default.
  int get itemCharLimit => maxItemChars ?? defaultMaxItemChars;

  /// The banned words.
  final List<String>? bannedWords;

  /// The allowed words.
  final List<String>? allowedWords;

  /// The banned patterns, merged by `id`.
  final List<PatternEntry>? bannedPatterns;

  /// The groups of fields a doc must carry at least one of each.
  final List<List<String>>? requiredFieldGroups;

  /// The word caps after the merge, built-in entries included; null when no
  /// layer writes `max_sentence_words`.
  final SentenceCaps? maxSentenceWords;

  /// The word caps `check` applies: [maxSentenceWords], else the built-in ones.
  SentenceCaps get sentenceWordCaps => maxSentenceWords ?? builtInSentenceWords;

  /// The character caps after the merge, built-in entries included; null when
  /// no layer writes `max_sentence_chars`.
  final SentenceCaps? maxSentenceChars;

  /// The character caps `check` applies: [maxSentenceChars], else the built-in
  /// ones.
  SentenceCaps get sentenceCharCaps => maxSentenceChars ?? builtInSentenceChars;

  /// Whether a trace note must close its item; null when no layer sets it.
  final bool? traceNoteLast;

  /// Whether a trace note must close its item: [traceNoteLast], else `true`.
  bool get isTraceNoteLast => traceNoteLast ?? true;

  /// Whether a digit in the `# ` title line is a finding; null when no layer
  /// sets it.
  final bool? titleNoNumber;

  /// Returns a copy with each non-null argument replacing its property.
  MergedLint copyWith({
    int? maxChars,
    int? maxLines,
    int? maxItemChars,
    List<String>? bannedWords,
    List<String>? allowedWords,
    List<PatternEntry>? bannedPatterns,
    List<List<String>>? requiredFieldGroups,
    SentenceCaps? maxSentenceWords,
    SentenceCaps? maxSentenceChars,
    bool? traceNoteLast,
    bool? titleNoNumber,
  }) => MergedLint(
    maxChars: maxChars ?? this.maxChars,
    maxLines: maxLines ?? this.maxLines,
    maxItemChars: maxItemChars ?? this.maxItemChars,
    bannedWords: bannedWords ?? this.bannedWords,
    allowedWords: allowedWords ?? this.allowedWords,
    bannedPatterns: bannedPatterns ?? this.bannedPatterns,
    requiredFieldGroups: requiredFieldGroups ?? this.requiredFieldGroups,
    maxSentenceWords: maxSentenceWords ?? this.maxSentenceWords,
    maxSentenceChars: maxSentenceChars ?? this.maxSentenceChars,
    traceNoteLast: traceNoteLast ?? this.traceNoteLast,
    titleNoNumber: titleNoNumber ?? this.titleNoNumber,
  );

  /// Returns the JSON object of this lint with only the keys set.
  ///
  /// The object is empty when no layer writes a lint key.
  Map<String, Object> toJson() => {
    'maxChars': ?maxChars,
    'maxLines': ?maxLines,
    'maxItemChars': ?maxItemChars,
    'bannedWords': ?bannedWords,
    'allowedWords': ?allowedWords,
    'bannedPatterns': ?bannedPatterns?.map((p) => p.toJson()).toList(),
    'requiredFieldGroups': ?requiredFieldGroups,
    'maxSentenceWords': ?maxSentenceWords?.toJson(),
    'maxSentenceChars': ?maxSentenceChars?.toJson(),
    'traceNoteLast': ?traceNoteLast,
    'titleNoNumber': ?titleNoNumber,
  };
}
