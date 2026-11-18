import 'dart:math';

import 'package:specstone_core/src/doc_model/sentences.dart';
import 'package:test/test.dart' hide collapseWhitespace;

/// The regex form `collapseWhitespace` was read by, kept as the reference its
/// one-pass scan must match.
String _referenceCollapse(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('collapseWhitespace reads as the regex form did', () {
    test(r'every code unit is whitespace as \s says', () {
      for (var unit = 0; unit <= 0xFFFF; unit++) {
        final char = String.fromCharCode(unit);
        for (final text in ['a${char}b', '$char$char', '> $char> b']) {
          expect(
            collapseWhitespace(text),
            _referenceCollapse(text),
            reason: 'U+${unit.toRadixString(16)} in "$text"',
          );
        }
      }
    });

    test('tabs, CRLF remnants, no-break spaces, and quote marks at '
        'line starts', () {
      for (final text in [
        '> a\n>   b\r\n>\tc\n\n',
        '  > > deep\n\t- item\u00a0one\n1) two\n12345678901. no\n',
        '- > x\n> - y\n>- z\n-> arrow\na > b\n',
        'x\u2028> after separator\u2029> and another\r> after CR',
        '\ufeff> bom\n\u3000> ideographic\n',
        '>\n> \n>\t\n  \n',
        '',
      ]) {
        expect(
          collapseWhitespace(text),
          _referenceCollapse(text),
          reason: '"$text"',
        );
      }
    });

    test('200,000 random strings over the characters that matter', () {
      const alphabet = [
        ' ', '\t', '\n', '\r', '\u00a0', '\u2028', '\u2029', '>', '-', '+', //
        '*', '1', '9', '.', ')', 'a', '\ufeff', '\u200b', '\u180e', '|',
      ];
      final random = Random(5);
      for (var round = 0; round < 200000; round++) {
        final text = [
          for (var i = 0, n = random.nextInt(16); i < n; i++)
            alphabet[random.nextInt(alphabet.length)],
        ].join();

        if (collapseWhitespace(text) != _referenceCollapse(text)) {
          fail('collapseWhitespace differs on ${text.codeUnits}');
        }
      }
    });
  });

  group('sentencesOf', () {
    test('a paragraph is cut after . ? ! a space or the end follows', () {
      const text =
          'First one. Is it two? Yes! Three\n'
          'and a half.';
      expect(sentencesOf(text), [
        'First one.',
        'Is it two?',
        'Yes!',
        'Three and a half.',
      ]);
    });

    test('a mark with no space after it cuts nothing', () {
      expect(sentencesOf('Version 1.5 and a.b hold. Wait...\n'), [
        'Version 1.5 and a.b hold.',
        'Wait...',
      ]);
    });

    test('a list item reads without its marker', () {
      const text =
          '- Bullet one. Bullet two.\n'
          '* Star item.\n'
          '+ Plus item.\n'
          '1. Numbered item.\n'
          '2) Paren item.\n'
          '   - Nested item.\n';
      expect(sentencesOf(text), [
        'Bullet one.',
        'Bullet two.',
        'Star item.',
        'Plus item.',
        'Numbered item.',
        'Paren item.',
        'Nested item.',
      ]);
    });

    test('a list item wrapped over lines is one block', () {
      const text =
          '- The first line\n'
          '  and the second.\n'
          '- Next.\n';
      expect(sentencesOf(text), ['The first line and the second.', 'Next.']);
    });

    test('a table with no outer pipes reads its cells, not one '
        'paragraph', () {
      const text =
          'Field | Note\n'
          '---|---\n'
          'limit | Pick a value. Then stop.\n'
          '\n'
          'After.\n';
      expect(sentencesOf(text), [
        'Field',
        'Note',
        'limit',
        'Pick a value.',
        'Then stop.',
        'After.',
      ]);
    });

    test('a table with no outer pipes ends at a fence, and the '
        'paragraph after it is read whole', () {
      const text =
          'Field | Note\n'
          '---|---\n'
          'limit | A value.\n'
          '```\n'
          'code\n'
          '```\n'
          'A sentence that\n'
          'wraps here.\n';
      expect(sentencesOf(text), [
        'Field',
        'Note',
        'limit',
        'A value.',
        'A sentence that wraps here.',
      ]);
    });

    test('a table starts by the column rule of markdown: a one-column '
        'table has no header pipe, and unequal counts make no table', () {
      expect(sentencesOf('abc\n|---|\nrow\n'), ['abc', 'row']);
      expect(sentencesOf('a | b | c\n--- | ---\nx | y | z\n'), [
        'a | b | c --- | --- x | y | z',
      ]);
    });

    test('a table ends at a list item or a change of quote depth', () {
      const text =
          'a | b\n'
          '--- | ---\n'
          'c | d\n'
          '- item that\n'
          '  wraps.\n';
      expect(sentencesOf(text), ['a', 'b', 'c', 'd', 'item that wraps.']);
    });

    test('a delimiter row that starts like a list item still makes '
        'a table', () {
      expect(sentencesOf('a | b\n- | -\nc | d\n'), ['a', 'b', 'c', 'd']);
    });

    test('a header line that opens with a list marker still makes '
        'a table, its marker part of the first cell', () {
      expect(sentencesOf('- a | b\n--- | ---\nc | d\n'), [
        '- a',
        'b',
        'c',
        'd',
      ]);
      expect(sentencesOf('* a | b\n--- | ---\nc | d\n'), [
        '* a',
        'b',
        'c',
        'd',
      ]);
      expect(sentencesOf('- a\n--- | ---\nc | d\n'), ['a --- | --- c | d']);
    });

    test('a line that opens with a pipe is a row only inside a '
        'table', () {
      expect(sentencesOf('| one. two.\n| three.\n'), [
        '| one.',
        'two.',
        '| three.',
      ]);
    });

    test('a table with no outer pipes below a paragraph line '
        'ends that paragraph', () {
      const text =
          'Intro line\n'
          'a | b\n'
          ':-: | :-:\n'
          'c | d\n';
      expect(sentencesOf(text), ['Intro line', 'a', 'b', 'c', 'd']);
    });

    test('a table cell is read without pipes, a delimiter row is '
        'none', () {
      const text =
          '| Field | Note |\n'
          '|---|:-:|\n'
          '| limit | Pick a value. Then stop. |\n'
          '| a \\| b | |\n';
      expect(sentencesOf(text), [
        'Field',
        'Note',
        'limit',
        'Pick a value.',
        'Then stop.',
        r'a \| b',
      ]);
    });

    test('a ### or deeper heading is read without its marks', () {
      const text =
          '### Edge case. Two parts\n'
          '#### Deeper ####\n'
          'Body.\n';
      expect(sentencesOf(text), ['Edge case.', 'Two parts', 'Deeper', 'Body.']);
    });

    test('inline markup stays as written', () {
      const text = 'Use **bold** and `code` and [a link](x.md#y). Done.\n';
      expect(sentencesOf(text), [
        'Use **bold** and `code` and [a link](x.md#y).',
        'Done.',
      ]);
    });

    test('the frontmatter is no text', () {
      const text =
          '---\n'
          'title: Not a sentence. Nor this.\n'
          'draft: true\n'
          '---\n'
          'Body.\n';
      expect(sentencesOf(text), ['Body.']);
    });

    test('the # title and the ## headers are no text', () {
      const text =
          '# The title. Really.\n'
          '\n'
          'Lead.\n'
          '\n'
          '## Section header. Two\n'
          '\n'
          'Body.\n';
      expect(sentencesOf(text), ['Lead.', 'Body.']);
    });

    test('fenced code is no text, backtick or tilde', () {
      const text =
          'Before.\n'
          '```dart\n'
          'final x = 1. Not text.\n'
          '```\n'
          '~~~\n'
          '- not an item.\n'
          '~~~\n'
          'After.\n';
      expect(sentencesOf(text), ['Before.', 'After.']);
    });

    test('a blank line and a thematic break end a block', () {
      const text =
          'One\n'
          '\n'
          'two.\n'
          '\n'
          '***\n'
          'Three.\n';
      expect(sentencesOf(text), ['One', 'two.', 'Three.']);
    });

    test('a paragraph line that reads like a number is no marker', () {
      expect(sentencesOf('It was in\n2024. Then it ended.\n'), [
        'It was in 2024.',
        'Then it ended.',
      ]);
    });

    test('a cut at an abbreviation leaves each piece found in the '
        'source', () {
      const text = 'Use a tool, e.g. the CLI, for it. Not e.g.\n';
      expect(sentencesOf(text), [
        'Use a tool, e.g.',
        'the CLI, for it.',
        'Not e.g.',
      ]);
    });

    test('a paragraph wrapped over lines is found in its source '
        'with the wrap read as a space', () {
      const text =
          'A sentence that is\n'
          'wrapped. And one more\n'
          'across lines.\n';
      expect(sentencesOf(text), [
        'A sentence that is wrapped.',
        'And one more across lines.',
      ]);
    });

    test('a blockquote wrapped over two > lines gives one sentence, '
        'found in its source', () {
      const text =
          '> foo\n'
          '> bar.\n';
      expect(sentencesOf(text), ['foo bar.']);
    });

    test('a nested blockquote, a quoted list, and a quoted table '
        'are found in their source', () {
      const text =
          '> > deep one\n'
          '> > wraps. Next.\n'
          '>\n'
          '> - quoted item that\n'
          '>   wraps.\n'
          '> | q |\n'
          '> |---|\n'
          '> | cell. |\n'
          '- > item quote that\n'
          '  > wraps.\n';
      expect(sentencesOf(text), [
        'deep one wraps.',
        'Next.',
        'quoted item that wraps.',
        'q',
        'cell.',
        'item quote that wraps.',
      ]);
    });

    test('a mark followed by a closing quote or parenthesis cuts '
        'nothing', () {
      const text = 'She said "hi." Next one. It was (really?) Yes.\n';
      expect(sentencesOf(text), [
        'She said "hi." Next one.',
        'It was (really?) Yes.',
      ]);
    });

    test('a mark and a space inside an inline code span cut no sentence', () {
      const text = 'Run `a. b` now.\n';
      expect(sentencesOf(text), ['Run `a. b` now.']);
    });

    test('a code span holding ?, ., and ! ends no sentence', () {
      const text = 'Try `x? y. z!` then stop. Rest.\n';
      expect(sentencesOf(text), ['Try `x? y. z!` then stop.', 'Rest.']);
    });

    test('a cut right after a closed code span still cuts', () {
      const text = 'See `a.b`. Next one.\n';
      expect(sentencesOf(text), ['See `a.b`.', 'Next one.']);
    });

    test(
      'a mark and a space inside a code span of a table cell cut nothing',
      () {
        const text = '| a |\n|---|\n| `v. w` here. |\n';
        expect(sentencesOf(text), ['a', '`v. w` here.']);
      },
    );

    test('an indented # line between two paragraphs is the title, '
        'no text', () {
      expect(sentencesOf('One.\n\n  # x\n\nTwo.\n'), ['One.', 'Two.']);
    });

    test('a text with no sentence gives none', () {
      expect(sentencesOf(''), isEmpty);
      expect(sentencesOf('---\ndraft: true\n---\n'), isEmpty);
      expect(sentencesOf('# T\n\n## S\n\n```\ncode\n```\n'), isEmpty);
    });
  });

  group('collapseWhitespace', () {
    test('each run of whitespace becomes one space', () {
      expect(collapseWhitespace('a  b\n\n c\t\td\r\n'), 'a b c d ');
      expect(collapseWhitespace(''), '');
    });
  });
}
