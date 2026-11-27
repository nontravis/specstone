import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart'
    show CodePathField, codePathMessageOf, readPathOf;
import 'package:specstone_core/src/consistency_check/edge_case_blocks.dart';
import 'package:specstone_core/src/consistency_check/exact_case_path.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/literal_scan.dart';
import 'package:specstone_core/src/consistency_check/matrix_form.dart';
import 'package:specstone_core/src/consistency_check/models/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/record_doc.dart';
import 'package:specstone_core/src/consistency_check/test_pointer_rule.dart';
import 'package:specstone_core/src/consistency_check/trace_rules.dart'
    show isVerifiedByTest, shownTargetName;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/models/record_test_line.dart';
import 'package:specstone_core/src/index_query/record_entries.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show MergedField;
import 'package:specstone_core/src/templates/models/matrix_mode.dart';
import 'package:specstone_core/src/templates/models/record_status.dart';

/// Returns the findings of the Verification matrix rows of a record [doc]; any
/// other doc has none.
///
/// A row is checked against the code root of the record's own target. A row of
/// the form the mode does not read, naming an FR, gets the form finding alone.
/// A row naming no story or FR of the feature, or an item under a skip, is the
/// record entry rule's, so this rule checks the literal of an FR that is
/// neither skipped nor `planned` and no row of any other item. A test file is
/// read at most once per run, by the reader of the `tests` lines.
Iterable<Finding> checkMatrixRows(CheckContext context, IndexedDoc doc) sync* {
  final read = recordDocOf(context, doc);
  if (read == null || doc.matrixLines.isEmpty) return;
  yield* _MatrixWalk(
    context,
    doc,
    recordItemsOf(read.feature, context.index.childrenOf),
    _testPathsOf(doc, recordTestFieldOf(read.type)),
  ).findings();
}

/// Returns `matrix_row_missing` for each `implemented`, test-verified FR of
/// record [doc] that no row names, or under `edge_case` each of its edge cases
/// that no row names; none when the config leaves `verification_coverage` off.
///
/// A skip row or a test row covers what it names; a row of the form the mode
/// does not read covers nothing. The finding sits at the FR's `statuses` line
/// and names the target when the project holds twins.
Iterable<Finding> checkUnprovenEdgeCases(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final mode = context.matrixMode;
  if (mode == MatrixMode.off) return;
  final read = recordDocOf(context, doc);
  final statusField = read == null ? null : recordStatusFieldOf(read.type);
  if (read == null || statusField == null) return;
  final items = recordItemsOf(read.feature, context.index.childrenOf);
  final covered = {
    for (final row in doc.matrixLines.whereType<MatrixRow>())
      if (!isRefusedFormRow(context, doc, row)) row.label,
  };
  final lines = _lastStatusLines(read.lines, statusField.id);
  for (final MapEntry(key: name, value: line) in lines.entries) {
    final fr = items[name];
    if (fr == null || !_needsRows(context, doc, fr)) continue;
    switch (mode.readsForm) {
      case RowForm.perFr:
        if (!covered.contains(name)) {
          yield _missingRow(context, doc, name, null, line);
        }
      case RowForm.perEdgeCase:
        for (final edgeCase in edgeCaseBlocksOf(context, fr).keys) {
          if (covered.contains('$name#$edgeCase')) continue;
          yield _missingRow(context, doc, name, edgeCase, line);
        }
    }
  }
}

/// Returns the file line of each item's last `statuses` line, as the record
/// entries read a repeated item.
Map<String, int> _lastStatusLines(DocLines lines, String statusFieldId) => {
  for (final status in statusLinesOf(lines, statusFieldId))
    ?status.item: status.line,
};

/// Whether [fr] is `implemented` in [record]'s target and verified by test.
bool _needsRows(CheckContext context, IndexedDoc record, IndexedDoc fr) =>
    isVerifiedByTest(fr) &&
    context.index.itemStatus(fr, codeTarget: record.target) ==
        RecordStatus.implemented;

