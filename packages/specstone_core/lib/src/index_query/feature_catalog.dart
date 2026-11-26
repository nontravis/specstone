import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/table_cell.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show relativeHref;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart'
    show statusPartOf;
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/feature_group_paths.dart'
    show featureGroupPatterns;
import 'package:specstone_core/src/templates/generator_kinds.dart'
    show groupFeatureCatalogKind;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

/// The kind of the block that lists the top features.
const featureCatalogKind = 'feature_catalog';

const _featuresSectionId = 'features';
const _defaultGroupFile = 'FEATURES.md';
const _noValue = '—';
const _partSeparator = ' · ';
const _listSeparator = ', ';
const _tableHead =
    '| Feature | What it does | Status | Stories | Serves |\n'
    '|---|---|---|---|---|';
const _groupTableHead =
    '| Group | Features | Status | Stories |\n'
    '|---|---|---|---|';

/// The order the status counts of the summary line run in.
const List<RecordStatus> _statusOrder = [
  RecordStatus.implemented,
  RecordStatus.planned,
  RecordStatus.skipped,
  RecordStatus.deprecated,
];

final _lineBreak = RegExp(r'\s*\n\s*');

// MARK: - Generator

/// Returns the catalog block for the top of the features section of the doc
/// at [docPath].
List<GeneratedBlock> featureCatalogBlocks(
  Doc doc,
  String docPath,
  MergedDocType docType,
  DocIndex index,
) => [
  GeneratedBlock(
    kind: featureCatalogKind,
    sectionId: _featuresSectionId,
    place: const SectionTop(),
    text: featureCatalogText(index, docPath),
  ),
];

/// Returns the catalog block for the top of the `features` section of the group
/// features doc at [docPath].
List<GeneratedBlock> groupFeatureCatalogBlocks(
  Doc doc,
  String docPath,
  MergedDocType docType,
  DocIndex index,
) => [
  GeneratedBlock(
    kind: groupFeatureCatalogKind,
    sectionId: _featuresSectionId,
    place: const SectionTop(),
    text: groupFeatureCatalogText(index, docPath),
  ),
];

/// Returns the catalog without marker lines: one summary line, then a table
/// with one row per top feature in tree order, or, in a grouped layout, one row
/// per first-level group folder.
///
/// A project with no feature doc gets the summary line alone. Links reach the
/// features doc at [featuresDocPath].
String featureCatalogText(DocIndex index, String featuresDocPath) {
  final features = _topFeatures(index);
  final summary = _summaryLine(index, features);
  if (features.isEmpty) return summary;
  final folderSegments = _groupFolderSegments(index.set);
  final table = folderSegments.isEmpty
      ? _featureTable(index, features, featuresDocPath)
      : _groupTable(index, features, folderSegments.first, featuresDocPath);
  return '$summary\n\n$table';
}

/// Returns the catalog of the group features doc at [groupDocPath] without
/// marker lines.
///
/// It holds the summary line over the top features under the doc's folder, then
/// the group table of the next group level, or the feature table when the
/// folder holds the features. Links reach the doc at [groupDocPath].
String groupFeatureCatalogText(DocIndex index, String groupDocPath) {
  final pathSegments = groupDocPath.split('/');
  final folder = pathSegments.take(pathSegments.length - 1).join('/');
  final features = [
    for (final feature in _topFeatures(index))
      if (feature.docPath.startsWith('$folder/')) feature,
  ];
  final summary = _summaryLine(index, features);
  if (features.isEmpty) return summary;
  final folderSegments = _groupFolderSegments(index.set);
  final next = folderSegments.indexOf(pathSegments.length - 1) + 1;
  final table = next > 0 && next < folderSegments.length
      ? _groupTable(index, features, folderSegments[next], groupDocPath)
      : _featureTable(index, features, groupDocPath);
  return '$summary\n\n$table';
}

