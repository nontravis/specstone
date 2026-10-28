import 'package:specstone_core/src/setup_migration/migrate_fault.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

const _featuresFolder = 'prds/features/';
const _featureFile = 'FEATURE.md';
const _specMapHeading = '## Spec map';

final _featureName = RegExp(r'^[a-z]+(\d+)((?:_\d+)*)_([a-z0-9_]+)$');
final _groupPrefix = RegExp('^[a-z]+[0-9]+_');
final _separatorCell = RegExp(r'^:?-+:?$');

/// One row of the legacy `specs/INDEX.md` Spec map table.
final class SpecMapRow {
  const new({
    required this.codePath,
    required this.specPath,
    required this.featureId,
  });

  /// The code folder the row covers, as written.
  final String codePath;

  /// The spec folder of the row, a DocPath folder ending in `/`.
  final String specPath;

  /// The row's `feature_id`, or the dash that marks a cross-cutting row.
  final String featureId;
}

/// Returns the rows of the table under `## Spec map` in [indexLfText].
///
/// Finds the columns by their header cells `Code path`, `Spec path`, and
/// `feature_id`; trims each cell and drops one pair of backticks. Returns `[]`
/// when the section or one of the three columns is missing.
List<SpecMapRow> readSpecMap(String indexLfText) {
  final lines = indexLfText.split('\n');
  final heading = lines.indexWhere((line) => line.trim() == _specMapHeading);
  if (heading < 0) return const [];

  final table = lines
      .skip(heading + 1)
      .takeWhile((line) => !line.startsWith('## '))
      .map((line) => line.trim())
      .where((line) => line.startsWith('|'))
      .map(_cellsOf)
      .where((cells) => !cells.every(_separatorCell.hasMatch))
      .toList();
  if (table.isEmpty) return const [];

  final header = table.first;
  final codeColumn = header.indexOf('Code path');
  final specColumn = header.indexOf('Spec path');
  final idColumn = header.indexOf('feature_id');
  if (codeColumn < 0 || specColumn < 0 || idColumn < 0) return const [];

  String cell(List<String> cells, int column) =>
      column < cells.length ? cells[column] : '';

  return [
    for (final cells in table.skip(1))
      SpecMapRow(
        codePath: cell(cells, codeColumn),
        specPath: _asFolder(cell(cells, specColumn)),
        featureId: cell(cells, idColumn),
      ),
  ];
}

List<String> _cellsOf(String row) {
  final inner = row.substring(1, row.endsWith('|') ? row.length - 1 : null);
  return [for (final cell in inner.split('|')) _unticked(cell.trim())];
}

String _unticked(String cell) =>
    cell.length >= 2 && cell.startsWith('`') && cell.endsWith('`')
    ? cell.substring(1, cell.length - 1)
    : cell;

String _asFolder(String path) =>
    path.isEmpty || path.endsWith('/') ? path : '$path/';

/// One legacy feature folder and where the run places it.
final class LegacyFeature {
  const new({required this.folder, this.group, this.featurePath});

  /// The feature's DocPath folder, ending in `/`.
  final String folder;

  /// The DocPath folder of its group ending in `/`, or null when flat.
  final String? group;

  /// The FeaturePath the run moves the feature to, or null when it stays.
  ///
  /// Null for a name with no `<prefix><NN>_<slug>` form and for a flat
  /// feature of a grouped tree.
  final String? featurePath;
}

/// The features of a legacy tree and its container `FEATURE.md` files.
final class LegacyFeatures {
  const new({
    required this.features,
    required this.containers,
    required this.grouped,
  });

  /// The feature folders in code point order.
  final List<LegacyFeature> features;

  /// The DocPaths of the container `FEATURE.md` files in code point order.
  final List<String> containers;

  /// Whether any feature sits in a group.
  final bool grouped;
}

