import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/models/catalog_doc.dart';
import 'package:specstone_core/src/consistency_check/models/code_at.dart';
import 'package:specstone_core/src/consistency_check/models/raised_code.dart';
import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/models/code_span.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

/// Returns the error-catalog findings of the run's scope.
///
/// [targets] names the code targets read, the unnamed target as the empty
/// string; null reads every target. A doc-type layer that sets `catalog`
/// makes a section's table a code catalog, and one that sets `names_codes`
/// lets a whole code span in a section name a code. A catalog belongs to the
/// doc its own doc hangs under; a catalog of a doc whose type takes no parent
/// is its target's project catalog, and a doc missing its parent holds none.
/// Per target: a code in two rows of one catalog, a row no unskipped
/// requirement names (under its owner, or in the target for a project
/// catalog), and an unskipped requirement naming a cataloged code while its
/// nearest owner and the project catalog both lack it each give one finding.
/// No layer setting either key runs no rule.
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

/// Returns each catalog doc of every target, a shared doc once; empty when no
/// layer sets `catalog`. A doc whose type takes no parent has no owner: its
/// catalog is its target's project catalog; a doc missing its parent holds
/// none.
List<CatalogDoc> _catalogsOf(CheckContext context) {
  final catalogs = <CatalogDoc>[];
  for (final doc in context.index.docs) {
    if (doc.docTypeId == null || !context.isChecked(doc)) continue;
    if (context.hasNoParent(doc)) continue;
    final owner = context.index.parentOf(doc);
    final content = context.contentOf(doc);
    for (var i = 0; i < content.sections.length; i++) {
      final catalog = context.templateSectionAt(doc, i)?.catalog;
      if (catalog == null) continue;
      final rows = _catalogRowsOf(
        sectionBodyLines(content.sections, content.lineFacts, i),
        catalog.column,
      );
      if (rows.isNotEmpty) {
        catalogs.add(CatalogDoc(doc: doc, owner: owner, rows: rows));
      }
    }
  }
  return catalogs;
}

