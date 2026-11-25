import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart'
    show DocTarget, resolveDocLink;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show LinkPlace, relativeHref, withLinkPlaces;

/// A heading anchor in a doc: the doc's DocPath and the anchor.
final class AnchorPlace {
  const new(this.docPath, this.anchor);

  final String docPath;
  final String anchor;
}

/// Where each heading anchor a keyed move changes sits after it, by its
/// DocPath and anchor before the move.
final class AnchorMoves {
  final _places = <String, Map<String, AnchorPlace>>{};

  bool get isEmpty => _places.isEmpty;

  /// The DocPaths whose anchors change.
  Iterable<String> get docPaths => _places.keys;

  /// Records that the anchor [anchor] of [docPath] becomes [place].
  void add(String docPath, String anchor, AnchorPlace place) =>
      (_places[docPath] ??= {})[anchor] = place;

  /// Returns where the anchor [anchor] of [docPath] sits after the move; null
  /// when it does not change.
  AnchorPlace? placeOf(String docPath, String anchor) =>
      _places[docPath]?[anchor];
}

/// Returns [lfText], written in the doc at [docPath], with each link to an
/// anchor [moves] changes set to reach its new place; null when none changes.
///
/// A link that reaches the doc it sits in takes an empty path, and a link
/// whose doc keeps the anchor's heading keeps its path.
String? withFollowedAnchors(String lfText, String docPath, AnchorMoves moves) {
  if (moves.isEmpty) return null;
  final body = Doc.parse(lfText).afterFrontmatter;
  final edited = withLinkPlaces(
    body,
    (href) => _followedPlace(href, docPath, moves),
  );
  if (edited == body) return null;
  return lfText.substring(0, lfText.length - body.length) + edited;
}

LinkPlace? _followedPlace(String href, String docPath, AnchorMoves moves) {
  if (resolveDocLink(href, docPath) case DocTarget(
    docPath: final target,
    :final anchor?,
  )) {
    final place = moves.placeOf(target, anchor);
    if (place == null) return null;
    return LinkPlace(
      path: switch (place.docPath) {
        final to when to == target => null,
        final to when to == docPath => '',
        final to => relativeHref(docPath, to),
      },
      anchor: place.anchor == anchor ? null : place.anchor,
    );
  }
  return null;
}
