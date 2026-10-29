import 'dart:typed_data';

import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';

/// A doc link of a doc: the docPath it resolves to, the file line it is
/// written on, and its destination as written.
typedef LinkPlace = ({String target, int line, String shown});

/// Returns the links of [lfBody] that resolve to a `.md` doc other than
/// [docPath], in source order.
///
/// [lfBody] is the doc text after the frontmatter, with LF line ends, and
/// [firstLine] is its first file line. `markdown` decides which links exist.
/// Each is then placed in the source text (see [_scanUses]) for its line and
/// its destination as written: the nth link to an href takes the nth use of
/// that href, so no other link moves it. A link the scan cannot place takes
/// line 1 and the href `markdown` gives as its destination.
///
/// Returns null when `markdown` fails on [lfBody] (see [parseMarkdown]), and
/// `const []` for a body with no link syntax, which it never parses.
List<LinkPlace>? linkPlacesOf(
  String lfBody, {
  required String docPath,
  required int firstLine,
}) {
  // Exact: a doc link is inline (`](`) or has a `]:` definition; an autolink
  // is absolute, so it never resolves to a doc.
  if (!lfBody.contains('](') && !lfBody.contains(']:')) return const [];
  final hrefs = _hrefsOf(lfBody);
  if (hrefs == null) return null;
  final (:placed, :longestHref) = _placedHrefs(docPath, hrefs);
  final uses = _scanUses(lfBody, firstLine, longestHref);
  final places = <LinkPlace>[];
  final usesOf = <String, List<_Use>>{};
  for (final use in uses) {
    usesOf.putIfAbsent(_normalize(use.dest), () => []).add(use);
  }
  final taken = <String, int>{};
  for (final (:href, :docPath) in placed) {
    final sameHref = usesOf[href] ?? const <_Use>[];
    final nth = taken[href] ?? 0;
    taken[href] = nth + 1;
    final use = nth < sameHref.length ? sameHref[nth] : null;
    places.add((
      target: docPath,
      line: use?.line ?? 1,
      shown: use?.dest ?? href,
    ));
  }
  return places;
}

/// A link written in the source: its destination as written and its line.
typedef _Use = ({String dest, int line});

/// A placed href together with the doc path it resolved to.
typedef _PlacedHref = ({String href, String docPath});

/// Returns the hrefs [linkPlacesOf] places, each with the doc path it
/// resolved to, and the longest placed href's length.
///
/// The filter runs once here, for both consumers: `_scanUses` compares a
/// candidate destination's length against the length (R2), and
/// `linkPlacesOf` loops over the filtered hrefs to place each one. Each
/// href resolves exactly once: the caller reads the doc path from here
/// instead of resolving again.
({List<_PlacedHref> placed, int longestHref}) _placedHrefs(
  String docPath,
  List<String> hrefs,
) {
  final placed = <_PlacedHref>[];
  var longest = 0;
  for (final href in hrefs) {
    final target = resolveDocLink(href, docPath);
    if (target is! DocTarget ||
        !target.docPath.endsWith('.md') ||
        target.docPath == docPath) {
      continue;
    }
    placed.add((href: href, docPath: target.docPath));
    if (href.length > longest) longest = href.length;
  }
  return (placed: placed, longestHref: longest);
}

final _definitionStart = RegExp(r'^ {0,3}\[', multiLine: true);
final _bareDest = RegExp(r'\S+');
final _span = RegExp('`[^`\n]*`');

