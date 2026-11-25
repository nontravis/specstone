import 'package:specstone_core/src/doc_model/table_cell.dart';
import 'package:test/test.dart';

void main() {
  group('escapeTableCellPipes', () {
    const rows = [
      ('a bare pipe is escaped', 'a|b', r'a\|b'),
      ('an escaped pipe stays', r'a\|b', r'a\|b'),
      ('a pipe after an escaped backslash is escaped', r'a\\|b', r'a\\\|b'),
      ('a pipe after three backslashes stays', r'a\\\|b', r'a\\\|b'),
      ('each bare pipe of a text is escaped', 'a|b|c', r'a\|b\|c'),
    ];
    for (final (name, text, escaped) in rows) {
      test(name, () => expect(escapeTableCellPipes(text), escaped));
    }
  });

  group('tableCellPipe', () {
    const rows = [
      ('a bare pipe splits', 'a|b', ['a', 'b']),
      ('an escaped pipe splits none', r'a\|b', [r'a\|b']),
      ('a pipe after an escaped backslash splits', r'a\\|b', [r'a\\', 'b']),
      ('a pipe after three backslashes splits none', r'a\\\|b', [r'a\\\|b']),
    ];
    for (final (name, text, cells) in rows) {
      test(name, () => expect(text.split(tableCellPipe), cells));
    }
  });
}
