import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fr_trace_rows.dart';
import 'package:specstone_core/src/consistency_check/models/fr_trace_row.dart';
import 'package:specstone_core/src/consistency_check/models/yaml_entry.dart';
import 'package:specstone_core/src/consistency_check/table_first_cells.dart';
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show headingItemTextOf;
import 'package:specstone_core/src/doc_model/markdown_lines.dart'
    show tableCellRanges;
import 'package:specstone_core/src/doc_model/models/body_line.dart';
import 'package:specstone_core/src/doc_model/models/code_span.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/project_config.dart'
    show isPortableCodeEntry;

const _systemsSection = 'systems';
const _systemField = 'system';
const _frTraceSection = 'fr_trace';
const _operationsSection = 'operations';
const _scopesSection = 'scopes';
const _requiredForColumn = 'Required for';
const _scopeSection = 'scope';
const _coversField = 'covers';

/// Returns the cross-doc guide findings of a typed [doc]; an untyped doc has
/// none.
///
/// Each rule ties a value in one doc to a row or block in another: a feature
/// `system:` value to a Systems table row of the features doc, an api
/// `fr_trace` row's operation to an `operations` `###` heading and back, an
/// auth scope's Required for cell to an operation of its feature's api doc,
/// and a topic `scope` path to a `covers` prefix. A rule runs only when the
/// merged set holds the doc type, section, or field it reads.
Iterable<Finding> checkCrossDocGuideRules(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (!context.isChecked(doc)) return;
  final type = context.typeOf(doc);
  if (type == null) return;
  if (_holdsField(type, _systemField)) yield* _systemFindings(context, doc);
  if (_holdsSection(type, _frTraceSection) &&
      _holdsSection(type, _operationsSection)) {
    yield* _operationFindings(context, doc);
  }
  if (_holdsSection(type, _scopesSection)) {
    yield* _scopeOperationFindings(context, doc);
  }
  if (_holdsSection(type, _scopeSection) && _holdsField(type, _coversField)) {
    yield* _scopePathFindings(context, doc);
  }
}

bool _holdsField(MergedDocType? type, String id) =>
    type != null && type.fields.any((field) => field.id == id);

bool _holdsSection(MergedDocType? type, String id) =>
    type != null && type.sections.any((section) => section.id == id);

Iterable<Finding> _systemFindings(CheckContext context, IndexedDoc doc) sync* {
  final rows = {
    for (final features in context.index.docs)
      if (_holdsSection(context.typeOf(features), _systemsSection))
        for (final name in firstCellsOf(context, features, _systemsSection))
          name,
  };
  final lines = context.linesOf(doc);
  for (final YamlEntry(:value, :line) in lines.entriesOf(_systemField)) {
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
  final operations = _operationHeadings(context, api);
  final traced = [
    for (final _OperationCell(:operation, :line) in _traceOperations(
      context,
      api,
    ))
      _OperationCell(operation: operation, line: line),
  ];
  for (final _OperationCell(:operation, :line) in traced) {
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
    final text = line.fenced ? null : headingItemTextOf(line.text);
    if (text == null) continue;
    final operation = _headingOperation(text);
    if (operation != null) headings.putIfAbsent(operation, () => line.line);
  }
  return headings;
}

/// Returns the operation of an Operations `###` [heading]: its code span when
/// it holds one, else the whole heading text trimmed.
String? _headingOperation(String heading) {
  for (final CodeSpan(:start, :end, :ticks) in codeSpansOf(heading)) {
    final inner = heading.substring(start + ticks, end - ticks).trim();
    if (inner.isNotEmpty) return inner;
  }
  final text = heading.trim();
  return text.isEmpty ? null : text;
}

/// Returns each `fr_trace` row's Operation cell with the row's file line.
Iterable<_OperationCell> _traceOperations(
  CheckContext context,
  IndexedDoc api,
) sync* {
  final held = context.contentOf(api).sections;
  for (var i = 0; i < held.length; i++) {
    if (context.templateSectionAt(api, i)?.id != _frTraceSection) continue;
    final body = context.bodyLinesOf(api, i);
    final textByLine = {for (final line in body) line.line: line.text};
    for (final FrTraceRow(:line) in readFrTraceRows(body)) {
      final operation = _secondCell(textByLine[line] ?? '');
      if (operation != null) {
        yield _OperationCell(operation: operation, line: line);
      }
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
  final api = _apiOf(context, auth);
  if (api == null) return;
  final operations = _operationHeadings(context, api).keys.toSet();
  final index = context.heldIndexOf(auth, _scopesSection);
  if (index == null) return;
  for (final _OperationCell(:operation, :line) in _requiredForCells(
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
    final type = context.typeOf(child);
    if (child.target != doc.target ||
        !_holdsSection(type, _frTraceSection) ||
        !_holdsSection(type, _operationsSection)) {
      continue;
    }
    found ??= child;
  }
  return found;
}

/// Returns each body row's Required for cell with the row's line, one pair of
/// backticks dropped.
Iterable<_OperationCell> _requiredForCells(List<BodyLine> body) sync* {
  for (final table in tablesOf(body)) {
    for (final row in table.rows) {
      final cell = cellAt(row.text, table.header.indexOf(_requiredForColumn));
      if (cell != null && cell.isNotEmpty) {
        yield _OperationCell(operation: unquoted(cell), line: row.line);
      }
    }
  }
}

Iterable<Finding> _scopePathFindings(
  CheckContext context,
  IndexedDoc topic,
) sync* {
  final covers = [
    for (final YamlEntry(:value)
        in context.linesOf(topic).entriesOf(_coversField))
      if (value is String) ?reachablePathOf(value),
  ];
  final index = context.heldIndexOf(topic, _scopeSection);
  if (index == null) return;
  for (final line in context.bodyLinesOf(topic, index)) {
    if (line.fenced) continue;
    for (final CodeSpan(:start, :end, :ticks) in codeSpansOf(line.text)) {
      final path = line.text.substring(start + ticks, end - ticks).trim();
      if (!path.contains('/') || !isPortableCodeEntry(path)) continue;
      if (covers.any((entry) => entryReaches(entry, path))) continue;
      yield context.finding(
        topic,
        FindingKind.scopePathUncovered,
        line: line.line,
        message: '$path is under no covers entry',
        keys: {'codePath': path},
      );
    }
  }
}

/// An operation a table cell names, and the row's file line.
final class _OperationCell {
  const new({required this.operation, required this.line});

  final String operation;
  final int line;
}
