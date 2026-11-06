import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/doc_model/html_attributes.dart';
import 'package:specstone_core/src/rendering/html_page.dart' show escapeText;

/// Rewrites every `a` element under [nodes] in place for the single-file html.
///
/// An `http` or `https` link (any letter case) stays. A link to a doc in
/// [anchors] jumps to the prefixed id of the anchor its fragment names in that
/// doc's [docAnchors], else to the doc's anchor (an empty fragment included). A
/// bare `#fragment` is the same link to the doc itself, except that a page
/// anchor stays. The renderer's own footnote reference and back link point at
/// the prefixed footnote ids. Any other link, and a target the grammar cannot
/// read, becomes an `outside-link` span that keeps the link text and shows the
/// path or the target as written in `code`.
///
/// - [docPath]: the path of the doc holding [nodes], relative to the docs root.
/// - [anchors]: the section anchor of each doc in the build, by docPath. A bare
///   `#fragment` in a doc with no entry becomes an `outside-link` span.
/// - [docAnchors]: the anchor set of each doc in the build, by docPath.
void rewriteLinks(
  List<Node> nodes, {
  required String docPath,
  required Map<String, String> anchors,
  required Map<String, DocAnchors> docAnchors,
}) {
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is! Element) continue;
    final children = node.children;
    if (children != null) {
      rewriteLinks(
        children,
        docPath: docPath,
        anchors: anchors,
        docAnchors: docAnchors,
      );
    }
    if (node.tag == 'a') {
      nodes[i] = _rewriteLink(
        node,
        docPath: docPath,
        anchors: anchors,
        docAnchors: docAnchors,
      );
    }
  }
}

Node _rewriteLink(
  Element link, {
  required String docPath,
  required Map<String, String> anchors,
  required Map<String, DocAnchors> docAnchors,
}) {
  final href = link.attributes['href'] ?? '';
  if (_isFootnoteLink(link)) return _scopedFootnote(link, anchors[docPath]);
  final target = resolveDocLink(href, docPath);
  switch (target) {
    case WebTarget():
      return link;
    case DocTarget(docPath: final resolved, :final anchor):
      final sectionAnchor = anchors[resolved];
      if (sectionAnchor == null) return _outsideSpan(link, resolved);
      if (href.startsWith('#') && anchors.containsValue(href.substring(1))) {
        return link;
      }
      final named =
          anchor != null &&
          anchor.isNotEmpty &&
          (docAnchors[resolved]?.holds(anchor) ?? false);
      link.attributes['href'] = named
          ? '#$sectionAnchor-${href.substring(href.indexOf('#') + 1)}'
          : '#$sectionAnchor';
      return link;
    case OutsideTarget(:final shown) || UnreadableTarget(:final shown):
      return _outsideSpan(link, shown);
  }
}

// The renderer's footnote reference carries an `fnref-` id and its back link
// the `footnote-backref` class; an author's link carries neither.
bool _isFootnoteLink(Element link) =>
    link.attributes['class'] == 'footnote-backref' ||
    (link.attributes['id'] ?? '').startsWith('fnref-');

Element _scopedFootnote(Element link, String? sectionAnchor) {
  final href = link.attributes['href'] ?? '';
  if (sectionAnchor != null && href.startsWith('#')) {
    link.attributes['href'] = '#$sectionAnchor-${href.substring(1)}';
  }
  return link;
}

/// Prefixes every `id` in [bodyHtml], and the `name` of each `<a>`, with
/// [anchor] and a hyphen.
///
/// Ids then stay unique across the docs of one page. Only real start tags are
/// read: the quotes of an attribute value may be double, single, or absent,
/// attribute names match in any letter case, the first of a repeated name
/// counts, and a comment, declaration, or end tag holds no attribute. Run it
/// after the tag filter, so a tag the filter turns into text holds no id. No
/// `href` changes here; `rewriteLinks` resolved every link it owns.
///
/// - [bodyHtml]: the rendered, tag-filtered html of one doc's body.
/// - [anchor]: the section anchor of that doc.
String scopeIds(String bodyHtml, {required String anchor}) {
  final out = StringBuffer();
  var copied = 0;
  for (final attribute in scanStartTagAttributes(bodyHtml)) {
    if (!_isAnchorSetAttribute(attribute)) continue;
    out
      ..write(bodyHtml.substring(copied, attribute.start))
      ..write('$anchor-${attribute.value}');
    copied = attribute.end;
  }
  return (out..write(bodyHtml.substring(copied))).toString();
}

// The attributes whose values are the doc's anchors (doc_model RULE-13).
bool _isAnchorSetAttribute(HtmlAttribute attribute) =>
    attribute.name == 'id' ||
    (attribute.tag == 'a' && attribute.name == 'name');

// The renderer writes a Text as given, so the path is escaped here.
Element _outsideSpan(Element link, String shown) => Element('span', [
  ...?link.children,
  Text(' ('),
  Element('code', [Text(escapeText(shown))]),
  Text(')'),
])..attributes['class'] = 'outside-link';
