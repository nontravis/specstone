import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart' show withKeyBlock;
import 'package:specstone_core/src/doc_model/list_block_writer.dart';
import 'package:specstone_core/src/document_writing/code_judge.dart'
    show stampFieldsOf;
import 'package:specstone_core/src/document_writing/sync_lines.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/matrix_rows.dart'
    show matrixLinesIn;
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/record_entries.dart'
    show RecordLines, addRecordLines, recordTestFieldOf;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/matrix_mode.dart';
import 'package:specstone_core/src/templates/project_config.dart'
    show verificationCoverageKey;

const _literalSeparator = ', ';
const _headEnd = ': ';

// MARK: - Tests lines

/// Returns [lfText], a record of [recordType], with the `<item>:<test file>`
/// line of [line] added to its `tests` field for `+`, or removed for `-`; as
/// it is when the field already reads so. A field left with no line loses its
/// key. Throws an [IndexFault] `argument_invalid` when [recordType] holds no
/// `tests` field.
String applyTestsLine(String lfText, MergedDocType recordType, TestsLine line) {
  final field =
      recordTestFieldOf(recordType) ??
      (throw IndexFault(
        IndexFaultCode.argumentInvalid,
        'the ${recordType.id} type holds no tests field',
      ));
  final entry = '${line.item}:${line.testFile}';
  final held = stampFieldsOf(lfText, [field]).firstOrNull;
  if (line.adds) {
    if (held?.entries.contains(entry) ?? false) return lfText;
    return addRecordLines(lfText, recordType, RecordLines(tests: [entry])) ??
        lfText;
  }
  if (held == null || !held.entries.contains(entry)) return lfText;
  final kept = [
    for (final value in held.entries)
      if (value != entry) value,
  ];
  return withKeyBlock(
    lfText,
    field.id,
    kept.isEmpty ? null : listBlockOf(field.id, kept, onDisk: held.block),
  );
}

// MARK: - Row lines

/// Returns [lfText], a record of [recordType], with the `+` literals of
/// [line] added to its item's rows and the `-` literals removed, as [mode]
/// reads them; a row left with no literal is removed. [isRefusedForm] tells a
/// row [mode] does not read. Throws an [IndexFault] `argument_invalid` for a
/// line [mode] refuses or a literal on both sides.
String applyRowLine(
  String lfText,
  MergedDocType recordType,
  RowLine line, {
  required MatrixMode mode,
  required bool Function(MatrixRow row) isRefusedForm,
}) {
  final rows = [
    for (final row in matrixLinesIn(lfText, recordType).whereType<MatrixRow>())
      if (row.item == line.item) row,
  ];
  _refuseForm(line, mode, rows.any(isRefusedForm));
  final change = _Change.of(line);
  final edits = switch (line.edgeCase) {
    null => _perFrEdits(line.item, rows, change),
    final edgeCase => _perEdgeCaseEdits(line.item, edgeCase, rows, change),
  };
  final text = _withLines(lfText, edits.changed);
  return addRecordLines(text, recordType, RecordLines(rows: edits.added)) ??
      text;
}

/// Throws the `argument_invalid` [IndexFault] of [line] when [mode] refuses
/// it: a per-edge-case line under off or `fr`, a per-FR line that adds a
/// literal under `edge_case`, or a per-FR line under off or `fr` beside a
/// refused-form row of its item, which waits for `specstone migrate`.
void _refuseForm(RowLine line, MatrixMode mode, bool holdsRefusedForm) {
  final coverage = '$verificationCoverageKey ${_modeName(mode)}';
  final message = switch ((line.edgeCase, mode.readsForm)) {
    (_?, RowForm.perFr) =>
      'a per-edge-case row line under $coverage; write one row per FR',
    (null, RowForm.perEdgeCase) when line.added.isNotEmpty =>
      'a per-FR row line that adds a literal under $coverage; '
          'write one row per edge case',
    (null, RowForm.perFr) when holdsRefusedForm =>
      '${line.item} holds per-edge-case rows, which wait for '
          'specstone migrate under $coverage',
    _ => null,
  };
  if (message != null) {
    throw IndexFault(IndexFaultCode.argumentInvalid, message);
  }
}

String _modeName(MatrixMode mode) => switch (mode) {
  MatrixMode.off => 'off',
  MatrixMode.fr => 'fr',
  MatrixMode.edgeCase => 'edge_case',
};

/// The literals one row line adds and removes, each once.
final class _Change {
  const new(this.added, this.removed);

  /// Reads [line]; throws an [IndexFault] `argument_invalid` naming a literal
  /// on both of its sides.
  factory of(RowLine line) {
    final removed = line.removed.toSet();
    for (final literal in line.added) {
      if (!removed.contains(literal)) continue;
      throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '${codeSpanOf(literal)} is both added and removed; write it once',
      );
    }
    return _Change(line.added.toSet().toList(), removed);
  }

  final List<String> added;
  final Set<String> removed;
}

