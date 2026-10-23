import 'package:markdown/markdown.dart';
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
  final target = _resolve(href, docPath);
  switch (target) {
    case _Web():
      return link;
    case _Doc(:final path):
      final anchor = anchors[path];
      if (anchor == null) return _outsideSpan(link, path);
      if (href.startsWith('#')) return link;
      link.attributes['href'] = '#$anchor';
      return link;
    case _Outside(:final shown):
      return _outsideSpan(link, shown);
  }
}

final _idAttribute = RegExp(r'(\sid=")([^"]*)(")');
final _fragmentHref = RegExp(r'(\shref="#)([^"]*)(")');

/// Prefixes every `id` in [bodyHtml] with [anchor] and a hyphen, and points
/// each bare `#fragment` link at the result.
///
/// Ids then stay unique across the docs of one page. A fragment that names an
/// id of the body (`fn-1`, `top`) goes to the prefixed id (`doc-3-fn-1`); any
/// other fragment goes to [anchor]. A fragment that is a page anchor in
/// [pageAnchors] is a link `rewriteLinks` already resolved and stays. Markdown
/// escapes the quotes of code and text, so only real tags match.
///
/// - [bodyHtml]: the rendered html of one doc's body.
/// - [anchor]: the section anchor of that doc.
/// - [pageAnchors]: the section anchor of every doc in the build.
String scopeIds(
  String bodyHtml, {
  required String anchor,
  required Set<String> pageAnchors,
}) {
  final ids = {
    for (final match in _idAttribute.allMatches(bodyHtml)) match.group(2)!,
  };
  return bodyHtml
      .replaceAllMapped(
        _idAttribute,
        (match) => '${match[1]}$anchor-${match[2]}${match[3]}',
      )
      .replaceAllMapped(_fragmentHref, (match) {
        final fragment = match[2]!;
        final String target;
        if (_namesId(fragment, ids)) {
          target = '$anchor-$fragment';
        } else if (pageAnchors.contains(fragment)) {
          target = fragment;
        } else {
          target = anchor;
        }
        return '${match[1]}$target${match[3]}';
      });
}

final _brokenPercent = RegExp('%(?![0-9A-Fa-f]{2})');

// A fragment may be written percent-encoded, an id never is.
bool _namesId(String fragment, Set<String> ids) {
  if (ids.contains(fragment)) return true;
  if (_brokenPercent.hasMatch(fragment)) return false;
  try {
    return ids.contains(Uri.decodeComponent(fragment));
  } on FormatException {
    return false;
  }
}

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
