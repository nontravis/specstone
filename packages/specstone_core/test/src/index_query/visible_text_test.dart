import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show parseMarkdownTreeByBlock;
import 'package:specstone_core/src/index_query/link_places.dart'
    show parserReadSourcesOf;
import 'package:specstone_core/src/index_query/link_scan.dart'
    show linkSourcesOf;
import 'package:specstone_core/src/index_query/visible_text.dart';
import 'package:test/test.dart';

/// The code points of file lines [first] to [last] of [body], the first file
/// line of which is [firstLine], with the line feeds that join them.
int rawCodePoints(String body, int first, int last, {int firstLine = 1}) => body
    .split('\n')
    .sublist(first - firstLine, last - firstLine + 1)
    .join('\n')
    .runes
    .length;

/// What a reader sees of file lines [first] to [last] of [body]: its raw code
/// points less the ones the links and definitions of [body] hide.
int visibleCodePoints(String body, int first, int last, {int firstLine = 1}) =>
    rawCodePoints(body, first, last, firstLine: firstLine) -
    HiddenText.of(body, firstLine: firstLine).codePointsOn(first, last);

void main() {
  group('HiddenText', () {
    test('long item counts its link text alone', () {
      final links = [
        for (var i = 0; i < 8; i++) '[link](${'a' * 17}.md)',
        '[link](${'b' * 7}.md)',
      ];
      final head = '- ${links.join(' ')} ';
      final item = '$head${'x' * (625 - head.length)}';

      expect(item.length, 625);
      expect(HiddenText.of(item, firstLine: 1).codePointsOn(1, 1), 206);
      expect(visibleCodePoints(item, 1, 1), 419);
    });

    test('inline link keeps its text', () {
      expect(visibleCodePoints('- See [the rule](a/b.md#rules).\n', 1, 1), 15);
    });

    test('definition line hides with its line feed', () {
      const body = '[r]: a/b.md\nSee [the rule][r].\n';

      expect(visibleCodePoints(body, 1, 2), 13);
      expect(visibleCodePoints(body, 2, 2), 13);
      expect(visibleCodePoints(body, 1, 1), 0);
    });

    test('definition at the end of the body has no line feed to hide', () {
      const body = 'See [r].\n\n[r]: a.md';

      expect(visibleCodePoints(body, 3, 3), 0);
      expect(visibleCodePoints(body, 1, 3), 8);
    });

    test('definition inside a blockquote keeps the marker', () {
      const body = '> [r]: a/b.md\n> See [r].\n';

      expect(HiddenText.of(body, firstLine: 1).codePointsOn(1, 1), 11);
      expect(visibleCodePoints(body, 1, 2), 10);
    });

    test('code span keeps link-shaped text', () {
      expect(visibleCodePoints('- Run `[a](b.md)` once.\n', 1, 1), 23);
    });

    test('failed parse hides nothing', () {
      const body = '[a](b.md)\n\n[a]:<b\\';

      expect(HiddenText.of(body, firstLine: 1).codePointsOn(1, 3), 0);
      expect(visibleCodePoints(body, 1, 1), 9);
    });

    test('shortcut reference keeps its label', () {
      expect(visibleCodePoints('[r]: a/b.md\nSee [r].\n', 1, 2), 6);
    });

    test('undefined shortcut keeps every bracket', () {
      const body = '- See [x].\n- See [a](b.md).\n';

      expect(visibleCodePoints(body, 1, 1), 10);
      expect(visibleCodePoints(body, 2, 2), 8);
    });

    test('definition-shaped paragraph line counts', () {
      expect(visibleCodePoints('See this.\n[r]: a/b.md\n', 1, 2), 21);
    });

    test('autolink and bare url count whole', () {
      const body = '- <https://a.b/c> https://d.e/f\n';

      expect(HiddenText.of(body, firstLine: 1).codePointsOn(1, 1), 0);
      expect(visibleCodePoints(body, 1, 1), 31);
    });

    test('image keeps its alt', () {
      expect(visibleCodePoints('![alt text](a.png)\n', 1, 1), 8);
    });

    test('full and collapsed reference keep their text', () {
      const body = '[r]: a.md\n\n[full text][r] and [r][].\n';

      expect(visibleCodePoints(body, 3, 3), 16);
    });

    test('astral link text counts one per code point', () {
      expect(visibleCodePoints('- [😀😀](a.md)\n', 1, 1), 4);
      expect(HiddenText.of('[a](😀.md)\n', firstLine: 1).codePointsOn(1, 1), 8);
    });

    test('link text across a line feed drops both brackets', () {
      const body = 'See [the\nrule](a.md) now.\n';
      final hidden = HiddenText.of(body, firstLine: 1);

      expect(hidden.codePointsOn(1, 1), 1);
      expect(hidden.codePointsOn(2, 2), 7);
      expect(hidden.codePointsOn(1, 2), 8);
    });

    test('image inside link text drops each mark once', () {
      expect(visibleCodePoints('[![alt](i.png)](a.md)\n', 1, 1), 3);
    });

    test('table cell link drops its destination', () {
      const body = '| h1 | h2 |\n| --- | --- |\n| [a](b.md) | c |\n';

      expect(HiddenText.of(body, firstLine: 1).codePointsOn(3, 3), 8);
      expect(visibleCodePoints(body, 3, 3), 9);
    });

    test('lines read from the first file line of the body', () {
      const body = 'See [a](b.md).\nAnd [c](d.md).\n';
      final hidden = HiddenText.of(body, firstLine: 5);

      expect(hidden.codePointsOn(5, 5), 8);
      expect(hidden.codePointsOn(6, 6), 8);
      expect(hidden.codePointsOn(5, 6), 16);
    });

    test('a body with no link syntax hides nothing', () {
      expect(
        HiddenText.of('Plain [text].\n', firstLine: 1).codePointsOn(1, 1),
        0,
      );
      expect(HiddenText.none.codePointsOn(1, 9), 0);
    });
  });

  group('parserReadSourcesOf', () {
    List<String?> readIn(String body, {required String parsed}) => [
      for (final source in parserReadSourcesOf(
        linkSourcesOf(body, firstLine: 1),
        parseMarkdownTreeByBlock(parsed)!,
      ))
        source.shown,
    ];

    test('scan-only link hides nothing when readers disagree', () {
      // A tree of other text stands in for a markdown reading the scan misses.
      expect(readIn('[a](a.md) [c](c.md)\n', parsed: '[a](a.md)\n'), ['a.md']);
      expect(readIn('[a](x.md) [b](x.md)\n', parsed: '[a](x.md)\n'), ['x.md']);
    });

    test('readers that agree give every link the parser reads', () {
      const body = '[a](a.md) ![i](b.png) <https://c.d>\n';

      expect(readIn(body, parsed: body), ['a.md', 'b.png', null]);
    });

    test('link of a dropped footnote definition is no parser-read source', () {
      const body = '[^1]: [b](b.md)\n\n[a](a.md)\n';

      expect(readIn(body, parsed: body), ['a.md']);
    });
  });
}
