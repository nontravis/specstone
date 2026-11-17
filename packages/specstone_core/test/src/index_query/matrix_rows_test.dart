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
}
