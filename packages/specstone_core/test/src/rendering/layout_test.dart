import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/rendering/layout.dart';
import 'package:test/test.dart';

const _slug = 'rendering/format_docs/normalize_layout_whitespace';

void main() {
  final laidOut = <({String input, bool underHeading, Set<String> kinds})>[];

  void check(
    String name,
    String input,
    String expected, {
    bool underHeading = false,
    Set<String> blockKinds = const {},
  }) {
    laidOut.add((input: input, underHeading: underHeading, kinds: blockKinds));
    test('$_slug $name', () {
      expect(
        layOutText(input, underHeading: underHeading, blockKinds: blockKinds),
        expected,
      );
    });
  }

  group('tables', () {
    check(
      'E01: a padded table is compacted',
      '| Field     | Type   |\n'
          '|-----------|--------|\n'
          '| a         | b      |\n',
      '| Field | Type |\n|---|---|\n| a | b |\n',
    );
    check(
      'E02: a delimiter row keeps its alignment marks',
      '| a | b | c |\n|:-----|-----:|:----:|\n',
      '| a | b | c |\n|:---|---:|:---:|\n',
    );
    check(
      r'E03: an escaped \| stays in its cell',
      '| a   | b\\|c   |\n|---|---|\n',
      '| a | b\\|c |\n|---|---|\n',
    );
    check(
      'a row without outer pipes keeps none',
      'a   |   b\n---|---\n',
      'a | b\n---|---\n',
    );
    check(
      'an escaped pipe inside inline code stays in its cell',
      '| `a\\|b`   | c |\n|---|---|\n',
      '| `a\\|b` | c |\n|---|---|\n',
    );
    check(
      'a table row keeps its indent',
      '  | a   | b |\n  |---|---|\n',
      '  | a | b |\n  |---|---|\n',
    );
  });

  group('trailing whitespace', () {
    check(
      'E04: 2 or more spaces before a paragraph line become exactly 2',
      'first line    \nsecond line\n',
      'first line  \nsecond line\n',
    );
    check('E04: 1 space is dropped', 'one \nnext\n', 'one\nnext\n');
    check('E04: a tab is dropped', 'tab\t\nnext\n', 'tab\nnext\n');
    check(
      'E04: spaces before a blank line are dropped',
      'text   \n\nafter\n',
      'text\n\nafter\n',
    );
    check(
      'E04: spaces before a heading are dropped',
      'text  \n# H\n\nbody\n',
      'text\n# H\n\nbody\n',
    );
    check(
      'E04: spaces before a table row are dropped',
      'text  \n| a | b |\n|---|---|\n',
      'text\n| a | b |\n|---|---|\n',
    );
    check('E04: spaces at the end of the text are dropped', 'last   ', 'last');
    check(
      'spaces before a list item are dropped',
      'a  \n- item\n',
      'a\n- item\n',
    );
    check(
      'spaces before a fence line are dropped',
      'a  \n```\ncode\n```\n',
      'a\n```\ncode\n```\n',
    );
    check('a blank line of spaces is emptied', 'a\n   \nb\n', 'a\n\nb\n');
  });

  group('heading gap', () {
    check(
      'E05: text under a title gets one blank line',
      '# Title\ntext\n',
      '# Title\n\ntext\n',
    );
    check(
      'E05: text under a ## header gets one blank line',
      '## Header\ntext\n',
      '## Header\n\ntext\n',
    );
    check(
      'E05: text under a ### heading gets one blank line',
      '### Heading\ntext\n',
      '### Heading\n\ntext\n',
    );
    check(
      'E05: 2 or more blank lines become one',
      '## H\n\n\n\ntext',
      '## H\n\ntext',
    );
    check(
      'a heading followed by a heading gets one blank line',
      '# A\n## B\ntext\n',
      '# A\n\n## B\n\ntext\n',
    );
    check('a heading at the end gets none', '# A', '# A');
    check('a heading and a final line break gets none', '# A\n', '# A\n');
    check('7 hashes are no heading', '####### x\ntext\n', '####### x\ntext\n');
    check('# without a space is no heading', '#tag\ntext\n', '#tag\ntext\n');
  });

  group('underHeading', () {
    check('0 leading blank lines', 'text', '\ntext', underHeading: true);
    check('1 leading blank line', '\ntext', '\ntext', underHeading: true);
    check('3 leading blank lines', '\n\n\ntext', '\ntext', underHeading: true);
    check('empty text', '', '', underHeading: true);
    check('blank-only text', '\n\n', '', underHeading: true);
  });

  group('protected lines', () {
    const body = '| a    | b |\n|--|--|\n# not   \ntrail   \n';
    check(
      'E06: a backtick fence is unchanged',
      '```\n$body```\n',
      '```\n$body```\n',
    );
    check(
      'E06: a tilde fence is unchanged',
      '~~~\n$body~~~\n',
      '~~~\n$body~~~\n',
    );
    check(
      'a closed block is unchanged, one blank line under its heading',
      '# H\n${generatedOpenMarker('scenario_copy')}\n$body'
          '$generatedEndMarker\n',
      '# H\n\n${generatedOpenMarker('scenario_copy')}\n$body'
          '$generatedEndMarker\n',
      blockKinds: {'scenario_copy'},
    );
    check(
      'a block kind not passed is not protected',
      '${generatedOpenMarker('scenario_copy')}\ntrail   \n'
          '$generatedEndMarker\n',
      '${generatedOpenMarker('scenario_copy')}\ntrail  \n'
          '$generatedEndMarker\n',
    );
  });

  group('only spaces and tabs change', () {
    check('a line ending in NBSP stays', 'a \nb\n', 'a \nb\n');
    check('a line ending in U+3000 stays', 'a　\nb\n', 'a　\nb\n');
    check(
      'spaces after a trailing NBSP go, the NBSP stays',
      'a   \n\nb\n',
      'a \n\nb\n',
    );
    check(
      'an NBSP-only line is not blank under a heading',
      '# H\n \n\ntext\n',
      '# H\n\n \n\ntext\n',
    );
    check(
      'a table cell keeps its edge NBSP',
      '|  a | b　 |\n|---|---|\n',
      '|  a | b　 |\n|---|---|\n',
    );
    check(
      'an NBSP gap after a list marker is no list item',
      'a  \n- b\n',
      'a  \n- b\n',
    );
  });

  group('quote lines', () {
    check(
      'a quote after a plain line ends its paragraph',
      'text  \n> quote\n',
      'text\n> quote\n',
    );
    check(
      'a plain line before a quote needs no change',
      'text\n> quote\n',
      'text\n> quote\n',
    );
    check(
      'a quote line continues a quote paragraph',
      '> a  \n> b\n',
      '> a  \n> b\n',
    );
  });

  group('lazy table row', () {
    check(
      'a pipe-less line after a table is a row: its trailing spaces go',
      '| a | b |\n|---|---|\nafter  \nnext\n',
      '| a | b |\n|---|---|\nafter\nnext\n',
    );
  });

  group('shape', () {
    check(
      'E07: text already laid out is unchanged',
      '# T\n\n| a | b |\n|---|---|\n\nx  \ny\n',
      '# T\n\n| a | b |\n|---|---|\n\nx  \ny\n',
    );
    check('empty text returns empty', '', '');
    check('blank-only text returns empty', '\n  \n\n', '');
    check('a missing final line break is not added', 'a\n\nb', 'a\n\nb');
    check('a final line break is kept', 'a\n\nb\n', 'a\n\nb\n');
  });

  test('$_slug E07: laying out twice equals once', () {
    for (final c in laidOut) {
      String run(String s) =>
          layOutText(s, underHeading: c.underHeading, blockKinds: c.kinds);
      final once = run(c.input);
      expect(run(once), once, reason: 'input: ${c.input}');
    }
  });
}
