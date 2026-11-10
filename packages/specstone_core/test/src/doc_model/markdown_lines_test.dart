import 'package:specstone_core/src/doc_model/markdown_lines.dart';
import 'package:test/test.dart';

void main() {
  group('atxHeadingOf', () {
    test('reads the level and the text of a heading', () {
      expect(atxHeadingOf('# Title'), (level: 1, text: 'Title'));
      expect(atxHeadingOf('## Section'), (level: 2, text: 'Section'));
      expect(atxHeadingOf('### Edge case. Two'), (
        level: 3,
        text: 'Edge case. Two',
      ));
      expect(atxHeadingOf('   ###### Deep'), (level: 6, text: 'Deep'));
    });

    test('drops a closing run of # and trailing spaces', () {
      expect(atxHeadingOf('#### Deeper ####'), (level: 4, text: 'Deeper'));
      expect(atxHeadingOf('### Foo  '), (level: 3, text: 'Foo'));
      expect(atxHeadingOf('### Foo#'), (level: 3, text: 'Foo#'));
    });

    test('reads a heading with no text as empty text', () {
      expect(atxHeadingOf('###'), (level: 3, text: ''));
    });

    test('reads no heading from a line that is none', () {
      expect(atxHeadingOf('#hashtag'), isNull);
      expect(atxHeadingOf('####### seven'), isNull);
      expect(atxHeadingOf('    ### indented code'), isNull);
      expect(atxHeadingOf('plain # text'), isNull);
    });
  });

  group('isTableDelimiterRow', () {
    test('accepts a delimiter row with or without edge pipes and colons', () {
      expect(isTableDelimiterRow('|---|---|'), isTrue);
      expect(isTableDelimiterRow('| :--- | :---: | ---: |'), isTrue);
      expect(isTableDelimiterRow('--- | ---'), isTrue);
      expect(isTableDelimiterRow('  |-|-|  '), isTrue);
    });

    test('rejects a row that holds text or no pipe', () {
      expect(isTableDelimiterRow('| a | b |'), isFalse);
      expect(isTableDelimiterRow('---'), isFalse);
      expect(isTableDelimiterRow(''), isFalse);
    });
  });
}
