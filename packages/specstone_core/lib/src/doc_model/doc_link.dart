import 'package:specstone_core/src/doc_model/reference_grammar.dart';

/// Where a markdown link points, relative to the doc that holds it.
sealed class DocLinkTarget;

/// An `http` or `https` address.
final class WebTarget extends DocLinkTarget;

/// A doc under the docs root.
final class DocTarget extends DocLinkTarget {
  new(this.docPath, {this.anchor, this.rawAnchor});

  /// The docPath the link resolves to.
  final String docPath;

  /// The fragment the link carries, decoded (RULE-7); null with no `#`; `''`
  /// for `#` alone (the doc's top, RULE-13).
  final String? anchor;

  /// The fragment as written, escapes kept; null with no `#`.
  final String? rawAnchor;
}

/// A target the grammar cannot read (RULE-11); [shown] is the href as
/// written.
final class UnreadableTarget extends DocLinkTarget {
  new(this.shown);

  /// The href as written.
  final String shown;
}

/// Anything else: another scheme, a rooted path, or a path above the docs root.
final class OutsideTarget extends DocLinkTarget {
  new(this.shown);

  /// The path the span shows.
  final String shown;
}

/// Resolves [href], written in the doc at [docPath], to its target, reading
/// [href] through the reference grammar (RULE-11).
///
/// An escape that is not UTF-8 reads as U+FFFD, so such a link resolves like
/// any other path.
DocLinkTarget resolveDocLink(String href, String docPath) {
  switch (readLinkTarget(href)) {
    case UnreadableLink():
      return UnreadableTarget(href);
    case SchemeLink(:final scheme):
      return scheme == 'http' || scheme == 'https'
          ? WebTarget()
          : OutsideTarget(href);
    case AuthorityLink() || RootedLink():
      return OutsideTarget(href);
    case RelativeLink(:final segments, :final anchor, :final rawAnchor):
      // An empty path (`#frag`, `?q`) names the doc itself.
      if (segments.isEmpty) {
        return DocTarget(docPath, anchor: anchor, rawAnchor: rawAnchor);
      }
      final resolved = _resolveSegments(segments, docPath);
      if (resolved == null || resolved.isEmpty) return OutsideTarget(href);
      return DocTarget(resolved, anchor: anchor, rawAnchor: rawAnchor);
  }
}

/// Returns the path [href], written in the doc at [docPath], reaches from
/// the docs root, decoded and normalized, or null when [href] names no file
/// path.
///
/// A path that leaves the docs root keeps its leading `../` segments, except
/// one that re-enters it as `../docs/...`, which names the same file as the
/// path without those two segments. The fragment and query are not part of
/// the path. Null for a web address, another scheme, an authority, a rooted
/// path, an empty path, a path whose walk ends at the docs root itself, and a
/// segment holding an encoded slash.
String? relativeFilePathOf(String href, String docPath) {
  if (readLinkTarget(href) case RelativeLink(:final segments)) {
    // An empty path (`#frag`, `?q`) names no file.
    if (segments.isEmpty) return null;
    final path = _resolveSegments(segments, docPath, keepParents: true);
    return path == null || path.isEmpty ? null : path;
  }
  return null;
}

/// The folder name of the docs root under the project root.
const docsFolderName = 'docs';

/// Returns the docPath [segments] reach from [docPath]'s folder, or null when
/// a `..` pops past the docs root or a segment holds a `/`. An empty result
/// names the docs root.
///
/// A walk that leaves the docs root by exactly one `..` and re-enters it
/// through [docsFolderName] resolves as if it never left. With [keepParents],
/// any other `..` past the docs root stays in the result instead of failing.
///
/// [segments] are already percent-decoded, so an encoded slash (`%2F`)
/// decoded to one segment cannot name a doc.
String? _resolveSegments(
  List<String> segments,
  String docPath, {
  bool keepParents = false,
}) {
  final path = docPath.split('/')..removeLast();
  for (final segment in segments) {
    switch (segment) {
      case '' || '.':
        continue;
      case '..':
        if (path.isEmpty || path.last == '..') {
          path.add('..');
        } else {
          path.removeLast();
        }
      case _ when segment.contains('/'):
        return null;
      default:
        path.add(segment);
    }
  }
  if (path.length >= 2 && path[0] == '..' && path[1] == docsFolderName) {
    path.removeRange(0, 2);
  }
  if (!keepParents && path.isNotEmpty && path.first == '..') return null;
  return path.join('/');
}
