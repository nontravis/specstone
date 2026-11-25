import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show IndexedDoc, featureType;

/// The feature a doc sits under and the doc's name relative to it.
final class FeatureRelative {
  const new({required this.feature, required this.relative});

  final IndexedDoc feature;

  /// The doc's name without the feature's name and its `/`.
  final String relative;
}

/// Returns the feature [doc] is or sits under, climbing [parents] over
/// [byPath]; null for an orphan.
IndexedDoc? featureOf(
  IndexedDoc doc,
  Map<String, IndexedDoc> byPath,
  Map<String, String> parents,
) {
  var at = doc;
  while (at.docTypeId != featureType) {
    final parent = byPath[parents[at.docPath]];
    if (parent == null) return null;
    at = parent;
  }
  return at;
}

/// Returns the feature [doc] sits under and its name relative to it, climbing
/// [parents] over [byPath]; null for an orphan.
FeatureRelative? featureRelativeOf(
  IndexedDoc doc,
  Map<String, IndexedDoc> byPath,
  Map<String, String> parents,
) {
  final feature = featureOf(doc, byPath, parents);
  if (feature == null) return null;
  return FeatureRelative(
    feature: feature,
    relative: doc.name.substring(feature.name.length + 1),
  );
}
