import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/html_attributes.dart';
import 'package:specstone_core/src/doc_model/percent_decode.dart';
import 'package:specstone_core/src/rendering/html_page.dart' show escapeText;

/// Rewrites every `a` element under [nodes] in place for the single-file html.
///
/// An `http` or `https` link (any letter case) stays. A link to a doc in
/// [anchors] jumps to that doc's anchor. A bare `#fragment` stays as written
/// for `scopeIds`, which runs on the rendered html. Any other link becomes an
/// `outside-link` span that keeps the link text and shows the path in `code`.
///
/// - [docPath]: the path of the doc holding [nodes], relative to the docs root.
/// - [anchors]: the section anchor of each doc in the build, by docPath. A bare
///   `#fragment` in a doc with no entry becomes an `outside-link` span.
void rewriteLinks(
  List<Node> nodes, {
  required String docPath,
  required Map<String, String> anchors,
}) {
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is! Element) continue;
    final children = node.children;
    if (children != null) {
      rewriteLinks(children, docPath: docPath, anchors: anchors);
    }
    if (node.tag == 'a') {
      nodes[i] = _rewriteLink(node, docPath: docPath, anchors: anchors);
    }
  }
}

Node _rewriteLink(
  Element link, {
  required String docPath,
  required Map<String, String> anchors,
}) {
  final href = link.attributes['href'] ?? '';
  final target = resolveDocLink(href, docPath);
  switch (target) {
    case WebTarget():
      return link;
    case DocTarget(docPath: final resolved):
      final anchor = anchors[resolved];
      if (anchor == null) return _outsideSpan(link, resolved);
      if (href.startsWith('#')) return link;
      link.attributes['href'] = '#$anchor';
      return link;
    case OutsideTarget(:final shown):
      return _outsideSpan(link, shown);
    case UnreadableTarget(:final shown):
      // Task 7 gives the unreadable target its own outcome.
      return _outsideSpan(link, shown);
  }
}

/// Prefixes every `id` in [bodyHtml] with [anchor] and a hyphen, and points
/// each bare `#fragment` link at the result.
///
/// Ids then stay unique across the docs of one page. Only real start tags are
/// read: the quotes of an attribute value may be double, single, or absent,
/// attribute names match in any letter case, the first of a repeated name
/// counts, and a comment, declaration, or end tag holds no attribute. A
/// fragment that is a page anchor in [pageAnchors] is a link `rewriteLinks`
/// already resolved and stays, even when the body holds an id equal to it. Else
/// a fragment that names an id of the body (`fn-1`, `top`) goes to the prefixed
/// id (`doc-3-fn-1`), and any other fragment goes to [anchor]. Run it after the
/// tag filter, so a tag the filter turns into text holds no id.
///
/// - [bodyHtml]: the rendered, tag-filtered html of one doc's body.
/// - [anchor]: the section anchor of that doc.
/// - [pageAnchors]: the section anchor of every doc in the build.
String scopeIds(
  String bodyHtml, {
  required String anchor,
  required Set<String> pageAnchors,
}) {
  final attributes = scanStartTagAttributes(bodyHtml);
  final ids = {
    for (final attribute in attributes)
      if (attribute.name == 'id') attribute.value,
  };
  final out = StringBuffer();
  var copied = 0;
  for (final attribute in attributes) {
    final String? replacement;
    if (attribute.name == 'id') {
      replacement = '$anchor-${attribute.value}';
    } else if (attribute.value.startsWith('#')) {
      final fragment = attribute.value.substring(1);
      if (pageAnchors.contains(fragment)) continue;
      replacement =
          '#${_namesId(fragment, ids) ? '$anchor-$fragment' : anchor}';
    } else {
      continue;
    }
    out
      ..write(bodyHtml.substring(copied, attribute.start))
      ..write(replacement);
    copied = attribute.end;
  }
  return (out..write(bodyHtml.substring(copied))).toString();
}

// A fragment may be written percent-encoded, an id never is.
bool _namesId(String fragment, Set<String> ids) =>
    ids.contains(fragment) || ids.contains(percentDecoded(fragment));

// The renderer writes a Text as given, so the path is escaped here.
Element _outsideSpan(Element link, String shown) => Element('span', [
  ...?link.children,
  Text(' ('),
  Element('code', [Text(escapeText(shown))]),
  Text(')'),
])..attributes['class'] = 'outside-link';
