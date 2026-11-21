import 'package:specstone_core/src/fault.dart';
import 'package:specstone_core/src/index_query/bundle_join.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/template_fault.dart';

/// The mode a bundle's docs are picked for; [wire] is the `--for` word.
enum BundleMode {
  query('query'),
  implement('implement'),
  design('design');

  new(this.wire);

  /// The word `--for` takes.
  final String wire;

  /// Returns the mode [value] names, or throws for null or another word.
  static BundleMode parse(String? value) {
    if (value == null) {
      throw missingArgument(
        'context',
        '--for',
        'specstone context login --for implement',
      );
    }
    for (final mode in BundleMode.values) {
      if (mode.wire == value) return mode;
    }
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '--for takes query, implement, or design, not $value',
    );
  }
}

/// The side of a `bundle_with` link a joined doc enters the bundle from.
enum JoinDirection {
  /// The holder joins a bundle that prints the doc it names.
  inward,

  /// The doc a holder target names joins that target's bundle.
  outward,
}

/// A doc no rule picks that a `bundle_with` field joins to a bundle.
final class LinkedDoc {
  const new({
    required this.docPath,
    required this.anchorPath,
    required this.direction,
  });

  /// The joined doc's DocPath.
  final String docPath;

  /// The DocPath of the doc it prints beside: the doc it names when it joins
  /// inward, its holder when it joins outward.
  final String anchorPath;

  /// The side the doc joined from.
  final JoinDirection direction;
}

/// The docs one target's pick adds, apart from the other targets'.
final class TargetPicks {
  const new({
    required this.topPath,
    required this.wholePaths,
    required this.summaryPaths,
    required this.subtreePaths,
    this.targetPath,
  });

  /// The DocPath of the target's top doc: its nearest nesting doc in `design`.
  final String topPath;

  /// The docs the target's rule prints whole, by DocPath.
  final Set<String> wholePaths;

  /// The docs the target's rule prints in summary, by DocPath.
  final Set<String> summaryPaths;

  /// The target's own subtree, by DocPath; filled in `design`.
  final Set<String> subtreePaths;

  /// The DocPath of the doc the call names for this target, when it names
  /// one: an outward join runs from it.
  final String? targetPath;
}

/// The docs one `context` call prints, picked by [BundleMode].
final class Bundle {
  new(this.mode, {this.summary = false, this.codeTarget});

  /// The mode the docs are picked for.
  final BundleMode mode;

  /// Whether `--summary` asked for the feature's stories in summary.
  final bool summary;

  /// The code target whose per-target docs alone this bundle keeps; null keeps
  /// every target's.
  final String? codeTarget;

  /// The doc type ids of the docs the target names; empty for a code path.
  final Set<String> targetTypeIds = {};

  /// The docs the chain rule picks, by DocPath.
  final Set<String> docPaths = {};

  /// The docs the call names, by DocPath; filled in `query` alone, where each
  /// prints whole.
  final Set<String> targetPaths = {};

  /// The docs a design bundle prints in summary, by DocPath.
  final Set<String> summaryPaths = {};

  /// The non-ChainType children of a chain doc above a design target, by
  /// DocPath; filled by [addTarget] when asked to mark them.
  final Set<String> ancestorSpecPaths = {};

  /// The target story or FR's story subtree, or a top or nesting-type doc
  /// target's whole subtree, by DocPath; filled with [ancestorSpecPaths].
  final Set<String> targetSubtreePaths = {};

  /// The docs that join only through their doc type's `bundle:` list.
  final Set<String> joinedPaths = {};

  /// The docs `--no-project` drops: those [joinedPaths] would hold without
  /// it; a link into one is not followed.
  final Set<String> droppedPaths = {};

  /// The docs a `bundle_with` field joins that no rule picks, by DocPath in
  /// join order.
  final Map<String, LinkedDoc> linkedDocs = {};

  /// The docs that print in summary only: [summaryPaths] that no target picks
  /// whole and no `bundle:` or `bundle_with` join adds.
  Set<String> get summaryOnly => summaryPaths
      .difference(docPaths)
      .difference(joinedPaths)
      .difference(linkedDocs.keys.toSet());

  /// The docs a design bundle may print feature pattern parts after, by
  /// DocPath: the chain of each target, or with `--code` every doc it holds.
  final Set<String> patternListerPaths = {};

