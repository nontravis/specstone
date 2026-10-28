import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';

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
List<LinkPlace> linkPlacesOf(
  String lfBody, {
  required String docPath,
  required int firstLine,
}) {
  // Exact: a doc link is inline (`](`) or has a `]:` definition; an autolink
  // is absolute, so it never resolves to a doc.
  if (!lfBody.contains('](') && !lfBody.contains(']:')) return const [];
  final uses = _scanUses(lfBody, firstLine);
  final places = <LinkPlace>[];
  final usesOf = <String, List<_Use>>{};
  for (final use in uses) {
    usesOf.putIfAbsent(_normalize(use.dest), () => []).add(use);
  }
  final taken = <String, int>{};
  for (final href in _hrefsOf(lfBody)) {
    final target = resolveDocLink(href, docPath);
    if (target is! DocTarget ||
        !target.docPath.endsWith('.md') ||
        target.docPath == docPath) {
      continue;
    }
    final sameHref = usesOf[href] ?? const <_Use>[];
    final nth = taken[href] ?? 0;
    taken[href] = nth + 1;
    final use = nth < sameHref.length ? sameHref[nth] : null;
    places.add((
      target: target.docPath,
      line: use?.line ?? 1,
      shown: use?.dest ?? href,
    ));
  }
  return places;
}

/// A link written in the source: its destination as written and its line.
typedef _Use = ({String dest, int line});

final _definitionStart = RegExp(r'^ {0,3}\[', multiLine: true);
final _definition = RegExp(r'\[([^\]]+)\]:[ \t]*(<[^>]*>|\S+)');
final _span = RegExp('`[^`\n]*`');

/// Returns the links of [body] in source order, outside fenced code.
///
/// The body is scanned as one string, so link text and a destination may wrap
/// over lines, and `[]` in link text and `()` in a destination may nest. An
/// inline `](dest)` or `](<dest>)` gives its dest; a reference use
/// (`[text][label]`, `[label][]`, `[label]`) gives the dest of its
/// `[label]: dest` definition and the line of the use. Images are no link.
List<_Use> _scanUses(String body, int firstLine) {
  final masked = _masked(body);
  final definitions = <String, String>{};
  final definitionStarts = <int>{};
  _scanDefinitions(masked, (start, label, dest) {
    definitionStarts.add(start);
    definitions.putIfAbsent(_label(label), () => _bare(dest));
  });
  final texts = _pairs(masked, '[', ']');
  final parens = _pairs(masked, '(', ')');
  final uses = <_Use>[];
  var line = firstLine;
  var counted = 0;
  for (var i = 0; i < masked.length; i++) {
    if (masked[i] != '[' || definitionStarts.contains(i)) continue;
    if (i > 0 && masked[i - 1] == '!') continue;
    final textEnd = texts[i];
    if (textEnd == null) continue;
    final dest = _destAfter(masked, i, textEnd, definitions, texts, parens);
    if (dest == null) continue;
    for (; counted < i; counted++) {
      if (body.codeUnitAt(counted) == 0x0A) line++;
    }
    uses.add((dest: dest, line: line));
  }
  return uses;
}

/// Calls [found] with the offset, label, and destination of each definition
/// (`[label]: dest`) in [text], in order.
///
/// A label runs to the first `]`, over line ends. That `]` is looked up once
/// for all the line-start `[` before it, so brackets that never close cost no
/// rescan.
void _scanDefinitions(
  String text,
  void Function(int start, String label, String dest) found,
) {
  var resume = 0;
  var close = -1;
  for (final candidate in _definitionStart.allMatches(text)) {
    final at = candidate.end - 1;
    if (at < resume) continue;
    if (close <= at) close = text.indexOf(']', at + 1);
    if (close < 0) return;
    if (close == at + 1 || !text.startsWith(':', close + 1)) continue;
    final match = _definition.matchAsPrefix(text, at);
    if (match == null) continue;
    found(at, match[1]!, match[2]!);
    resume = match.end;
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
String? _destAfter(
  String text,
  int textStart,
  int textEnd,
  Map<String, String> definitions,
  Map<int, int> texts,
  Map<int, int> parens,
) {
  final after = textEnd + 1 < text.length ? text[textEnd + 1] : '';
  final linkText = text.substring(textStart + 1, textEnd);
  if (after == '(') {
    final end = parens[textEnd + 1];
    return end == null ? null : _inlineDest(text.substring(textEnd + 2, end));
  }
  if (after == '[') {
    final end = texts[textEnd + 1];
    if (end == null) return null;
    final label = text.substring(textEnd + 2, end);
    return definitions[_label(label.isEmpty ? linkText : label)];
  }
  return definitions[_label(linkText)];
}

String _inlineDest(String inside) {
  final trimmed = inside.trim();
  if (trimmed.startsWith('<')) {
    final close = trimmed.indexOf('>');
    if (close > 0) return trimmed.substring(1, close);
  }
  final end = trimmed.indexOf(RegExp(r'\s'));
  return end < 0 ? trimmed : trimmed.substring(0, end);
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

/// Returns the hrefs of the links in [body], in order.
List<String> _hrefsOf(String body) {
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

  visit(Document(extensionSet: ExtensionSet.gitHubFlavored).parse(body));
  return hrefs;
}
