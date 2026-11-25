import 'package:specstone_core/src/index_query/matrix_rows.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/templates/models/matrix_mode.dart';
import 'package:test/test.dart';

void main() {
  test('a test row reads the same with or without trailing whitespace', () {
    expect(
      parseMatrixLine('- show_toast E01: `queues a toast` ', 10),
      parseMatrixLine('- show_toast E01: `queues a toast`', 10),
    );
    expect(
      parseMatrixLine('- show_toast E01: `queues a toast` 3f9a1c0b7e2d  ', 10),
      const TestRow(
        item: 'show_toast',
        edgeCase: 'E01',
        literals: ['queues a toast'],
        fingerprint: '3f9a1c0b7e2d',
        line: 10,
      ),
    );
  });

  group('a per-FR row', () {
    test('reads a per-FR test row with two literals', () {
      final row = parseMatrixLine(
        '- show_toast: `queues a toast`, `drops a toast`',
        7,
      ) as TestRow;

      expect(row.form, RowForm.perFr);
      expect(row.item, 'show_toast');
      expect(row.edgeCase, isNull);
      expect(row.literals, ['queues a toast', 'drops a toast']);
      expect(row.firstLiteral, 'queues a toast');
      expect(row.fingerprint, isNull);
      expect(row.label, 'show_toast');
      expect(row.written, 'show_toast: `queues a toast`, `drops a toast`');
      expect(row.line, 7);

      final stamped = parseMatrixLine(
        '- show_toast: `queues a toast`, `drops a toast` 3f9a1c0b7e2d',
        7,
      ) as TestRow;

      expect(stamped.form, RowForm.perFr);
      expect(stamped.literals, ['queues a toast', 'drops a toast']);
      expect(stamped.fingerprint, '3f9a1c0b7e2d');
      expect(stamped.label, 'show_toast');
      expect(stamped.written, 'show_toast: `queues a toast`, `drops a toast`');
    });

    test('reads a per-FR skip row and its fingerprint', () {
      final row = parseMatrixLine(
        '- show_toast skipped: needs a clock 3f9a1c0b7e2d',
        7,
      ) as SkipRow;
      final unstamped = parseMatrixLine(
        '- show_toast skipped: needs a clock on CI',
        8,
      ) as SkipRow;

      expect(row.form, RowForm.perFr);
      expect(row.item, 'show_toast');
      expect(row.edgeCase, isNull);
      expect(row.reason, 'needs a clock');
      expect(row.fingerprint, '3f9a1c0b7e2d');
      expect(row.label, 'show_toast');
      expect(row.written, 'show_toast skipped: needs a clock');
      expect(unstamped.reason, 'needs a clock on CI');
      expect(unstamped.fingerprint, isNull);
    });

    test('keeps a comma inside one code span as one literal', () {
      final row =
          parseMatrixLine('- show_toast: `queues, then drops`', 7) as TestRow;

      expect(row.literals, ['queues, then drops']);
      expect(row.written, 'show_toast: `queues, then drops`');
    });

    test('reads a literal written twice as no row', () {
      expect(
        parseMatrixLine('- show_toast: `queues`, `queues`', 7),
        isA<MalformedRow>(),
      );
    });

    test('reads two spans joined without a space as no row', () {
      expect(
        parseMatrixLine('- show_toast: `queues`,`drops`', 7),
        isA<MalformedRow>(),
      );
    });

    test('reads a dangling separator before a fingerprint as no row', () {
      for (final text in [
        '- show_toast: `queues`,  3f9a1c0b7e2d',
        '- show_toast E01: `queues`,  3f9a1c0b7e2d',
        '- show_toast: `queues`, ',
      ]) {
        expect(parseMatrixLine(text, 7), isA<MalformedRow>(), reason: text);
      }
    });

    test('reads an upper-case fingerprint as no row', () {
      expect(
        parseMatrixLine('- show_toast: `queues` 3F9A1C0B7E2D', 7),
        isA<MalformedRow>(),
      );
    });

    test('reads a double-backtick span as CommonMark does', () {
      final row =
          parseMatrixLine('- show_toast: `` a `x` ``, `drops`', 7) as TestRow;

      expect(row.literals, ['a `x`', 'drops']);
      expect(row.written, 'show_toast: `` a `x` ``, `drops`');
    });

    test('tells two rows of other literals apart', () {
      final one = parseMatrixLine('- show_toast: `queues`, `drops`', 7);
      final other = parseMatrixLine('- show_toast: `queues`, `pins`', 7);

      expect(one, isNot(other));
      expect(one.hashCode, isNot(other.hashCode));
    });
  });

  test('a mode reads the per-FR form unless it is the edge case mode', () {
    expect(MatrixMode.off.readsForm, RowForm.perFr);
    expect(MatrixMode.fr.readsForm, RowForm.perFr);
    expect(MatrixMode.edgeCase.readsForm, RowForm.perEdgeCase);
  });

  group('a per-edge-case row', () {
    test('still reads a per-edge-case row', () {
      final test = parseMatrixLine(
        '- show_toast E01: `queues a toast` 3f9a1c0b7e2d',
        7,
      ) as TestRow;
      final skip = parseMatrixLine(
        '- show_toast E02 skipped: needs a clock',
        8,
      ) as SkipRow;

      expect(test.form, RowForm.perEdgeCase);
      expect(test.item, 'show_toast');
      expect(test.edgeCase, 'E01');
      expect(test.literals, ['queues a toast']);
      expect(test.firstLiteral, 'queues a toast');
      expect(test.fingerprint, '3f9a1c0b7e2d');
      expect(test.label, 'show_toast#E01');
      expect(test.written, 'show_toast E01: `queues a toast`');
      expect(skip.form, RowForm.perEdgeCase);
      expect(skip.edgeCase, 'E02');
      expect(skip.reason, 'needs a clock');
      expect(skip.fingerprint, isNull);
      expect(skip.label, 'show_toast#E02');
      expect(skip.written, 'show_toast E02 skipped: needs a clock');
    });

    test('reads two literals after an edge case as no row', () {
      expect(
        parseMatrixLine('- show_toast E01: `queues`, `drops`', 7),
        isA<MalformedRow>(),
      );
    });
  });

  group('the written form of a row', () {
    for (final (text, written) in [
      (
        '- show_toast E01: `queues a toast` 3f9a1c0b7e2d  ',
        'show_toast E01: `queues a toast`',
      ),
      ('- show_toast E01: `` a `x` ``', 'show_toast E01: `` a `x` ``'),
      ('- show_toast E01: `  padded  `', 'show_toast E01: `  padded  `'),
      (
        '- show_toast E02 skipped: needs a clock   3f9a1c0b7e2d',
        'show_toast E02 skipped: needs a clock',
      ),
      (
        '- show_toast E02 skipped: needs  a clock',
        'show_toast E02 skipped: needs  a clock',
      ),
    ]) {
      test('keeps ${written.trim()} as the file writes it', () {
        expect((parseMatrixLine(text, 10) as MatrixRow).written, written);
      });
    }

    test('goes through the index JSON', () {
      final row = parseMatrixLine(
        '- show_toast E01: `` a `x` `` 3f9a1c0b7e2d',
        10,
      );

      final read = MatrixLine.fromJson(row.toJson());

      expect(read, row);
      expect((read as MatrixRow).written, 'show_toast E01: `` a `x` ``');

      for (final text in [
        '- show_toast: `queues`, `drops` 3f9a1c0b7e2d',
        '- show_toast skipped: needs a clock 3f9a1c0b7e2d',
      ]) {
        final perFr = parseMatrixLine(text, 7);

        expect(MatrixLine.fromJson(perFr.toJson()), perFr, reason: text);
      }
    });

    test('tells two rows of one literal apart by the form written', () {
      final wide = parseMatrixLine('- show_toast E01: ``queues``', 10);
      final narrow = parseMatrixLine('- show_toast E01: `queues`', 10);

      expect(wide, isNot(narrow));
      expect(wide.hashCode, isNot(narrow.hashCode));
    });
  });
}