Finding _missingRow(
  CheckContext context,
  IndexedDoc record,
  String item,
  String? edgeCase,
  int line,
) {
  final target = shownTargetName(context, record.target);
  final inTarget = target == null ? '' : ' in target $target';
  final named = edgeCase == null ? item : '$item#$edgeCase';
  return context.finding(
    record,
    FindingKind.matrixRowMissing,
    line: line,
    message: '$named is implemented$inTarget and no matrix row names it',
    keys: {'item': item, 'edgeCase': ?edgeCase, 'target': ?target},
  );
}

/// Returns the test file paths of each item's `tests` lines in [record].
Map<String, Set<String>> _testPathsOf(IndexedDoc record, MergedField? field) {
  final paths = <String, Set<String>>{};
  if (field == null) return paths;
  for (final RecordTestLine(:item, :path) in recordTestLinesOf(record, field)) {
    paths.putIfAbsent(item, () => {}).add(path);
  }
  return paths;
}

/// Returns the test row literals of the project that the test file at [path]
/// under [target]'s code root holds, given its [text].
///
/// A run searches each file once, for every row's literals at once: a search
/// per literal reads each file once per literal.
Set<String> _rowLiteralsIn(
  CheckContext context,
  CodeTarget target,
  String path,
  String text,
) => (_rowLiteralsByContext[context] ??= _RowLiterals(
  context,
)).foundIn(target, path, text);

/// The row literals each run has found, held for the run's lifetime.
final Expando<_RowLiterals> _rowLiteralsByContext = Expando(
  'row literals found',
);

/// The test row literals of every record of one run, and those each test file
/// holds.
final class _RowLiterals {
  new(CheckContext context)
    : _scan = LiteralScan({
        for (final doc in context.index.docs)
          for (final row in doc.matrixLines.whereType<TestRow>())
            ...row.literals,
      });

  final LiteralScan _scan;
  final Map<(CodeTarget, String), Set<String>> _found = {};

  Set<String> foundIn(CodeTarget target, String path, String text) =>
      _found.putIfAbsent((target, path), () => _scan.foundIn(text));
}

/// One record's matrix lines read in file order.
final class _MatrixWalk {
  new(this._context, this._record, this._items, this._testPaths)
    : _target = _context.targets
          .where((target) => target.name == _record.target)
          .firstOrNull;

  final CheckContext _context;
  final IndexedDoc _record;
  final Map<String, IndexedDoc> _items;
  final Map<String, Set<String>> _testPaths;
  final CodeTarget? _target;

  final Map<String, Map<String, String>> _edgeCases = {};
  final Map<String, List<MatrixRow>> _earlierRows = {};

  Iterable<Finding> findings() sync* {
    for (final line in _record.matrixLines) {
      switch (line) {
        case MalformedRow(:final text):
          yield _malformed(line.line, text);
        case final MatrixRow row when isRefusedFormRow(_context, _record, row):
          yield _refusedForm(row);
        case final MatrixRow row when !_isRecordRules(row):
          yield* _resolved(row);
          yield* _related(row);
        case MatrixRow():
          break;
      }
    }
  }

  Finding _malformed(int line, String text) => _finding(
    FindingKind.matrixRowMalformed,
    line,
    '$text is no matrix row; write ${_shapeOfReadForm()}',
    {'row': text},
  );

  String _shapeOfReadForm() => switch (_context.matrixMode.readsForm) {
    RowForm.perFr =>
      '"- <item>: `<test name>`" or "- <item> skipped: <reason>"',
    RowForm.perEdgeCase =>
      '"- <item> <edge case>: `<test name>`" or '
          '"- <item> <edge case> skipped: <reason>"',
  };

  // Only the Owner's `migrate` clears a per-edge-case row under off or `fr`;
  // the sync rewrites a per-FR row under `edge_case`.
  Finding _refusedForm(MatrixRow row) {
    final readsFr = _context.matrixMode.readsForm == RowForm.perFr;
    return _context.finding(
      _record,
      FindingKind.matrixRowMalformed,
      line: row.line,
      message: readsFr
          ? 'per-edge-case row; run specstone migrate to fold it into one '
                'row per FR'
          : 'per-FR row under verification_coverage edge_case; write one row '
                'per edge case',
      waitsFor: refusedFormRowWait(modeReadsFr: readsFr),
      keys: {'row': _lineOf(row)},
    );
  }

  String _lineOf(MatrixRow row) => switch (row.fingerprint) {
    final fingerprint? => '- ${row.written} $fingerprint',
    null => '- ${row.written}',
  };

