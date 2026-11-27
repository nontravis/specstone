import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart'
    show DocTarget, resolveDocLink;
import 'package:specstone_core/src/document_writing/rewrite_refs.dart'
    show LinkPlace, relativeHref, withLinkPlaces;
import 'package:specstone_core/src/setup_migration/heading_ledger.dart';
import 'package:specstone_core/src/setup_migration/merge_doc_step.dart'
    show FoldedDocs;

/// What a link pass changed in one doc, by the step kind it followed.
enum LinkChange {
  merged('links to merged docs'),
  renamed('links to renamed sections'),
  dropped('links to dropped sections');

  new(this.label);

  /// The plan label of the change.
  final String label;
}

/// A doc after the link pass: its text and the kinds of change made.
final class FollowedLinks {
  const new(this.lf, this.changes);

  final String lf;

  /// In [LinkChange] order.
  final List<LinkChange> changes;
}

/// What one link becomes: a new place, or its text alone.
final class _Fate {
  const new(this.change, {this.place}) : unwraps = place == null;

  final LinkChange change;
  final LinkPlace? place;
  final bool unwraps;
}

/// Returns [lf], the doc at [docPath] after the run's steps, with each link
/// set where [anchors] puts its target, and each typed link text [folds]
/// retypes set to its last typed name and key.
///
/// A link that would reach the doc holding it with no anchor, or reach an
/// anchor of it a drop took, becomes its text.
FollowedLinks followLinks(
  String lf,
  String docPath, {
  required FinalAnchors anchors,
  required FoldedDocs folds,
}) {
  final body = Doc.parse(lf).afterFrontmatter;
  final changes = <LinkChange>{};
  final fates = <String, _Fate?>{};
  _Fate? fateOf(String href) =>
      fates.putIfAbsent(href, () => _fateOf(href, docPath, anchors));
  final edited = withLinkPlaces(
    body,
    (href) => _noted(fateOf(href), changes)?.place,
    textOf: folds.mayRetype(body)
        ? (_, text) {
            final retyped = folds.textOf(text);
            if (retyped != null) {
              changes.add(
                retyped.isFolded ? LinkChange.merged : LinkChange.renamed,
              );
            }
            return retyped?.text;
          }
        : null,
    unwraps: anchors.follows(docPath)
        ? (href) => _noted(fateOf(href), changes)?.unwraps ?? false
        : null,
  );
  return FollowedLinks(
    edited == body ? lf : lf.substring(0, lf.length - body.length) + edited,
    [
      for (final change in LinkChange.values)
        if (changes.contains(change)) change,
    ],
  );
}

_Fate? _noted(_Fate? fate, Set<LinkChange> changes) {
  if (fate != null) changes.add(fate.change);
  return fate;
}

/// Returns the fate of [href], written in the doc at [docPath], or null when
/// it keeps its target.
_Fate? _fateOf(String href, String docPath, FinalAnchors anchors) {
  if (resolveDocLink(href, docPath) case DocTarget(
    docPath: final target,
    :final anchor,
  )) {
    if (anchor == null && target == docPath && anchors.isFoldTarget(docPath)) {
      return const _Fate(LinkChange.merged);
    }
    return switch (anchors.landingOf(target, anchor)) {
      null => null,
      final landing when landing.isLost => _lostFate(
        landing,
        docPath,
        target: target,
      ),
      final landing => _movedFate(
        landing,
        docPath,
        target: target,
        anchor: anchor,
        change: anchors.isFolded(target)
            ? LinkChange.merged
            : LinkChange.renamed,
      ),
    };
  }
  return null;
}

/// Returns the fate of a link from the doc at [docPath] to an anchor of
/// [target] gone from [landing]'s doc: unwrapped there, the doc whole
/// elsewhere, its path kept as written when that doc is still [target].
_Fate _lostFate(
  LinkLanding landing,
  String docPath, {
  required String target,
}) => landing.docPath == docPath
    ? const _Fate(LinkChange.dropped)
    : _Fate(
        LinkChange.dropped,
        place: LinkPlace(
          path: landing.docPath == target
              ? null
              : relativeHref(docPath, landing.docPath),
          dropsAnchor: true,
        ),
      );

/// Returns the fate of a link from the doc at [docPath] to [anchor] of
/// [target], which lands at [landing], or null when it stays.
_Fate? _movedFate(
  LinkLanding landing,
  String docPath, {
  required String target,
  required String? anchor,
  required LinkChange change,
}) {
  final isHere = landing.docPath == docPath;
  // A whole-doc link from another doc reaches the `to` doc whole; only the
  // `to` doc itself needs the anchor to name no self link.
  final slug = anchor == null && !isHere ? null : landing.slug;
  if (slug == null && isHere) return _Fate(change);
  if (landing.docPath == target && slug == anchor) return null;
  return _Fate(
    change,
    place: LinkPlace(
      path: landing.docPath == target
          ? null
          : (isHere ? '' : relativeHref(docPath, landing.docPath)),
      anchor: slug == null || slug == anchor ? null : Uri.encodeComponent(slug),
    ),
  );
}
