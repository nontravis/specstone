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
  new(this.mode, {this.summary = false, this.codeTarget});

  /// The mode the docs are picked for.
  final BundleMode mode;

  /// Whether `--summary` asked for the feature's stories in summary.
  final bool summary;

  /// The code target whose per-target docs alone this bundle keeps; null keeps
  /// every target's (E24, E25).
  final String? codeTarget;

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

  /// Whether [doc] belongs to [codeTarget]: it is shared, or of that target.
  bool _keepsTarget(IndexedDoc doc) =>
      codeTarget == null || doc.target == null || doc.target == codeTarget;

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
          _keepsTarget(doc) &&
          !docPaths.contains(doc.docPath)) {
        joinedPaths.add(doc.docPath);
      }
    }
  }

  /// Adds the design docs of [target] read from its nearest nesting doc.
  ///
  /// The nearest nesting doc and its unit take the design rule; each chain doc
  /// above prints whole with a name list of its ChainType children (SF-C7).
  void _addDesign(DocIndex index, IndexedDoc target, IndexedDoc top) {
    final designTop = _designTopOf(index, target, top);
    final chain = index.chainOf(target);
    final topAt = chain.indexOf(designTop);
    _addDesignSubtree(index, designTop, topAt == 0 ? null : chain[topAt - 1]);
    for (final ancestor in chain.skip(topAt + 1)) {
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
    docPaths.add(designTop.docPath);
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
      if (_keepsTarget(doc)) paths.add(doc.docPath);
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
      if (_keepsTarget(doc)) docPaths.add(doc.docPath);
    }
    for (var i = 1; i < chain.length; i++) {
      final ancestor = chain[i];
      final nextBelow = chain[i - 1];
      for (final child in index.childrenOf(ancestor)) {
        if (child.docTypeId != nextBelow.docTypeId && _keepsTarget(child)) {
          docPaths.add(child.docPath);
        }
      }
    }
  }

  void _addTopWithChildren(DocIndex index, IndexedDoc top) {
    docPaths.add(top.docPath);
    for (final child in index.childrenOf(top)) {
      if (!index.isChainDoc(child) && _keepsTarget(child)) {
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

/// Returns the bundle [target] holds for [mode] (`index_query/get_task_bundle/pick_bundle_docs`).
///
/// `--no-project` drops the docs that join through `bundle:` lists. [summary]
/// prints a top doc's ChainType children in summary and throws
/// `argument_conflict` outside `BundleMode.design`. [codeTarget] keeps the
/// per-target docs of that code target alone and is required for
/// `BundleMode.implement` with two or more targets (E23).
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
  }
  bundle.join(index, noProject: noProject);
  return bundle;
}

/// Throws `argument_missing` for an implement bundle over two or more code
/// targets with none picked (E23).
void _refuseAmbiguousTarget(DocIndex index) {
  if (index.targetNames.length < 2) return;
  throw IndexFault(
    IndexFaultCode.argumentMissing,
    '--for implement needs --target with two or more code targets; '
    'the targets are ${index.targetNames.join(', ')}',
  );
}