/// Returns the group features docs a format run keeps beside the features doc.
///
/// One doc per group folder, at every group level, whose subtree holds a top
/// feature, in tree order. A project with no group level, or whose merged set
/// has no doc type that lists [groupFeatureCatalogKind], lists none.
CompanionDocs featureCatalogCompanions(
  String docPath,
  MergedDocType docType,
  DocIndex index,
) {
  final type = _groupDocType(index.set);
  final folderSegments = _groupFolderSegments(index.set);
  if (type == null || folderSegments.isEmpty) {
    return const CompanionDocs(docTypeId: '', docs: []);
  }
  final file = _groupFileOf(index.set);
  final folders = <String>{
    for (final feature in _topFeatures(index))
      for (final segments in folderSegments)
        feature.docPath.split('/').take(segments).join('/'),
  };
  return CompanionDocs(
    docTypeId: type.id,
    docs: [
      for (final folder in folders)
        CompanionDoc(
          docPath: '$folder/$file',
          seedText: _groupSeedText(type, folder),
        ),
    ],
  );
}

List<IndexedDoc> _topFeatures(DocIndex index) => [
  for (final doc in index.docs)
    if (doc.docTypeId == featureType && index.parentOf(doc) == null) doc,
];

String _featureTable(
  DocIndex index,
  List<IndexedDoc> features,
  String fromDocPath,
) => [
  _tableHead,
  for (final feature in features) _row(index, feature, fromDocPath),
].join('\n');

String _groupTable(
  DocIndex index,
  List<IndexedDoc> features,
  int segments,
  String fromDocPath,
) => [
  _groupTableHead,
  for (final MapEntry(:key, :value) in _byGroupFolder(
    features,
    segments,
  ).entries)
    _groupRow(
      index,
      key,
      value,
      fromDocPath,
      groupFile: _groupFileOf(index.set),
    ),
].join('\n');

String _groupSeedText(MergedDocType type, String folder) {
  final headers = [
    for (final section in type.sections) '\n## ${section.header}\n',
  ];
  return '# ${folder.split('/').last} features\n${headers.join()}';
}

// MARK: - Summary line

String _summaryLine(DocIndex index, List<IndexedDoc> features) {
  final count = '${features.length} features';
  if (features.isEmpty) return '$count${_partSeparator}0 stories';
  if (!index.hasTwins) return _summaryPart(index, features, null, count);
  return [
    count,
    for (final target in index.targetNames)
      _summaryPart(index, features, target, '$target:'),
  ].join(_partSeparator);
}

String _summaryPart(
  DocIndex index,
  List<IndexedDoc> features,
  String? target,
  String lead,
) {
  final stories = features.fold(
    0,
    (sum, feature) => sum + _storiesOf(index, feature, target).counted,
  );
  final counts = _statusCounts(index, features, target);
  return target == null
      ? '$lead$_partSeparator$stories stories$_partSeparator$counts'
      : '$lead $stories stories$_listSeparator$counts';
}

String _statusCounts(
  DocIndex index,
  List<IndexedDoc> features,
  String? target,
) {
  final byStatus = <String, int>{};
  for (final feature in features) {
    final status = index.statusOf(feature, codeTarget: target);
    if (status == null) continue;
    byStatus.update(status, (n) => n + 1, ifAbsent: () => 1);
  }
  return [
    for (final status in _statusOrder)
      if (byStatus[status.wire] case final n?) '$n ${status.wire}',
  ].join(_listSeparator);
}

// MARK: - Rows

String _row(DocIndex index, IndexedDoc feature, String featuresDocPath) {
  final cells = [
    _featureLink(feature, featuresDocPath),
    _cell(feature.oneLineSummary ?? ''),
    statusPartOf(index, feature, null) ?? _noValue,
    _byTarget(index, (target) => _storiesOf(index, feature, target).cell),
    _cell(
      [
        ...feature.valuesOf('vision'),
        ...feature.valuesOf('goals'),
      ].join(_listSeparator),
    ),
  ];
  return _tableRow(cells);
}

String _tableRow(List<String> cells) =>
    '| ${cells.map((c) => c.isEmpty ? _noValue : c).join(' | ')} |';

String _featureLink(IndexedDoc feature, String featuresDocPath) {
  final text = feature.hasTitle ? feature.title! : feature.name;
  final href = relativeHref(featuresDocPath, feature.docPath);
  return '[${_cell(text)}]($href)';
}

