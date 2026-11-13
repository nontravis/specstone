import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show RecordStatus;

/// Returns the error-catalog findings of the run's scope.
///
/// [targets] names the code targets read, the unnamed target as the empty
/// string; null reads every target. A doc-type layer that sets `catalog`
/// makes a section's table a code catalog, and one that sets `names_codes`
/// lets a whole code span in a section name a code. A catalog belongs to the
/// doc its own doc hangs under. Per target: a code in two rows of one
/// catalog, a row no unskipped requirement under its owner names, and an
/// unskipped requirement naming a cataloged code of the project while the
/// nearest owner above it lacks it each give one finding. No layer setting
/// either key runs no rule.
Iterable<Finding> checkErrorCatalogs(
  CheckContext context,
  Set<String>? targets,
) sync* {
  final names = {
    for (final name
        in targets ?? {for (final target in context.targets) target.name ?? ''})
      if (name.isEmpty) null else name,
  };
  final catalogs = _catalogsOf(context);
  final catalogedCodes = {
    for (final catalog in catalogs) ...catalog.rows.map((row) => row.code),
  };
  if (catalogedCodes.isEmpty) return;
  for (final catalog in catalogs) {
    if (catalog.doc.target == null || names.contains(catalog.doc.target)) {
      yield* _duplicateFindings(context, catalog);
    }
  }
  for (final name in names) {
    yield* _targetFindings(context, name, catalogs, catalogedCodes);
  }
}

/// One code catalog: its doc, the doc it hangs under, and its body rows.
typedef CatalogDoc = ({
  IndexedDoc doc,
  IndexedDoc owner,
  List<({String code, int line})> rows,
});

/// Returns each catalog doc of every target, a shared doc once; empty when no
/// layer sets `catalog`.
List<CatalogDoc> _catalogsOf(CheckContext context) {
  final catalogs = <CatalogDoc>[];
  for (final doc in context.index.docs) {
    if (doc.docTypeId == null || !context.isChecked(doc)) continue;
    final owner = context.index.parentOf(doc);
    if (owner == null) continue;
    final content = context.contentOf(doc);
    for (var i = 0; i < content.sections.length; i++) {
      final catalog = context.templateSectionAt(doc, i)?.catalog;
      if (catalog == null) continue;
      final rows = _catalogRowsOf(
        sectionBodyLines(content.sections, content.lineFacts, i),
        catalog.column,
      );
      if (rows.isNotEmpty) {
        catalogs.add((doc: doc, owner: owner, rows: rows));
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

/// One code an unskipped requirement names: where.
typedef RaisedCode = ({IndexedDoc doc, String code, int line});

/// Returns the catalog findings of one target [name]: each catalog row no
/// unskipped requirement under its owner names, and each code a requirement
/// names while its nearest owner's catalogs here lack it.
Iterable<Finding> _targetFindings(
  CheckContext context,
  String? name,
  List<CatalogDoc> catalogs,
  Set<String> catalogedCodes,
) sync* {
  final byOwner = <String, List<CatalogDoc>>{};
  for (final catalog in catalogs) {
    if (catalog.doc.target == null || catalog.doc.target == name) {
      (byOwner[catalog.owner.docPath] ??= []).add(catalog);
    }
  }
  if (byOwner.isEmpty) return;
  final raised = <String, List<RaisedCode>>{};
  for (final doc in context.index.docs) {
    if (doc.target != null && doc.target != name) continue;
    final named = _namedCodesOf(context, doc, catalogedCodes);
    if (named.isEmpty) continue;
    if (context.index.statusOf(doc, codeTarget: name) == _skipped) continue;
    final owner = context.index
        .chainOf(doc)
        .where((member) => byOwner.containsKey(member.docPath))
        .firstOrNull;
    if (owner == null) continue;
    (raised[owner.docPath] ??= []).addAll([
      for (final (:code, :line) in named) (doc: doc, code: code, line: line),
    ]);
  }
  for (final MapEntry(key: ownerPath, value: owned) in byOwner.entries) {
    final named = {
      for (final raisedCode in raised[ownerPath] ?? const <RaisedCode>[])
        raisedCode.code,
    };
    for (final catalog in owned) {
      for (final row in catalog.rows) {
        if (named.contains(row.code)) continue;
        yield context.finding(
          catalog.doc,
          FindingKind.errorCodeUnraised,
          line: row.line,
          message: 'no requirement of ${catalog.owner.name} names ${row.code}',
          keys: {'code': row.code},
        );
      }
    }
  }
  for (final MapEntry(key: ownerPath, value: found) in raised.entries) {
    final owned = byOwner[ownerPath]!;
    final held = {
      for (final catalog in owned) ...catalog.rows.map((row) => row.code),
    };
    for (final raisedCode in found) {
      if (held.contains(raisedCode.code)) continue;
      yield context.finding(
        raisedCode.doc,
        FindingKind.errorCodeUncataloged,
        line: raisedCode.line,
        message:
            '${raisedCode.code} names no row of the catalog of '
            '${owned.first.owner.name}${name == null ? '' : ' in $name'}',
        keys: {'code': raisedCode.code},
      );
    }
  }
}

/// The status wire a skipped item reads.
final String _skipped = RecordStatus.skipped.wire;

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
