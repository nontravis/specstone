import 'package:specstone_core/src/consistency_check/fr_trace_rows.dart';
import 'package:specstone_core/src/consistency_check/models/fr_trace_row.dart';
import 'package:specstone_core/src/doc_model/models/body_line.dart';
import 'package:test/test.dart';

BodyLine _line(String text, int line, {bool fenced = false}) =>
    BodyLine(text: text, line: line, fenced: fenced);

void main() {
  test('the reader keeps the rows check tracks', () {
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
      const FrTraceRow(cell: 'us01/fr01', line: 4),
      const FrTraceRow(cell: 'us01/fr03', line: 9),
      const FrTraceRow(cell: ' x ', line: 10),
    ]);
  });
}
