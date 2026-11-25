import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/refs.dart';

/// The holders of each index, by the DocPath of the doc they name, built on
/// first use: an index is one read snapshot.
final _holdersOf = Expando<Map<String, List<IndexedDoc>>>();

/// Returns the docs whose `bundle_with` field names [named], in tree order.
List<IndexedDoc> holdersNaming(DocIndex index, IndexedDoc named) =>
    (_holdersOf[index] ??= _holdersBuilt(index))[named.docPath] ?? const [];

Map<String, List<IndexedDoc>> _holdersBuilt(DocIndex index) {
  final byNamed = <String, List<IndexedDoc>>{};
  for (final holder in index.docs) {
    for (final named in linkedDocsOf(index, holder)) {
      (byNamed[named.docPath] ??= []).add(holder);
    }
  }
  return byNamed;
}

/// Adds to [bundle] the docs a `bundle_with` field joins, per target in
/// [picks].
///
/// A target's top doc and whole subtree draw their holders in `design`; a
/// target that is a holder draws the docs it names in every mode. A doc some
/// rule already picks takes no join and keeps its place, and one another
/// target prints in summary moves to whole. Only a doc no rule picks becomes
/// a [LinkedDoc]. A joined doc joins nothing further.
void joinLinkedDocs(DocIndex index, Bundle bundle, List<TargetPicks> picks) {
  final join = _Join(index, bundle);
  for (final target in picks) {
    if (bundle.mode == BundleMode.design) join.inward(target);
    join.outward(target);
  }
}

/// Adds to [bundle] the docs each of [holders] names, in every mode.
///
/// A holder that is no target has no pick: a doc another rule makes
/// summary moves to whole, and a joined doc joins nothing further.
void joinNamedBy(DocIndex index, Bundle bundle, Iterable<IndexedDoc> holders) {
  final join = _Join(index, bundle);
  for (final holder in holders) {
    join.namedBy(holder, const {});
  }
}

final class _Join {
  new(this.index, this.bundle);

  final DocIndex index;
  final Bundle bundle;

  late final Map<String, int> _printAt = {
    for (final (at, doc) in bundle.printOrder(index).indexed) doc.docPath: at,
  };

  /// Joins each holder naming the top doc or a whole doc of [target]'s subtree.
  void inward(TargetPicks target) {
    for (final named in index.docs) {
      final path = named.docPath;
      if (!target.wholePaths.contains(path)) continue;
      if (path != target.topPath && !target.subtreePaths.contains(path)) {
        continue;
      }
      for (final holder in holdersNaming(index, named)) {
        _admit(holder, named, JoinDirection.inward, target.summaryPaths);
      }
    }
  }

  /// Joins each doc [target]'s own doc names, when that doc is a holder.
  void outward(TargetPicks target) {
    final holder = switch (target.targetPath) {
      final path? => index.at(path),
      null => null,
    };
    if (holder != null) namedBy(holder, target.summaryPaths);
  }

  /// Joins each doc [holder] names; [summaryPaths] are the docs the holder's
  /// own target prints in summary, which stay summary.
  void namedBy(IndexedDoc holder, Set<String> summaryPaths) {
    for (final named in linkedDocsOf(index, holder)) {
      _admit(named, holder, JoinDirection.outward, summaryPaths);
    }
  }

  void _admit(
    IndexedDoc doc,
    IndexedDoc anchor,
    JoinDirection direction,
    Set<String> targetSummary,
  ) {
    final path = doc.docPath;
    if (!bundle.keepsTarget(doc) ||
        bundle.docPaths.contains(path) ||
        bundle.joinedPaths.contains(path)) {
      return;
    }
    if (bundle.summaryPaths.contains(path)) {
      if (!targetSummary.contains(path)) bundle.docPaths.add(path);
      return;
    }
    final held = bundle.linkedDocs[path];
    if (held != null && !_printsBefore(anchor.docPath, held.anchorPath)) return;
    bundle.linkedDocs[path] = LinkedDoc(
      docPath: path,
      anchorPath: anchor.docPath,
      direction: direction,
    );
  }

  bool _printsBefore(String path, String other) {
    final at = _printAt[path];
    final otherAt = _printAt[other];
    return at != null && otherAt != null && at < otherAt;
  }
}
