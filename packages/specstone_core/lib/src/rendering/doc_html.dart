import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/html_page.dart' show escapeText;

/// Renders [doc] as html: its title, frontmatter table, draft label, body.
///
/// The body is the text after the frontmatter minus the first line equal to
/// the title line, read as GitHub-flavored markdown. A `mermaid` fence
/// becomes `<pre class="mermaid">` holding its escaped source.
String renderDocBody(Doc doc) {
  final title = doc.title;
  final frontmatter = doc.frontmatter;
  final body = Document(extensionSet: ExtensionSet.gitHubFlavored)
      .parse(_withoutTitleLine(doc.afterFrontmatter, title));
  return [
    if (title != null) '<h1>${escapeText(title)}</h1>',
    if (frontmatter != null && frontmatter.isNotEmpty)
      _frontmatterTable(frontmatter),
    if (doc.isDraft) '<p class="draft">Draft</p>',
    renderToHtml(_withMermaidPre(body)).trimRight(),
  ].where((part) => part.isNotEmpty).join('\n');
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

String _withoutTitleLine(String text, String? title) {
  if (title == null) return text;
  final lines = text.split('\n');
  final index = lines.indexOf('# $title');
  if (index < 0) return text;
  return (lines..removeAt(index)).join('\n');
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
