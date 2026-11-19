import 'package:specstone_core/src/doc_model/markdown_lines.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show withoutTrailingLinkGroup;

const _entityColumn = 'Entity';
const _kindColumn = 'Kind';
const _aggregateRootKind = 'Aggregate root';
const _serviceKind = 'Service';

/// One row of a domain doc's entities table.
final class EntityRow {
  const new({required this.entity, required this.kind});

  final String entity;
  final String kind;
}

/// Returns the rows of the first table in [sectionLines], read by its Entity
/// and Kind header names; gives none when it lacks either column.
List<EntityRow> entityRowsOf(Iterable<String> sectionLines) {
  final lines = sectionLines.toList();
  final head = _firstTableHead(lines);
  if (head == null) return const [];
  final header = _cellsOf(lines[head]);
  final entityIndex = header.indexOf(_entityColumn);
  final kindIndex = header.indexOf(_kindColumn);
  if (entityIndex < 0 || kindIndex < 0) return const [];
  final width = entityIndex > kindIndex ? entityIndex : kindIndex;
  final rows = <EntityRow>[];
  for (final line in lines.skip(head + 2)) {
    if (line.trim().isEmpty || !line.contains('|')) break;
    final cells = _cellsOf(line);
    if (cells.length <= width) continue;
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

int? _firstTableHead(List<String> lines) {
  for (var i = 0; i + 1 < lines.length; i++) {
    if (startsTable(lines[i], lines[i + 1])) return i;
  }
  return null;
}

List<String> _cellsOf(String row) => [
  for (final cell in tableCellRanges(row))
    row.substring(cell.start, cell.end).trim(),
];

List<String> _entitiesOfKind(List<EntityRow> rows, String kind) => [
  for (final row in rows)
    if (row.kind == kind) row.entity,
];

String _normalized(String text) =>
    withoutTrailingLinkGroup(text).replaceAll('`', '').trim();
