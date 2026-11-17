import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/edge_case_blocks.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_entry.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/consistency_check/test_pointer_rule.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/matrix_rows.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';

/// Returns the findings of the Verification matrix rows of a record [doc]; any
/// other doc has none.
///
/// A row is checked against the code root of the record's own target. A row
/// naming no story or FR of the feature, or an item under a skip, is the
/// record entry rule's, so this rule checks the literal of an FR that is
/// neither skipped nor `planned` and no row of any other item. A test file is
/// read at most once per run, by the reader of the `tests` lines.
Iterable<Finding> checkMatrixRows(CheckContext context, IndexedDoc doc) sync* {
  final read = recordDocOf(context, doc);
  if (read == null || doc.matrixLines.isEmpty) return;
  final testField = recordTestFieldOf(read.type);
  yield* _MatrixWalk(
    context,
    doc,
    recordItemsOf(read.feature, context.index.childrenOf),
    testField == null ? const [] : recordTestLinesOf(doc, testField),
  ).findings();
}

/// One record's matrix lines read in file order.
final class _MatrixWalk {
  new(this._context, this._record, this._items, this._testLines)
    : _target = _context.targets
          .where((target) => target.name == _record.target)
          .firstOrNull;

  final CheckContext _context;
  final IndexedDoc _record;
  final Map<String, IndexedDoc> _items;
  final List<({String item, String path})> _testLines;
  final CodeTarget? _target;

  final Map<String, Map<String, String>> _edgeCases = {};
  final Map<String, List<MatrixRow>> _earlierRows = {};

  Iterable<Finding> findings() sync* {
    for (final line in _record.matrixLines) {
      switch (line) {
        case MalformedRow(:final text):
          yield _finding(
            FindingKind.matrixRowMalformed,
            line.line,
            '$text is no matrix row; write "- <item> <edge case>: '
            '`<test name>`" or "- <item> <edge case> skipped: <reason>"',
            {'row': text},
          );
        case final MatrixRow row:
          yield* _resolved(row);
          yield* _related(row);
      }
    }
  }

  Iterable<Finding> _resolved(MatrixRow row) sync* {
    final item = _items[row.item];
    if (item == null) return;
    if (item.docTypeId != frType) {
      yield _finding(
        FindingKind.matrixRowUnresolved,
        row.line,
        '${row.item} is a story; a row names an FR',
        {'item': row.item},
      );
      return;
    }
    if (!_edgeCasesOf(item).containsKey(row.edgeCase)) {
      yield _finding(
        FindingKind.matrixRowUnresolved,
        row.line,
        '${row.item} has no edge case ${row.edgeCase}',
        {'item': row.item, 'edge_case': row.edgeCase},
      );
    }
    if (row is TestRow) yield* _literalOf(row, item);
  }

  Map<String, String> _edgeCasesOf(IndexedDoc fr) =>
      _edgeCases.putIfAbsent(fr.docPath, () => edgeCaseBlocksOf(_context, fr));

  Iterable<Finding> _literalOf(TestRow row, IndexedDoc fr) sync* {
    final target = _target;
    if (target == null || !_isChecked(fr)) return;
    final paths = {
      for (final line in _testLines)
        if (line.item == row.item) line.path,
    };
    var unreadable = false;
    for (final path in paths) {
      // A path naming no file is the `tests` line rule's.
      if (!ImplementsEntry(path).namesFileFrom(_context.codeRootOf(target))) {
        continue;
      }
      final text = testFileTextOf(_context, target, path);
      if (text == null) {
        unreadable = true;
      } else if (text.contains(row.literal)) {
        return;
      }
    }
    if (unreadable) return;
    yield _finding(
      FindingKind.matrixTestUnresolved,
      row.line,
      paths.isEmpty
          ? '${row.item} has no tests line to hold ${row.literal}'
          : '${row.literal} occurs in no test file of ${row.item}',
      {'item': row.item, 'name': row.literal},
    );
  }

  /// Whether [fr]'s literals are checked: its status in the record's target is
  /// `implemented` or `deprecated`.
  bool _isChecked(IndexedDoc fr) =>
      switch (_context.index.itemStatus(fr, codeTarget: _record.target)) {
        RecordStatus.implemented || RecordStatus.deprecated => true,
        RecordStatus.planned || RecordStatus.skipped => false,
      };

  Iterable<Finding> _related(MatrixRow row) sync* {
    final earlier = _earlierRows.putIfAbsent(row.label, () => []);
    if (row is TestRow) {
      final repeated = earlier
          .whereType<TestRow>()
          .where((other) => other.literal == row.literal)
          .firstOrNull;
      if (repeated != null) {
        yield _finding(
          FindingKind.matrixRowRepeated,
          row.line,
          '${row.label} names ${row.literal} again; line ${repeated.line} '
          'holds it, keep one row',
          {'first': repeated.line},
        );
      }
    }
    final beside = row is SkipRow
        ? earlier.firstOrNull
        : earlier.whereType<SkipRow>().firstOrNull;
    if (beside != null) {
      yield _finding(
        FindingKind.matrixSkipConflict,
        row.line,
        '${row.label} has a skip row beside another row; line ${beside.line} '
        'holds the other',
        {'first': beside.line},
      );
    }
    earlier.add(row);
  }

  Finding _finding(
    FindingKind kind,
    int line,
    String message,
    Map<String, Object> keys,
  ) =>
      _context.finding(_record, kind, line: line, message: message, keys: keys);
}
