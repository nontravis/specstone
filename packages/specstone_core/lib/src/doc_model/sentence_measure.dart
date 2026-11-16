import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/inline_holders.dart';

/// What the check counts in one sentence.
///
/// `language` is the key of its cap map. A sentence that `countsChars` has
/// `chars` and `runs` and no `words`; any other has `words` alone. `runs`
/// holds the other-script runs and code spans, which [weightedChars] weighs.
typedef SentenceMeasure = ({
  String language,
  bool countsChars,
  int words,
  int chars,
  int runs,
});

const _defaultLanguage = 'default';

/// Stands in for a code span, which counts as one word or one run whatever
/// its letters; a Unicode noncharacter, so no text holds it.
final _spanMark = String.fromCharCode(0xFDD0);

/// Code points below this one belong to no script `measureSentence` votes on.
const _firstVotedCodePoint = 0x0370;

/// The runs of other scripts and code spans each count the cap over this.
const _runWeightDivisor = 25;

/// The Thai and Lao AM vowels, which add no character.
final _amVowels = String.fromCharCodes(const [0x0E33, 0x0EB3]);

const _thai = 'th';
const _lao = 'lo';
const _khmer = 'km';
const _myanmar = 'my';
const _chinese = 'zh';
const _japanese = 'ja';
const _korean = 'ko';
const _arabic = 'ar';
const _hebrew = 'he';
const _hindi = 'hi';
const _greek = 'el';

const _kanaScripts = ['Hiragana', 'Katakana'];

/// The Unicode scripts of each language with no spaces between its words;
/// Han and kana share one entry, which reads `ja` when kana is present.
const Map<String, List<String>> _noSpaceScriptNames = {
  _thai: ['Thai'],
  _lao: ['Lao'],
  _khmer: ['Khmer'],
  _myanmar: ['Myanmar'],
  _chinese: ['Han', ..._kanaScripts],
};

/// The Unicode script of each language that spaces its words and has an entry
/// of its own.
const Map<String, List<String>> _spacedScriptNames = {
  _korean: ['Hangul'],
  _arabic: ['Arabic'],
  _hebrew: ['Hebrew'],
  _hindi: ['Devanagari'],
  _greek: ['Greek'],
};

typedef _Script = ({String language, RegExp letters});

RegExp _lettersOf(List<String> scripts) => RegExp(
  '(?=\\p{L})[${scripts.map((name) => '\\p{Script=$name}').join()}]',
  unicode: true,
);

List<_Script> _votesOf(Map<String, List<String>> names) => [
  for (final MapEntry(:key, :value) in names.entries)
    (language: key, letters: _lettersOf(value)),
];

final List<_Script> _noSpaceScripts = _votesOf(_noSpaceScriptNames);
final List<_Script> _spacedScripts = _votesOf(_spacedScriptNames);
final RegExp _kanaLetters = _lettersOf(_kanaScripts);

final String _noSpaceClass = [
  for (final name in _noSpaceScriptNames.values.expand((names) => names))
    '\\p{Script_Extensions=$name}',
].join();

/// A code span, a run of no-space script, or a run of anything else.
final _runs = RegExp(
  '(?<span>$_spanMark)|(?<scripted>[$_noSpaceClass]+)|'
  '(?<other>[^$_noSpaceClass$_spanMark]+)',
  unicode: true,
);

final _whitespaceRuns = RegExp(r'\s+');
final _wordPart = RegExp('[\\p{L}\\p{Nd}$_spanMark]', unicode: true);
final _letterOrDigit = RegExp(r'[\p{L}\p{Nd}]', unicode: true);
final _uncounted = RegExp('[\\p{M}\\p{Cf}$_amVowels]', unicode: true);

/// Emphasis marks: every `*`, and each `_` that does not join two word
/// characters.
final _emphasisMarks = RegExp(
  r'\*+|(?<![\p{L}\p{Nd}])_+|_+(?![\p{L}\p{Nd}])',
  unicode: true,
);