  /// The tops whose query map prints.
  final Set<String> mapTops = {};

  /// The tops whose ChainType children print as a name list.
  final Set<String> nameListTops = {};

  /// The warnings the picking raised.
  final List<String> warnings = [];

  /// Whether a cited doc of [type] prints in summary in this bundle: its type
  /// lists no `summary_for`, or lists the doc type of a target.
  ///
  /// A code path has no target type, so it asks `printsSummaryFor(null)`.
  bool printsSummaryOf(MergedDocType? type) =>
      type == null ||
      (targetTypeIds.isEmpty
          ? type.printsSummaryFor(null)
          : targetTypeIds.any(type.printsSummaryFor));

  /// Whether the bundle holds an ancestor spec doc.
  bool get hasAncestorSpecs => ancestorSpecPaths.isNotEmpty;

  /// Whether [doc] belongs to [codeTarget]: it is shared, or of that target.
  ///
  /// Public so the code-path bundle's spec-folder walk keeps to the picked
  /// target's docs.
  bool keepsTarget(IndexedDoc doc) => doc.inTarget(codeTarget);

  /// Whether [doc] joins through its doc type's `bundle:` list and that type
  /// sets `bundle_refs`, so a split bundle places it in the refs file.
  ///
  /// A doc the chain rule also picks is no join, and stays read-first.
  bool joinsRefs(DocIndex index, IndexedDoc doc) =>
      joinedPaths.contains(doc.docPath) &&
      index.typeOf(doc)?.bundleRefs == true;

  /// Adds [target] and its chain docs by [mode]'s rule.
  ///
  /// [marksSpecs] fills [ancestorSpecPaths] and [targetSubtreePaths] in a
  /// `design` bundle; only a doc target asks for it.
  void addTarget(DocIndex index, IndexedDoc target, {bool marksSpecs = false}) {
    final effective = _effectiveOf(index, target);
    final top = _topDocOf(index, effective);
    switch (mode) {
      case BundleMode.query:
        _addAll(docPaths, index.chainOf(effective));
        mapTops.add(top.docPath);
      case BundleMode.design:
        _addDesign(index, effective, top, marksSpecs: marksSpecs);
        _addAll(patternListerPaths, index.chainOf(effective));
      case BundleMode.implement:
        _addImplement(index, effective, top);
    }
  }

  /// Adds [target] as [addTarget] does with specs marked, and returns what
  /// that target alone picks.
  ///
  /// A [forCode] pick marks no specs in this bundle and names no target doc,
  /// so no outward join runs from it.
  TargetPicks pickTarget(
    DocIndex index,
    IndexedDoc target, {
    bool forCode = false,
  }) {
    final own = Bundle(mode, summary: summary, codeTarget: codeTarget)
      ..addTarget(index, target, marksSpecs: true);
    docPaths.addAll(own.docPaths);
    summaryPaths.addAll(own.summaryPaths);
    if (!forCode) {
      ancestorSpecPaths.addAll(own.ancestorSpecPaths);
      targetSubtreePaths.addAll(own.targetSubtreePaths);
    }
    patternListerPaths.addAll(own.patternListerPaths);
    mapTops.addAll(own.mapTops);
    nameListTops.addAll(own.nameListTops);
    final effective = _effectiveOf(index, target);
    final top = _topDocOf(index, effective);
    return TargetPicks(
      topPath: mode == BundleMode.design
          ? _designTopOf(index, effective, top).docPath
          : top.docPath,
      wholePaths: own.docPaths,
      summaryPaths: own.summaryPaths,
      subtreePaths: own.targetSubtreePaths,
      targetPath: forCode ? null : target.docPath,
    );
  }

  /// Records [doc], a doc the call names, as a target that prints whole.
  ///
  /// Only a `query` bundle holds targets, and a code path names none.
  void nameTarget(IndexedDoc doc) {
    if (mode != BundleMode.query || !keepsTarget(doc)) return;
    docPaths.add(doc.docPath);
    targetPaths.add(doc.docPath);
  }

  /// Adds every typed doc whose doc type's `bundle:` list holds the mode,
  /// unless [noProject] drops it.
  void join(DocIndex index, {required bool noProject}) {
    for (final doc in index.docs) {
      final bundle = index.typeOf(doc)?.bundle;
      if (bundle != null &&
          bundle.contains(mode.wire) &&
          keepsTarget(doc) &&
          !docPaths.contains(doc.docPath)) {
        (noProject ? droppedPaths : joinedPaths).add(doc.docPath);
      }
    }
  }

