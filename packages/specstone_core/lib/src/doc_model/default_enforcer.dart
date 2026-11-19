import 'package:specstone_core/src/doc_model/table_cell.dart';

const _entityColumn = 'Entity';
const _kindColumn = 'Kind';
const _aggregateRootKind = 'Aggregate root';
const _serviceKind = 'Service';

final _separatorCell = RegExp(r'^:?-+:?$');
final _trailingLinkGroup = RegExp(r'\s*\(\[[^\]]*\]\([^)]*\)\)\s*$');

/// One row of a domain doc's entities table.
final class EntityRow {
  const new({required this.entity, required this.kind});

  final String entity;
  final String kind;
}

/// Returns the rows of the first table in [sectionLines] with an Entity and a
/// Kind column, read by header name.
List<EntityRow> entityRowsOf(Iterable<String> sectionLines) {
  final lines = sectionLines
      .map((line) => line.trim())
      .where((line) => line.startsWith('|'))
      .toList();
  if (lines.isEmpty) return const [];
  final header = _cellsOf(lines.first);
  final entityIndex = header.indexOf(_entityColumn);
  final kindIndex = header.indexOf(_kindColumn);
  if (entityIndex < 0 || kindIndex < 0) return const [];
  final width = entityIndex > kindIndex ? entityIndex : kindIndex;
  final rows = <EntityRow>[];
  for (final line in lines.skip(1)) {
    final cells = _cellsOf(line);
    if (cells.length <= width || _isSeparator(cells)) continue;
    rows.add(EntityRow(entity: cells[entityIndex], kind: cells[kindIndex]));
  }
  return rows;
}

/// Returns the default enforcer's Entity cell, or null when none applies.
///
/// [chain] holds the doc's own rows first, then each ancestor's, nearest
/// first. The first doc holding an Aggregate root or Service row decides.
String? defaultEnforcerOf(List<List<EntityRow>> chain) {
  for (final rows in chain) {
    final roots = _entitiesOfKind(rows, _aggregateRootKind);
    final services = _entitiesOfKind(rows, _serviceKind);
    if (roots.isEmpty && services.isEmpty) continue;
    final candidates = roots.isNotEmpty ? roots : services;
    return candidates.length == 1 ? candidates.single : null;
  }
  return null;
}

/// Returns whether [text] names [entityCell], letter case included.
///
/// Each side drops a trailing parenthesized link group and backticks, then
/// trims outer spaces.
bool namesDefaultEnforcer(String text, String entityCell) =>
    _normalized(text) == _normalized(entityCell);

/// Returns the same file name in each parent folder of [docPath], nearest
/// first, up to the folder at the path's first segment.
///
/// [docPath] is relative to the docs root and starts at its spec folder.
Iterable<String> ancestorTwinPaths(String docPath) sync* {
  final segments = docPath.split('/');
  final name = segments.last;
  for (var folders = segments.length - 2; folders >= 1; folders--) {
    yield [...segments.take(folders), name].join('/');
  }
}

List<String> _cellsOf(String row) {
  var inner = row.trim();
  if (inner.startsWith('|')) inner = inner.substring(1);
  if (inner.endsWith('|') && !inner.endsWith(r'\|')) {
    inner = inner.substring(0, inner.length - 1);
  }
  return inner.split(tableCellPipe).map((cell) => cell.trim()).toList();
}

bool _isSeparator(List<String> cells) => cells.every(_separatorCell.hasMatch);

List<String> _entitiesOfKind(List<EntityRow> rows, String kind) => [
  for (final row in rows)
    if (row.kind == kind) row.entity,
];

String _normalized(String text) =>
    text.replaceFirst(_trailingLinkGroup, '').replaceAll('`', '').trim();