/// Reads the features of the legacy tree whose docs are [docPaths].
///
/// A feature folder holds `FEATURE.md` and no child folder holding one; a
/// container holds `FEATURE.md` and a child folder that does (INV-3).
LegacyFeatures scanLegacyFeatures(List<String> docPaths) {
  final folders = [
    for (final path in docPaths)
      if (path.startsWith(_featuresFolder) &&
          path.endsWith('/$_featureFile') &&
          path.length > _featuresFolder.length + _featureFile.length + 1)
        path.substring(0, path.length - _featureFile.length),
  ]..sort(compareCodePoints);

  bool isContainer(String folder) =>
      folders.any((other) => other != folder && other.startsWith(folder));

  final containers = [
    for (final folder in folders)
      if (isContainer(folder)) '$folder$_featureFile',
  ];
  final featureFolders = folders.where((f) => !isContainer(f));
  final grouped = featureFolders.any((f) => _groupOf(f) != null);

  return LegacyFeatures(
    features: [
      for (final folder in featureFolders)
        LegacyFeature(
          folder: folder,
          group: _groupOf(folder),
          featurePath: _featurePathIn(folder, grouped: grouped),
        ),
    ],
    containers: containers,
    grouped: grouped,
  );
}

String? _groupOf(String featureFolder) {
  final parent = _parentOf(featureFolder);
  return parent == _featuresFolder ? null : parent;
}

String? _featurePathIn(String featureFolder, {required bool grouped}) {
  final group = _groupOf(featureFolder);
  if (group == null) {
    return grouped ? null : featurePathOf(_nameOf(featureFolder));
  }
  return featurePathOf(
    _nameOf(featureFolder),
    groupSlug: groupSlugOf(_nameOf(group)),
  );
}

/// Returns [folderName] with its leading `[a-z]+[0-9]+_` removed.
String groupSlugOf(String folderName) =>
    folderName.replaceFirst(_groupPrefix, '');

/// Returns the FeaturePath of the feature folder [folderName], or null.
///
/// A name `<prefix><NN>[_<NN>]*_<slug>` gives `f<NN>_<slug>`, NN the last
/// number with its digits as written, under `<groupSlug>/` when given.
String? featurePathOf(String folderName, {String? groupSlug}) {
  final match = _featureName.firstMatch(folderName);
  if (match == null) return null;
  final first = match.group(1)!;
  final more = match.group(2)!;
  final number = more.isEmpty ? first : more.split('_').last;
  final path = 'f${number}_${match.group(3)}';
  return groupSlug == null ? path : '$groupSlug/$path';
}

/// Throws [MigrateFault] `group_slug_duplicate` when two group folders give
/// one GroupSlug (INV-3).
///
/// One entry per duplicated slug in code point order of the slug, the second
/// and later chained under `more`.
void refuseDuplicateGroups(LegacyFeatures features) {
  final foldersBySlug = <String, Set<String>>{};
  for (final group in features.features.map((f) => f.group).nonNulls) {
    (foldersBySlug[groupSlugOf(_nameOf(group))] ??= {}).add(group);
  }

  final duplicates = [
    for (final slug in foldersBySlug.keys.toList()..sort(compareCodePoints))
      if (foldersBySlug[slug]!.length > 1)
        (
          slug: slug,
          folders: foldersBySlug[slug]!.toList()..sort(compareCodePoints),
        ),
  ];
  if (duplicates.isEmpty) return;
  throw _duplicateFault(
    duplicates.first,
    more: [for (final next in duplicates.skip(1)) _duplicateFault(next)],
  );
}

MigrateFault _duplicateFault(
  ({String slug, List<String> folders}) duplicate, {
  List<MigrateFault> more = const [],
}) => MigrateFault(
  MigrateFaultCode.groupSlugDuplicate,
  'two group folders give the group ${duplicate.slug}; rename one, then run '
  'specstone migrate again',
  file: _withoutSlash(duplicate.folders.first),
  relatedFiles: [for (final f in duplicate.folders.skip(1)) _withoutSlash(f)],
  more: more,
);

String _withoutSlash(String folder) => folder.substring(0, folder.length - 1);

String _nameOf(String folder) {
  final trimmed = _withoutSlash(folder);
  return trimmed.substring(trimmed.lastIndexOf('/') + 1);
}

String _parentOf(String folder) {
  final trimmed = _withoutSlash(folder);
  return trimmed.substring(0, trimmed.lastIndexOf('/') + 1);
}
