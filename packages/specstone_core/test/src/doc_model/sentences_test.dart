import 'dart:math';

import 'package:specstone_core/src/doc_model/sentences.dart';
import 'package:test/test.dart' hide collapseWhitespace;

const _story =
    'document_writing/approve_drafts/show_changes_since_approval E22';

/// Expects every sentence of [source] to occur in the held text of [source].
void _expectEachHeld(String source) {
  final held = heldTextOf(source);
  for (final sentence in sentencesOf(source)) {
    expect(held, contains(sentence), reason: 'sentence: "$sentence"');
  }
}

/// The regex form `collapseWhitespace` and `heldTextOf` were read by, kept as
/// the reference their one-pass scans must match.
String _referenceCollapse(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

String _referenceHeld(String lfText) => _referenceCollapse(
  lfText.replaceAllMapped(
    RegExp(
      r'^(?:[ \t]*(?:>[ \t]?|(?:[-+*]|\d{1,9}[.)])[ \t]+))+',
      multiLine: true,
    ),
    (opening) => opening[0]!.replaceAll(RegExp(r'>[ \t]?'), ''),
  ),
);

void main() {
  group('collapseWhitespace and heldTextOf read as the regex form did', () {
    test('$_story: every code unit is whitespace as \\s says', () {
      for (var unit = 0; unit <= 0xFFFF; unit++) {
        final char = String.fromCharCode(unit);
        for (final text in ['a${char}b', '$char$char', '> $char> b']) {
          expect(
            collapseWhitespace(text),
            _referenceCollapse(text),
            reason: 'U+${unit.toRadixString(16)} in "$text"',
          );
          expect(
            heldTextOf(text),
            _referenceHeld(text),
            reason: 'U+${unit.toRadixString(16)} in "$text"',
          );
        }
      }
    });

    test('$_story: tabs, CRLF remnants, no-break spaces, and quote marks at '
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
        expect(heldTextOf(text), _referenceHeld(text), reason: '"$text"');
        expect(
          collapseWhitespace(text),
          _referenceCollapse(text),
          reason: '"$text"',
        );
      }
    });

    test('$_story: 200,000 random strings over the characters that matter', () {
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

        final held = heldTextOf(text);
        if (held != _referenceHeld(text)) {
          fail('heldTextOf differs on ${text.codeUnits}');
        }
        if (collapseWhitespace(text) != _referenceCollapse(text)) {
          fail('collapseWhitespace differs on ${text.codeUnits}');
        }
      }
    });
  });

  group('sentencesOf', () {
    test(
      '$_story: a paragraph is cut after . ? ! a space or the end follows',
      () {
        const text =
            'First one. Is it two? Yes! Three\n'
            'and a half.';
        expect(sentencesOf(text), [
          'First one.',
          'Is it two?',
          'Yes!',
          'Three and a half.',
        ]);
      },
    );

    test('$_story: a mark with no space after it cuts nothing', () {
      expect(sentencesOf('Version 1.5 and a.b hold. Wait...\n'), [
        'Version 1.5 and a.b hold.',
        'Wait...',
      ]);
    });

    test('$_story: a list item reads without its marker', () {
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

    test('$_story: a list item wrapped over lines is one block', () {
      const text =
          '- The first line\n'
          '  and the second.\n'
          '- Next.\n';
      expect(sentencesOf(text), ['The first line and the second.', 'Next.']);
    });

    test('$_story: a table with no outer pipes reads its cells, not one '
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

    test('$_story: a table with no outer pipes ends at a fence, and the '
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

    test('$_story: a table starts by the column rule of markdown: a one-column '
        'table has no header pipe, and unequal counts make no table', () {
      expect(sentencesOf('abc\n|---|\nrow\n'), ['abc', 'row']);
      expect(sentencesOf('a | b | c\n--- | ---\nx | y | z\n'), [
        'a | b | c --- | --- x | y | z',
      ]);
    });

    test('$_story: a table ends at a list item or a change of quote depth', () {
      const text =
          'a | b\n'
          '--- | ---\n'
          'c | d\n'
          '- item that\n'
          '  wraps.\n';
      expect(sentencesOf(text), ['a', 'b', 'c', 'd', 'item that wraps.']);
    });

    test('$_story: a line that opens with a pipe is a row only inside a '
        'table', () {
      expect(sentencesOf('| one. two.\n| three.\n'), [
        '| one.',
        'two.',
        '| three.',
      ]);
    });

    test('$_story: a table with no outer pipes below a paragraph line '
        'ends that paragraph', () {
      const text =
          'Intro line\n'
          'a | b\n'
          ':-: | :-:\n'
          'c | d\n';
      expect(sentencesOf(text), ['Intro line', 'a', 'b', 'c', 'd']);
    });

    test('$_story: a table cell is read without pipes, a delimiter row is '
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

    test('$_story: a ### or deeper heading is read without its marks', () {
      const text =
          '### Edge case. Two parts\n'
          '#### Deeper ####\n'
          'Body.\n';
      expect(sentencesOf(text), ['Edge case.', 'Two parts', 'Deeper', 'Body.']);
    });

    test('$_story: inline markup stays as written', () {
      const text = 'Use **bold** and `code` and [a link](x.md#y). Done.\n';
      expect(sentencesOf(text), [
        'Use **bold** and `code` and [a link](x.md#y).',
        'Done.',
      ]);
    });

    test('$_story: the frontmatter is no text', () {
      const text =
          '---\n'
          'title: Not a sentence. Nor this.\n'
          'draft: true\n'
          '---\n'
          'Body.\n';
      expect(sentencesOf(text), ['Body.']);
    });

    test('$_story: the # title and the ## headers are no text', () {
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

    test('$_story: fenced code is no text, backtick or tilde', () {
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

    test('$_story: a blank line and a thematic break end a block', () {
      const text =
          'One\n'
          '\n'
          'two.\n'
          '\n'
          '***\n'
          'Three.\n';
      expect(sentencesOf(text), ['One', 'two.', 'Three.']);
    });

    test('$_story: a paragraph line that reads like a number is no marker', () {
      expect(sentencesOf('It was in\n2024. Then it ended.\n'), [
        'It was in 2024.',
        'Then it ended.',
      ]);
    });

    test('$_story: a cut at an abbreviation leaves each piece found in the '
        'source', () {
      const text = 'Use a tool, e.g. the CLI, for it. Not e.g.\n';
      expect(sentencesOf(text), [
        'Use a tool, e.g.',
        'the CLI, for it.',
        'Not e.g.',
      ]);
      _expectEachHeld(text);
    });

    test('$_story: a paragraph wrapped over lines is found in its source '
        'with the wrap read as a space', () {
      const text =
          'A sentence that is\n'
          'wrapped. And one more\n'
          'across lines.\n';
      expect(sentencesOf(text), [
        'A sentence that is wrapped.',
        'And one more across lines.',
      ]);
      _expectEachHeld(text);
    });

    test('$_story: a blockquote wrapped over two > lines gives one sentence, '
        'found in its source', () {
      const text =
          '> foo\n'
          '> bar.\n';
      expect(sentencesOf(text), ['foo bar.']);
      expect(heldTextOf(text), 'foo bar. ');
      _expectEachHeld(text);
    });

    test('$_story: a nested blockquote, a quoted list, and a quoted table '
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
      _expectEachHeld(text);
    });

    test('$_story: a mark followed by a closing quote or parenthesis cuts '
        'nothing', () {
      const text = 'She said "hi." Next one. It was (really?) Yes.\n';
      expect(sentencesOf(text), [
        'She said "hi." Next one.',
        'It was (really?) Yes.',
      ]);
      _expectEachHeld(text);
    });

    test('$_story: a mark and a space inside an inline code span cut, each '
        'piece held', () {
      const text = 'Run `a. b` now.\n';
      expect(sentencesOf(text), ['Run `a.', 'b` now.']);
      _expectEachHeld(text);
    });

    test('$_story: an indented # line between two paragraphs is the title, '
        'no text', () {
      expect(sentencesOf('One.\n\n  # x\n\nTwo.\n'), ['One.', 'Two.']);
    });

    test('$_story: a text with no sentence gives none', () {
      expect(sentencesOf(''), isEmpty);
      expect(sentencesOf('---\ndraft: true\n---\n'), isEmpty);
      expect(sentencesOf('# T\n\n## S\n\n```\ncode\n```\n'), isEmpty);
    });
  });

  group('collapseWhitespace', () {
    test('$_story: each run of whitespace becomes one space', () {
      expect(collapseWhitespace('a  b\n\n c\t\td\r\n'), 'a b c d ');
      expect(collapseWhitespace(''), '');
    });
  });

  group('heldTextOf', () {
    test('$_story: block quote marks go and whitespace collapses', () {
      expect(heldTextOf('> a\n>> b\n> > c\n  > d\n'), 'a b c d ');
    });

    test('$_story: a > inside a line stays', () {
      expect(heldTextOf('a -> b and x > y\n'), 'a -> b and x > y ');
    });

    test('$_story: a quote mark after a list marker goes, the marker '
        'stays', () {
      expect(heldTextOf('- > item\n'), '- item ');
    });
  });
}
