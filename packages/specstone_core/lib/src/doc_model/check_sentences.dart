import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/inline_holders.dart';
import 'package:specstone_core/src/doc_model/models/check_sentence.dart';
import 'package:specstone_core/src/doc_model/models/text_block.dart';
import 'package:specstone_core/src/doc_model/sentences.dart';

const _space = 0x20;
const _openBracket = 0x5B;
const _openParen = 0x28;
const _closeParen = 0x29;

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
      CheckSentence(
        text: kept[i],
        isHeading: block.isHeading && i == kept.length - 1,
      ),
  ];
}

const _asciiLimit = 0x80;

/// Per ASCII code unit, whether it is a stop of any kind; read before the set
/// lookups, which cost more per character than a list index.
final _asciiStops = List<bool>.generate(
  _asciiLimit,
  (unit) =>
      spacedTerminators.contains(unit) ||
      _openStops.contains(unit) ||
      _clauseStops.contains(unit),
  growable: false,
);

bool _endsSentence(String text, List<bool> held, int i, int parenDepth) {
  final unit = text.codeUnitAt(i);
  if (unit < _asciiLimit && !_asciiStops[unit]) return false;
  final next = i + 1;
  if (spacedTerminators.contains(unit)) {
    return next == text.length || text.codeUnitAt(next) == _space;
  }
  if (!_isUnspacedStop(unit, parenDepth)) return false;
  return next == text.length ||
      held[next] ||
      !_isUnspacedStop(text.codeUnitAt(next), parenDepth);
}

/// Whether [unit] ends a sentence with no space after it at [parenDepth].
bool _isUnspacedStop(int unit, int parenDepth) =>
    _openStops.contains(unit) ||
    (_clauseStops.contains(unit) && parenDepth == 0);

/// Returns, per offset of [text], whether a code span or a link holds it.
List<bool> _heldMask(String text) {
  final held = List<bool>.filled(text.length, false);
  final spans = codeSpansOf(text);
  void hold(int start, int end) => held.fillRange(start, end, true);
  for (final span in spans) {
    hold(span.start, span.end);
  }
  final spanEnds = {for (final span in spans) span.start: span.end};
  var i = 0;
  while (i < text.length) {
    final spanEnd = spanEnds[i];
    if (spanEnd != null) {
      i = spanEnd;
      continue;
    }
    final end = text.codeUnitAt(i) == _openBracket && !isEscaped(text, i)
        ? linkAt(text, i, skips: spanEnds)?.end
        : null;
    if (end == null) {
      i++;
      continue;
    }
    hold(i, end);
    i = end;
  }
  return held;
}
