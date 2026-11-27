import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/models/body_line.dart';
import 'package:specstone_core/src/doc_model/models/doc_item.dart';
import 'package:specstone_core/src/doc_model/models/section_item.dart';
import 'package:specstone_core/src/doc_model/text_scan.dart';
import 'package:specstone_core/src/index_query/item_facts.dart'
    show withGeneratedFenced;
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_test_support/specstone_test_support.dart';
import 'package:test/test.dart';

const _firstLine = 20;

/// Builds the body lines of [text], numbered from [_firstLine], with the
/// lines of a ``` fence, fences included, marked fenced.
List<BodyLine> _body(String text) {
  var inFence = false;
  return [
    for (final (k, line) in text.split('\n').indexed)
      BodyLine(
        text: line,
        line: _firstLine + k,
        fenced: () {
          final isFence = line.trimLeft().startsWith('```');
          final fenced = inFence || isFence;
          if (isFence) inFence = !inFence;
          return fenced;
        }(),
      ),
  ];
}

List<DocItem> _items(String text) => _itemsOf(_body(text));

List<DocItem> _itemsOf(List<BodyLine> body) => [
  for (final item in sectionItemsOf(body))
    DocItem(
      line: item.line,
      chars: item.text.length - scanText(item.text).pairs,
      text: item.head,
      heading: item.kind == SectionItemKind.heading,
    ),
];

