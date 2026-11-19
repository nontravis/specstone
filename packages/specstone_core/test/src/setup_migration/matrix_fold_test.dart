import 'package:specstone_core/src/setup_migration/matrix_fold.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/record_doc_type.dart';

final MergedDocType _recordType = recordDocType();

const _frNames = {'check_rows', 'show_toast'};

const _fingerprint = '3f9a1c0b7e2d';
const _otherFingerprint = '0123456789ab';

/// A record text whose matrix section holds [rows].
String _record(List<String> rows) =>
    '---\n'
    'statuses:\n'
    '  - check_rows:implemented\n'
    '---\n\n'
    '# Matrix implementation\n\n'
    '## Verification matrix\n\n'
    '${rows.join('\n')}\n';

/// The folded text of a record of [rows] under [_frNames], or null.
String? _folded(List<String> rows) =>
    foldMatrixRows(_record(rows), _recordType, _frNames)?.text;

void main() {
  test("folds one FR's test rows into one per-FR row at its first row", () {
    final folded = foldMatrixRows(
      _record([
        '- other: `keeps`',
        '- check_rows E01: `reads a row`',
        '- show_toast: `queues a toast`',
        '- check_rows E02: `reads a skip row`',
      ]),
      _recordType,
      _frNames,
    );

    expect(
      folded?.text,
      _record([
        '- other: `keeps`',
        '- check_rows: `reads a row`, `reads a skip row`',
        '- show_toast: `queues a toast`',
      ]),
    );
    expect(folded?.rowsBefore, 2);
    expect(folded?.rowsAfter, 1);
  });

  test('keeps literals once in the order they first appear', () {
    expect(
      _folded([
        '- check_rows E01: `b`',
        '- check_rows E02: `a`',
        '- check_rows E03: `b`',
        '- check_rows E04: `c`',
      ]),
      _record(['- check_rows: `b`, `a`, `c`']),
    );
  });

  test('keeps the span of a literal with a backtick or an edge space', () {
    expect(
      _folded([
        '- check_rows E01: `` a `x` ``',
        '- check_rows E02: `  padded  `',
        '- check_rows E03: `plain`',
      ]),
      _record(['- check_rows: `` a `x` ``, `  padded  `, `plain`']),
    );
  });

  test('folds skip rows into one skip row joining distinct reasons', () {
    expect(
      _folded([
        '- check_rows E01 skipped: needs a symlink',
        '- check_rows E02 skipped: needs a clock',
        '- check_rows E03 skipped: needs a symlink',
      ]),
      _record(['- check_rows skipped: needs a symlink; needs a clock']),
    );
  });

  test('keeps only the test row when test and skip rows mix', () {
    const skip = '- check_rows E02 skipped: needs a symlink';

    expect(
      _folded(['- check_rows E01: `reads a row`', skip]),
      _record(['- check_rows: `reads a row`']),
    );
    expect(
      _folded(['- check_rows: `reads a row`', skip]),
      _record(['- check_rows: `reads a row`']),
    );
  });

  test(
    'appends edge case literals to a per-FR test row and drops its fingerprint',
    () {
      expect(
        _folded([
          '- check_rows: `reads a row` $_fingerprint',
          '- check_rows E01: `reads a skip row`',
        ]),
        _record(['- check_rows: `reads a row`, `reads a skip row`']),
      );
    },
  );

  test('replaces a per-FR skip row with the folded test row', () {
    expect(
      _folded([
        '- check_rows skipped: needs a symlink',
        '- check_rows E01: `reads a row`',
        '- check_rows E02: `reads a skip row`',
      ]),
      _record(['- check_rows: `reads a row`, `reads a skip row`']),
    );
  });

  test('folds a row naming an edge case the FR lacks', () {
    expect(
      _folded([
        '- check_rows E01: `reads a row`',
        '- check_rows E99: `reads an unknown edge case`',
      ]),
      _record(['- check_rows: `reads a row`, `reads an unknown edge case`']),
    );
  });

  test('keeps rows of other items and malformed lines in place', () {
    final rows = [
      '- other E01: `repeats`',
      'not a row',
      '- check_rows E01: `reads a row`',
      '- other E01: `repeats`',
      '- other skipped: needs a clock',
      '- check_rows E02: `reads a skip row` $_fingerprint',
    ];

    expect(
      _folded(rows),
      _record([
        '- other E01: `repeats`',
        'not a row',
        '- check_rows: `reads a row`, `reads a skip row`',
        '- other E01: `repeats`',
        '- other skipped: needs a clock',
      ]),
    );
  });

  test('drops every fingerprint when it folds', () {
    expect(
      _folded([
        '- check_rows E01: `reads a row` $_fingerprint',
        '- check_rows E02 skipped: needs a symlink $_otherFingerprint',
        '- show_toast E01 skipped: needs a clock $_fingerprint',
        '- show_toast E02 skipped: needs a symlink $_otherFingerprint',
      ]),
      _record([
        '- check_rows: `reads a row`',
        '- show_toast skipped: needs a clock; needs a symlink',
      ]),
    );
  });

  test('returns null on a record with nothing to fold', () {
    expect(_folded(['- check_rows: `reads a row`']), isNull);
    expect(_folded(['- other E01: `reads a row`']), isNull);
    expect(_folded(['- check_rows skipped: needs a symlink']), isNull);
    expect(_folded(const []), isNull);
    expect(
      foldMatrixRows(
        '# Matrix implementation\n\n- check_rows E01: `reads a row`\n',
        _recordType,
        _frNames,
      ),
      isNull,
    );
  });
}
