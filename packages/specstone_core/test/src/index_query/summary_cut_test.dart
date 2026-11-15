// The test literals hold whole table lines as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/summary_cut.dart';
import 'package:test/test.dart';

const _head = '| Date | Run |\n|---|---|\n';

void main() {
  test('cuts a lead line and a three-row table to its first row', () {
    final cut = cutToRows(
      'Newest first.\n\n$_head| a | 1 |\n| b | 2 |\n| c | 3 |\n',
      1,
    );

    expect(cut.body, 'Newest first.\n\n$_head| a | 1 |');
    expect(cut.lineCount, 5);
  });

  test('cuts at the first table and drops a second table', () {
    final cut = cutToRows(
      'Lead.\n\n$_head| a | 1 |\n| b | 2 |\n\nMore.\n\n$_head| x | 9 |\n',
      1,
    );

    expect(cut.body, 'Lead.\n\n$_head| a | 1 |');
    expect(cut.lineCount, 5);
  });

  test('keeps prose text whole when the section holds no table', () {
    final cut = cutToRows('Run one met.\nRun two missed.\n', 1);

    expect(cut.body, 'Run one met.\nRun two missed.\n');
    expect(cut.lineCount, 2);
  });

  test(
    'prints the lead and the header rows when the table has no body row',
    () {
      final cut = cutToRows('Newest first.\n\n$_head', 1);

      expect(cut.body, 'Newest first.\n\n| Date | Run |\n|---|---|');
      expect(cut.lineCount, 4);
    },
  );

  test('prints every row of a table shorter than the count', () {
    final cut = cutToRows('$_head| a | 1 |\n| b | 2 |\n\nAfter.\n', 5);

    expect(cut.body, '$_head| a | 1 |\n| b | 2 |');
    expect(cut.lineCount, 4);
  });

  test('reads a pipe table in fenced code as no table', () {
    const body = 'Lead.\n\n```\n$_head| a | 1 |\n| b | 2 |\n```\n';

    final cut = cutToRows(body, 1);

    expect(cut.body, body);
    expect(cut.lineCount, 8);
  });

  test('finds a table that follows a fenced block', () {
    final cut = cutToRows(
      '```\n| not | table |\n```\n\n$_head| a | 1 |\n| b | 2 |\n',
      1,
    );

    expect(cut.body, '```\n| not | table |\n```\n\n$_head| a | 1 |');
    expect(cut.lineCount, 7);
  });

  test('skips a table inside an HTML comment before the real table', () {
    final cut = cutToRows(
      'Lead.\n<!--\n| Old | Run |\n|---|---|\n| x | 0 |\n-->\n\n$_head| a | 1 |\n| b | 2 |\n',
      1,
    );

    expect(
      cut.body,
      'Lead.\n<!--\n| Old | Run |\n|---|---|\n| x | 0 |\n-->\n\n$_head| a | 1 |',
    );
    expect(cut.lineCount, 10);
  });

  test('cuts a table in a blockquote', () {
    final cut = cutToRows(
      'Lead.\n\n> | Date | Run |\n> |---|---|\n> | a | 1 |\n> | b | 2 |\n',
      1,
    );

    expect(cut.body, 'Lead.\n\n> | Date | Run |\n> |---|---|\n> | a | 1 |');
    expect(cut.lineCount, 5);
  });
}