  /// Returns the docs in print order: the joined docs in tree order, then a
  /// pre-order walk from each doc of [docPaths] and [summaryPaths] whose
  /// parent is outside both, children inside both sorted by chain type first,
  /// then doc type id, then DocPath, by code point. The walk drops a
  /// joined doc, which prints once, whole.
  ///
  /// A `bundle_with` doc takes its place after that walk: an inward doc after
  /// the last doc of its anchor's walked subtree, an outward doc right after
  /// its holder.
  List<IndexedDoc> printOrder(DocIndex index) {
    final inDocPaths = {...docPaths, ...summaryPaths};
    final roots = [
      for (final doc in index.docs)
        if (inDocPaths.contains(doc.docPath) &&
            (doc.parentPath == null || !inDocPaths.contains(doc.parentPath)))
          doc,
    ];
    final walkOrder = <IndexedDoc>[];
    for (final root in roots) {
      _walk(index, root, inDocPaths, walkOrder);
    }
    return _withLinkedDocs(index, [
      for (final doc in index.docs)
        if (joinedPaths.contains(doc.docPath)) doc,
      for (final doc in walkOrder)
        if (!joinedPaths.contains(doc.docPath)) doc,
    ]);
  }

  /// Returns [ordered] with each [linkedDocs] doc spliced in at its place.
  ///
  /// Inward docs of one anchor sort by doc type id, then DocPath; where two
  /// anchors end at one doc, the deeper anchor's docs come first. A doc whose
  /// anchor [ordered] lacks goes last.
  List<IndexedDoc> _withLinkedDocs(DocIndex index, List<IndexedDoc> ordered) {
    if (linkedDocs.isEmpty) return ordered;
    final inward = <String, List<IndexedDoc>>{};
    final outward = <String, List<IndexedDoc>>{};
    for (final linked in linkedDocs.values) {
      final doc = index.at(linked.docPath);
      if (doc == null) continue;
      final byAnchor = linked.direction == JoinDirection.inward
          ? inward
          : outward;
      (byAnchor[linked.anchorPath] ??= []).add(doc);
    }
    final after = <int, List<IndexedDoc>>{};
    final unplaced = <IndexedDoc>[];
    void place(String anchorPath, List<IndexedDoc> docs, {Set<String>? span}) {
      var end = ordered.indexWhere((d) => d.docPath == anchorPath);
      if (end < 0) {
        unplaced.addAll(docs);
        return;
      }
      while (span != null &&
          end + 1 < ordered.length &&
          span.contains(ordered[end + 1].docPath)) {
        end++;
      }
      (after[end] ??= []).addAll(docs);
    }

    final inwardAnchors = [for (final path in inward.keys) ?index.at(path)]
      ..sort((a, b) => index.chainOf(b).length - index.chainOf(a).length);
    for (final anchor in inwardAnchors) {
      place(
        anchor.docPath,
        inward[anchor.docPath]!..sort(_compareByTypeThenPath),
        span: {for (final d in index.subtreeOf(anchor)) d.docPath},
      );
    }
    outward.forEach(place);
    return [
      for (final (at, doc) in ordered.indexed) ...[doc, ...?after[at]],
      ...unplaced,
    ];
  }

  /// Adds the design docs of [target] read from its nearest nesting doc.
  ///
  /// The nearest nesting doc and its unit take the design rule; each chain doc
  /// above prints whole with a name list of its ChainType children.
  void _addDesign(
    DocIndex index,
    IndexedDoc target,
    IndexedDoc top, {
    required bool marksSpecs,
  }) {
    final designTop = _designTopOf(index, target, top);
    final chain = index.chainOf(target);
    final topAt = chain.indexOf(designTop);
    _addDesignSubtree(
      index,
      designTop,
      topAt == 0 ? null : chain[topAt - 1],
      marksSpecs: marksSpecs,
    );
    for (final ancestor in chain.skip(topAt + 1)) {
      if (!keepsTarget(ancestor)) continue;
      docPaths.add(ancestor.docPath);
      for (final child in index.childrenOf(ancestor)) {
        if (index.isChainDoc(child)) continue;
        _addAll(docPaths, index.subtreeOf(child));
        if (marksSpecs) _addAll(ancestorSpecPaths, [child]);
      }
      nameListTops.add(ancestor.docPath);
    }
  }