/// Measures [markdownSentence] by the script of its letters.
///
/// Code spans, links, and emphasis marks are read first: a span is one token,
/// a link is its text, and the marks drop. Letters inside a span take no part
/// in the script vote.
SentenceMeasure measureSentence(String markdownSentence) {
  final text = _plainText(markdownSentence);
  final noSpace = _isVotable(text) ? _voteOf(text, _noSpaceScripts) : null;
  if (noSpace != null) {
    final language = noSpace == _chinese && _kanaLetters.hasMatch(text)
        ? _japanese
        : noSpace;
    final (:chars, :runs) = _charsAndRuns(text);
    return (
      language: language,
      countsChars: true,
      words: 0,
      chars: chars,
      runs: runs,
    );
  }
  final language =
      (_isVotable(text) ? _voteOf(text, _spacedScripts) : null) ??
      _defaultLanguage;
  return (
    language: language,
    countsChars: false,
    words: _wordsIn(text),
    chars: 0,
    runs: 0,
  );
}

/// Returns the character total of [measure] under the character [cap].
///
/// Each run of another script or code span weighs the cap over 25, and the
/// total rounds up to a whole number.
int weightedChars(SentenceMeasure measure, int cap) =>
    measure.chars +
    (measure.runs * cap + _runWeightDivisor - 1) ~/ _runWeightDivisor;

/// Returns [markdown] with each code span as one mark, each link as its text,
/// and the emphasis marks dropped.
String _plainText(String markdown) {
  final text = markdown.replaceAll(_spanMark, '');
  return _linkTexts(_spansAsMarks(text)).replaceAll(_emphasisMarks, '');
}

String _spansAsMarks(String text) {
  final buffer = StringBuffer();
  var from = 0;
  for (final span in codeSpansOf(text)) {
    buffer
      ..write(text.substring(from, span.start))
      ..write(_spanMark);
    from = span.end;
  }
  return (buffer..write(text.substring(from))).toString();
}

String _linkTexts(String text) {
  final buffer = StringBuffer();
  var from = 0;
  var i = text.indexOf('[');
  while (i >= 0) {
    final link = isEscaped(text, i) ? null : linkAt(text, i);
    if (link == null) {
      i = text.indexOf('[', i + 1);
      continue;
    }
    buffer
      ..write(text.substring(from, i))
      ..write(text.substring(i + 1, link.textEnd));
    from = link.end;
    i = text.indexOf('[', from);
  }
  return (buffer..write(text.substring(from))).toString();
}

/// Whether [text] holds a code point of a script the vote reads.
bool _isVotable(String text) =>
    text.codeUnits.any((unit) => unit >= _firstVotedCodePoint);

/// Returns the language of the script in [scripts] with the most letters in
/// [text], the one whose first letter comes first on a tie; null when none
/// has a letter.
String? _voteOf(String text, List<_Script> scripts) {
  String? winner;
  var winnerCount = 0;
  var winnerFirst = 0;
  for (final script in scripts) {
    var count = 0;
    var first = 0;
    for (final letter in script.letters.allMatches(text)) {
      if (count++ == 0) first = letter.start;
    }
    if (count > winnerCount ||
        (count == winnerCount && count > 0 && first < winnerFirst)) {
      winner = script.language;
      winnerCount = count;
      winnerFirst = first;
    }
  }
  return winner;
}

int _wordsIn(String text) => [
  for (final token in text.split(_whitespaceRuns))
    if (_wordPart.hasMatch(token)) token,
].length;

({int chars, int runs}) _charsAndRuns(String text) {
  var chars = 0;
  var runs = 0;
  for (final token in text.split(_whitespaceRuns)) {
    for (final run in _runs.allMatches(token)) {
      final scripted = run.namedGroup('scripted');
      if (scripted != null) {
        chars += scripted.replaceAll(_uncounted, '').runes.length;
      } else if (run.namedGroup('span') != null ||
          _letterOrDigit.hasMatch(run.namedGroup('other')!)) {
        runs++;
      }
    }
  }
  return (chars: chars, runs: runs);
}
