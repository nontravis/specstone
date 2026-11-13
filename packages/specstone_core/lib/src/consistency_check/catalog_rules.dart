import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

/// Returns the error-catalog findings of the run's scope.
///
/// [targets] names the code targets read; null reads every target. A doc-type
/// layer that sets `catalog` makes a section's table a code catalog, and one
/// that sets `names_codes` lets a whole code span in a section name a code.
/// Per target: a code in two rows of one catalog, a row no unskipped FR edge
/// case or story scenario of its feature names, and an unskipped case or
/// scenario naming a cataloged code its feature's catalog in that target
/// lacks each give one finding. No layer setting either key runs no rule.
Iterable<Finding> checkErrorCatalogs(
  CheckContext context,
  Set<String>? targets,
) sync* {
  final names =
      targets ?? {for (final target in context.targets) target.name ?? ''};
  final catalogs = _catalogsOf(context, names);
  if (catalogs.isEmpty) return;
  final catalogedCodes = {
    for (final catalog in catalogs) ...catalog.rows.map((row) => row.code),
  };
  if (catalogedCodes.isEmpty) return;
  for (final catalog in catalogs) {
    yield* _duplicateFindings(context, catalog);
  }
  for (final name in names) {
    yield* _targetFindings(context, name, catalogs, catalogedCodes);
  }
}

/// One code catalog: its doc, its feature's name, and its body rows.
typedef CatalogDoc = ({
  IndexedDoc doc,
  String feature,
  List<({String code, int line})> rows,
});

/// Returns each catalog doc the targets [names] hold, a shared doc counting
/// for every target; empty when no layer sets `catalog`.
List<CatalogDoc> _catalogsOf(CheckContext context, Set<String?> names) {
  final catalogs = <CatalogDoc>[];
  for (final doc in context.index.docs) {
    if (doc.docTypeId == null || !context.isChecked(doc)) continue;
    if (doc.target != null && !names.contains(doc.target)) continue;
    final feature = _featureNameOf(context, doc);
    if (feature == null) continue;
    final content = context.contentOf(doc);
    for (var i = 0; i < content.sections.length; i++) {
      final catalog = context.templateSectionAt(doc, i)?.catalog;
      if (catalog == null) continue;
      final rows = _catalogRowsOf(
        sectionBodyLines(content.sections, content.lineFacts, i),
        catalog.column,
      );
      if (rows.isNotEmpty) {
        catalogs.add((doc: doc, feature: feature, rows: rows));
      }
    }
  }
  return catalogs;
}

/// Returns each body row's code span under [column]; header and separator
/// rows hold none.
List<({String code, int line})> _catalogRowsOf(
  List<BodyLine> body,
  String column,
) {
  final rows = <({String code, int line})>[];
  int? codeColumn;
  for (final line in body) {
    final text = line.text.trim();
    if (line.fenced || !text.startsWith('|')) continue;
    final cells = _cellsOf(text);
    if (cells.every((cell) => cell.isEmpty || _isSeparator(cell))) continue;
    codeColumn ??= _columnOf(cells, column);
    if (codeColumn >= cells.length) continue;
    final span = codeSpansOf(cells[codeColumn]).firstOrNull;
    if (span == null) continue;
    rows.add((code: _spanText(cells[codeColumn], span), line: line.line));
  }
  return rows;
}

/// Returns the cells of table row [row], its outer pipes dropped.
List<String> _cellsOf(String row) {
  var inner = row.substring(1);
  if (inner.endsWith('|')) inner = inner.substring(0, inner.length - 1);
  return [for (final cell in inner.split('|')) cell.trim()];
}

bool _isSeparator(String cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell);

/// Returns the index of [column] in [cells], or 0 when it names none.
int _columnOf(List<String> cells, String column) {
  final index = cells.indexWhere((cell) => cell == column);
  return index < 0 ? 0 : index;
}

String _spanText(String line, CodeSpan span) =>
    line.substring(span.start + span.ticks, span.end - span.ticks);

