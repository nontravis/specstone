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

void main() {
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
