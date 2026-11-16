import 'package:specstone_core/src/doc_model/code_spans.dart';

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

const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _openParen = 0x28;
const _closeParen = 0x29;
const _backslash = 0x5C;

/// The Thai and Lao AM vowels, which add no character.
final _amVowels = String.fromCharCodes(const [0x0E33, 0x0EB3]);

typedef _Script = ({String language, RegExp letters});

RegExp _lettersOf(String scripts) =>
    RegExp('(?=\\p{L})[$scripts]', unicode: true);

String _scriptOf(String name) => '\\p{Script=$name}';

/// The scripts with no spaces between words, `ja` and `zh` as one script.
final _noSpaceScripts = <_Script>[
  (language: 'th', letters: _lettersOf(_scriptOf('Thai'))),
  (language: 'lo', letters: _lettersOf(_scriptOf('Lao'))),
  (language: 'km', letters: _lettersOf(_scriptOf('Khmer'))),
  (language: 'my', letters: _lettersOf(_scriptOf('Myanmar'))),
  (
    language: 'zh',
    letters: _lettersOf(
      [_scriptOf('Han'), _scriptOf('Hiragana'), _scriptOf('Katakana')].join(),
    ),
  ),
];

final RegExp _kanaLetters = _lettersOf(
  [_scriptOf('Hiragana'), _scriptOf('Katakana')].join(),
);

/// The scripts that space their words and have a language of their own.
final _spacedScripts = <_Script>[
  (language: 'ko', letters: _lettersOf(_scriptOf('Hangul'))),
  (language: 'ar', letters: _lettersOf(_scriptOf('Arabic'))),
  (language: 'he', letters: _lettersOf(_scriptOf('Hebrew'))),
  (language: 'hi', letters: _lettersOf(_scriptOf('Devanagari'))),
  (language: 'el', letters: _lettersOf(_scriptOf('Greek'))),
];

final String _noSpaceClass = [
  for (final name in [
    'Thai',
    'Lao',
    'Khmer',
    'Myanmar',
    'Han',
    'Hiragana',
    'Katakana',
  ])
    '\\p{Script_Extensions=$name}',
].join();

/// A code span, a run of no-space script, or a run of anything else.
final _runs = RegExp(
  '(?<span>$_spanMark)|(?<scripted>[$_noSpaceClass]+)|'
  '(?<other>[^$_noSpaceClass$_spanMark]+)',
  unicode: true,
);

final _whitespaceRuns = RegExp(r'\s+');
final _wordPart = RegExp('[\\p{L}\\p{N}$_spanMark]', unicode: true);
final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _uncounted = RegExp('[\\p{M}\\p{Cf}$_amVowels]', unicode: true);

/// Emphasis marks: every `*`, and each `_` that does not join two word
/// characters.
final _emphasisMarks = RegExp(
  r'\*+|(?<![\p{L}\p{N}])_+|_+(?![\p{L}\p{N}])',
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
    final language = noSpace == 'zh' && _kanaLetters.hasMatch(text)
        ? 'ja'
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
    final link = _isEscaped(text, i) ? null : _linkAt(text, i);
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

/// Returns where the link `[text](destination)` opening at [open] ends, or
/// null when none does.
({int textEnd, int end})? _linkAt(String text, int open) {
  final textEnd = _closerOf(text, open, _openBracket, _closeBracket);
  if (textEnd < 0 ||
      textEnd + 1 >= text.length ||
      text.codeUnitAt(textEnd + 1) != _openParen) {
    return null;
  }
  final destEnd = _closerOf(text, textEnd + 1, _openParen, _closeParen);
  return destEnd < 0 ? null : (textEnd: textEnd, end: destEnd + 1);
}

/// Returns the offset of the [closer] that matches the [opener] at [open],
/// skipping escapes and nested pairs; -1 when none matches.
int _closerOf(String text, int open, int opener, int closer) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (_isEscaped(text, i)) continue;
    final unit = text.codeUnitAt(i);
    if (unit == opener) {
      depth++;
    } else if (unit == closer && --depth == 0) {
      return i;
    }
  }
  return -1;
}

bool _isEscaped(String text, int at) {
  var start = at;
  while (start > 0 && text.codeUnitAt(start - 1) == _backslash) {
    start--;
  }
  return (at - start).isOdd;
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
