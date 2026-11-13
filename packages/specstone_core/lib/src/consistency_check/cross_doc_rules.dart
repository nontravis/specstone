import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fr_trace_rows.dart';
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show tableCellRanges, tableHeadCells;
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show normalCodeEntry;
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _featuresType = 'features';
const _systemsSection = 'systems';
const _systemField = 'system';
const _apiType = 'api';
const _frTraceSection = 'fr_trace';
const _operationsSection = 'operations';
const _authType = 'auth';
const _scopesSection = 'scopes';
const _requiredForColumn = 'Required for';
const _topicType = 'topic';
const _scopeSection = 'scope';
const _coversField = 'covers';

final _hex12 = RegExp(r'^[0-9a-f]{12}$');

/// Returns the cross-doc guide findings of a typed [doc]; an untyped doc has
/// none.
///
/// Each rule ties a value in one doc to a row or block in another: a feature
/// `system:` value to a Systems table row of the `features` doc, an api
/// `fr_trace` row's operation to an `operations` `###` heading and back, an
/// auth scope's Required for cell to an operation of its feature's api doc,
/// and a topic `scope` path to a `covers` prefix. A rule runs only when the
/// merged set holds the doc type, section, or field it reads.
Iterable<Finding> checkCrossDocGuideRules(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (!context.isChecked(doc)) return;
  switch (doc.docTypeId) {
    case featureType:
      yield* _systemFindings(context, doc);
    case _apiType:
      yield* _operationFindings(context, doc);
    case _authType:
      yield* _scopeOperationFindings(context, doc);
    case _topicType:
      yield* _scopePathFindings(context, doc);
  }
}

Iterable<Finding> _systemFindings(CheckContext context, IndexedDoc doc) sync* {
  if (!context.typeHoldsField(context.typeOf(doc), _systemField)) return;
  if (!context.typeHoldsSection(_featuresType, _systemsSection)) return;
  final rows = {
    for (final features in context.index.docs)
      if (features.docTypeId == _featuresType)
        for (final name in _firstCellsOf(context, features, _systemsSection))
          name,
  };
  final lines = context.linesOf(doc);
  for (final (:value, :line, text: _) in lines.entriesOf(_systemField)) {
    if (value is! String || rows.contains(value)) continue;
    yield context.finding(
      doc,
      FindingKind.systemUnresolved,
      line: line,
      message: '$value names no row of the Systems table',
      keys: {'system': value},
    );
  }
}

Iterable<Finding> _operationFindings(
  CheckContext context,
  IndexedDoc api,
) sync* {
  if (!context.typeHoldsSection(_apiType, _frTraceSection) ||
      !context.typeHoldsSection(_apiType, _operationsSection)) {
    return;
  }
  final operations = _operationHeadings(context, api);
  final traced = [
    for (final (:operation, :line) in _traceOperations(context, api))
      (operation: operation, line: line),
  ];
  for (final (:operation, :line) in traced) {
    if (operations.containsKey(operation)) continue;
    yield context.finding(
      api,
      FindingKind.operationUnmatched,
      line: line,
      message: '$operation has no Operations block',
      keys: {'operation': operation},
    );
  }
  final tracedNames = traced.map((row) => row.operation).toSet();
  for (final MapEntry(:key, :value) in operations.entries) {
    if (tracedNames.contains(key)) continue;
    yield context.finding(
      api,
      FindingKind.operationUnmatched,
      line: value,
      message: '$key has no FR trace row',
      keys: {'operation': key},
    );
  }
}

/// Returns the `###` heading operation of the `operations` section of [api],
/// with the heading's file line.
Map<String, int> _operationHeadings(CheckContext context, IndexedDoc api) {
  final headings = <String, int>{};
  final index = context.heldIndexOf(api, _operationsSection);
  if (index == null) return headings;
  for (final line in context.bodyLinesOf(api, index)) {
    if (line.fenced || !line.text.startsWith('### ')) continue;
    final operation = _headingOperation(line.text.substring(4));
    if (operation != null) headings.putIfAbsent(operation, () => line.line);
  }
  return headings;
}

/// Returns the operation of an Operations `###` [heading]: its code span when
/// it holds one, else the whole heading text trimmed.
String? _headingOperation(String heading) {
  for (final (:start, :end, :ticks) in codeSpansOf(heading)) {
    final inner = heading.substring(start + ticks, end - ticks).trim();
    if (inner.isNotEmpty) return inner;
  }
  final text = heading.trim();
  return text.isEmpty ? null : text;
}

/// Returns each `fr_trace` row's Operation cell with the row's file line.
Iterable<({String operation, int line})> _traceOperations(
  CheckContext context,
  IndexedDoc api,
) sync* {
  final held = context.contentOf(api).sections;
  for (var i = 0; i < held.length; i++) {
    if (context.templateSectionAt(api, i)?.id != _frTraceSection) continue;
    final body = context.bodyLinesOf(api, i);
    final textByLine = {for (final line in body) line.line: line.text};
    for (final (:line, cell: _) in readFrTraceRows(body)) {
      final operation = _secondCell(textByLine[line] ?? '');
      if (operation != null) yield (operation: operation, line: line);
    }
  }
}

String? _secondCell(String row) {
  final cells = tableCellRanges(row);
  if (cells.length < 2) return null;
  final cell = row.substring(cells[1].start, cells[1].end).trim();
  return cell.length > 1 && cell.startsWith('`') && cell.endsWith('`')
      ? cell.substring(1, cell.length - 1)
      : cell;
}

