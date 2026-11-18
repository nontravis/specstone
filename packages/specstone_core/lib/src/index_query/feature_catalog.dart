import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/document_writing/moved_paths.dart'
    show relativeHref;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart'
    show statusPartOf;
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show RecordStatus;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The kind of the block that lists the top features.
const featureCatalogKind = 'feature_catalog';

const _featuresSectionId = 'features';
const _noValue = '—';
const _partSeparator = ' · ';
const _listSeparator = ', ';
const _tableHead =
    '| Feature | What it does | Status | Stories | Serves |\n'
    '|---|---|---|---|---|';

/// The order the status counts of the summary line run in.
const List<RecordStatus> _statusOrder = [
  RecordStatus.implemented,
  RecordStatus.planned,
  RecordStatus.skipped,
  RecordStatus.deprecated,
];

final _lineBreak = RegExp(r'\s*\n\s*');
final _unescapedPipe = RegExp(r'(?<!\\)\|');

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

/// Returns the catalog without marker lines: one summary line, then a table
/// with one row per top feature in tree order.
///
/// A project with no feature doc gets the summary line alone. Links reach the
/// features doc at [featuresDocPath].
String featureCatalogText(DocIndex index, String featuresDocPath) {
  final features = [
    for (final doc in index.docs)
      if (doc.docTypeId == featureType && index.parentOf(doc) == null) doc,
  ];
  final summary = _summaryLine(index, features);
  if (features.isEmpty) return summary;
  return [
    summary,
    '',
    _tableHead,
    for (final feature in features) _row(index, feature, featuresDocPath),
  ].join('\n');
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
  return '| ${cells.map((c) => c.isEmpty ? _noValue : c).join(' | ')} |';
}

String _featureLink(IndexedDoc feature, String featuresDocPath) {
  final text = feature.hasTitle ? feature.title! : feature.name;
  final href = relativeHref(featuresDocPath, feature.docPath);
  return '[${_cell(text)}]($href)';
}

/// Returns [text] as one table cell: line breaks become spaces and each `|` not
/// written `\|` is escaped.
String _cell(String text) =>
    text.trim().replaceAll(_lineBreak, ' ').replaceAll(_unescapedPipe, r'\|');

/// Returns what [cell] gives for the one target, or for each target as
/// `<target>: <cell>` joined by `, ` when the project names two or more.
String _byTarget(DocIndex index, String Function(String? target) cell) =>
    index.hasTwins
    ? [for (final target in index.targetNames) '$target: ${cell(target)}']
          .join(_listSeparator)
    : cell(null);

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
