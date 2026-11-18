import 'package:specstone_core/src/doc_model/models/link_ends.dart';

const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _openParen = 0x28;
const _closeParen = 0x29;
const _backslash = 0x5C;

/// Whether the character at [at] in [text] follows an odd run of backslashes.
bool isEscaped(String text, int at) {
  var start = at;
  while (start > 0 && text.codeUnitAt(start - 1) == _backslash) {
    start--;
  }
  return (at - start).isOdd;
}

/// Returns where the link opening at [open] in [text] ends, or null when none
/// does.
///
/// A key of [skips] is the offset where a held run begins and its value is
/// where the run ends; the scan jumps over each such run.
LinkEnds? linkAt(String text, int open, {Map<int, int> skips = const {}}) {
  final textEnd = _closerOf(text, open, _openBracket, _closeBracket, skips);
  if (textEnd < 0 ||
      textEnd + 1 >= text.length ||
      text.codeUnitAt(textEnd + 1) != _openParen) {
    return null;
  }
  final destEnd = _closerOf(text, textEnd + 1, _openParen, _closeParen, skips);
  return destEnd < 0 ? null : LinkEnds(textEnd: textEnd, end: destEnd + 1);
}

/// Returns the offset of the [closer] that matches the [opener] at [open],
/// skipping held runs, escapes, and nested pairs; -1 when none matches.
int _closerOf(
  String text,
  int open,
  int opener,
  int closer,
  Map<int, int> skips,
) {
  var depth = 0;
  var i = open;
  while (i < text.length) {
    final skipTo = skips[i];
    if (skipTo != null) {
      i = skipTo;
      continue;
    }
    final unit = text.codeUnitAt(i);
    if (!isEscaped(text, i)) {
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