/// Returns the links of [body] in source order, outside fenced code.
///
/// The body is scanned as one string, so link text and a destination may wrap
/// over lines, and `[]` in link text and `()` in a destination may nest. An
/// inline `](dest)` or `](<dest>)` gives its dest; a reference use
/// (`[text][label]`, `[label][]`, `[label]`) gives the dest of its
/// `[label]: dest` definition and the line of the use. Images are no link.
///
/// [maxHref] is the length of the longest href `linkPlacesOf` places; the
/// scan decides each `[` opener from offsets and fixed tables, never from a
/// copy of its span, so nesting depth costs nothing. Three rules keep the
/// output identical to a per-opener copy:
/// - R1: a span is looked up in the definitions only when it holds no `]`
///   and its kept count (code units that are neither `String.trim`
///   whitespace nor RegExp `\s`) is at most the longest definition key's
///   length; any other span misses. A key is a label cut at its first `]`,
///   so no key holds `]`, and a label only trims, collapses blanks, and
///   lowercases, which never grows its kept count past the key's length.
/// - R2: an inline destination is found by offsets (the trimmed content's
///   bounds, its first `>`, its first `\s`) and copied only when no longer
///   than [maxHref]; a longer one makes no use, because normalization never
///   shortens a destination and a use matters only for a placed href.
/// - R3: the destination or label after a close is computed once per close
///   offset, not once per opener that shares the close. A null result is
///   cached too (`putIfAbsent`), because a null held by `??=` would never
///   land in the map and every sharing opener would recompute it.
List<_Use> _scanUses(String body, int firstLine, int maxHref) {
  final masked = _masked(body);
  final definitions = <String, String>{};
  final definitionStarts = <int>{};
  _scanDefinitions(masked, (start, label, dest) {
    definitionStarts.add(start);
    definitions.putIfAbsent(_label(label), () => _bare(dest));
  });
  final texts = _pairs(masked, '[', ']');
  final parens = _pairs(masked, '(', ')');
  final closes = _closeCounts(masked);
  final nextAngle = _nextOf(masked, '>');
  final nextBlank = _nextBlank(masked);
  final inlineByEnd = <int, String?>{};
  final labelByEnd = <int, String?>{};
  var longestKey = 0;
  for (final key in definitions.keys) {
    if (key.length > longestKey) longestKey = key.length;
  }
  final uses = <_Use>[];
  var line = firstLine;
  var counted = 0;
  for (var i = 0; i < masked.length; i++) {
    if (masked[i] != '[' || definitionStarts.contains(i)) continue;
    if (i > 0 && masked[i - 1] == '!') continue;
    final textEnd = texts[i];
    if (textEnd == null) continue;
    final dest = _destAfter(
      masked,
      i,
      textEnd,
      definitions,
      texts,
      parens,
      closes,
      nextAngle,
      nextBlank,
      inlineByEnd,
      labelByEnd,
      longestKey,
      maxHref,
    );
    if (dest == null) continue;
    for (; counted < i; counted++) {
      if (body.codeUnitAt(counted) == 0x0A) line++;
    }
    uses.add((dest: dest, line: line));
  }
  return uses;
}

/// Returns whether [unit] is `String.trim` whitespace: RegExp `\s` plus
/// U+0085, the one code unit `trim` strips that `\s` does not match.
bool _trim(int unit) => _blank(unit) || unit == 0x85;

/// Returns, per offset, how many `]` the span starting there holds ([0]) and
/// its kept count of code units that are neither `String.trim` whitespace
/// nor RegExp `\s` ([1]), each entry covering the span from that offset to
/// the end of the text.
///
/// One backward pass fills both: a span starting at `i` holds what the span
/// starting at `i + 1` holds plus its own first code unit. A span between an
/// opener and its close is then read as a subtraction of two entries, so no
/// opener pays for its span's length.
Int32List _closeCounts(String text) {
  final counts = Int32List(2 * (text.length + 1));
  for (var i = text.length - 1; i >= 0; i--) {
    final unit = text.codeUnitAt(i);
    counts[2 * i] = counts[2 * i + 2] + (unit == 0x5D ? 1 : 0);
    counts[2 * i + 1] = counts[2 * i + 3] + (_kept(unit) ? 1 : 0);
  }
  return counts;
}

/// Returns whether [unit] is neither `String.trim` whitespace nor RegExp
/// `\s` — that is, neither `_trim` nor `_blank` — the code units `_label`
/// can keep.
bool _kept(int unit) => !_trim(unit) && !_blank(unit);

/// Returns, per offset, the offset of the next [char] at or after it, or the
/// text's length when none follows.
///
/// One backward pass fills the table, so the next `>` or blank after any
/// offset is one lookup instead of a scan.
Int32List _nextOf(String text, String char) {
  final next = Int32List(text.length + 1);
  next[text.length] = text.length;
  final unit = char.codeUnitAt(0);
  for (var i = text.length - 1; i >= 0; i--) {
    next[i] = text.codeUnitAt(i) == unit ? i : next[i + 1];
  }
  return next;
}

/// Returns, per offset, the offset of the next RegExp `\s` code unit at or
/// after it, or the text's length when none follows.
Int32List _nextBlank(String text) {
  final next = Int32List(text.length + 1);
  next[text.length] = text.length;
  for (var i = text.length - 1; i >= 0; i--) {
    next[i] = _blank(text.codeUnitAt(i)) ? i : next[i + 1];
  }
  return next;
}

