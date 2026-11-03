import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';

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
  new(this.mode, {this.summary = false});

  /// The mode the docs are picked for.
  final BundleMode mode;

  /// Whether `--summary` asked for the feature's stories in summary.
  final bool summary;

  /// The docs the chain rule picks, by DocPath.
  final Set<String> docPaths = {};

  /// The docs a design bundle prints in summary, by DocPath.
  final Set<String> summaryPaths = {};

  /// The docs that join only through their doc type's `bundle:` list.
  final Set<String> joinedPaths = {};

  /// The docs that print in summary only: [summaryPaths] that no target picks
  /// whole and no `bundle:` join adds (DB-C9).
  Set<String> get summaryOnly =>
      summaryPaths.difference(docPaths).difference(joinedPaths);

  /// The tops whose query map prints.
  final Set<String> mapTops = {};

  /// The tops whose ChainType children print as a name list.
  final Set<String> nameListTops = {};

  /// The warnings the picking raised.
  final List<String> warnings = [];

  /// Adds [target] and its chain docs by [mode]'s rule (INV-11, INV-12).
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
        for (final doc in index.chainOf(effective)) {
          docPaths.add(doc.docPath);
        }
        mapTops.add(top.docPath);
      case BundleMode.design:
        _addDesign(index, effective, top);
      case BundleMode.implement:
        _addImplement(index, effective, top);
    }
  }

  /// Adds every typed doc whose doc type's `bundle:` list holds the mode,
  /// unless [noProject] drops it (INV-13).
  void join(DocIndex index, {required bool noProject}) {
    if (noProject) return;
    for (final doc in index.docs) {
      final bundle = index.typeOf(doc)?.bundle;
      if (bundle != null &&
          bundle.contains(mode.wire) &&
          !docPaths.contains(doc.docPath)) {
        joinedPaths.add(doc.docPath);
      }
    }
  }

  /// Adds the design docs of [target]: a top doc takes its whole subtree, or
  /// with [summary] its non-ChainType children whole and the rest in summary;
  /// any other target takes its unit (the chain doc below the top) whole, the
  /// top's non-ChainType children whole, and the top's other ChainType
  /// children's subtrees in summary.
  void _addDesign(DocIndex index, IndexedDoc target, IndexedDoc top) {
    final isTop = target.docPath == top.docPath;
    if (isTop && !summary) {
      _addAll(docPaths, index.subtreeOf(top));
      return;
    }
    final chain = index.chainOf(target);
    final unit = isTop ? null : chain[chain.length - 2];
    docPaths.add(top.docPath);
    for (final child in index.childrenOf(top)) {
      final typeId = child.docTypeId;
      if (typeId == null || !index.isChainType(typeId)) {
        _addAll(docPaths, index.subtreeOf(child));
      } else if (child.docPath == unit?.docPath) {
        _addAll(docPaths, index.subtreeOf(child));
      } else {
        _addAll(summaryPaths, index.subtreeOf(child));
      }
    }
  }

  void _addAll(Set<String> paths, Iterable<IndexedDoc> docs) {
    for (final doc in docs) {
      paths.add(doc.docPath);
    }
  }

  void _addImplement(DocIndex index, IndexedDoc target, IndexedDoc top) {
    if (target.docPath == top.docPath && index.childrenOf(top).isNotEmpty) {
      _addTopWithChildren(index, top);
      return;
    }
    final chain = index.chainOf(target);
    for (final doc in chain) {
      docPaths.add(doc.docPath);
    }
    for (final doc in index.subtreeOf(target)) {
      docPaths.add(doc.docPath);
    }
    for (var i = 1; i < chain.length; i++) {
      final ancestor = chain[i];
      final nextBelow = chain[i - 1];
      for (final child in index.childrenOf(ancestor)) {
        if (child.docTypeId != nextBelow.docTypeId) {
          docPaths.add(child.docPath);
        }
      }
    }
  }

  void _addTopWithChildren(DocIndex index, IndexedDoc top) {
    docPaths.add(top.docPath);
    for (final child in index.childrenOf(top)) {
      final typeId = child.docTypeId;
      if (typeId == null || !index.isChainType(typeId)) {
        docPaths.add(child.docPath);
      }
    }
    nameListTops.add(top.docPath);
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

/// Returns the bundle [target] holds for [mode] (us05 FR-01).
///
/// `--no-project` drops the docs that join through `bundle:` lists. [summary]
/// prints a top doc's ChainType children in summary.
Bundle pickBundle(
  DocIndex index,
  String target,
  BundleMode mode, {
  required bool noProject,
  bool summary = false,
}) {
  final resolved = index.resolve(target);
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
  final bundle = Bundle(mode, summary: summary);
  for (final doc in picked) {
    bundle.addTarget(index, doc);
  }
  bundle.join(index, noProject: noProject);
  return bundle;
}
