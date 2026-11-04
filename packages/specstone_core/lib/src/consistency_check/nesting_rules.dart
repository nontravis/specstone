import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_link.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// The most characters a doc's path from the project root may hold (SF-C5).
const pathLengthLimit = 200;

/// The fewest chain children a nested nesting-type doc holds (SF-C4).
const _minimumChildren = 2;

/// Returns the nesting findings of the typed [doc] (FR-10).
///
/// A nesting-type doc holding a child of its own type and a child of another
/// chain type is mixed; one whose parent is a nesting-type doc and that holds
/// fewer than 2 chain children is too small.
Iterable<Finding> checkNesting(CheckContext context, IndexedDoc doc) sync* {
  final nesting = context.index.set.nestingType;
  if (nesting == null || doc.docTypeId != nesting.id) return;
  final childTypes = {
    for (final child in context.index.childrenOf(doc))
      if (context.index.isChainDoc(child)) child.docTypeId!,
  };
  if (childTypes.contains(nesting.id) && childTypes.length > 1) {
    final ids = childTypes.toList()..sort();
    yield context.finding(
      doc,
      FindingKind.featureMixedChildren,
      line: 1,
      message: 'holds both ${ids.join(' and ')} children',
      keys: {'docTypes': ids},
    );
  }
  final parent = context.index.parentOf(doc);
  if (parent?.docTypeId != nesting.id) return;
  final held = context.index
      .childrenOf(doc)
      .where(context.index.isChainDoc)
      .length;
  if (held >= _minimumChildren) return;
  yield context.finding(
    doc,
    FindingKind.subFeatureTooSmall,
    line: 1,
    message:
        'holds $held children; a nested ${nesting.id} holds at '
        'least $_minimumChildren',
    keys: {'minimum': _minimumChildren, 'actual': held},
  );
}

/// Returns `path_over_limit` for [doc] when `docs/<DocPath>` is too long
/// (FR-11).
Iterable<Finding> checkPathLength(CheckContext context, IndexedDoc doc) sync* {
  final length = '$docsFolderName/${doc.docPath}'.length;
  if (length <= pathLengthLimit) return;
  yield context.finding(
    doc,
    FindingKind.pathOverLimit,
    line: 1,
    message:
        'the path from the project root has $length characters; the limit is '
        '$pathLengthLimit',
    keys: {'limit': pathLengthLimit, 'actual': length},
  );
}