/// Returns whether [unit] matches RegExp `\s`: ECMAScript WhiteSpace plus
/// LineTerminator. U+0085 (Cc) matches neither, so it stays non-blank here
/// even though `String.trim` strips it (`_trim`).
bool _blank(int unit) =>
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0B ||
    unit == 0x0C ||
    unit == 0x0D ||
    unit == 0x20 ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200A) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000 ||
    unit == 0xFEFF;

/// Calls [found] with the offset, label, and destination of each definition
/// (`[label]: dest`) in [text], in order.
///
/// A label runs to the first `]`, over line ends, and a `<` destination to the
/// first `>`. Each is looked up once for all the starts before it, so a bracket
/// or `<` that never closes costs no rescan.
void _scanDefinitions(
  String text,
  void Function(int start, String label, String dest) found,
) {
  var resume = 0;
  var close = -1;
  var angleClose = -1;
  var noAngleClose = false;
  for (final candidate in _definitionStart.allMatches(text)) {
    final at = candidate.end - 1;
    if (at < resume) continue;
    if (close <= at) close = text.indexOf(']', at + 1);
    if (close < 0) return;
    if (close == at + 1 || !text.startsWith(':', close + 1)) continue;
    var destAt = close + 2;
    while (destAt < text.length &&
        (text[destAt] == ' ' || text[destAt] == '\t')) {
      destAt++;
    }
    var destEnd = -1;
    if (text.startsWith('<', destAt)) {
      if (!noAngleClose && angleClose <= destAt) {
        angleClose = text.indexOf('>', destAt + 1);
        noAngleClose = angleClose < 0;
      }
      if (!noAngleClose) destEnd = angleClose + 1;
    }
    if (destEnd < 0) {
      destEnd = _bareDest.matchAsPrefix(text, destAt)?.end ?? -1;
      if (destEnd < 0) continue;
    }
    found(at, text.substring(at + 1, close), text.substring(destAt, destEnd));
    resume = destEnd;
  }
}

/// Returns [body] with fenced code lines and inline code spans blanked, the
/// length and every line end kept.
String _masked(String body) {
  final lines = body.split('\n');
  final fenced = fencedLines(lines);
  return [
    for (var i = 0; i < lines.length; i++)
      if (fenced[i])
        ' ' * lines[i].length
      else
        lines[i].replaceAllMapped(_span, (m) => ' ' * m[0]!.length),
  ].join('\n');
}

/// Maps the offset of each [open] in [text] to the offset of its matching
/// [close]; an unmatched [open] has no entry.
///
/// A backslash escapes the next character. An escaped [open] is no opener for
/// the brackets around it, yet a scan that starts at it still pairs it, so it
/// is paired here with the first [close] that leaves the depth of its start.
/// One pass makes the lookup linear, where a scan per bracket is quadratic.
Map<int, int> _pairs(String text, String open, String close) {
  final pairs = <int, int>{};
  final opens = <int>[];
  final escaped = <({int offset, int depth})>[];
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == r'\') {
      if (i + 1 < text.length && text[i + 1] == open) {
        escaped.add((offset: i + 1, depth: opens.length));
      }
      i++;
    } else if (char == open) {
      opens.add(i);
    } else if (char == close) {
      while (escaped.isNotEmpty && escaped.last.depth == opens.length) {
        pairs[escaped.removeLast().offset] = i;
      }
      if (opens.isNotEmpty) pairs[opens.removeLast()] = i;
    }
  }
  return pairs;
}

