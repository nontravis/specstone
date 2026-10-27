import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';

/// Returns the `doc_ref_unresolved` and `link_unresolved` findings of [doc].
///
/// A typed doc is checked for both, an untyped doc of a checked folder for
/// links only.
Iterable<Finding> checkDocLinks(CheckContext context, IndexedDoc doc) sync* {
  if (doc.isTyped) yield* _unresolvedDocRefs(context, doc);
  yield* _unresolvedLinks(context, doc);
}

/// Yields a finding per `doc_ref` value that no doc of the field's doc types
/// carries as its Name; any doc counts when the field names no doc type.
Iterable<Finding> _unresolvedDocRefs(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final fields = context.typeOf(doc)?.fields ?? const [];
  for (final field in fields) {
    if (field.type != FieldType.docRef) continue;
    final docTypes = field.docTypes;
    for (final (:value, :line, text: _)
        in context.linesOf(doc).entriesOf(field.id)) {
      if (value is! String) continue;
      final named = context.index.docs.any(
        (other) =>
            other.name == value &&
            (docTypes == null || docTypes.contains(other.docTypeId)),
      );
      if (named) continue;
      yield context.finding(
        doc,
        FindingKind.docRefUnresolved,
        line: line,
        message: '${field.id} value $value names no doc',
        keys: {'field': field.id, 'value': value},
      );
    }
  }
}

/// Yields a finding per link of [doc] whose target is indexed nowhere.
///
/// `markdown` decides which links exist and which resolve to no doc: the index
/// stores each target once, so a doc holding an unindexed target is parsed
/// again to list its links in order. Each such link is then placed in the
/// source text (see [_scanUses]) for its line and its target as written.
/// A link the scan cannot place takes line 1 and the href `markdown` gives as
/// its target; a link inside an indented code block is one such case.
Iterable<Finding> _unresolvedLinks(CheckContext context, IndexedDoc doc) sync* {
  final unindexed = {
    for (final target in context.contentOf(doc).links)
      if (context.index.at(target) == null) target,
  };
  if (unindexed.isEmpty) return;
  final text = toLf(context.contentOf(doc).text);
  final body = Doc.parse(text).afterFrontmatter;
  final firstLine =
      '\n'.allMatches(text.substring(0, text.length - body.length)).length + 1;
  final uses = _scanUses(body, firstLine);
  var next = 0;
  for (final href in _hrefsOf(body)) {
    final target = resolveDocLink(href, doc.docPath);
    if (target is! DocTarget || !unindexed.contains(target.docPath)) continue;
    final found = uses.indexWhere((use) => _normalize(use.dest) == href, next);
    if (found >= 0) next = found + 1;
    final line = found >= 0 ? uses[found].line : 1;
    final shown = found >= 0 ? uses[found].dest : href;
    yield context.finding(
      doc,
      FindingKind.linkUnresolved,
      line: line,
      message: 'link target $shown is no doc',
      keys: {'target': shown},
    );
  }
}

/// A link written in the source: its destination as written and its line.
typedef _Use = ({String dest, int line});

final _definition = RegExp(
  r'^ {0,3}\[([^\]]+)\]:[ \t]*(<[^>]*>|\S+)',
  multiLine: true,
);
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
  for (final match in _definition.allMatches(masked)) {
    definitionStarts.add(masked.indexOf('[', match.start));
    definitions.putIfAbsent(_label(match[1]!), () => _bare(match[2]!));
  }
  final uses = <_Use>[];
  for (var i = 0; i < masked.length; i++) {
    if (masked[i] != '[' || definitionStarts.contains(i)) continue;
    if (i > 0 && masked[i - 1] == '!') continue;
    final textEnd = _closing(masked, i, '[', ']');
    if (textEnd < 0) continue;
    final dest = _destAfter(masked, i, textEnd, definitions);
    if (dest == null) continue;
    final line = firstLine + '\n'.allMatches(body.substring(0, i)).length;
    uses.add((dest: dest, line: line));
  }
  return uses;
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

/// Returns the offset of the [close] that matches the [open] at [start], or -1.
///
/// A backslash escapes the next character.
int _closing(String text, int start, String open, String close) {
  var depth = 0;
  for (var i = start; i < text.length; i++) {
    final char = text[i];
    if (char == r'\') {
      i++;
    } else if (char == open) {
      depth++;
    } else if (char == close && --depth == 0) {
      return i;
    }
  }
  return -1;
}

/// Returns the destination of the link whose text ends at [textEnd], or null
/// when no link follows.
String? _destAfter(
  String text,
  int textStart,
  int textEnd,
  Map<String, String> definitions,
) {
  final after = textEnd + 1 < text.length ? text[textEnd + 1] : '';
  final linkText = text.substring(textStart + 1, textEnd);
  if (after == '(') {
    final end = _closing(text, textEnd + 1, '(', ')');
    return end < 0 ? null : _inlineDest(text.substring(textEnd + 2, end));
  }
  if (after == '[') {
    final end = _closing(text, textEnd + 1, '[', ']');
    if (end < 0) return null;
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
