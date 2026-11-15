import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

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

  /// The docs a design bundle prints in summary, by DocPath.
  final Set<String> summaryPaths = {};

  /// The docs that join only through their doc type's `bundle:` list.
  final Set<String> joinedPaths = {};

  /// The docs `--no-project` drops: those [joinedPaths] would hold without
  /// it; a link into one is not followed.
  final Set<String> droppedPaths = {};

  /// The docs that print in summary only: [summaryPaths] that no target picks
  /// whole and no `bundle:` join adds.
  Set<String> get summaryOnly =>
      summaryPaths.difference(docPaths).difference(joinedPaths);

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

  /// Whether [doc] belongs to [codeTarget]: it is shared, or of that target.
  ///
  /// Public so the code-path bundle's spec-folder walk keeps to the picked
  /// target's docs.
  bool keepsTarget(IndexedDoc doc) => doc.inTarget(codeTarget);

  /// Adds [target] and its chain docs by [mode]'s rule.
  void addTarget(DocIndex index, IndexedDoc target) {
    final typeId = target.docTypeId;
    final parent = index.parentOf(target);
    final effective =
        typeId != null && !index.isChainType(typeId) && parent != null
        ? parent
        : target;
    final top = _topDocOf(index, effective);
    switch (mode) {
      case BundleMode.query:
        _addAll(docPaths, index.chainOf(effective));
        mapTops.add(top.docPath);
      case BundleMode.design:
        _addDesign(index, effective, top);
        _addAll(patternListerPaths, index.chainOf(effective));
      case BundleMode.implement:
        _addImplement(index, effective, top);
    }
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
    return [
      for (final doc in index.docs)
        if (joinedPaths.contains(doc.docPath)) doc,
      for (final doc in walkOrder)
        if (!joinedPaths.contains(doc.docPath)) doc,
    ];
  }

  /// Adds the design docs of [target] read from its nearest nesting doc.
  ///
  /// The nearest nesting doc and its unit take the design rule; each chain doc
  /// above prints whole with a name list of its ChainType children.
  void _addDesign(DocIndex index, IndexedDoc target, IndexedDoc top) {
    final designTop = _designTopOf(index, target, top);
    final chain = index.chainOf(target);
    final topAt = chain.indexOf(designTop);
    _addDesignSubtree(index, designTop, topAt == 0 ? null : chain[topAt - 1]);
    for (final ancestor in chain.skip(topAt + 1)) {
      if (!keepsTarget(ancestor)) continue;
      docPaths.add(ancestor.docPath);
      for (final child in index.childrenOf(ancestor)) {
        if (!index.isChainDoc(child)) {
          _addAll(docPaths, index.subtreeOf(child));
        }
      }
      nameListTops.add(ancestor.docPath);
    }
  }

  void _addDesignSubtree(
    DocIndex index,
    IndexedDoc designTop,
    IndexedDoc? unit,
  ) {
    if (unit == null && !summary) {
      _addAll(docPaths, index.subtreeOf(designTop));
      return;
    }
    if (keepsTarget(designTop)) docPaths.add(designTop.docPath);
    for (final child in index.childrenOf(designTop)) {
      if (!index.isChainDoc(child) || child.docPath == unit?.docPath) {
        _addAll(docPaths, index.subtreeOf(child));
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

int Function(IndexedDoc, IndexedDoc) _compareSiblings(DocIndex index) =>
    (a, b) {
      final aChain = index.isChainDoc(a) ? 0 : 1;
      final bChain = index.isChainDoc(b) ? 0 : 1;
      if (aChain != bChain) return aChain - bChain;
      final byType = compareCodePoints(a.docTypeId ?? '', b.docTypeId ?? '');
      if (byType != 0) return byType;
      return compareCodePoints(a.docPath, b.docPath);
    };

/// Returns the bundle [target] holds for [mode].
///
/// `--no-project` drops the docs that join through `bundle:` lists. [summary]
/// prints a top doc's ChainType children in summary and throws
/// `argument_conflict` outside `BundleMode.design`. [codeTarget] keeps the
/// per-target docs of that code target alone and is required for
/// `BundleMode.implement` with two or more targets.
Bundle pickBundle(
  DocIndex index,
  String target,
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
  final picked = chainDocs.length == 1
      ? <IndexedDoc>[chainDocs.single]
      : resolved;
  if (summary) {
    for (final doc in picked) {
      if (index.parentOf(doc) != null || index.childrenOf(doc).isEmpty) {
        throw IndexFault(
          IndexFaultCode.argumentConflict,
          '--summary takes a doc with children and no parent, such as a '
          'feature; ${nameWithType(doc)} is not one',
        );
      }
    }
  }
  final bundle = Bundle(mode, summary: summary, codeTarget: codeTarget);
  for (final doc in picked) {
    bundle.addTarget(index, doc);
    if (doc.docTypeId case final typeId?) bundle.targetTypeIds.add(typeId);
  }
  bundle.join(index, noProject: noProject);
  return bundle;
}

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