/// Returns the destination of the link whose text ends at [textEnd], or null
/// when no link follows.
///
/// Decides from the precomputed tables ([closes], [nextAngle], [nextBlank])
/// and the per-close caches ([inlineByEnd], [labelByEnd], R3), copying only
/// what R1 and R2 let through.
String? _destAfter(
  String text,
  int textStart,
  int textEnd,
  Map<String, String> definitions,
  Map<int, int> texts,
  Map<int, int> parens,
  Int32List closes,
  Int32List nextAngle,
  Int32List nextBlank,
  Map<int, String?> inlineByEnd,
  Map<int, String?> labelByEnd,
  int longestKey,
  int maxHref,
) {
  final after = textEnd + 1 < text.length ? text[textEnd + 1] : '';
  if (after == '(') {
    final end = parens[textEnd + 1];
    if (end == null) return null;
    // R3: the inline destination of a close is the same for every opener
    // that shares it, so it is computed once per close offset. A stored
    // null (no destination) counts too, so `putIfAbsent`, not `??=`: a
    // null held by `??=` would never land in the map and every opener
    // that shares the close would recompute it.
    return inlineByEnd.putIfAbsent(
      end,
      () => _inlineDestByOffsets(
        text,
        textEnd + 1,
        end,
        nextAngle,
        nextBlank,
        maxHref,
      ),
    );
  }
  if (after == '[') {
    final end = texts[textEnd + 1];
    if (end == null) return null;
    // R3: the label between the brackets is the same for every opener that
    // shares this close. A shortcut label is decided on the raw span being
    // empty, not on the normalized label: a whitespace-only `[ ]` is no
    // shortcut (b7bf9ff read `label.isEmpty` before `_label`), so it looks
    // itself up and never falls back to the link text.
    if (end == textEnd + 2) {
      final linkLabel = _labelSpan(
        text,
        textStart + 1,
        textEnd,
        closes,
        longestKey,
      );
      return linkLabel == null ? null : definitions[linkLabel];
    }
    // A stored null label counts too, so `putIfAbsent`, not `??=` (same
    // reason as [inlineByEnd] above).
    final cached = labelByEnd.putIfAbsent(
      end,
      () => _labelSpan(text, textEnd + 2, end, closes, longestKey),
    );
    return cached == null ? null : definitions[cached];
  }
  // R1: a span that holds `]` or outlengths every key cannot be a label, so
  // the lookup would miss without copying the span.
  final label = _labelSpan(text, textStart + 1, textEnd, closes, longestKey);
  return label == null ? null : definitions[label];
}

/// Returns the inline destination inside the parens that open at [open] and
/// close at [end], by offsets (R2), or null when it is longer than
/// [maxHref] and so makes no use.
String? _inlineDestByOffsets(
  String text,
  int open,
  int end,
  Int32List nextAngle,
  Int32List nextBlank,
  int maxHref,
) {
  // The trimmed content: blanks at both ends drop, the same `_inlineDest`
  // trimmed with `String.trim`.
  var start = open + 1;
  while (start < end && _trim(text.codeUnitAt(start))) {
    start++;
  }
  var stop = end;
  while (stop > start && _trim(text.codeUnitAt(stop - 1))) {
    stop--;
  }
  if (text.codeUnitAt(start) == 0x3C) {
    final close = nextAngle[start];
    if (close > start && close < stop) {
      if (close - start - 1 > maxHref) return null;
      return text.substring(start + 1, close);
    }
  }
  final blank = nextBlank[start];
  final stopAt = blank < stop ? blank : stop;
  if (stopAt - start > maxHref) return null;
  return text.substring(start, stopAt);
}

/// Returns the label of the span from [start] to [end], or null when the
/// span holds a `]` or its kept count is above [longestKey], so no
/// definition key can equal its label (R1).
String? _labelSpan(
  String text,
  int start,
  int end,
  Int32List closes,
  int longestKey,
) {
  if (closes[2 * start] - closes[2 * end] > 0) return null;
  if (closes[2 * start + 1] - closes[2 * end + 1] > longestKey) return null;
  return _label(text.substring(start, end));
}

String _label(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String _bare(String dest) => dest.startsWith('<') && dest.endsWith('>')
    ? dest.substring(1, dest.length - 1)
    : dest;

/// Mirrors `markdown`'s link destination normalization: percent-escapes stay,
/// the rest is percent-encoded.
String _normalize(String dest) => dest.splitMapJoin(
  RegExp('%[0-9A-Fa-f]{2}'),
  onMatch: (m) => m.group(0)!,
  onNonMatch: Uri.encodeFull,
);

/// Returns the hrefs of the links in [body], in order, or null when `markdown`
/// fails on it.
List<String>? _hrefsOf(String body) {
  final nodes = parseMarkdown(body);
  if (nodes == null) return null;
  final hrefs = <String>[];
  void visit(List<Node> nodes) {
    for (final node in nodes) {
      if (node is! Element) continue;
      final href = node.attributes['href'];
      if (node.tag == 'a' && href != null) hrefs.add(href);
      final children = node.children;
      if (children != null) visit(children);
    }
  }

  visit(nodes);
  return hrefs;
}
