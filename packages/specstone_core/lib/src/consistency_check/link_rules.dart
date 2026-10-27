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
/// A link `markdown` reports and the scan cannot place is a bug: it asserts in
/// debug, and in release the finding takes line 1 and the normalized href.
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
    while (next < uses.length && _normalize(uses[next].dest) != href) {
      next++;
    }
    final placed = next < uses.length;
    assert(placed, 'link $href of ${doc.docPath} is not in its source text');
    yield context.finding(
      doc,
      FindingKind.linkUnresolved,
      line: placed ? uses[next].line : 1,
      message: 'link target ${placed ? uses[next].dest : href} is no doc',
      keys: {'target': placed ? uses[next].dest : href},
    );
    if (placed) next++;
  }
}

/// A link written in the source: its destination as written and its line.
typedef _Use = ({String dest, int line});

final _definition = RegExp(r'^ {0,3}\[([^\]]+)\]:[ \t]*(<[^>]*>|\S+)');
final _span = RegExp('`[^`]*`');
final _bracket = RegExp(r'(!?)\[([^\]]*)\](?:\(([^)]*)\)|\[([^\]]*)\])?');

/// Returns the links of [body] in source order, outside fenced code.
///
/// An inline `](dest)` or `](<dest>)` gives its dest; a reference use
/// (`[text][label]`, `[label][]`, `[label]`) gives the dest of its
/// `[label]: dest` definition and the line of the use. Images are no link.
List<_Use> _scanUses(String body, int firstLine) {
  final lines = body.split('\n');
  final fenced = fencedLines(lines);
  final definitions = <String, String>{};
  final definitionLines = <int>{};
  for (var i = 0; i < lines.length; i++) {
    if (fenced[i]) continue;
    final match = _definition.firstMatch(lines[i]);
    if (match == null) continue;
    definitionLines.add(i);
    definitions.putIfAbsent(_label(match[1]!), () => _bare(match[2]!));
  }
  final uses = <_Use>[];
  for (var i = 0; i < lines.length; i++) {
    if (fenced[i] || definitionLines.contains(i)) continue;
    final line = lines[i].replaceAllMapped(_span, (m) => ' ' * m[0]!.length);
    for (final match in _bracket.allMatches(line)) {
      if (match[1] == '!') continue;
      final inline = match[3];
      final label = match[4];
      final dest = inline != null
          ? _inlineDest(inline.trim())
          : definitions[_label(
              label == null || label.isEmpty ? match[2]! : label,
            )];
      if (dest != null) uses.add((dest: dest, line: firstLine + i));
    }
  }
  return uses;
}

String _inlineDest(String inside) {
  if (inside.startsWith('<')) {
    final close = inside.indexOf('>');
    if (close > 0) return inside.substring(1, close);
  }
  return inside.split(RegExp(r'\s+')).first;
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
