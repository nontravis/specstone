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

/// Yields a finding per link of [doc] that targets a doc of a checked folder
/// where none is indexed.
///
/// The index stores each target once, so a doc holding such a target is parsed
/// again to list its links in order; each finding's line is that of the first
/// `](<href>` or `]: <href>` after the previous finding's match.
Iterable<Finding> _unresolvedLinks(CheckContext context, IndexedDoc doc) sync* {
  final broken = {
    for (final target in context.contentOf(doc).links)
      if (context.isCheckedPath(target) && context.index.at(target) == null)
        target,
  };
  if (broken.isEmpty) return;
  final text = toLf(context.contentOf(doc).text);
  var cursor = text.length - Doc.parse(text).afterFrontmatter.length;
  for (final href in _hrefsOf(text.substring(cursor))) {
    final target = resolveDocLink(href, doc.docPath);
    if (target is! DocTarget || !broken.contains(target.docPath)) continue;
    final at = _firstMention(text, href, cursor);
    if (at >= 0) cursor = at;
    yield context.finding(
      doc,
      FindingKind.linkUnresolved,
      line: _lineAt(text, cursor),
      message: 'link target $href is no doc',
      keys: {'target': href},
    );
    cursor += 1;
  }
}

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

/// Returns the offset of the first `](<href>` or `]: <href>` in [text] at or
/// after [from], or -1 when neither occurs.
int _firstMention(String text, String href, int from) {
  final inline = text.indexOf(']($href', from);
  final definition = text.indexOf(']: $href', from);
  if (inline < 0) return definition;
  if (definition < 0) return inline;
  return inline < definition ? inline : definition;
}

/// Returns the 1-based line of the character at [offset] in [text].
int _lineAt(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length + 1;