/// Returns the name of the nearest feature at or above [doc], or null.
String? _featureNameOf(CheckContext context, IndexedDoc doc) {
  for (
    IndexedDoc? member = doc;
    member != null;
    member = context.index.parentOf(member)
  ) {
    if (member.docTypeId == featureTypeId) return member.name;
  }
  return null;
}

const featureTypeId = 'feature';
const frTypeId = 'fr';
const storyTypeId = 'user_story';

Iterable<Finding> _duplicateFindings(
  CheckContext context,
  CatalogDoc catalog,
) sync* {
  final seen = <String>{};
  for (final row in catalog.rows) {
    if (!seen.add(row.code)) {
      yield context.finding(
        catalog.doc,
        FindingKind.errorCodeDuplicate,
        line: row.line,
        message: '${row.code} is written into the catalog more than once',
        keys: {'code': row.code},
      );
    }
  }
}

/// One code an unskipped requirement of a feature names: where and in what.
typedef RaisedCode = ({IndexedDoc doc, String code, int line});

/// Returns the catalog findings of one target [name]: each catalog row no
/// unskipped requirement of its feature names, and each code a requirement
/// names while its feature's catalog here lacks it.
Iterable<Finding> _targetFindings(
  CheckContext context,
  String? name,
  List<CatalogDoc> catalogs,
  Set<String> catalogedCodes,
) sync* {
  final catalogByFeature = <String, CatalogDoc>{};
  for (final catalog in catalogs) {
    if (catalog.doc.target == null || catalog.doc.target == name) {
      catalogByFeature.putIfAbsent(catalog.feature, () => catalog);
    }
  }
  if (catalogByFeature.isEmpty) return;
  final raised = <String, List<RaisedCode>>{};
  for (final doc in context.index.docs) {
    if (doc.target != null && doc.target != name) continue;
    final typeId = doc.docTypeId;
    if (typeId != frTypeId && typeId != storyTypeId) continue;
    final feature = _featureNameOf(context, doc);
    if (feature == null || !catalogByFeature.containsKey(feature)) continue;
    if (context.index.coveringSkipOf(doc, codeTarget: name) != null) continue;
    (raised[feature] ??= []).addAll([
      for (final named in _namedCodesOf(context, doc, catalogedCodes))
        (doc: doc, code: named.code, line: named.line),
    ]);
  }
  for (final catalog in catalogByFeature.values) {
    final named = {
      for (final raisedCode in raised[catalog.feature] ?? const <RaisedCode>[])
        raisedCode.code,
    };
    for (final row in catalog.rows) {
      if (named.contains(row.code)) continue;
      yield context.finding(
        catalog.doc,
        FindingKind.errorCodeUnraised,
        line: row.line,
        message: 'no requirement of ${catalog.feature} names ${row.code}',
        keys: {'code': row.code},
      );
    }
  }
  for (final entry in raised.entries) {
    final catalog = catalogByFeature[entry.key]!;
    final held = {for (final row in catalog.rows) row.code};
    for (final raisedCode in entry.value) {
      if (held.contains(raisedCode.code)) continue;
      yield context.finding(
        raisedCode.doc,
        FindingKind.errorCodeUncataloged,
        line: raisedCode.line,
        message:
            '${raisedCode.code} names no row of the catalog of '
            '${entry.key}${(name == null || name.isEmpty) ? '' : ' in $name'}',
        keys: {'code': raisedCode.code},
      );
    }
  }
}

/// Returns each cataloged code a `names_codes` section of [doc] names as a
/// code span, with its line, in source order; a span whose text no catalog
/// of the project holds names nothing.
List<({String code, int line})> _namedCodesOf(
  CheckContext context,
  IndexedDoc doc,
  Set<String> catalogedCodes,
) {
  final content = context.contentOf(doc);
  final named = <({String code, int line})>[];
  for (var i = 0; i < content.sections.length; i++) {
    if (!(context.templateSectionAt(doc, i)?.namesCodes ?? false)) continue;
    for (final line in sectionBodyLines(
      content.sections,
      content.lineFacts,
      i,
    )) {
      for (final span in codeSpansOf(line.text)) {
        final code = _spanText(line.text, span);
        if (catalogedCodes.contains(code)) {
          named.add((code: code, line: line.line));
        }
      }
    }
  }
  return named;
}
