import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/html_attributes.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:specstone_core/src/rendering/html_page.dart' show escapeText;
import 'package:specstone_core/src/rendering/link_rewrite.dart';

/// Renders [doc] as html: its title, frontmatter table, draft label, body.
///
/// The body is the text after the frontmatter, read as GitHub-flavored
/// markdown, minus its title heading. A `mermaid` fence becomes
/// `<pre class="mermaid">` holding its escaped source. A blank title line shows
/// no title. Every heading, the title included, takes the id of its slug in
/// [docAnchors] (doc_model RULE-13). Links are rewritten by `rewriteLinks`. The
/// GFM tag filter then turns a raw start or end tag of `title`, `script`,
/// `style`, `textarea` and the like into text, so one doc cannot swallow the
/// docs after it. Last, `scopeIds` prefixes every `id` and each `<a>`'s `name`
/// of a real start tag of the body, raw html included, with the doc's anchor.
///
/// When `parseMarkdown` fails on the body, the body part is its escaped text in
/// one `<pre>`, the title, frontmatter table, and draft label render as above,
/// and `bodyParsed` is false.
///
/// - [docPath]: the path of [doc] relative to the docs root.
/// - [anchors]: the section anchor of each doc in the build, by docPath.
/// - [docAnchors]: the anchor set of each doc in the build, by docPath, read
///   from the text after the frontmatter, title line included.
({String html, bool bodyParsed}) renderDocBody(
  Doc doc, {
  required String docPath,
  required Map<String, String> anchors,
  required Map<String, DocAnchors> docAnchors,
}) {
  final title = shownTitle(doc);
  final anchor = anchors[docPath];
  final frontmatter = doc.frontmatter;
  final parsed = parseMarkdown(doc.afterFrontmatter);
  final headed = parsed == null
      ? null
      : _withHeadingIds(
          parsed,
          slugs: docAnchors[docPath]?.headingSlugs ?? const [],
          hasTitle: doc.titleLineIndex != null,
        );
  final body = headed?.body;
  if (body != null) {
    rewriteLinks(
      body,
      docPath: docPath,
      anchors: anchors,
      docAnchors: docAnchors,
    );
  }
  final html = [
    if (title != null) _titleHtml(title, anchor, headed?.titleSlug),
    if (frontmatter != null && frontmatter.isNotEmpty)
      _frontmatterTable(frontmatter),
    if (doc.isDraft) '<p class="draft">Draft</p>',
    if (body == null)
      '<pre>${escapeText(_withoutTitleLine(doc))}</pre>'
    else
      _bodyHtml(body, anchor).trimRight(),
  ].where((part) => part.isNotEmpty).join('\n');
  return (html: html, bodyParsed: body != null);
}

String _titleHtml(String title, String? anchor, String? slug) {
  final id = anchor == null || slug == null ? '' : ' id="$anchor-$slug"';
  return '<h1$id>${escapeText(title)}</h1>';
}

// A doc with no anchor is not on the page, so its ids have nothing to scope to.
String _bodyHtml(List<Node> body, String? anchor) {
  final html = withTagFilter(renderToHtml(_withMermaidPre(body)));
  return anchor == null ? html : scopeIds(html, anchor: anchor);
}

// Gives each heading, in document order, the slug `anchorsOf` gave it, so
// check and build agree (P2), and takes the title heading out of the body: the
// first `h1`, which the title line makes. Code subtrees hold no heading.
({List<Node> body, String? titleSlug}) _withHeadingIds(
  List<Node> nodes, {
  required List<String> slugs,
  required bool hasTitle,
}) {
  var next = 0;
  void walk(List<Node> level) {
    for (final node in level) {
      if (node is! Element || node.tag == 'code' || node.tag == 'pre') continue;
      if (_isHeading(node.tag) && next < slugs.length) {
        node.attributes['id'] = slugs[next];
      }
      if (_isHeading(node.tag)) next++;
      walk(node.children ?? const []);
    }
  }

  walk(nodes);
  if (!hasTitle) return (body: nodes, titleSlug: null);
  final at = nodes.indexWhere((n) => n is Element && n.tag == 'h1');
  if (at < 0) return (body: nodes, titleSlug: null);
  final titleSlug = (nodes[at] as Element).attributes['id'];
  return (body: [...nodes]..removeAt(at), titleSlug: titleSlug);
}

bool _isHeading(String tag) =>
    const {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(tag);

/// Returns the title [doc] shows, or null when it has none or it is blank.
String? shownTitle(Doc doc) {
  final title = doc.title;
  return title == null || title.trim().isEmpty ? null : title;
}

String _frontmatterTable(List<KeyBlock> blocks) {
  final rows = [for (final block in blocks) _row(block)];
  return '<table class="frontmatter">${rows.join()}</table>';
}

String _row(KeyBlock block) {
  final key = escapeText(block.key);
  final value = escapeText(block.key.isEmpty ? block.text : block.valueText);
  return '<tr><th>$key</th><td>$value</td></tr>';
}

String _withoutTitleLine(Doc doc) {
  final index = doc.titleLineIndex;
  if (index == null) return doc.afterFrontmatter;
  return (doc.afterFrontmatter.split('\n')..removeAt(index)).join('\n');
}

List<Node> _withMermaidPre(List<Node> nodes) => [
  for (final node in nodes) _replaceMermaid(node),
];

Node _replaceMermaid(Node node) {
  if (node is! Element) return node;
  final code = _mermaidCode(node);
  if (code != null) {
    return Element('pre', [Text(code.textContent.trimRight())])
      ..attributes['class'] = 'mermaid';
  }
  final children = node.children;
  if (children != null) {
    for (var i = 0; i < children.length; i++) {
      children[i] = _replaceMermaid(children[i]);
    }
  }
  return node;
}

/// Returns the `code` child of a `pre` holding a mermaid fence, else null.
Element? _mermaidCode(Element element) {
  if (element.tag != 'pre') return null;
  final children = element.children;
  if (children == null || children.length != 1) return null;
  final child = children.single;
  if (child is Element &&
      child.tag == 'code' &&
      child.attributes['class'] == 'language-mermaid') {
    return child;
  }
  return null;
}
