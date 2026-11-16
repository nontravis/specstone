import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Id of the doc type whose `overrides` field is one NFR id, no override line.
const nfTypeId = 'nf';

const _overridesField = 'overrides';

/// Whether a doc of [type] can hold override lines: it declares the
/// `overrides` field and is not an `nf` or a type built on it, whose field is
/// one NFR id.
bool carriesOverrides(MergedDocType? type) =>
    type != null &&
    !type.buildsOn(nfTypeId) &&
    type.fields.any((field) => field.id == _overridesField);

/// Returns the DocPaths of the docs above [doc], the only docs an `Overrides:`
/// line of [doc] may link.
///
/// They are the project spec docs of [doc]'s code target and, for a feature's
/// spec doc, that target's spec docs under each ancestor feature of its
/// feature. An ancestor's doc counts only when its type carries `overrides`.
/// `check` and `move` both read this chain.
Set<String> overrideChainOf(DocIndex index, IndexedDoc doc) {
  bool inTarget(IndexedDoc other) => other.target == doc.target;
  final paths = {
    for (final other in index.docs)
      if (other.isTyped && inTarget(other))
        if (index.set.isProjectSpecType(index.typeOf(other)!)) other.docPath,
  };
  final feature = index.parentOf(doc);
  var ancestor = feature == null ? null : index.parentOf(feature);
  for (; ancestor != null; ancestor = index.parentOf(ancestor)) {
    for (final spec in index.childrenOf(ancestor)) {
      if (inTarget(spec) && carriesOverrides(index.typeOf(spec))) {
        paths.add(spec.docPath);
      }
    }
  }
  return paths;
}