void main() {
  group('sectionItemsOf', () {
    test('a list item counts without its nested items '
        'and a nested item alone', () {
      final items = _items(
        '- parent one\n'
        '  carries on\n'
        '  - child\n'
        '- second',
      );

      expect(items, [
        const DocItem(line: 20, chars: 25, text: 'parent one', heading: false),
        const DocItem(line: 22, chars: 9, text: 'child', heading: false),
        const DocItem(line: 23, chars: 8, text: 'second', heading: false),
      ]);
    });

    test('an ordered item '
        'reads its text after the marker', () {
      expect(_items('1. first\n2) second'), [
        const DocItem(line: 20, chars: 8, text: 'first', heading: false),
        const DocItem(line: 21, chars: 9, text: 'second', heading: false),
      ]);
    });

    test('a table row below the delimiter row is an item, '
        'the header and delimiter rows are none', () {
      final items = _items(
        '| ID | Name |\n'
        '|---|---|\n'
        '| a | b |\n'
        '| c | d |\n'
        '\n'
        'after the table',
      );

      expect(items, [
        const DocItem(line: 22, chars: 9, text: 'a | b |', heading: false),
        const DocItem(line: 23, chars: 9, text: 'c | d |', heading: false),
        const DocItem(
          line: 25,
          chars: 15,
          text: 'after the table',
          heading: false,
        ),
      ]);
    });

    test('a table row reads its head from its first cell: the opening pipe '
        'and the blanks around it are no part of it', () {
      final items = _items(
        '| ID | Name |\n'
        '|---|---|\n'
        '| a | b |\n'
        '|c|d|\n'
        '   |   e | f |\n'
        'g | h |\n'
        r'\| i | j |',
      );

      expect(
        [for (final item in items) item.text],
        ['a | b |', 'c|d|', 'e | f |', 'g | h |', r'\| i | j |'],
      );
    });

    test('a quoted table row reads its head after the quote marks and its '
        'pipe', () {
      final items = _items('> | ID | Name |\n> |---|---|\n> | k | l |');

      expect([for (final item in items) item.text], ['k | l |']);
    });

    test('a table indented under a list item is part of that item, '
        'not rows of its own', () {
      final items = sectionItemsOf(
        _body('- BR-01 text\n  | a | b |\n  |---|---|\n  | c | d |\n- BR-02'),
      );

      expect(
        [for (final item in items) item.kind],
        [SectionItemKind.listItem, SectionItemKind.listItem],
      );
      expect(items.first.text, hasLength(greaterThan('- BR-01 text'.length)));
      expect(items.first.text, contains('| c | d |'));
    });

    test('a line four or more spaces in, outside a list item, is indented '
        'code: no table header, no row below the delimiter row', () {
      for (final indent in ['    ', '\t']) {
        final header = sectionItemsOf(
          _body('$indent| ID | Name |\n|---|---|\n| E01 | b |'),
        );
        final row = sectionItemsOf(
          _body('| ID | Name |\n|---|---|\n| x | y |\n$indent| E01 | b |'),
        );

        expect(
          [for (final item in header) item.kind],
          [SectionItemKind.paragraph],
          reason: indent,
        );
        expect(
          [for (final item in row) (item.kind, item.head)],
          [
            (SectionItemKind.tableRow, 'x | y |'),
            (SectionItemKind.paragraph, '| E01 | b |'),
          ],
          reason: indent,
        );
      }
    });

    test('a table opened up to three spaces in still has rows', () {
      final items = sectionItemsOf(
        _body('   | ID | Name |\n   |---|---|\n   | E01 | b |'),
      );

      expect([for (final item in items) item.head], ['E01 | b |']);
    });

    test('a list item or heading that opens with a pipe keeps it in its '
        'head', () {
      expect(
        [for (final item in _items('- | a\n\n### | b')) item.text],
        ['| a', '| b'],
      );
    });

    test('a paragraph is '
        'one item across its lines', () {
      final items = _items(
        'alpha beta\n'
        'gamma\n'
        '\n'
        'delta',
      );

      expect(items, [
        const DocItem(line: 20, chars: 16, text: 'alpha beta', heading: false),
        const DocItem(line: 23, chars: 5, text: 'delta', heading: false),
      ]);
    });

    test('a ### heading counts with the paragraph under it '
        'and never its bullets', () {
      final items = _items(
        '### Scenario 1\n'
        '\n'
        'The paragraph under it.\n'
        '- bullet one\n'
        '\n'
        '### Scenario 2\n'
        '\n'
        '- bullet two',
      );

      expect(items, [
        const DocItem(line: 20, chars: 39, text: 'Scenario 1', heading: true),
        const DocItem(line: 23, chars: 12, text: 'bullet one', heading: false),
        const DocItem(line: 25, chars: 14, text: 'Scenario 2', heading: true),
        const DocItem(line: 27, chars: 12, text: 'bullet two', heading: false),
      ]);
    });

    test('a bare ### line opens a heading item with empty text, a ###x line '
        'opens none', () {
      expect(_items('###\n\n- a\n\n###x'), [
        const DocItem(line: 20, chars: 3, text: '', heading: true),
        const DocItem(line: 22, chars: 3, text: 'a', heading: false),
        const DocItem(line: 24, chars: 4, text: '###x', heading: false),
      ]);
    });

    test('a ### heading inside a blockquote '
        'counts with a deeper quoted paragraph right under it', () {
      final items = _items(
        '> ### Quoted\n'
        '>\n'
        '> > deeper\n'
        '- bullet',
      );

      expect(items, [
        const DocItem(line: 20, chars: 25, text: 'Quoted', heading: true),
        const DocItem(line: 23, chars: 8, text: 'bullet', heading: false),
      ]);
    });

    test('a ### heading '
        'counts with the quoted paragraph right under it', () {
      final items = _items(
        '### PV-01\n'
        '\n'
        '> en: One line.\n'
        '- bullet',
      );

      expect(items, [
        const DocItem(line: 20, chars: 26, text: 'PV-01', heading: true),
        const DocItem(line: 23, chars: 8, text: 'bullet', heading: false),
      ]);
    });

    test('a blockquote paragraph and list item are items as anywhere else', () {
      final items = _items(
        '> quoted paragraph\n'
        '>\n'
        '> - quoted item',
      );

      expect(items, [
        const DocItem(
          line: 20,
          chars: 18,
          text: 'quoted paragraph',
          heading: false,
        ),
        const DocItem(line: 22, chars: 15, text: 'quoted item', heading: false),
      ]);
    });

    test('a fenced code '
        'block is no item', () {
      final items = _items(
        '- before\n'
        '```dart\n'
        '- not an item\n'
        '```\n'
        '- after',
      );

      expect(items, [
        const DocItem(line: 20, chars: 8, text: 'before', heading: false),
        const DocItem(line: 24, chars: 7, text: 'after', heading: false),
      ]);
    });

    test('an item holding '
        'an emoji counts a surrogate pair once', () {
      final items = _items(
        '- \u{1F600} smile\n'
        '  \u{1F600}\u{1F600}',
      );

      // "- 😀 smile" is 9 code points, "  😀😀" is 4, one line feed.
      expect(items, [
        const DocItem(
          line: 20,
          chars: 14,
          text: '\u{1F600} smile',
          heading: false,
        ),
      ]);
    });

    test('a fence inside a list item ends the item and the text '
        'after it is its own item', () {
      final items = _itemsOf([
        const BodyLine(text: '- item', line: 20, fenced: false),
        const BodyLine(text: '  ```', line: 21, fenced: true),
        const BodyLine(text: '  - code', line: 22, fenced: true),
        const BodyLine(text: '  ```', line: 23, fenced: true),
        const BodyLine(text: '  more', line: 24, fenced: false),
      ]);

      expect(items, [
        const DocItem(line: 20, chars: 6, text: 'item', heading: false),
        const DocItem(line: 24, chars: 6, text: 'more', heading: false),
      ]);
    });

    test('a closed generated block of a listed kind is no item, '
        'one of another kind is', () {
      final lines = [
        '- before',
        generatedOpenMarker('scenario_copy'),
        '- copied',
        generatedEndMarker,
        generatedOpenMarker('other_copy'),
        '- kept',
        generatedEndMarker,
        '- after',
      ];
      final marked = generatedBlockLines(lines, {'scenario_copy'});
      final body = [
        for (final (k, line) in lines.indexed)
          BodyLine(text: line, line: _firstLine + k, fenced: false),
      ];

      final items = _itemsOf(
        withGeneratedFenced(body, (line) => marked[line - _firstLine]),
      );

      final at = [for (final item in items) item.line];
      expect(at, containsAll([20, 25, 27]));
      expect(at.where((line) => line >= 21 && line <= 23), isEmpty);
    });

    test('a fence inside '
        'a blockquote is no item', () {
      final items = _itemsOf([
        const BodyLine(text: '> ```', line: 20, fenced: true),
        const BodyLine(text: '> - code', line: 21, fenced: true),
        const BodyLine(text: '> ```', line: 22, fenced: true),
      ]);

      expect(items, isEmpty);
    });

    test('rows with no '
        'delimiter row are one paragraph', () {
      expect(_items('| a | b |\n| c | d |'), [
        const DocItem(line: 20, chars: 19, text: '| a | b |', heading: false),
      ]);
    });

    test('a #### line '
        'reads as paragraph text', () {
      expect(_items('#### Deep\nparagraph'), [
        const DocItem(line: 20, chars: 19, text: '#### Deep', heading: false),
      ]);
    });

    test('an empty body '
        'holds no item', () {
      expect(_items(''), isEmpty);
    });

    test('a thematic break is no item and ends the '
        'paragraph above it', () {
      expect(_items('first\n***\nsecond'), [
        const DocItem(line: 20, chars: 5, text: 'first', heading: false),
        const DocItem(line: 22, chars: 6, text: 'second', heading: false),
      ]);
      expect(_items('one\n\n---\n\ntwo'), [
        const DocItem(line: 20, chars: 3, text: 'one', heading: false),
        const DocItem(line: 24, chars: 3, text: 'two', heading: false),
      ]);
      expect(_items('* * *\n- - -\n> ---\n_ _ _'), isEmpty);
    });

    test('a table starts by the column rule of markdown, '
        'with or without a pipe in the header', () {
      expect(_items('abc\n|---|\nrow'), [
        const DocItem(line: 22, chars: 3, text: 'row', heading: false),
      ]);
      expect(_items('a | b | c\n--- | ---\nx | y | z'), [
        const DocItem(line: 20, chars: 29, text: 'a | b | c', heading: false),
      ]);
    });

    test('a delimiter row that starts like a list '
        'item still makes a table', () {
      expect(_items('a | b\n- | -\nc | d'), [
        const DocItem(line: 22, chars: 5, text: 'c | d', heading: false),
      ]);
    });

    test('a header line that opens with a list '
        'marker still makes a table', () {
      for (final header in ['- a | b', '* a | b', '+ a | b', '1. a | b']) {
        expect(_items('$header\n--- | ---\nc | d'), [
          const DocItem(line: 22, chars: 5, text: 'c | d', heading: false),
        ], reason: header);
      }
      expect(_items('- a\n--- | ---\nc | d'), [
        const DocItem(line: 20, chars: 19, text: 'a', heading: false),
      ]);
    });

    test('a line of 200,000 leading > marks reads in linear time, a fenced '
        'one included', () {
      final marks = '>' * 200000;
      final spent = cpuTimeOf(() {
        expect(_items('${marks}x'), [
          const DocItem(line: 20, chars: 200001, text: 'x', heading: false),
        ]);
        expect(_items('```\n$marks\n```'), isEmpty);
      });

      // Copying the rest of the line per mark takes seconds at this size.
      expect(spent, lessThan(const Duration(seconds: 2)));
    });

    test('a > mark takes up to 3 spaces before it and one after it', () {
      expect(_items('   > > a\n\n    > b\n\n>c\n\n>  d'), [
        const DocItem(line: 20, chars: 8, text: 'a', heading: false),
        const DocItem(line: 22, chars: 7, text: '> b', heading: false),
        const DocItem(line: 24, chars: 2, text: 'c', heading: false),
        const DocItem(line: 26, chars: 4, text: 'd', heading: false),
      ]);
    });
  });

  group('opensHeadingItem', () {
    test('holds for each line the item reader opens a heading item at', () {
      for (final line in ['### A', '###', '> ### A', '  > > ### A', '### ']) {
        expect(opensHeadingItem(line), isTrue, reason: line);
        expect(_items(line).single.heading, isTrue, reason: line);
      }
    });

    test('fails for a ###x line, a deeper or higher heading, and an '
        'indented code line', () {
      for (final line in [
        '###x',
        '#### A',
        '## A',
        '    ### A',
        ' ### A',
        '###\tA',
        'text',
      ]) {
        expect(opensHeadingItem(line), isFalse, reason: line);
      }
    });
  });
}
