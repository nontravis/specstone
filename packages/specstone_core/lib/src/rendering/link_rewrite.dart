import 'package:markdown/markdown.dart';
import 'package:specstone_core/src/rendering/html_page.dart' show escapeText;

/// Rewrites every `a` element under [nodes] in place for the single-file html,
/// and prefixes every `id` under [nodes] with the doc's anchor.
///
/// An `http` or `https` link (any letter case) stays. A bare `#fragment` naming
/// an `id` under [nodes] points at that id once prefixed (`doc-3-fn-1`), so ids
/// stay unique across the docs of one page. A link to a doc in [anchors], or
/// any other bare `#fragment`, jumps to that doc's anchor. Any other link
/// becomes an `outside-link` span that keeps the link text and shows the path
/// in `code`.
///
/// - [docPath]: the path of the doc holding [nodes], relative to the docs root.
/// - [anchors]: the section anchor of each doc in the build, by docPath. A doc
///   with no entry keeps its ids as written.
void rewriteLinks(
  List<Node> nodes, {
  required String docPath,
  required Map<String, String> anchors,
}) {
  final idPrefix = anchors[docPath];
  final ownIds = idPrefix == null ? const <String>{} : _collectIds(nodes);
  _rewrite(
    nodes,
    docPath: docPath,
    anchors: anchors,
    idPrefix: idPrefix,
    ownIds: ownIds,
  );
  if (idPrefix != null) _prefixIds(nodes, idPrefix);
}

void _rewrite(
  List<Node> nodes, {
  required String docPath,
  required Map<String, String> anchors,
  required String? idPrefix,
  required Set<String> ownIds,
}) {
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is! Element) continue;
    final children = node.children;
    if (children != null) {
      _rewrite(
        children,
        docPath: docPath,
        anchors: anchors,
        idPrefix: idPrefix,
        ownIds: ownIds,
      );
    }
    if (node.tag == 'a') {
      nodes[i] = _rewriteLink(
        node,
        docPath: docPath,
        anchors: anchors,
        idPrefix: idPrefix,
        ownIds: ownIds,
      );
    }
  }
}

Set<String> _collectIds(List<Node> nodes) => {
  for (final node in nodes)
    if (node is Element) ...[
      ?node.attributes['id'],
      ..._collectIds(node.children ?? const []),
    ],
};

void _prefixIds(List<Node> nodes, String prefix) {
  for (final node in nodes) {
    if (node is! Element) continue;
    final id = node.attributes['id'];
    if (id != null) node.attributes['id'] = '$prefix-$id';
    _prefixIds(node.children ?? const [], prefix);
  }
}

Node _rewriteLink(
  Element link, {
  required String docPath,
  required Map<String, String> anchors,
  required String? idPrefix,
  required Set<String> ownIds,
}) {
  final href = link.attributes['href'] ?? '';
  if (idPrefix != null && ownIds.contains(_bareFragment(href))) {
    link.attributes['href'] = '#$idPrefix-${href.substring(1)}';
    return link;
  }
  final target = _resolve(href, docPath);
  switch (target) {
    case _Web():
      return link;
    case _Doc(:final path):
      final anchor = anchors[path];
      if (anchor == null) return _outsideSpan(link, path);
      link.attributes['href'] = '#$anchor';
      return link;
    case _Outside(:final shown):
      return _outsideSpan(link, shown);
  }
}

/// Returns the decoded fragment of a `#fragment` [href], else null.
String? _bareFragment(String href) =>
    href.startsWith('#') ? Uri.tryParse(href)?.fragment : null;

// The renderer writes a Text as given, so the path is escaped here.
Element _outsideSpan(Element link, String shown) => Element('span', [
  ...?link.children,
  Text(' ('),
  Element('code', [Text(escapeText(shown))]),
  Text(')'),
])..attributes['class'] = 'outside-link';

sealed class _Target;

final class _Web extends _Target;

final class _Doc extends _Target {
  new(this.path);

  /// The docPath the link resolves to.
  final String path;
}

final class _Outside extends _Target {
  new(this.shown);

  /// The path the span shows.
  final String shown;
}

_Target _resolve(String href, String docPath) {
  final uri = Uri.tryParse(href);
  if (uri == null) return _Outside(href);
  if (uri.hasScheme) {
    final scheme = uri.scheme;
    return scheme == 'http' || scheme == 'https' ? _Web() : _Outside(href);
  }
  if (uri.hasAuthority || uri.path.startsWith('/')) return _Outside(href);
  // An empty path (`#frag`, `?q`) names the doc itself.
  if (uri.path.isEmpty) return _Doc(docPath);
  final resolved = _resolveSegments(uri.pathSegments, docPath);
  if (resolved == null || resolved.isEmpty) return _Outside(href);
  return _Doc(resolved);
}

/// Returns the docPath [segments] reach from [docPath]'s folder, or null when
/// a `..` pops past the docs root or a decoded segment holds a `/`. An empty
/// result names the docs root.
///
/// [segments] are split on `/` before they are percent-decoded, so an encoded
/// slash (`%2F`) belongs to one segment and cannot name a doc.
String? _resolveSegments(List<String> segments, String docPath) {
  final path = docPath.split('/')..removeLast();
  for (final segment in segments) {
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (path.isEmpty) return null;
        path.removeLast();
      case _ when segment.contains('/'):
        return null;
      default:
        path.add(segment);
    }
  }
  return path.join('/');
}