Iterable<Finding> _scopeOperationFindings(
  CheckContext context,
  IndexedDoc auth,
) sync* {
  if (!context.typeHoldsSection(_authType, _scopesSection)) return;
  final api = _apiOf(context, auth);
  if (api == null) return;
  final operations = _operationHeadings(context, api).keys.toSet();
  final index = context.heldIndexOf(auth, _scopesSection);
  if (index == null) return;
  for (final (:operation, :line) in _requiredForCells(
    context.bodyLinesOf(auth, index),
  )) {
    if (operations.contains(operation)) continue;
    yield context.finding(
      auth,
      FindingKind.scopeOperationUnresolved,
      line: line,
      message: '$operation is no operation of ${api.name}',
      keys: {'operation': operation},
    );
  }
}

/// Returns the api doc of the feature [doc] nests under, in [doc]'s target;
/// null when the doc nests under none or the feature holds no api doc.
IndexedDoc? _apiOf(CheckContext context, IndexedDoc doc) {
  final feature = context.index.parentOf(doc);
  if (feature == null) return null;
  IndexedDoc? found;
  for (final child in context.index.childrenOf(feature)) {
    if (child.docTypeId != _apiType || child.target != doc.target) continue;
    found ??= child;
  }
  return found;
}

/// Returns each body row's Required for cell with the row's line, one pair of
/// backticks dropped.
Iterable<({String operation, int line})> _requiredForCells(
  List<BodyLine> body,
) sync* {
  for (final table in _tablesOf(body)) {
    for (final row in table.rows) {
      final cell = _cellAt(row.text, table.header.indexOf(_requiredForColumn));
      if (cell != null && cell.isNotEmpty) {
        yield (operation: _unquoted(cell), line: row.line);
      }
    }
  }
}

Iterable<Finding> _scopePathFindings(
  CheckContext context,
  IndexedDoc topic,
) sync* {
  if (!context.typeHoldsSection(_topicType, _scopeSection) ||
      !context.typeHoldsField(context.typeOf(topic), _coversField)) {
    return;
  }
  final covers = [
    for (final (:value, line: _, text: _)
        in context.linesOf(topic).entriesOf(_coversField))
      if (value is String) normalCodeEntry(_withoutFingerprint(value)),
  ];
  final index = context.heldIndexOf(topic, _scopeSection);
  if (index == null) return;
  for (final line in context.bodyLinesOf(topic, index)) {
    if (line.fenced) continue;
    for (final (:start, :end, :ticks) in codeSpansOf(line.text)) {
      final path = line.text.substring(start + ticks, end - ticks).trim();
      if (path.isEmpty) continue;
      if (covers.any((entry) => _reaches(entry, path))) continue;
      yield context.finding(
        topic,
        FindingKind.scopePathUncovered,
        line: line.line,
        message: '$path is under no covers entry',
        keys: {'path': path},
      );
    }
  }
}

/// Whether [entry] equals [path] or names a folder that holds it, by path
/// segment.
bool _reaches(String entry, String path) =>
    entry.isEmpty || path == entry || path.startsWith('$entry/');

String _withoutFingerprint(String entry) {
  final lastSpace = entry.lastIndexOf(' ');
  if (lastSpace > 0 && _hex12.hasMatch(entry.substring(lastSpace + 1))) {
    return entry.substring(0, lastSpace);
  }
  return entry;
}

/// Returns each table of [body]: its header cells and body rows.
List<({List<String> header, List<BodyLine> rows})> _tablesOf(
  List<BodyLine> body,
) {
  final tables = <({List<String> header, List<BodyLine> rows})>[];
  var k = 0;
  while (k + 1 < body.length) {
    if (body[k].fenced || body[k + 1].fenced) {
      k++;
      continue;
    }
    final cells = tableHeadCells(body[k].text, body[k + 1].text);
    if (cells == null) {
      k++;
      continue;
    }
    var end = k + 2;
    while (end < body.length && _isRow(body[end])) {
      end++;
    }
    tables.add((
      header: [
        for (final cell in cells)
          body[k].text.substring(cell.start, cell.end).trim(),
      ],
      rows: body.sublist(k + 2, end),
    ));
    k = end;
  }
  return tables;
}

bool _isRow(BodyLine line) => !line.fenced && line.text.trim().startsWith('|');

String? _cellAt(String row, int at) {
  if (at < 0) return null;
  final cells = tableCellRanges(row);
  return at < cells.length
      ? row.substring(cells[at].start, cells[at].end).trim()
      : null;
}

String _unquoted(String cell) =>
    cell.length > 1 && cell.startsWith('`') && cell.endsWith('`')
    ? cell.substring(1, cell.length - 1)
    : cell;

/// Returns the first cell of each body row of the section [sectionId] of
/// [doc], one pair of backticks dropped.
Iterable<String> _firstCellsOf(
  CheckContext context,
  IndexedDoc doc,
  String sectionId,
) sync* {
  final index = context.heldIndexOf(doc, sectionId);
  if (index == null) return;
  for (final table in _tablesOf(context.bodyLinesOf(doc, index))) {
    for (final row in table.rows) {
      final cell = _cellAt(row.text, 0);
      if (cell != null && cell.isNotEmpty) yield _unquoted(cell);
    }
  }
}
