/// Where a markdown link points, relative to the doc that holds it.
sealed class DocLinkTarget;

/// An `http` or `https` address.
final class WebTarget extends DocLinkTarget;

/// A doc under the docs root.
final class DocTarget extends DocLinkTarget {
  new(this.docPath);

  /// The docPath the link resolves to.
  final String docPath;
}

/// Anything else: another scheme, a rooted path, or a path above the docs root.
final class OutsideTarget extends DocLinkTarget {
  new(this.shown);

  /// The path the span shows.
  final String shown;
}

/// Resolves [href], written in the doc at [docPath], to its target.
DocLinkTarget resolveDocLink(String href, String docPath) {
  final uri = Uri.tryParse(href);
  if (uri == null) return OutsideTarget(href);
  if (uri.hasScheme) {
    final scheme = uri.scheme;
    return scheme == 'http' || scheme == 'https'
        ? WebTarget()
        : OutsideTarget(href);
  }
  if (uri.hasAuthority || uri.path.startsWith('/')) return OutsideTarget(href);
  // An empty path (`#frag`, `?q`) names the doc itself.
  if (uri.path.isEmpty) return DocTarget(docPath);
  final resolved = _resolveSegments(uri.pathSegments, docPath);
  if (resolved == null || resolved.isEmpty) return OutsideTarget(href);
  return DocTarget(resolved);
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