  void _addDesignSubtree(
    DocIndex index,
    IndexedDoc designTop,
    IndexedDoc? unit, {
    required bool marksSpecs,
  }) {
    if (marksSpecs) {
      _addAll(targetSubtreePaths, index.subtreeOf(unit ?? designTop));
    }
    if (unit == null && !summary) {
      _addAll(docPaths, index.subtreeOf(designTop));
      return;
    }
    if (keepsTarget(designTop)) docPaths.add(designTop.docPath);
    for (final child in index.childrenOf(designTop)) {
      if (!index.isChainDoc(child) || child.docPath == unit?.docPath) {
        _addAll(docPaths, index.subtreeOf(child));
        if (marksSpecs && unit != null && !index.isChainDoc(child)) {
          _addAll(ancestorSpecPaths, [child]);
        }
      } else {
        _addAll(summaryPaths, index.subtreeOf(child));
      }
    }
  }

  void _addAll(Set<String> paths, Iterable<IndexedDoc> docs) {
    for (final doc in docs) {
      if (keepsTarget(doc)) paths.add(doc.docPath);
    }
  }

  void _addImplement(DocIndex index, IndexedDoc target, IndexedDoc top) {
    if (target.docPath == top.docPath && index.childrenOf(top).isNotEmpty) {
      _addTopWithChildren(index, top);
      return;
    }
    final chain = index.chainOf(target);
    _addAll(docPaths, chain);
    for (final doc in index.subtreeOf(target)) {
      if (keepsTarget(doc)) docPaths.add(doc.docPath);
    }
    for (var i = 1; i < chain.length; i++) {
      final ancestor = chain[i];
      final nextBelow = chain[i - 1];
      for (final child in index.childrenOf(ancestor)) {
        if (child.docTypeId != nextBelow.docTypeId && keepsTarget(child)) {
          docPaths.add(child.docPath);
        }
      }
    }
  }

  void _addTopWithChildren(DocIndex index, IndexedDoc top) {
    docPaths.add(top.docPath);
    for (final child in index.childrenOf(top)) {
      if (!index.isChainDoc(child) && keepsTarget(child)) {
        docPaths.add(child.docPath);
      }
    }
    nameListTops.add(top.docPath);
  }

  IndexedDoc _designTopOf(DocIndex index, IndexedDoc target, IndexedDoc top) {
    final nestingId = index.set.nestingType?.id;
    if (nestingId == null) return top;
    return index
            .chainOf(target)
            .where((doc) => doc.docTypeId == nestingId)
            .firstOrNull ??
        top;
  }

  IndexedDoc _effectiveOf(DocIndex index, IndexedDoc target) {
    final typeId = target.docTypeId;
    final parent = index.parentOf(target);
    return typeId != null && !index.isChainType(typeId) && parent != null
        ? parent
        : target;
  }

  IndexedDoc _topDocOf(DocIndex index, IndexedDoc target) {
    var top = target;
    for (
      var parent = index.parentOf(top);
      parent != null;
      parent = index.parentOf(top)
    ) {
      top = parent;
    }
    return top;
  }
}

void _walk(
  DocIndex index,
  IndexedDoc doc,
  Set<String> inDocPaths,
  List<IndexedDoc> out,
) {
  out.add(doc);
  final children = [
    for (final child in index.childrenOf(doc))
      if (inDocPaths.contains(child.docPath)) child,
  ]..sort(_compareSiblings(index));
  for (final child in children) {
    _walk(index, child, inDocPaths, out);
  }
}

int _compareByTypeThenPath(IndexedDoc a, IndexedDoc b) {
  final byType = compareCodePoints(a.docTypeId ?? '', b.docTypeId ?? '');
  return byType != 0 ? byType : compareCodePoints(a.docPath, b.docPath);
}

int Function(IndexedDoc, IndexedDoc) _compareSiblings(DocIndex index) =>
    (a, b) {
      final aChain = index.isChainDoc(a) ? 0 : 1;
      final bChain = index.isChainDoc(b) ? 0 : 1;
      if (aChain != bChain) return aChain - bChain;
      return _compareByTypeThenPath(a, b);
    };

