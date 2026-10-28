import 'package:specstone_core/src/consistency_check/section_counts.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
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
  };
  const headers = {
    'plain header': header,
    'header with a pair': '## Emoji \u{1F600}',
    'header ending in a high surrogate': '## Half \uD83D',
    'header with a line break': '## Odd\nheader',
  };

  for (final MapEntry(key: headerName, value: headerLine) in headers.entries) {
    for (final MapEntry(key: bodyName, value: body) in bodies.entries) {
      test('$headerName, $bodyName: counts what split and runes count', () {
        final section = IndexedSection(
          key: 'statement',
          headerLine: headerLine,
          body: body,
        );
        final counts = sectionCountsOf(section);
        expect(counts.lines, section.text.split('\n').length);
        expect(counts.chars, section.text.runes.length);
      });
    }
  }
}
