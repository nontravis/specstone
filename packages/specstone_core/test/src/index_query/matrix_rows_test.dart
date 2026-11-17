import 'package:specstone_core/src/index_query/matrix_rows.dart';
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
        literal: 'queues a toast',
        fingerprint: '3f9a1c0b7e2d',
        line: 10,
      ),
    );
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
    });

    test('tells two rows of one literal apart by the form written', () {
      final wide = parseMatrixLine('- show_toast E01: ``queues``', 10);
      final narrow = parseMatrixLine('- show_toast E01: `queues`', 10);

      expect(wide, isNot(narrow));
      expect(wide.hashCode, isNot(narrow.hashCode));
    });
  });
}
