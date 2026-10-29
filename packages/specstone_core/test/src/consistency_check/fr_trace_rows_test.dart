import 'package:specstone_core/src/consistency_check/fr_trace_rows.dart';
import 'package:test/test.dart';

TraceBodyLine _line(String text, int line, {bool fenced = false}) =>
    (text: text, line: line, fenced: fenced);

void main() {
  test('f06/us01/fr06: the reader keeps the rows check tracks', () {
    final rows = readFrTraceRows([
      _line('', 1),
      _line('| FR id | Method |', 2),
      _line('|:-----:|--------|', 3),
      _line('| `us01/fr01` | CLI |', 4),
      _line('```', 5, fenced: true),
      _line('| us01/fr02 | CLI |', 6, fenced: true),
      _line('```', 7, fenced: true),
      _line('prose | not a row', 8),
      _line('|  us01/fr03  | CLI |', 9),
      _line('| ` x ` |', 10),
    ]);

    expect(rows, [
      (cell: 'us01/fr01', line: 4),
      (cell: 'us01/fr03', line: 9),
      (cell: ' x ', line: 10),
    ]);
  });
}
