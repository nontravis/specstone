import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/nested_paths.dart';

/// The id of the doc type whose merged `path` holds the group levels.
const featureTypeId = 'feature';

const _slugSegment = '{slug}';
const _numberPlaceholder = '{nn}';
const _featureFolderSegment = 'f{nn}_{slug}';

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

/// Returns how many group levels [featurePath] holds.
int featureGroupLevelCount(String featurePath) {
  final segments = featurePath.split('/');
  final ownIndex = segments.indexWhere((s) => s.contains(_numberPlaceholder));
  if (ownIndex == -1) return 0;
  return segments.take(ownIndex).where((s) => s == _slugSegment).length;
}

/// Returns the `{slug}` segments right before the first feature folder of
/// [childPath]; null when no segment is exactly `f{nn}_{slug}`.
int? childGroupLevelCount(String childPath) {
  final segments = childPath.split('/');
  final folderIndex = segments.indexOf(_featureFolderSegment);
  if (folderIndex == -1) return null;
  var count = 0;
  while (count < folderIndex &&
      segments[folderIndex - 1 - count] == _slugSegment) {
    count++;
  }
  return count;
}

/// Returns [docTypes] with the `feature` path's group levels inserted once
/// into each child path that holds none.
///
/// A child is a doc type whose `parent` chain reaches `feature`. A child path
/// that already holds group levels, or has no feature folder, is left as
/// written; every other doc type comes back as the same object.
List<MergedDocType> withGroupLevels(List<MergedDocType> docTypes) {
  final featurePath = [
    for (final docType in docTypes)
      if (docType.id == featureTypeId) docType.path,
  ].firstOrNull;
  if (featurePath == null) return docTypes;
  final levels = featureGroupLevelCount(featurePath);
  if (levels == 0) return docTypes;
  final byId = {for (final docType in docTypes) docType.id: docType};
  return [for (final docType in docTypes) _grouped(docType, levels, byId)];
}

MergedDocType _grouped(
  MergedDocType docType,
  int levels,
  Map<String, MergedDocType> byId,
) {
  final path = docType.path;
  if (path == null ||
      docType.id == featureTypeId ||
      childGroupLevelCount(path) != 0 ||
      !parentChainReaches(docType, featureTypeId, byId)) {
    return docType;
  }
  return docType.copyWith(
    path: insertGroupLevels(path, levels),
    insertedGroupLevels: levels,
  );
}

/// Returns [pattern] with [levels] `{slug}` segments right before its first
/// `f{nn}_{slug}` segment.
///
/// A [pattern] with no feature folder or with group levels already, or a
/// [levels] of 0, comes back as written.
String insertGroupLevels(String pattern, int levels) {
  if (levels == 0 || childGroupLevelCount(pattern) != 0) return pattern;
  final segments = pattern.split('/');
  segments.insertAll(
    segments.indexOf(_featureFolderSegment),
    List.filled(levels, _slugSegment),
  );
  return segments.join('/');
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
