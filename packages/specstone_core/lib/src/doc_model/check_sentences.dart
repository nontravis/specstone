import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/sentences.dart';

/// A sentence of the check's cut, and whether a `###` heading ends it.
typedef CheckSentence = ({String text, bool isHeading});

const _space = 0x20;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _openParen = 0x28;
const _closeParen = 0x29;
const _backslash = 0x5C;

/// Stops of other scripts, `。`, `！`, `？`, `।`, `؟`, `။`, `។`, that end a
/// sentence with or without a space after them.
const _openStops = {0x3002, 0xFF01, 0xFF1F, 0x0964, 0x061F, 0x104B, 0x17D4};

/// Clause stops, `;`, `；`, `؛`, that end a sentence outside parentheses.
const _clauseStops = {0x3B, 0xFF1B, 0x061B};

/// Returns the sentences of [lfItemText] as `check` counts and measures them.
///
/// A code span or a link holds every stop, and a clause stop ends a sentence
/// outside parentheses too. A run of unspaced stops ends one sentence at its
/// last stop.
List<CheckSentence> checkSentencesOf(String lfItemText) => [
  for (final block in textBlocksOf(lfItemText)) ..._cut(block),
];

List<CheckSentence> _cut(TextBlock block) {
  final text = collapseWhitespace(block.text).trim();
  final held = _heldMask(text);
  final sentences = <String>[];
  var start = 0;
  var parenDepth = 0;
  for (var i = 0; i < text.length; i++) {
    if (held[i]) continue;
    final unit = text.codeUnitAt(i);
    if (unit == _openParen) {
      parenDepth++;
    } else if (unit == _closeParen && parenDepth > 0) {
      parenDepth--;
    }
    if (!_endsSentence(text, held, i, parenDepth)) continue;
    sentences.add(text.substring(start, i + 1).trim());
    start = i + 1;
  }
  sentences.add(text.substring(start).trim());
  final kept = [
    for (final sentence in sentences)
      if (sentence.isNotEmpty) sentence,
  ];
  return [
    for (var i = 0; i < kept.length; i++)
      (text: kept[i], isHeading: block.isHeading && i == kept.length - 1),
  ];
}

bool _endsSentence(String text, List<bool> held, int i, int parenDepth) {
  final unit = text.codeUnitAt(i);
  final next = i + 1;
  if (spacedTerminators.contains(unit)) {
    return next == text.length || text.codeUnitAt(next) == _space;
  }
  final isOpenStop =
      _openStops.contains(unit) ||
      (_clauseStops.contains(unit) && parenDepth == 0);
  if (!isOpenStop) return false;
  return next == text.length ||
      held[next] ||
      !_isUnspacedStop(text.codeUnitAt(next));
}

bool _isUnspacedStop(int unit) =>
    _openStops.contains(unit) || _clauseStops.contains(unit);

/// Returns, per offset of [text], whether a code span or a link holds it.
List<bool> _heldMask(String text) {
  final held = List<bool>.filled(text.length, false);
  final spans = codeSpansOf(text);
  void hold(int start, int end) => held.fillRange(start, end, true);
  for (final span in spans) {
    hold(span.start, span.end);
  }
  final spanAt = {for (final span in spans) span.start: span};
  var i = 0;
  while (i < text.length) {
    final span = spanAt[i];
    if (span != null) {
      i = span.end;
      continue;
    }
    final end = text.codeUnitAt(i) == _openBracket && !_isEscaped(text, i)
        ? _linkEnd(text, i, spanAt)
        : -1;
    if (end < 0) {
      i++;
      continue;
    }
    hold(i, end);
    i = end;
  }
  return held;
}

/// Returns the offset after the link `[text](destination)` opening at
/// [open], or -1 when none does.
int _linkEnd(String text, int open, Map<int, CodeSpan> spanAt) {
  final textEnd = _closerOf(text, open, _openBracket, _closeBracket, spanAt);
  if (textEnd < 0 ||
      textEnd + 1 >= text.length ||
      text.codeUnitAt(textEnd + 1) != _openParen) {
    return -1;
  }
  final destEnd = _closerOf(text, textEnd + 1, _openParen, _closeParen, spanAt);
  return destEnd < 0 ? -1 : destEnd + 1;
}

/// Returns the offset of the [closer] matching the [opener] at [open],
/// skipping code spans, escapes, and nested pairs; -1 when none matches.
int _closerOf(
  String text,
  int open,
  int opener,
  int closer,
  Map<int, CodeSpan> spanAt,
) {
  var depth = 0;
  var i = open;
  while (i < text.length) {
    final span = spanAt[i];
    if (span != null) {
      i = span.end;
      continue;
    }
    final unit = text.codeUnitAt(i);
    if (!_isEscaped(text, i)) {
      if (unit == opener) {
        depth++;
      } else if (unit == closer && --depth == 0) {
        return i;
      }
    }
    i++;
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