/// Returns the bundle [targets] hold for [mode], the union of each target's
/// docs, each doc once.
///
/// `--no-project` drops the docs that join through `bundle:` lists. [summary]
/// prints the ChainType children of a top doc or a nested feature in summary
/// and throws `argument_conflict` outside `BundleMode.design`. [codeTarget]
/// keeps the per-target docs of that code target alone and is required for
/// `BundleMode.implement` with two or more code targets.
///
/// Resolves every target before it picks. Throws the [IndexFault] of the one
/// target that names no typed doc, or an [IndexFaults] with one fault per such
/// target in argument order.
Bundle pickBundle(
  DocIndex index,
  List<String> targets,
  BundleMode mode, {
  required bool noProject,
  bool summary = false,
  String? codeTarget,
}) {
  if (summary && mode != BundleMode.design) {
    throw IndexFault(
      IndexFaultCode.argumentConflict,
      '--summary works only with --for design',
    );
  }
  if (mode == BundleMode.implement && codeTarget == null) {
    _refuseAmbiguousTarget(index);
  } else {
    index.checkCodeTarget(codeTarget);
  }
  final picked = [
    for (final docs in _pickAll(index, targets, codeTarget)) ...docs,
  ];
  if (summary) {
    for (final doc in picked) {
      if (!_takesSummary(index, doc)) {
        throw IndexFault(
          IndexFaultCode.argumentConflict,
          '--summary takes a doc with children, such as a feature; '
          '${nameWithType(doc)} is not one',
        );
      }
    }
  }
  final bundle = Bundle(mode, summary: summary, codeTarget: codeTarget);
  final picks = <TargetPicks>[];
  for (final doc in picked) {
    picks.add(bundle.pickTarget(index, doc));
    bundle.nameTarget(doc);
    if (doc.docTypeId case final typeId?) bundle.targetTypeIds.add(typeId);
  }
  bundle.join(index, noProject: noProject);
  joinLinkedDocs(index, bundle, picks);
  return bundle;
}

/// Returns the docs each of [targets] picks, in argument order.
///
/// A target that names no doc, an untyped doc, or a doc type the set lacks
/// adds its fault; any fault is thrown after every target is tried.
List<List<IndexedDoc>> _pickAll(
  DocIndex index,
  List<String> targets,
  String? codeTarget,
) {
  final picks = <List<IndexedDoc>>[];
  final faults = <SpecstoneFault>[];
  for (final target in targets) {
    try {
      picks.add(_pickOne(index, target, codeTarget));
    } on IndexFault catch (fault) {
      faults.add(fault);
    } on TemplateFault catch (fault) {
      faults.add(fault);
    }
  }
  return switch (faults) {
    [] => picks,
    [final fault] => throw fault,
    _ => throw IndexFaults(faults),
  };
}

/// Returns the docs one [target] argument picks: the one chain doc of a name
/// several docs share, else every doc the name resolves to.
List<IndexedDoc> _pickOne(DocIndex index, String target, String? codeTarget) {
  final resolved = index.resolve(target, codeTarget: codeTarget);
  final untyped = resolved.where((doc) => doc.docTypeId == null).toList();
  if (untyped.isNotEmpty) {
    final docPath = untyped.first.docPath;
    throw IndexFault(
      IndexFaultCode.untypedTarget,
      '$docPath has no doc type, so it never joins a bundle; '
      'read it with specstone get',
    );
  }
  final chainDocs = [
    for (final doc in resolved)
      if (doc.docTypeId case final typeId? when index.isChainType(typeId)) doc,
  ];
  return chainDocs.length == 1 ? [chainDocs.single] : resolved;
}

/// Whether [doc] has children and is a top doc or a doc of the nesting type.
bool _takesSummary(DocIndex index, IndexedDoc doc) =>
    index.childrenOf(doc).isNotEmpty &&
    (index.parentOf(doc) == null || doc.docTypeId == index.set.nestingType?.id);

/// Throws `argument_missing` for an implement bundle over two or more code
/// targets with none picked.
void _refuseAmbiguousTarget(DocIndex index) {
  if (!index.hasTwins) return;
  throw IndexFault(
    IndexFaultCode.argumentMissing,
    '--for implement needs --target with two or more code targets; '
    'the targets are ${index.targetNames.join(', ')}',
  );
}
