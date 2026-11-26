import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The id of the doc type whose merged `path` holds the group levels.
const featureTypeId = 'feature';

const _slugSegment = '{slug}';
const _numberPlaceholder = '{nn}';

/// Returns one pattern per group level of [featurePath], shallowest first.
///
/// A group level is a path segment that is exactly `{slug}`, sitting before
/// the segment that holds `{nn}`. Pattern k is the segments up to and
/// including group level k, then `/`, then [file]; an ungrouped path gives
/// none.
List<String> featureGroupPatterns(String featurePath, String file) {
  final segments = featurePath.split('/');
  final ownIndex = segments.indexWhere((s) => s.contains(_numberPlaceholder));
  if (ownIndex == -1) return const [];
  return [
    for (var level = 0; level < ownIndex; level++)
      if (segments[level] == _slugSegment)
        '${segments.take(level + 1).join('/')}/$file',
  ];
}

/// Returns [docTypes] with the derived patterns of each `path_from` type.
///
/// The patterns come from the path of the `feature` type and the type's own
/// `file`. Every other doc type comes back as the same object, and a list with
/// no `path_from` type comes back whole.
List<MergedDocType> withFeatureGroupPaths(List<MergedDocType> docTypes) {
  if (!docTypes.any((docType) => docType.pathFrom != null)) return docTypes;
  final featurePath = [
    for (final docType in docTypes)
      if (docType.id == featureTypeId) docType.path,
  ].firstOrNull;
  return [
    for (final docType in docTypes)
      if (docType.pathFrom == null)
        docType
      else
        docType.copyWith(
          derivedPaths: switch ((featurePath, docType.file)) {
            (final path?, final file?) => featureGroupPatterns(path, file),
            _ => const <String>[],
          },
        ),
  ];
}
