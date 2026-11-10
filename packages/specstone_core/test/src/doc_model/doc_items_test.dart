import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:test/test.dart';

const _firstLine = 20;

/// Builds the body lines of [text], numbered from [_firstLine], with the
/// lines of a ``` fence, fences included, marked fenced.
List<BodyLine> _body(String text) {
  var inFence = false;
  return [
    for (final (k, line) in text.split('\n').indexed)
      (
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

List<DocItem> _items(String text) => itemsOf(_body(text));

void main() {
  group('doc_model/doc_items itemsOf', () {
    test('index_query/view_docs_tree/print_docs_tree E09: a list item '
        'counts without its nested items and a nested item alone', () {
      final items = _items(
        '- parent one\n'
        '  carries on\n'
        '  - child\n'
        '- second',
      );

      expect(items, [
        (line: 20, chars: 25, text: 'parent one', heading: false),
        (line: 22, chars: 9, text: 'child', heading: false),
        (line: 23, chars: 8, text: 'second', heading: false),
      ]);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: an ordered item '
        'reads its text after the marker', () {
      expect(_items('1. first\n2) second'), [
        (line: 20, chars: 8, text: 'first', heading: false),
        (line: 21, chars: 9, text: 'second', heading: false),
      ]);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: a table row '
        'below the delimiter row is an item, the header and delimiter '
        'rows are none', () {
      final items = _items(
        '| ID | Name |\n'
        '|---|---|\n'
        '| a | b |\n'
        '| c | d |\n'
        '\n'
        'after the table',
      );

      expect(items, [
        (line: 22, chars: 9, text: '| a | b |', heading: false),
        (line: 23, chars: 9, text: '| c | d |', heading: false),
        (line: 25, chars: 15, text: 'after the table', heading: false),
      ]);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: a paragraph is '
        'one item across its lines', () {
      final items = _items(
        'alpha beta\n'
        'gamma\n'
        '\n'
        'delta',
      );

      expect(items, [
        (line: 20, chars: 16, text: 'alpha beta', heading: false),
        (line: 23, chars: 5, text: 'delta', heading: false),
      ]);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: a ### heading '
        'counts with the paragraph under it and never its bullets', () {
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
        (line: 20, chars: 39, text: 'Scenario 1', heading: true),
        (line: 23, chars: 12, text: 'bullet one', heading: false),
        (line: 25, chars: 14, text: 'Scenario 2', heading: true),
        (line: 27, chars: 12, text: 'bullet two', heading: false),
      ]);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: a blockquote '
        'paragraph and list item are items as anywhere else', () {
      final items = _items(
        '> quoted paragraph\n'
        '>\n'
        '> - quoted item',
      );

      expect(items, [
        (line: 20, chars: 18, text: 'quoted paragraph', heading: false),
        (line: 22, chars: 15, text: 'quoted item', heading: false),
      ]);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: a fenced code '
        'block is no item', () {
      final items = _items(
        '- before\n'
        '```dart\n'
        '- not an item\n'
        '```\n'
        '- after',
      );

      expect(items, [
        (line: 20, chars: 8, text: 'before', heading: false),
        (line: 24, chars: 7, text: 'after', heading: false),
      ]);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: an item holding '
        'an emoji counts a surrogate pair once', () {
      final items = _items(
        '- \u{1F600} smile\n'
        '  \u{1F600}\u{1F600}',
      );

      // "- 😀 smile" is 9 code points, "  😀😀" is 4, one line feed.
      expect(items, [
        (line: 20, chars: 14, text: '\u{1F600} smile', heading: false),
      ]);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: a fence inside '
        'a list item ends the item and the text after it is its own '
        'item', () {
      final items = itemsOf([
        (text: '- item', line: 20, fenced: false),
        (text: '  ```', line: 21, fenced: true),
        (text: '  - code', line: 22, fenced: true),
        (text: '  ```', line: 23, fenced: true),
        (text: '  more', line: 24, fenced: false),
      ]);

      expect(items, [
        (line: 20, chars: 6, text: 'item', heading: false),
        (line: 24, chars: 6, text: 'more', heading: false),
      ]);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: a fence inside '
        'a blockquote is no item', () {
      final items = itemsOf([
        (text: '> ```', line: 20, fenced: true),
        (text: '> - code', line: 21, fenced: true),
        (text: '> ```', line: 22, fenced: true),
      ]);

      expect(items, isEmpty);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: rows with no '
        'delimiter row are one paragraph', () {
      expect(_items('| a | b |\n| c | d |'), [
        (line: 20, chars: 19, text: '| a | b |', heading: false),
      ]);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: a #### line '
        'reads as paragraph text', () {
      expect(_items('#### Deep\nparagraph'), [
        (line: 20, chars: 19, text: '#### Deep', heading: false),
      ]);
    });

    test('index_query/view_docs_tree/print_docs_tree E09: an empty body '
        'holds no item', () {
      expect(_items(''), isEmpty);
    });

    test('doc_model/doc_items E09: a thematic break is no item and ends the '
        'paragraph above it', () {
      expect(_items('first\n***\nsecond'), [
        (line: 20, chars: 5, text: 'first', heading: false),
        (line: 22, chars: 6, text: 'second', heading: false),
      ]);
      expect(_items('one\n\n---\n\ntwo'), [
        (line: 20, chars: 3, text: 'one', heading: false),
        (line: 24, chars: 3, text: 'two', heading: false),
      ]);
      expect(_items('* * *\n- - -\n> ---\n_ _ _'), isEmpty);
    });
  });
}
