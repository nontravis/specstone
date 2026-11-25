import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// Returns the top-level feature [target] names, else throws
/// `argument_invalid`.
///
/// A top-level feature is a `feature` doc with no parent; a shared name picks
/// its feature, so `login` still names the feature beside its spec docs.
IndexedDoc syncFeatureOf(DocIndex index, String target, {String? codeTarget}) {
  final features = [
    for (final doc in index.resolve(target, codeTarget: codeTarget))
      if (doc.docTypeId == featureType && index.parentOf(doc) == null) doc,
  ];
  if (features.length != 1) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '--for sync takes a top-level feature, not $target',
    );
  }
  return features.single;
}