/// The row lines one row line changes, by 1-based file line, a null
/// removing the line, and the rows it adds at the section's end.
final class _RowEdits {
  const new({this.changed = const {}, this.added = const []});

  final Map<int, String?> changed;
  final List<String> added;
}

_RowEdits _perFrEdits(String item, List<MatrixRow> rows, _Change change) {
  final row = rows.where((row) => row.form == RowForm.perFr).firstOrNull;
  final made = _rowText(item, null, change.added.map(codeSpanOf));
  return switch (row) {
    TestRow() => _RowEdits(changed: _testRowChanged(row, change)),
    SkipRow() when change.added.isNotEmpty => _RowEdits(
      changed: {row.line: made},
    ),
    null when change.added.isNotEmpty => _RowEdits(added: [made]),
    _ => const _RowEdits(),
  };
}

/// Returns the line [row] becomes, its fingerprint kept, or none when
/// [change] leaves its literals as they are.
Map<int, String?> _testRowChanged(TestRow row, _Change change) {
  final spans = _writtenSpansOf(row);
  final kept = <String, String>{
    for (final (at, literal) in row.literals.indexed)
      if (!change.removed.contains(literal)) literal: spans[at],
  };
  final keptOfRow = kept.length;
  for (final literal in change.added) {
    kept.putIfAbsent(literal, () => codeSpanOf(literal));
  }
  if (keptOfRow == row.literals.length && kept.length == keptOfRow) {
    return const {};
  }
  return {
    row.line: kept.isEmpty
        ? null
        : _rowText(row.item, null, kept.values, row.fingerprint),
  };
}

/// Returns the edits of a per-edge-case line: a row per literal, matched by
/// its first literal, since a per-edge-case test row holds one.
_RowEdits _perEdgeCaseEdits(
  String item,
  String edgeCase,
  List<MatrixRow> rows,
  _Change change,
) {
  final tests = [
    for (final row in rows.whereType<TestRow>())
      if (row.edgeCase == edgeCase) row,
  ];
  final held = {for (final row in tests) row.firstLiteral};
  final gone = [
    for (final row in tests)
      if (change.removed.contains(row.firstLiteral)) row.line,
  ];
  final made = [
    for (final literal in change.added)
      if (!held.contains(literal))
        _rowText(item, edgeCase, [codeSpanOf(literal)]),
  ];
  // A made row takes the place of a removed one, so a renamed test's row
  // stays where it stood.
  return _RowEdits(
    changed: {
      for (final (at, line) in gone.indexed)
        line: at < made.length ? made[at] : null,
    },
    added: made.skip(gone.length).toList(),
  );
}

/// Returns each code span of [row] as the record writes it, in literal order.
List<String> _writtenSpansOf(TestRow row) {
  final rest = row.written.substring(
    row.written.indexOf(_headEnd) + _headEnd.length,
  );
  return [
    for (final span in codeSpansOf(rest)) rest.substring(span.start, span.end),
  ];
}

String _rowText(
  String item,
  String? edgeCase,
  Iterable<String> spans, [
  String? fingerprint,
]) {
  final head = edgeCase == null ? item : '$item $edgeCase';
  final tail = fingerprint == null ? '' : ' $fingerprint';
  return '- $head$_headEnd${spans.join(_literalSeparator)}$tail';
}

// MARK: - Row stamps

/// Returns the rows of [lfText], a record of [recordType], that [entry]
/// names: `<item>` its per-FR rows, `<item> <edge case>` its rows of that
/// edge case.
List<MatrixRow> matrixRowsNamed(
  String lfText,
  MergedDocType recordType,
  String entry,
) {
  final space = entry.indexOf(' ');
  final item = space < 0 ? entry : entry.substring(0, space);
  final edgeCase = space < 0 ? null : entry.substring(space + 1);
  return [
    for (final row in matrixLinesIn(lfText, recordType).whereType<MatrixRow>())
      if (row.item == item && row.edgeCase == edgeCase) row,
  ];
}

/// Returns [lfText] with each of [rows] ending in [fingerprint] in place of
/// the one it records.
String withRowsStamped(
  String lfText,
  List<MatrixRow> rows,
  String fingerprint,
) => _withLines(lfText, {
  for (final row in rows)
    if (row.fingerprint != fingerprint)
      row.line: '- ${row.written} $fingerprint',
});

/// Returns [lfText] with each 1-based line of [changed] set to its value, a
/// null removing the line.
String _withLines(String lfText, Map<int, String?> changed) {
  if (changed.isEmpty) return lfText;
  return [
    for (final (at, line) in lfText.split('\n').indexed)
      if (!changed.containsKey(at + 1)) line else ?changed[at + 1],
  ].join('\n');
}