/// Returns [text] as one table cell: line breaks become spaces and each `|`
/// that splits a row is escaped.
String _cell(String text) =>
    escapeTableCellPipes(text.trim().replaceAll(_lineBreak, ' '));

/// Returns what [cell] gives for the one target, or for each target as
/// `<target>: <cell>` joined by `, ` when the project names two or more.
String _byTarget(DocIndex index, String Function(String? target) cell) =>
    index.hasTwins
    ? [for (final target in index.targetNames) '$target: ${cell(target)}']
          .join(_listSeparator)
    : cell(null);

// MARK: - Group rows

/// Returns how many path segments the group folder of each group level holds,
/// shallowest first; empty when the merged `feature` path has no group level.
List<int> _groupFolderSegments(MergedSet set) {
  final path = set.lookup(featureType)?.path;
  if (path == null) return const [];
  return [
    for (final pattern in featureGroupPatterns(path, _groupFileOf(set)))
      pattern.split('/').length - 1,
  ];
}

/// Returns the one doc type that lists [groupFeatureCatalogKind], or null when
/// none does; a merged set holds at most one.
MergedDocType? _groupDocType(MergedSet set) {
  for (final type in set.docTypes) {
    if (type.listedGenerators.contains(groupFeatureCatalogKind)) return type;
  }
  return null;
}

/// Returns the file name of the group features docs.
String _groupFileOf(MergedSet set) =>
    _groupDocType(set)?.file ?? _defaultGroupFile;

/// Returns [features] by the first [segments] segments of their doc path, in
/// the order the first feature of each folder runs.
Map<String, List<IndexedDoc>> _byGroupFolder(
  List<IndexedDoc> features,
  int segments,
) {
  final byFolder = <String, List<IndexedDoc>>{};
  for (final feature in features) {
    final folder = feature.docPath.split('/').take(segments).join('/');
    (byFolder[folder] ??= []).add(feature);
  }
  return byFolder;
}

String _groupRow(
  DocIndex index,
  String folderPath,
  List<IndexedDoc> features,
  String fromDocPath, {
  required String groupFile,
}) {
  final href = relativeHref(fromDocPath, '$folderPath/$groupFile');
  return _tableRow([
    '[${_cell(folderPath.split('/').last)}]($href)',
    '${features.length}',
    _groupStatus(index, features),
    _byTarget(index, (target) => _groupStories(index, features, target).cell),
  ]);
}

String _groupStatus(DocIndex index, List<IndexedDoc> features) => index.hasTwins
    ? [
        for (final target in index.targetNames)
          '$target: ${_statusCounts(index, features, target)}',
      ].join(_partSeparator)
    : _statusCounts(index, features, null);

_StoryCount _groupStories(
  DocIndex index,
  List<IndexedDoc> features,
  String? target,
) {
  final counts = [for (final f in features) _storiesOf(index, f, target)];
  return _StoryCount(
    implemented: counts.fold(0, (sum, c) => sum + c.implemented),
    counted: counts.fold(0, (sum, c) => sum + c.counted),
  );
}

// MARK: - Stories

/// The stories of one feature's subtree that count in one target.
final class _StoryCount {
  const new({required this.implemented, required this.counted});

  /// The counted stories that read `implemented`.
  final int implemented;

  /// The stories that read neither `skipped` nor `deprecated`.
  final int counted;

  String get cell => '$implemented/$counted';
}

_StoryCount _storiesOf(DocIndex index, IndexedDoc feature, String? target) {
  var implemented = 0;
  var counted = 0;
  for (final doc in index.subtreeOf(feature)) {
    if (doc.docTypeId != storyType) continue;
    final status = index.statusOf(doc, codeTarget: target);
    if (status == RecordStatus.skipped.wire ||
        status == RecordStatus.deprecated.wire) {
      continue;
    }
    counted++;
    if (status == RecordStatus.implemented.wire) implemented++;
  }
  return _StoryCount(implemented: implemented, counted: counted);
}
