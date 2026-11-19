import 'package:specstone_core/src/doc_model/code_spans.dart';
import 'package:specstone_core/src/index_query/matrix_rows.dart'
    show matrixLinesIn;
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Constants

const _literalSeparator = ', ';
const _reasonSeparator = '; ';
const _headEnd = ': ';

// MARK: - Types

/// A record's text with its per-edge-case matrix rows folded, and the row
/// counts the fold changed.
final class FoldedRecord {
  const new({
    required this.text,
    required this.rowsBefore,
    required this.rowsAfter,
  });

  /// The record text, every folded row at the place of its item's first row.
  final String text;

  /// The rows of the folded items before the fold.
  final int rowsBefore;

  /// The rows of the folded items after the fold: one per item.
  final int rowsAfter;
}

// MARK: - Fold

/// Folds each item of [frNames] that holds a per-edge-case row in [lfText], a
/// record of [recordType], into one per-FR row at its first row; null when
/// none folds.
///
/// The row has no fingerprint. Test rows win over skip rows and keep each
/// distinct literal once; skip rows join distinct reasons with `; `.
FoldedRecord? foldMatrixRows(
  String lfText,
  MergedDocType recordType,
  Set<String> frNames,
) {
  final byItem = _foldableItemsIn(lfText, recordType, frNames);
  if (byItem.isEmpty) return null;
  final folded = <int, String>{};
  final dropped = <int>{};
  var rowsBefore = 0;
  for (final MapEntry(key: item, value: rows) in byItem.entries) {
    folded[rows.first.line - 1] = _foldedRowOf(item, rows);
    dropped.addAll(rows.skip(1).map((row) => row.line - 1));
    rowsBefore += rows.length;
  }
  final lines = lfText.split('\n');
  return FoldedRecord(
    text: [
      for (final (at, text) in lines.indexed)
        if (!dropped.contains(at)) folded[at] ?? text,
    ].join('\n'),
    rowsBefore: rowsBefore,
    rowsAfter: byItem.length,
  );
}

/// Returns the rows, in file order, of each item of [frNames] that holds at
/// least one per-edge-case row.
Map<String, List<MatrixRow>> _foldableItemsIn(
  String lfText,
  MergedDocType recordType,
  Set<String> frNames,
) {
  final byItem = <String, List<MatrixRow>>{};
  for (final row in matrixLinesIn(lfText, recordType).whereType<MatrixRow>()) {
    if (frNames.contains(row.item)) (byItem[row.item] ??= []).add(row);
  }
  byItem.removeWhere(
    (_, rows) => rows.every((row) => row.form == RowForm.perFr),
  );
  return byItem;
}

String _foldedRowOf(String item, List<MatrixRow> rows) {
  final tests = rows.whereType<TestRow>().toList();
  if (tests.isEmpty) {
    final reasons = {for (final row in rows.whereType<SkipRow>()) row.reason};
    return '- $item skipped: ${reasons.join(_reasonSeparator)}';
  }
  return '- $item$_headEnd${_distinctSpansOf(tests).join(_literalSeparator)}';
}

/// Returns each distinct literal of [tests] as its row wrote it, so a literal
/// with a backtick or an edge space keeps its span.
List<String> _distinctSpansOf(List<TestRow> tests) {
  final spans = <String, String>{};
  for (final row in tests) {
    final rest = row.written.substring(
      row.written.indexOf(_headEnd) + _headEnd.length,
    );
    final written = codeSpansOf(rest);
    for (final (at, literal) in row.literals.indexed) {
      spans.putIfAbsent(
        literal,
        () => rest.substring(written[at].start, written[at].end),
      );
    }
  }
  return spans.values.toList();
}
