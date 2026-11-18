import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/section_counts.dart';
import 'package:test/test.dart';

void main() {
  const header = '## Statement';
  const bodies = {
    'empty body': '',
    'one line, no trailing newline': 'one line',
    'one line, trailing newline': 'one line\n',
    'two trailing newlines': 'one line\n\n',
    'only a newline': '\n',
    'only newlines': '\n\n\n',
    'blank line inside': 'a\n\nb\n',
    'CRLF kept in the body': 'a\r\nb\r\n',
    'lone CR': 'a\rb',
    'surrogate pair': 'emoji \u{1F600} end\n',
    'pairs side by side': '\u{1F600}\u{1F680}',
    'pair at the end': 'end \u{1F600}',
    'pair at the start': '\u{1F600} start\n',
    'lone high surrogate': 'a\uD83Db\n',
    'lone low surrogate': 'a\uDE00b\n',
    'high then high then low': '\uD83D😀',
    'low then high': '\uDE00\uD83D',
    'multibyte text': 'ภาษาไทย ünï\ncódé\n',
    'blank line first': '\n\nx\n',
  };
  const headers = {
    'plain header': header,
    'header with a pair': '## Emoji \u{1F600}',
    'header ending in a high surrogate': '## Half \uD83D',
    'header with a line break': '## Odd\nheader',
  };

  for (final MapEntry(key: headerName, value: headerLine) in headers.entries) {
    for (final MapEntry(key: bodyName, value: body) in bodies.entries) {
      test('$headerName, $bodyName: counts the body by split and runes', () {
        final section = IndexedSection(
          key: 'statement',
          headerLine: headerLine,
          body: body,
        );
        final counts = sectionCountsOf(section);
        final text = body.endsWith('\n')
            ? body.substring(0, body.length - 1)
            : body;
        expect(counts.lines, nonBlankLinesOf(text.split('\n')));
        expect(counts.chars, text.runes.length);
      });
    }
  }

  test('a blank line and a 165-character paragraph store line count 1 and '
      'code-point count 166', () {
    final text = '# Title\n\n## Statement\n\n${'x' * 165}\n';
    final counts = DocLines.of(text).sectionCounts.single;
    expect(counts, (lines: 1, chars: 166));
  });
}

/// The non-blank lines of [lines], the expected section count.
int nonBlankLinesOf(List<String> lines) =>
    lines.where((line) => line.trim().isNotEmpty).length;
