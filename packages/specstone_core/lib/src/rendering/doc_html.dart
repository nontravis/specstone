import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/html_page.dart' show escapeText;
import 'package:specstone_core/src/rendering/link_rewrite.dart';

/// Renders [doc] as html: its title, frontmatter table, draft label, body.
///
/// The body is the text after the frontmatter minus the title line, read as
/// GitHub-flavored markdown. A `mermaid` fence becomes `<pre class="mermaid">`
/// holding its escaped source. A blank title line shows no title. Links are
/// rewritten by `rewriteLinks`, and every `id` of the body, raw html included,
/// is prefixed with the doc's anchor by `scopeIds`. The GFM tag filter turns a
/// raw start or end tag of `title`, `script`, `style`, `textarea` and the like
/// into text, so one doc cannot swallow the docs after it.
///
/// - [docPath]: the path of [doc] relative to the docs root.
/// - [anchors]: the section anchor of each doc in the build, by docPath.
String renderDocBody(
  Doc doc, {
  required String docPath,
  required Map<String, String> anchors,
}) {
  final title = shownTitle(doc);
  final anchor = anchors[docPath];
  final frontmatter = doc.frontmatter;
  final body = Document(extensionSet: ExtensionSet.gitHubFlavored)
      .parse(_withoutTitleLine(doc));
  rewriteLinks(body, docPath: docPath, anchors: anchors);
  return [
    if (title != null) '<h1>${escapeText(title)}</h1>',
    if (frontmatter != null && frontmatter.isNotEmpty)
      _frontmatterTable(frontmatter),
    if (doc.isDraft) '<p class="draft">Draft</p>',
    _withTagFilter(_bodyHtml(body, anchor, anchors)).trimRight(),
  ].where((part) => part.isNotEmpty).join('\n');
}

// A doc with no anchor is not on the page, so its ids have nothing to scope to.
String _bodyHtml(List<Node> body, String? anchor, Map<String, String> anchors) {
  final html = renderToHtml(_withMermaidPre(body));
  if (anchor == null) return html;
  return scopeIds(html, anchor: anchor, pageAnchors: anchors.values.toSet());
}

/// Tags the GFM "disallowed raw HTML" rule writes as text, plus `noscript` and
/// `template`, whose unclosed start tag also swallows the docs after it.
///
/// The `markdown` package's own filter only matches a start tag without
/// attributes, so `<title lang=x>` and `</title>` get through it.
final _disallowedTag = RegExp(
  '<(?=/?(?:title|textarea|style|xmp|iframe|noembed|noframes|script|plaintext'
  r'|noscript|template)[\s/>])',
  caseSensitive: false,
);

String _withTagFilter(String html) => html.replaceAll(_disallowedTag, '&lt;');

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
