import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/inline_holders.dart';
import 'package:specstone_core/src/doc_model/models/sentence_measure.dart';

const _defaultLanguage = 'default';

/// Stands in for a code span, which counts as one word or one run whatever
/// its letters; a Unicode noncharacter, so no text holds it.
final _spanMark = String.fromCharCode(0xFDD0);

/// Code points below this one belong to no script `measureSentence` votes on.
const _firstVotedCodePoint = 0x0370;

const _asciiLimit = 0x80;
const _tab = 0x09;
const _carriageReturn = 0x0D;
const _space = 0x20;
const _zero = 0x30;
const _nine = 0x39;
const _lowerA = 0x61;
const _lowerZ = 0x7A;

/// Set on an ASCII letter's code unit to fold it to lower case.
const _lowerCaseBit = 0x20;

/// The runs of other scripts and code spans each count the cap over this,
/// unless the caller names its own divisor.
const defaultRunWeightDivisor = 25;

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

/// A language and the letters of the scripts it is written in.
final class _Script {
  const new({required this.language, required this.letters});

  final String language;
  final RegExp letters;
}

RegExp _lettersOf(List<String> scripts) => RegExp(
  '(?=\\p{L})[${scripts.map((name) => '\\p{Script=$name}').join()}]',
  unicode: true,
);

List<_Script> _votesOf(Map<String, List<String>> names) => [
  for (final MapEntry(:key, :value) in names.entries)
    _Script(language: key, letters: _lettersOf(value)),
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
    final _CharsAndRuns(:chars, :runs) = _charsAndRuns(text);
    return SentenceMeasure(
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
  return SentenceMeasure(
    language: language,
    countsChars: false,
    words: _wordsIn(text),
    chars: 0,
    runs: 0,
  );
}

/// Returns the character total of [measure] under the character [cap].
///
/// Each run of another script or code span weighs the cap over [divisor], and
/// the total rounds up to a whole number.
int weightedChars(
  SentenceMeasure measure,
  int cap, {
  int divisor = defaultRunWeightDivisor,
}) => measure.chars + (measure.runs * cap + divisor - 1) ~/ divisor;

/// Returns [markdown] with each code span as one mark, each link as its text,
/// and the emphasis marks dropped.
String _plainText(String markdown) {
  final text = markdown.replaceAll(_spanMark, '');
  final linked = _linkTexts(_spansAsMarks(text));
  return linked.contains('*') || linked.contains('_')
      ? linked.replaceAll(_emphasisMarks, '')
      : linked;
}

String _spansAsMarks(String text) {
  if (!text.contains('`')) return text;
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

/// Returns how many whitespace-separated tokens of [text] hold a letter, a
/// digit, or a span mark.
///
/// Reads code units in place; only a token with a non-ASCII unit and no ASCII
/// letter or digit reaches the Unicode [_wordPart] test.
int _wordsIn(String text) {
  var count = 0;
  var at = 0;
  while (at < text.length) {
    while (at < text.length && _isSpaceUnit(text.codeUnitAt(at))) {
      at++;
    }
    final start = at;
    var hasAsciiWord = false;
    var hasWideUnit = false;
    while (at < text.length && !_isSpaceUnit(text.codeUnitAt(at))) {
      final unit = text.codeUnitAt(at++);
      if (_isAsciiLetterOrDigit(unit)) {
        hasAsciiWord = true;
      } else if (unit >= _asciiLimit) {
        hasWideUnit = true;
      }
    }
    if (hasAsciiWord ||
        (hasWideUnit && _wordPart.hasMatch(text.substring(start, at)))) {
      count++;
    }
  }
  return count;
}

bool _isSpaceUnit(int unit) =>
    unit == _space ||
    (unit >= _tab && unit <= _carriageReturn) ||
    (unit >= _asciiLimit &&
        _whitespaceRuns.hasMatch(String.fromCharCode(unit)));

bool _isAsciiLetterOrDigit(int unit) =>
    (unit >= _zero && unit <= _nine) ||
    ((unit | _lowerCaseBit) >= _lowerA && (unit | _lowerCaseBit) <= _lowerZ);

/// The counted characters of a text's no-space scripts, and its runs of other
/// scripts and code spans.
final class _CharsAndRuns {
  const new({required this.chars, required this.runs});

  final int chars;
  final int runs;
}

_CharsAndRuns _charsAndRuns(String text) {
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
  return _CharsAndRuns(chars: chars, runs: runs);
}