/// Returns each body row's code span under [column] of its own table; the
/// header and separator rows hold none, and a table whose header lacks
/// [column] yields none. A line that is no table row ends the table.
List<CodeAt> _catalogRowsOf(List<BodyLine> body, String column) {
  final rows = <CodeAt>[];
  int? codeColumn;
  var tableStarted = false;
  for (final line in body) {
    final text = line.text.trim();
    if (line.fenced || !text.startsWith('|')) {
      codeColumn = null;
      tableStarted = false;
      continue;
    }
    final cells = _cellsOf(text);
    if (cells.every((cell) => cell.isEmpty || _isSeparator(cell))) continue;
    if (!tableStarted) {
      tableStarted = true;
      codeColumn = _columnOf(cells, column);
      continue;
    }
    if (codeColumn == null || codeColumn >= cells.length) continue;
    final span = codeSpansOf(cells[codeColumn]).firstOrNull;
    if (span == null) continue;
    rows.add(CodeAt(code: _spanText(cells[codeColumn], span), line: line.line));
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

/// Returns the index of [column] in [cells], or null when it names none.
int? _columnOf(List<String> cells, String column) {
  final index = cells.indexWhere((cell) => cell == column);
  return index < 0 ? null : index;
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

/// Returns the catalog findings of one target [name]: each catalog row no
/// unskipped requirement under its owner names, and each code a requirement
/// names while its nearest owner's catalogs and the target's project catalogs
/// lack it. A project catalog row is named by any unskipped requirement of the
/// target.
Iterable<Finding> _targetFindings(
  CheckContext context,
  String? name,
  List<CatalogDoc> catalogs,
  Set<String> catalogedCodes,
) sync* {
  final byOwner = <String, List<CatalogDoc>>{};
  final projectCatalogs = <CatalogDoc>[];
  for (final catalog in catalogs) {
    if (catalog.doc.target != null && catalog.doc.target != name) continue;
    final owner = catalog.owner;
    if (owner == null) {
      projectCatalogs.add(catalog);
    } else {
      (byOwner[owner.docPath] ??= []).add(catalog);
    }
  }
  if (byOwner.isEmpty && projectCatalogs.isEmpty) return;
  final projectHeld = {
    for (final catalog in projectCatalogs)
      ...catalog.rows.map((row) => row.code),
  };
  final projectNamed = <String>{};
  final raised = <String, List<RaisedCode>>{};
  for (final doc in context.index.docs) {
    if (doc.target != null && doc.target != name) continue;
    final named = _namedCodesOf(context, doc, catalogedCodes);
    if (named.isEmpty) continue;
    if (context.index.statusOf(doc, codeTarget: name) == _skipped) continue;
    projectNamed.addAll(named.map((entry) => entry.code));
    final owner = context.index
        .chainOf(doc)
        .where((member) => byOwner.containsKey(member.docPath))
        .firstOrNull;
    if (owner == null) continue;
    (raised[owner.docPath] ??= []).addAll([
      for (final CodeAt(:code, :line) in named)
        RaisedCode(doc: doc, code: code, line: line),
    ]);
  }
  yield* _projectUnraised(context, name, projectCatalogs, projectNamed);
  yield* _ownedUnraised(context, byOwner, raised);
  yield* _uncatalogedFindings(context, name, byOwner, raised, projectHeld);
}

/// Returns each project catalog row no unskipped requirement of the target
/// names, whose codes are [projectNamed].
Iterable<Finding> _projectUnraised(
  CheckContext context,
  String? name,
  List<CatalogDoc> projectCatalogs,
  Set<String> projectNamed,
) sync* {
  for (final catalog in projectCatalogs) {
    for (final row in catalog.rows) {
      if (projectNamed.contains(row.code)) continue;
      yield context.finding(
        catalog.doc,
        FindingKind.errorCodeUnraised,
        line: row.line,
        message:
            'no requirement${name == null ? '' : ' in $name'} '
            'names ${row.code}',
        keys: {'code': row.code},
      );
    }
  }
}

/// Returns each feature catalog row no unskipped requirement under its owner
/// names, the codes of an owner's requirements being in [raised].
Iterable<Finding> _ownedUnraised(
  CheckContext context,
  Map<String, List<CatalogDoc>> byOwner,
  Map<String, List<RaisedCode>> raised,
) sync* {
  for (final MapEntry(key: ownerPath, value: owned) in byOwner.entries) {
    final named = {
      for (final raisedCode in raised[ownerPath] ?? const <RaisedCode>[])
        raisedCode.code,
    };
    for (final catalog in owned) {
      final owner = catalog.owner;
      if (owner == null) continue;
      for (final row in catalog.rows) {
        if (named.contains(row.code)) continue;
        yield context.finding(
          catalog.doc,
          FindingKind.errorCodeUnraised,
          line: row.line,
          message: 'no requirement of ${owner.name} names ${row.code}',
          keys: {'code': row.code},
        );
      }
    }
  }
}

/// Returns each code a requirement names that neither its owner's catalogs
/// nor the project catalogs ([projectHeld]) hold.
Iterable<Finding> _uncatalogedFindings(
  CheckContext context,
  String? name,
  Map<String, List<CatalogDoc>> byOwner,
  Map<String, List<RaisedCode>> raised,
  Set<String> projectHeld,
) sync* {
  for (final MapEntry(key: ownerPath, value: found) in raised.entries) {
    final owned = byOwner[ownerPath] ?? const <CatalogDoc>[];
    final ownerName = owned.firstOrNull?.owner?.name;
    if (ownerName == null) continue;
    final held = {
      for (final catalog in owned) ...catalog.rows.map((row) => row.code),
      ...projectHeld,
    };
    for (final raisedCode in found) {
      if (held.contains(raisedCode.code)) continue;
      yield context.finding(
        raisedCode.doc,
        FindingKind.errorCodeUncataloged,
        line: raisedCode.line,
        message:
            '${raisedCode.code} names no row of the catalog of '
            '$ownerName${name == null ? '' : ' in $name'}',
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
List<CodeAt> _namedCodesOf(
  CheckContext context,
  IndexedDoc doc,
  Set<String> catalogedCodes,
) {
  final content = context.contentOf(doc);
  final named = <CodeAt>[];
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
          named.add(CodeAt(code: code, line: line.line));
        }
      }
    }
  }
  return named;
}