  // The record entry rule reports a row of an item outside the feature, and
  // of a skipped FR, alone.
  bool _isRecordRules(MatrixRow row) {
    final item = _items[row.item];
    if (item == null) return true;
    return item.docTypeId == frType && isSkippedIn(_context, _record, item);
  }

  Iterable<Finding> _resolved(MatrixRow row) sync* {
    final item = _items[row.item]!;
    if (item.docTypeId != frType) {
      yield _finding(
        FindingKind.matrixRowUnresolved,
        row.line,
        '${row.item} is a story; a row names an FR',
        {'item': row.item},
      );
      return;
    }
    final edgeCase = row.edgeCase;
    if (edgeCase != null && !_edgeCasesOf(item).containsKey(edgeCase)) {
      yield _finding(
        FindingKind.matrixRowUnresolved,
        row.line,
        '${row.item} has no edge case $edgeCase',
        {'item': row.item, 'edgeCase': edgeCase},
      );
    }
    if (row is TestRow) yield* _literalOf(row, item);
  }

  Map<String, String> _edgeCasesOf(IndexedDoc fr) =>
      _edgeCases.putIfAbsent(fr.docPath, () => edgeCaseBlocksOf(_context, fr));

  Iterable<Finding> _literalOf(TestRow row, IndexedDoc fr) sync* {
    final target = _target;
    final status = _context.index.itemStatus(fr, codeTarget: _record.target);
    if (target == null || !status.isBuilt) return;
    final paths = _testPaths[row.item] ?? const <String>{};
    if (paths.isEmpty) {
      yield _unresolvedLiteral(
        row,
        row.firstLiteral,
        '${row.item} has no tests line to hold ${row.firstLiteral}',
      );
      return;
    }
    final found = <Set<String>>[];
    for (final path in paths) {
      final verdict = _context.exactPaths.resolve(
        _context.codeRootOf(target),
        path,
      );
      if (verdict.kind == CodePathKind.parentSegment) {
        yield* _outsideLiterals(row, path, verdict);
        return;
      }
      // Any other path naming no file is the `tests` line rule's.
      if (verdict.kind != CodePathKind.file) continue;
      final readPath = readPathOf(path, verdict.diskPath!);
      final text = testFileTextOf(_context, target, readPath);
      // An unreadable file is warned about once; its names are not checked.
      if (text == null) return;
      found.add(_rowLiteralsIn(_context, target, readPath, text));
    }
    for (final literal in row.literals) {
      if (found.any((literals) => literals.contains(literal))) continue;
      yield _unresolvedLiteral(
        row,
        literal,
        '$literal occurs in no test file of ${row.item}',
      );
    }
  }

  Iterable<Finding> _outsideLiterals(
    TestRow row,
    String path,
    CodePathVerdict verdict,
  ) sync* {
    final reason = codePathMessageOf(CodePathField.implements, path, verdict);
    for (final literal in row.literals) {
      yield _unresolvedLiteral(row, literal, '$literal is not read: $reason');
    }
  }

  Finding _unresolvedLiteral(TestRow row, String literal, String message) =>
      _finding(FindingKind.matrixTestUnresolved, row.line, message, {
        'item': row.item,
        'test': literal,
      });

  Iterable<Finding> _related(MatrixRow row) sync* {
    final earlier = _earlierRows.putIfAbsent(row.label, () => []);
    if (row is TestRow) {
      // A per-FR row is the one test row of its FR, whatever its literals.
      final repeated = earlier
          .whereType<TestRow>()
          .where(
            (other) =>
                row.form == RowForm.perFr ||
                other.firstLiteral == row.firstLiteral,
          )
          .firstOrNull;
      if (repeated != null) {
        yield _finding(
          FindingKind.matrixRowRepeated,
          row.line,
          row.form == RowForm.perFr
              ? '${row.label} has a second test row; line ${repeated.line} '
                    'holds the first, keep one row'
              : '${row.label} names ${row.firstLiteral} again; line '
                    '${repeated.line} holds it, keep one row',
          {'item': row.item, 'edgeCase': ?row.edgeCase, 'first': repeated.line},
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
        {'item': row.item, 'edgeCase': ?row.edgeCase, 'first': beside.line},
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
