/// Where a link destination sits in a text, and whether it is `<...>`.
typedef LinkDestination = ({int start, int end, bool angle});

/// Returns every destination that follows a `](` or `]:` in [text], as
/// spelled, in text order.
///
/// A destination is only read, not proven a link's; the link rewrite proves
/// each, and a mention scan skips every one.
Iterable<LinkDestination> destinationsIn(String text) sync* {
  for (final match in RegExp(r'\](?:\(|:)\s*').allMatches(text)) {
    if (_destinationAt(text, match.end) case final span?) yield span;
  }
}

/// Returns the destination that begins at [from], as spelled, or null.
///
/// An angle destination ends at the first `>` no backslash escapes; a plain
/// one ends at whitespace or at the `)` that closes the link, parentheses in
/// it balanced.
LinkDestination? _destinationAt(String text, int from) {
  final angle = from < text.length && text[from] == '<';
  final start = angle ? from + 1 : from;
  var depth = 0;
  var i = start;
  while (i < text.length) {
    final c = text[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (angle ? (c == '>' || c == '\n') : c.trim().isEmpty) break;
    if (!angle && c == '(') depth++;
    if (!angle && c == ')') {
      if (depth == 0) break;
      depth--;
    }
    i++;
  }
  final end = i.clamp(start, text.length);
  if (end == start || (angle && (i >= text.length || text[i] != '>'))) {
    return null;
  }
  return (start: start, end: end, angle: angle);
}
