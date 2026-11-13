// Label literals are built from parts so this file holds no number label.

import 'package:specstone_core/src/doc_model/number_label.dart';
import 'package:test/test.dart';

String f(int n) => 'F-$n';
String us(int n) => 'US-$n';
String fr(int n) => 'FR-$n';

String fPath(int n, [String slug = '']) => 'f${_pad(n)}$slug';
String usPath(int n, [String slug = '']) => 'us${_pad(n)}$slug';
String frPath(int n, [String slug = '']) => 'fr${_pad(n)}$slug';

String _pad(int n) => n.toString().padLeft(2, '0');

List<String> writtenIn(String line) => [
  for (final label in numberLabelsIn(line)) label.written,
];

const _applyName = 'setup_migration/upgrade_pack_pins/apply_steps_and_pins';

void main() {
  group('numberLabelsIn, the shapes of $_applyName E26', () {
    test('a full label of three parts', () {
      final run = '${f(12)} ${us(3)} ${fr(4)}';
      final labels = numberLabelsIn('Cite $run here.');
      expect(labels, hasLength(1));
      final label = labels.single;
      expect(label.written, run);
      expect(label.shape, LabelShape.full);
      expect((label.feature, label.story, label.fr), (12, 3, 4));
      expect(label.slug, isNull);
      expect(label.itemId, isNull);
      expect(label.start, 5);
      expect(label.end, 5 + run.length);
    });

    test('a full label of two parts', () {
      final label = numberLabelsIn('${f(1)} ${us(2)}').single;
      expect(label.shape, LabelShape.full);
      expect((label.feature, label.story, label.fr), (1, 2, null));
    });

    test('a full label of one part', () {
      final label = numberLabelsIn(f(7)).single;
      expect(label.shape, LabelShape.full);
      expect((label.feature, label.story, label.fr), (7, null, null));
    });

    test('a partial label of a story and an FR', () {
      final label = numberLabelsIn('${us(2)} ${fr(5)}').single;
      expect(label.shape, LabelShape.partial);
      expect((label.feature, label.story, label.fr), (null, 2, 5));
    });

    test('a partial label of a story alone', () {
      final label = numberLabelsIn(us(9)).single;
      expect(label.shape, LabelShape.partial);
      expect((label.feature, label.story, label.fr), (null, 9, null));
    });

    test('a partial label of an FR alone', () {
      final label = numberLabelsIn(fr(10)).single;
      expect(label.shape, LabelShape.partial);
      expect((label.feature, label.story, label.fr), (null, null, 10));
    });

    test('a folder path of three bare folders', () {
      final path = '${fPath(1)}/${usPath(2)}/${frPath(3)}';
      final label = numberLabelsIn('see `$path`').single;
      expect(label.written, path);
      expect(label.shape, LabelShape.folderPath);
      expect((label.feature, label.story, label.fr), (1, 2, 3));
      expect(label.slug, isNull);
    });

    test('a folder path whose last folder carries a slug', () {
      final path = '${usPath(2)}/${frPath(3, '_check_password')}';
      final label = numberLabelsIn('| `$path` |').single;
      expect(label.written, path);
      expect(label.shape, LabelShape.folderPath);
      expect((label.feature, label.story, label.fr), (null, 2, 3));
      expect(label.slug, 'check_password');
    });

    test('a folder path with a slugged folder before a bare one', () {
      final path = '${fPath(2, '_writing')}/${usPath(3)}';
      expect(writtenIn('at $path.'), [path]);
    });
  });

  group('numberLabelsIn, the boundary of '
      'consistency_check/find_broken_pointers/report_number_labels E09', () {
    test('a letter before the label is no boundary', () {
      expect(writtenIn('UTF-8 and UTF-16 and x-${fr(12)}'), isEmpty);
    });

    test('a digit before the label is no boundary', () {
      expect(writtenIn('9${f(1)} 1${us(2)}'), isEmpty);
    });

    test('a non-ASCII letter before the label is no boundary', () {
      expect(writtenIn('é${f(1)} ${f(2)} ด${f(3)}'), [f(2)]);
    });

    test('a bracket, a space, or a comma before the label is a boundary', () {
      expect(writtenIn('(${f(1)}) and, ${us(2)}'), [f(1), us(2)]);
    });

    test('a start of line is a boundary', () {
      expect(writtenIn(fr(3)), [fr(3)]);
    });

    test('a slash before a folder path is a boundary', () {
      expect(writtenIn('x/${usPath(1)}/${frPath(2)}'), [
        '${usPath(1)}/${frPath(2)}',
      ]);
    });

    test('a letter before a folder path is no boundary', () {
      expect(writtenIn('x${usPath(1)}/${frPath(2)}'), isEmpty);
    });
  });

  group('numberLabelsIn, what is no label', () {
    test('a placeholder is no label (R81)', () {
      expect(writtenIn('F-<nn> US-<nn> FR-<nn> f<nn>/us<nn>/fr<nn>'), isEmpty);
    });

    test('a path whose every folder carries its slug is no label', () {
      const path =
          'prds/features/f02_document_writing/us03_approve_drafts/'
          'USER_STORY.md';
      expect(writtenIn(path), isEmpty);
      expect(writtenIn('../us03_approve_drafts/USER_STORY.md'), isEmpty);
    });

    test('one bare folder alone is no folder path', () {
      expect(writtenIn('the ${fPath(1)} folder'), isEmpty);
    });

    test('folders out of order do not join', () {
      expect(writtenIn('${frPath(1)}/${usPath(2)}'), isEmpty);
    });

    test('an item ID is no label', () {
      expect(writtenIn('INV-6 RULE-12 E05 S3 BR-01 PV-02 NFR-P03'), isEmpty);
    });

    test('a label with no digit after the dash is no label', () {
      expect(writtenIn('F- US-x FR'), isEmpty);
    });

    test('a lower-case dash form is no label', () {
      expect(writtenIn('f-1 us-2 fr-3'), isEmpty);
    });
  });

  group('numberLabelsIn, runs', () {
    test('a run of out-of-order labels splits into one label each', () {
      expect(writtenIn('${fr(1)} ${us(2)}'), [fr(1), us(2)]);
    });

    test('a run skipping a part splits into one label each', () {
      expect(writtenIn('${f(1)} ${fr(2)}'), [f(1), fr(2)]);
    });

    test('a list of partial labels gives one label per run', () {
      final labels = numberLabelsIn('(${us(1)} ${fr(2)}, ${fr(3)})');
      expect(labels.map((l) => l.written), ['${us(1)} ${fr(2)}', fr(3)]);
    });

    test('two spaces end a run', () {
      expect(writtenIn('${f(1)}  ${us(2)}'), [f(1), us(2)]);
    });

    test('a number too long for an int still gives a label', () {
      final label = numberLabelsIn('F-${'9' * 30}').single;
      expect(label.written, 'F-${'9' * 30}');
      expect(label.feature, isNotNull);
    });
  });

  group('numberLabelsIn, the item ID after a label', () {
    test('a plain item ID follows', () {
      final label = numberLabelsIn('${f(2)} INV-6 holds').single;
      expect(label.written, f(2));
      expect(label.itemId, 'INV-6');
      expect(label.end, f(2).length);
    });

    test('a scenario and an edge case ID follow', () {
      expect(numberLabelsIn('${f(1)} S3').single.itemId, 'S3');
      expect(numberLabelsIn('${us(1)} ${fr(2)} E09').single.itemId, 'E09');
    });

    test('a letter-led NFR ID follows', () {
      expect(numberLabelsIn('${f(1)} NFR-P03').single.itemId, 'NFR-P03');
    });

    test('a label that is not ascending is a label, not an item ID', () {
      final labels = numberLabelsIn('${fr(1)} ${fr(2)}');
      expect(labels.map((l) => l.written), [fr(1), fr(2)]);
      expect(labels.first.itemId, isNull);
    });

    test('a lower-case word is no item ID', () {
      expect(numberLabelsIn('${f(1)} and').single.itemId, isNull);
    });

    test('an item ID after a folder path', () {
      final label = numberLabelsIn('${usPath(1)}/${frPath(2)} E04').single;
      expect(label.itemId, 'E04');
    });
  });

  group('numberLabelsInMarkdown, offsets into the whole text', () {
    test('a label on a later line has its offsets in the whole text', () {
      const prefix = 'first line\nsecond ';
      final text = '$prefix${f(4)}\nthird\n';
      final label = numberLabelsInMarkdown(text).single;
      expect(label.start, prefix.length);
      expect(label.end, prefix.length + f(4).length);
      expect(text.substring(label.start, label.end), f(4));
    });

    test('a label in prose is read', () {
      expect(
        numberLabelsInMarkdown('Cite ${f(1)} ${us(2)}.\n')
            .map((l) => l.written),
        ['${f(1)} ${us(2)}'],
      );
    });

    test('a label in a dart fence is skipped', () {
      final text = '```dart\nvar a = "${f(1)}";\n```\n${us(2)}\n';
      expect(numberLabelsInMarkdown(text).map((l) => l.written), [us(2)]);
    });

    test('a label in a tilde fence is skipped', () {
      final text = '~~~\n${f(1)}\n~~~\n';
      expect(numberLabelsInMarkdown(text), isEmpty);
    });

    test('a label in a fence with no language is skipped', () {
      final text = '```\n${f(1)}\n```\n';
      expect(numberLabelsInMarkdown(text), isEmpty);
    });

    test('a label in a mermaid fence is read', () {
      final text = '```mermaid\nA[get, ${f(1)} CLI entry]\n```\n';
      final labels = numberLabelsInMarkdown(text);
      expect(labels.map((l) => l.written), [f(1)]);
      expect(text.substring(labels.single.start, labels.single.end), f(1));
    });

    test('a mermaid fence after a closed fence is read', () {
      final text =
          '```dart\n${f(1)}\n```\n```mermaid\n${f(2)}\n```\n'
          '```sh\n${f(3)}\n```\n';
      expect(numberLabelsInMarkdown(text).map((l) => l.written), [f(2)]);
    });

    test('a mermaid fence in a block quote is read', () {
      final text = '> ```mermaid\n> ${f(1)}\n> ```\n';
      expect(numberLabelsInMarkdown(text).map((l) => l.written), [f(1)]);
    });

    test('a longer fence is not closed by a shorter run', () {
      final text = '````mermaid\n```\n${f(1)}\n````\n${f(2)}\n';
      expect(numberLabelsInMarkdown(text).map((l) => l.written), [f(1), f(2)]);
    });

    test('an unclosed fence reads to the end of the text', () {
      expect(numberLabelsInMarkdown('```dart\n${f(1)}\n'), isEmpty);
    });

    test('a label in an inline code span is skipped', () {
      final path = '${usPath(1)}/${frPath(2, '_slug')}';
      expect(numberLabelsInMarkdown('| `$path` |\n'), isEmpty);
    });

    test('a dash run in an inline code span is skipped', () {
      final text = 'Cite `${f(1)} ${us(2)}` and `${f(3)}` here.\n';
      expect(numberLabelsInMarkdown(text), isEmpty);
    });

    test('a label after a closed code span is read', () {
      final text = 'See `x` then ${f(1)}.\n';
      final labels = numberLabelsInMarkdown(text);
      expect(labels.map((l) => l.written), [f(1)]);
      expect(labels.single.start, 'See `x` then '.length);
    });

    test('a label between backticks in a mermaid fence is still read', () {
      final text = '```mermaid\nA[`${f(1)}`] B[${us(2)}]\n```\n';
      expect(numberLabelsInMarkdown(text).map((l) => l.written), [f(1), us(2)]);
    });

    test('a backtick escaped by a backslash opens no span, its label read', () {
      final text =
          r'See \`'
          '${f(1)}'
          r' there. Or \`x\` '
          '${us(2)}.\n';
      expect(numberLabelsInMarkdown(text).map((l) => l.written), [f(1), us(2)]);
    });

    test('a label in a link destination is skipped', () {
      final text = '[${us(1)} ${fr(2)}](../${usPath(1)}/${frPath(2)}.md)\n';
      final labels = numberLabelsInMarkdown(text);
      expect(labels.map((l) => l.written), ['${us(1)} ${fr(2)}']);
    });

    test('a label in a pointy-bracket link destination is skipped', () {
      final text = '[x](<../${usPath(1)}/${frPath(2)}.md>) ${f(3)}\n';
      expect(numberLabelsInMarkdown(text).map((l) => l.written), [f(3)]);
    });

    test('a link destination with balanced parentheses is skipped', () {
      final text = '[x](a_(${usPath(1)}/${frPath(2)})) ${f(3)}\n';
      expect(numberLabelsInMarkdown(text).map((l) => l.written), [f(3)]);
    });

    test('a reference definition destination is skipped', () {
      final text = '[x]: ../${usPath(1)}/${frPath(2)}.md\n${f(3)}\n';
      expect(numberLabelsInMarkdown(text).map((l) => l.written), [f(3)]);
    });

    test('a mermaid fence holding an indented fence-like line and an empty '
        'line still reads its label', () {
      final text = '```mermaid\n\n    ```\nA[${f(1)}]\n```\n${us(2)}\n';
      expect(numberLabelsInMarkdown(text).map((l) => l.written), [f(1), us(2)]);
    });

    test('a dart fence holding an indented fence-like line and an empty '
        'line reads none inside', () {
      final text = '```dart\n\n    ```\n${f(1)}\n```\n${us(2)}\n';
      expect(numberLabelsInMarkdown(text).map((l) => l.written), [us(2)]);
    });

    test('a stray backtick line opens no fence', () {
      expect(numberLabelsInMarkdown('`\n${f(1)}\n'), hasLength(1));
    });

    test('text with no label gives none', () {
      expect(numberLabelsInMarkdown('Nothing here.\n'), isEmpty);
      expect(numberLabelsInMarkdown(''), isEmpty);
    });
  });

  group('numberLabelsInMarkdown, legacy IDs', () {
    const legacyId = 'ai02/us13/fr01';

    test('a legacy ID reads only from its story folder unless the caller '
        'asks for it', () {
      final label = numberLabelsInMarkdown('See $legacyId.\n').single;

      expect(label.written, 'us13/fr01');
    });

    test('a legacy ID reads as a folder path with its numbers', () {
      final label = numberLabelsInMarkdown(
        'See $legacyId.\n',
        legacyIds: true,
      ).single;

      expect(label.written, legacyId);
      expect(label.shape, LabelShape.folderPath);
      expect((label.feature, label.story, label.fr), (2, 13, 1));
    });

    test('a legacy ID with a slug in every folder is no label', () {
      expect(
        numberLabelsInMarkdown(
          'ai02_chat/us13_pay/fr01_charge.md\n',
          legacyIds: true,
        ),
        isEmpty,
      );
    });

    test('a legacy ID keeps the prefix of its feature folder', () {
      final label = numberLabelsInMarkdown(
        'See $legacyId.\n',
        legacyIds: true,
      ).single;

      expect(label.prefix, 'ai');
    });

    test('a run followed by an item ID or scenario segment is a label as '
        'before, in both readers', () {
      for (final legacy in [false, true]) {
        final labels = numberLabelsInMarkdown(
          'f03/us02/fr04/e09 and f06/us01/s1\n',
          legacyIds: legacy,
        );

        expect(labels.map((l) => l.written), ['f03/us02/fr04', 'f06/us01']);
        expect(labels.every((l) => !l.isPartOfPath), isTrue);
      }
    });

    test('a run followed by a numbered folder that does not follow is read '
        'but names no doc by its folders, in both readers', () {
      final legacy = numberLabelsInMarkdown(
        'ai01/us01/nf01\n',
        legacyIds: true,
      ).single;
      final upgrade = numberLabelsInMarkdown('us01/fr01/nf02\n').single;

      expect((legacy.written, legacy.isPartOfPath), ('ai01/us01', true));
      expect((upgrade.written, upgrade.isPartOfPath), ('us01/fr01', true));
    });

    test('a story and an FR folder name keep their own ranks', () {
      final label = numberLabelsInMarkdown(
        'us13/fr01\n',
        legacyIds: true,
      ).single;

      expect((label.feature, label.story, label.fr), (null, 13, 1));
    });
  });
}
