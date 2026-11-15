import 'package:specstone_core/src/doc_model/records_root.dart'
    show isRecordsDocPath;
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

  /// The fragment the link carries, decoded; null with no `#`; `''`
  /// for `#` alone (the doc's top).
  final String? anchor;

  /// The fragment as written, escapes kept; null with no `#`.
  final String? rawAnchor;
}

/// A target the grammar cannot read; [shown] is the href as
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
/// [href] through the reference grammar.
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
/// the root that doc is read from (the docs root, or the project root for a
/// record), decoded and normalized, or null when [href] names no file path.
///
/// A path that leaves the docs root keeps its leading `../` segments, except
/// one that re-enters it as `../docs/...`, which names the same file as the
/// path without those two segments. A record keeps its project-root path, so
/// `../../../docs/x.md` stays `docs/x.md`. The fragment and query are not part
/// of the path. Null for a web address, another scheme, an authority, a rooted
/// path, an empty path, a path whose walk ends at the docs root itself (a
/// record's too) or at the project root a record is read from, and a segment
/// holding an encoded slash.
String? relativeFilePathOf(String href, String docPath) {
  if (readLinkTarget(href) case RelativeLink(:final segments)) {
    // An empty path (`#frag`, `?q`) names no file.
    if (segments.isEmpty) return null;
    final path = _resolveSegments(segments, docPath, keepParents: true);
    return path == null || path.isEmpty ? null : path;
  }
  return null;
}

/// Returns [filePath], as [relativeFilePathOf] gives it for the doc at
/// [docPath], as a path from the project root.
String projectFilePathOf(String filePath, String docPath) {
  if (isRecordsDocPath(docPath)) return filePath;
  if (filePath == '..') return '';
  return filePath.startsWith('../')
      ? filePath.substring('../'.length)
      : '$docsFolderName/$filePath';
}

/// The folder name of the docs root under the project root.
const docsFolderName = 'docs';

/// Returns the docPath [segments] reach from [docPath]'s folder, or null when
/// the walk lands in neither the docs root nor the records root or a segment
/// holds a `/`. An empty result names the docs root.
///
/// The walk runs from the project root, so a doc and a record share one rule:
/// a path below `docs/` is a docs DocPath, one below `.specstone/records/` is
/// a records DocPath, and a doc that leaves the docs root by one `..` and
/// re-enters it through [docsFolderName] resolves as if it never left. With
/// [keepParents] the result is a file path from the root [docPath] is read
/// from: a path outside the docs root keeps its leading `../`, and a record's
/// path stays from the project root.
///
/// [segments] are already percent-decoded, so an encoded slash (`%2F`)
/// decoded to one segment cannot name a doc.
String? _resolveSegments(
  List<String> segments,
  String docPath, {
  bool keepParents = false,
}) {
  final isRecord = isRecordsDocPath(docPath);
  final path = [if (!isRecord) docsFolderName, ...docPath.split('/')]
    ..removeLast();
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
  if (keepParents && isRecord) {
    final isDocsRoot = path.length == 1 && path.first == docsFolderName;
    return isDocsRoot ? '' : path.join('/');
  }
  if (path.isNotEmpty && path.first == docsFolderName) {
    return path.skip(1).join('/');
  }
  if (keepParents) return ['..', ...path].join('/');
  final fromProject = path.join('/');
  return isRecordsDocPath(fromProject) ? fromProject : null;
}
