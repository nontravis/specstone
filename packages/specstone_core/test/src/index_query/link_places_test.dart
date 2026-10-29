import 'package:specstone_core/src/index_query/link_blocks.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:test/test.dart';

void main() {
  group('linkPlacesOf', () {
    List<LinkPlace> placesOf(String body) =>
        linkPlacesOf(body, docPath: 'x.md', firstLine: 1)!;

    test('final-fix M1: a link is placed by its own href, whatever the links '
        'before it matched', () {
      final places = placesOf('[a](b\\.md)\n\n[u](z.md)\n\n[c](b.md)\n');

      expect(places.map((p) => p.target), ['b.md', 'z.md', 'b.md']);
      expect(places[1].line, 3);
    });

    test('final-fix M1: a use of a reference definition in a blockquote does '
        'not move the line of a later link', () {
      final places = placesOf(
        '> [d]: b.md\n\n[x][d]\n\n[u](z.md)\n\n[c](b.md)\n',
      );

      expect(places.map((p) => p.target), ['b.md', 'z.md', 'b.md']);
      expect(places[1].line, 5);
    });

    test(
      'final-fix M2: 10,000 links in one body are placed within two seconds',
      () {
        final body = List.filled(
          10000,
          'Some filler prose around the link [l](b.md) and more prose after.',
        ).join('\n\n');
        final watch = Stopwatch()..start();

        final places = placesOf(body);

        expect(places, hasLength(10000));
        expect(places.last.line, 19999);
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      },
    );

    test('final-fix M2: 10,000 unclosed brackets in one body are scanned '
        'within two seconds', () {
      final body =
          '${'[unclosed link text on its own line\n' * 10000}'
          '[l](b.md)\n';
      final watch = Stopwatch()..start();

      final places = placesOf(body);

      expect(places.map((p) => p.target), ['b.md']);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('final-fix M2: 10,000 definitions with an unclosed < destination are '
        'scanned within two seconds', () {
      final body = [
        for (var i = 0; i < 10000; i++) '[x$i]: <',
        '[l](b.md)',
        '',
      ].join('\n');
      final watch = Stopwatch()..start();

      final places = placesOf(body);

      expect(places.map((p) => p.target), ['b.md']);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('f04/us02/fr04, f04/nfr-p03, FN4: 10,000 brackets nested around one '
        'link are placed within one second', () {
      final body = '${'[' * 10000}x](b.md)${']' * 9999}\n';
      final watch = Stopwatch()..start();

      final places = placesOf(body);
      watch.stop();

      expect(places, [(target: 'b.md', line: 1, shown: 'b.md')]);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('f04/us02/fr04, f04/nfr-p03, FN4: 10,000 nested inline destinations '
        'are scanned within one second', () {
      final body = '${'[a](' * 10000}x${')' * 10000}\n\n[l](b.md)\n';
      final watch = Stopwatch()..start();

      final places = placesOf(body);
      watch.stop();

      expect(places, [(target: 'b.md', line: 3, shown: 'b.md')]);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('f04/us02/fr04, f04/nfr-p03, FN4: 10,000 escaped brackets before one '
        'close are scanned within one second', () {
      final body = '[${r'\[' * 10000}]\n\n[d]: b.md\n\n[l](b.md)\n';
      final watch = Stopwatch()..start();

      final places = placesOf(body);
      watch.stop();

      expect(places, [(target: 'b.md', line: 5, shown: 'b.md')]);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('f04/us02/fr04, f04/nfr-p03, FN4: 40,000 escaped openers sharing one '
        'close before a long destination are scanned within one second', () {
      final body = '[${r'\[' * 40000}](${' ' * 40000}zzzzz)\n\n[l](b.md)\n';
      final watch = Stopwatch()..start();

      final places = placesOf(body);
      watch.stop();

      expect(places, [(target: 'b.md', line: 3, shown: 'b.md')]);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('f04/us02/fr04, FN4: a reference whose text has blank runs and '
        'capitals is placed at its use', () {
      final places = placesOf('[foo bar]: b.md\n\n[Foo   Bar]\n');

      expect(places, [(target: 'b.md', line: 3, shown: 'b.md')]);
    });

    test('f04/us02/fr04, FN4: an angle-bracket destination with a space is '
        'placed at its use', () {
      final places = placesOf('x\n\n[a](<b c.md>)\n');

      expect(places, [(target: 'b c.md', line: 3, shown: 'b c.md')]);
    });

    test('f04/us02/fr04, FN4: a U+0085 inside an inline destination is not '
        'blank, so the use keeps it', () {
      final places = placesOf('[l](b\u0085c.md)\n');

      expect(places, [(target: 'b\u0085c.md', line: 1, shown: 'b\u0085c.md')]);
    });

    test('f04/us02/fr04, FN4: a shortcut use with a whitespace-only label '
        'does not fall back to the link text', () {
      final places = placesOf('[k]: .md\n[k][ ]\n[k]\n');

      expect(places, [(target: '.md', line: 3, shown: '.md')]);
    });

    test('f04/us02/fr04/e08, LP1: a link whose escape is not UTF-8 is placed '
        'at its line as written', () {
      final places = linkPlacesOf(
        'x\n\n[x](%DB.md)\n',
        docPath: 'prds/f/us/fr01.md',
        firstLine: 1,
      );

      expect(places, [
        (target: 'prds/f/us/\u{FFFD}.md', line: 3, shown: '%DB.md'),
      ]);
    });

    test('s03/inv24, LP2: a body the parser fails on gives null', () {
      final places = linkPlacesOf(
        '[s](b.md)\n\n[a]:<b\\',
        docPath: 'prds/f/us/fr01.md',
        firstLine: 1,
      );

      expect(places, isNull);
    });

    test('s03/inv24, LP2: a body with no link syntax is never parsed', () {
      final places = linkPlacesOf(
        '${'> ' * 2000}x',
        docPath: 'prds/f/us/fr01.md',
        firstLine: 1,
      );

      expect(places, isEmpty);
    });
  });

  group('look-alikes', () {
    List<LinkPlace> placesOf(String body, {int firstLine = 1}) =>
        linkPlacesOf(body, docPath: 'x.md', firstLine: firstLine)!;

    void placed(
      String name,
      String body,
      List<LinkPlace> expected, {
      int firstLine = 1,
    }) {
      test(name, () => expect(placesOf(body, firstLine: firstLine), expected));
    }

    placed(
      'f04/us02/fr04, LA1: an escaped bracket before a link is no use',
      '\\[a](b.md)\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA1: a link after an escaped bang is placed at its line',
      'x\n\\![a](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA1: a link inside link text leaves the outer brackets '
          'as text',
      '[a [x](y.md)](b.md)\n[c](b.md)\n',
      [
        (target: 'y.md', line: 1, shown: 'y.md'),
        (target: 'b.md', line: 2, shown: 'b.md'),
      ],
    );

    placed(
      'f04/us02/fr04, LA1: an opener a link turned off stays off after a '
          'later opener',
      '[a [b](c.md) [d] e](f.md)\n[g](f.md)\n',
      [
        (target: 'c.md', line: 1, shown: 'c.md'),
        (target: 'f.md', line: 2, shown: 'f.md'),
      ],
    );

    placed(
      'f04/us02/fr04, LA1: brackets inside a destination are no use',
      '[a](x[q](b.md))\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA1: a link in an image description is no use',
      '![x [a](b.md)](i.png)\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA1: a link in an image turns off the link around the '
          'image',
      '[![a [b](c.md)](i.png)](d.md)\n[e](d.md)\n',
      [(target: 'd.md', line: 2, shown: 'd.md')],
    );

    placed(
      'f04/us02/fr04, LA1: parens that hold no valid title make no use',
      '[a](b.md x)\n[d](b.md c.md)\n[c](b.md)\n',
      [(target: 'b.md', line: 3, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA3: brackets never pair across a blank line',
      '[a\n\nb](b.md)\n\n[c](b.md)\n',
      [(target: 'b.md', line: 5, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA1: a failed inline link falls back to its shortcut '
          'reference',
      'x\n[r](no link\n\n[r]: b.md\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA2: a tab stays in a bare destination, as markdown '
          'reads it',
      'x\n[a](b\tc.md)\n',
      [(target: 'b\tc.md', line: 2, shown: 'b\tc.md')],
    );

    placed(
      'f04/us02/fr04, LA2: a title after an open paren keeps the destination '
          'open, as markdown reads it',
      'x\n[a](b(c "t").md)\n',
      [(target: 'b(c.md', line: 2, shown: 'b(c.md')],
    );

    placed(
      'f04/us02/fr04, LA1: pin: emphasis delimiters around brackets change no '
          'link',
      '*[a*](b.md)\n[c](b.md)\n',
      [
        (target: 'b.md', line: 1, shown: 'b.md'),
        (target: 'b.md', line: 2, shown: 'b.md'),
      ],
    );

    placed(
      'f04/us02/fr04, LA1: pin: collapsed and shortcut references are placed '
          'at their uses',
      '[r][]\n[r]\n\n[r]: b.md\n',
      [
        (target: 'b.md', line: 1, shown: 'b.md'),
        (target: 'b.md', line: 2, shown: 'b.md'),
      ],
    );

    placed(
      'f04/us02/fr04, LA1: a body that starts after frontmatter keeps each '
          'link on its line',
      '\\[a](b.md)\n[c](b.md)\n',
      [(target: 'b.md', line: 6, shown: 'b.md')],
      firstLine: 5,
    );

    placed(
      'f04/us02/fr04, LA1: a code span of two backticks holds no use',
      '``[a](b.md)``\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA1: a code span over two lines holds no use',
      '`x\n[a](b.md)`\n[c](b.md)\n',
      [(target: 'b.md', line: 3, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA1: an escaped backtick opens no code span',
      '\\`[a](b.md)`\n[c](b.md)\n',
      [
        (target: 'b.md', line: 1, shown: 'b.md'),
        (target: 'b.md', line: 2, shown: 'b.md'),
      ],
    );

    // U+2028 is a code unit `.` does not match, so `markdown` ends no code span
    // at it unless it is the last code unit the span holds.
    final lineSeparator = String.fromCharCode(0x2028);

    placed(
      'f04/us02/fr04, LA2: a line separator inside backticks makes no code '
          'span, as markdown reads it',
      '`[a](b.md)${lineSeparator}x`\n[c](b.md)\n',
      [
        (target: 'b.md', line: 1, shown: 'b.md'),
        (target: 'b.md', line: 2, shown: 'b.md'),
      ],
    );

    placed(
      'f04/us02/fr04, LA2: a line separator may end a code span, as markdown '
          'reads it',
      '`[a](b.md)$lineSeparator`\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    test('f04/us02/fr04, LA2: a bare URL gives back the closing parens it '
        'does not balance, as markdown reads it', () {
      final sources = linkSourcesOf(
        'x\nhttp://a.b/))))))))(www.x.y)\n',
        firstLine: 1,
      );

      expect(sources.map((s) => (s.line, s.shown)), [(2, null), (2, null)]);
    });

    placed(
      'f04/us02/fr04, LA1: an autolink holds no use',
      '<http://x.y/[a](b.md)>\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA2: a bare URL runs through the brackets after it, as '
          'markdown reads it',
      'see http://x.y/[a](b.md)\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    placed(
      "f04/us02/fr04, LA2: a bare URL in link text runs through the link's "
          'close, as markdown reads it',
      '[see http://x.y/](b.md)\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA1: a raw HTML attribute holds no use',
      'x <span title="[a](b.md)">y</span>\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    test('f04/us02/fr04, LA1: an HTML comment holds no use, on one line or '
        'over lines', () {
      expect(placesOf('x <!-- [a](b.md) -->\n[c](b.md)\n'), [
        (target: 'b.md', line: 2, shown: 'b.md'),
      ]);
      expect(placesOf('x <!--\n[a](b.md)\n-->\n[c](b.md)\n'), [
        (target: 'b.md', line: 4, shown: 'b.md'),
      ]);
    });

    placed(
      'f04/us02/fr04, LA4: a destination with an entity is placed at its use',
      'x\n[a](b&#46;md)\n',
      [(target: 'b.md', line: 2, shown: 'b&#46;md')],
    );

    placed(
      'f04/us02/fr04, LA4: a destination with an escape is placed at its use',
      'x\n[a](b\\_c.md)\n',
      [(target: 'b_c.md', line: 2, shown: r'b\_c.md')],
    );

    placed(
      'f04/us02/fr04, LA4: pin: an email in link text leaves the link at its '
          'line',
      'x\n[a@b.md](c.md)\n',
      [(target: 'c.md', line: 2, shown: 'c.md')],
    );

    placed(
      'f04/us02/fr04, LA4: pin: a doc with a footnote takes the nth-use '
          'fallback',
      'x[^1]\n\n[^1]: see [a](b.md)\n\n[c](b.md)\n',
      [
        (target: 'b.md', line: 3, shown: 'b.md'),
        (target: 'b.md', line: 5, shown: 'b.md'),
      ],
    );

    placed(
      'f04/us02/fr04, LA4: pin: two forms of one doc keep their own lines and '
          'destinations',
      '[a](./b.md)\n[c](b.md)\n',
      [
        (target: 'b.md', line: 1, shown: './b.md'),
        (target: 'b.md', line: 2, shown: 'b.md'),
      ],
    );

    test('f04/us02/fr04, LA1: a code span in a reference label is part of the '
        'label', () {
      expect(linkSourcesOf('x\n[`a`]\n\n[`b`]: c.md\n', firstLine: 1), isEmpty);
      expect(
        linkSourcesOf(
          'x\n[`a`]\n\n[`a`]: c.md\n',
          firstLine: 1,
        ).map((s) => (s.line, s.shown)),
        [(2, 'c.md')],
      );
    });

    placed(
      'f04/us02/fr04, LA3: pin: an HTML comment block holds no use',
      '<!--\n[a](b.md)\n-->\n\n[c](b.md)\n',
      [(target: 'b.md', line: 5, shown: 'b.md')],
    );

    group('f04/us02/fr04, LA3: an HTML block runs to its end condition', () {
      placed(
        'a block of <details> runs to its closing tag',
        '<details>\n[a](b.md)\n</details>\n\n[c](b.md)\n',
        [(target: 'b.md', line: 5, shown: 'b.md')],
      );

      placed(
        'a block of an unknown tag runs to the next blank line',
        '<x-y>\n[a](b.md)\n\n[c](b.md)\n',
        [(target: 'b.md', line: 4, shown: 'b.md')],
      );

      placed(
        'a block of <pre> runs past a blank line to its closing tag',
        '<pre>\n\n[a](b.md)\n</pre>\n\n[c](b.md)\n',
        [(target: 'b.md', line: 6, shown: 'b.md')],
      );
    });

    test('f04/us02/fr04, LA3: an HTML block and an HTML start line right '
        'after it are one block', () {
      final sources = linkSourcesOf(
        '<!-- c -->\n<div>\n|---|\n[a](b.md)\n',
        firstLine: 1,
      );

      expect(sources, isEmpty);
    });

    placed(
      'f04/us02/fr04, LA3: pin: a tag line cannot interrupt a paragraph',
      'x\n<x-y>\n[a](b.md)\n',
      [(target: 'b.md', line: 3, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA3: an indented code block holds no use',
      '    [a](b.md)\n\n[c](b.md)\n',
      [(target: 'b.md', line: 3, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA3: pin: an indented line after a paragraph line is '
          'paragraph text',
      'x\n    [a](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA3: a definition-shaped line inside a paragraph '
          'defines nothing',
      'x\n[r]: b.md\n\n[d][r]\n[c](b.md)\n',
      [(target: 'b.md', line: 5, shown: 'b.md')],
    );

    group('f04/us02/fr04, LA3: a heading and a thematic break end the '
        'brackets before them', () {
      placed('a heading ends them', '# [a\nb](b.md)\n[c](b.md)\n', [
        (target: 'b.md', line: 3, shown: 'b.md'),
      ]);

      placed('a thematic break ends them', '[a\n***\nb](b.md)\n[c](b.md)\n', [
        (target: 'b.md', line: 4, shown: 'b.md'),
      ]);
    });

    placed(
      'f04/us02/fr04, LA3: pin: a fence ends the brackets before it',
      '[a\n```\nb](b.md)\n```\n[c](b.md)\n',
      [(target: 'b.md', line: 5, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA3: a table cell ends at an unescaped pipe',
      '| [a | b](b.md) |\n|---|---|\n\n[c](b.md)\n',
      [(target: 'b.md', line: 4, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA3: pin: an escaped pipe stays in its cell',
      '| [a \\| b](b.md) |\n|---|\n',
      [(target: 'b.md', line: 1, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA3: pin: a GFM list item takes a lone dash as markdown '
          'does, so the paragraph above it reads no link',
      'x\n\n[a](b.md)\n-\n\n[c](b.md)\n',
      [(target: 'b.md', line: 6, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA3: pin: a setext underline keeps the link above it',
      '[a](b.md)\n===\n[c](b.md)\n',
      [
        (target: 'b.md', line: 1, shown: 'b.md'),
        (target: 'b.md', line: 3, shown: 'b.md'),
      ],
    );

    placed(
      'f04/us02/fr04, LA3: pin: of two definitions of one label the first '
          'wins',
      '[t][r]\n\n[r]: b.md\n[r]: c.md\n',
      [(target: 'b.md', line: 1, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA3: pin: links in a heading and a table cell keep '
          'their lines',
      '# [a](b.md)\n\n| h |\n|---|\n| [c](b.md) |\n',
      [
        (target: 'b.md', line: 1, shown: 'b.md'),
        (target: 'b.md', line: 5, shown: 'b.md'),
      ],
    );

    placed(
      "f04/us02/fr04, LA3: pin: a definition's title on the next line is "
          'read with it',
      '[r]: b.md\n"t"\n[d][r]\n',
      [(target: 'b.md', line: 3, shown: 'b.md')],
    );

    void within(String name, String body, List<(int, String?)> expected) {
      test('f04/us02/fr04, f04/nfr-p03, LA6: $name within one second', () {
        final watch = Stopwatch()..start();

        final sources = linkSourcesOf(body, firstLine: 1);
        watch.stop();

        expect(sources.map((s) => (s.line, s.shown)), expected);
        expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      });
    }

    within(
      '10,000 unclosed bare destinations are scanned',
      '${'[a](b' * 10000}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 unclosed titles are scanned',
      '${'[a](b "t' * 10000}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 unclosed angle destinations are scanned',
      '${'[a](<b ' * 10000}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 openers before one close are scanned',
      'x ${'[a ' * 10000}](b.md)\n',
      [(1, 'b.md')],
    );

    within(
      '10,000 links in one image description are dropped',
      '![${'[x](b.md) ' * 10000}](i.png)\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 unclosed processing instructions are scanned',
      '${'x <? ' * 10000}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 unclosed declarations are scanned',
      '${'x <!X ' * 10000}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 unclosed comments are scanned',
      '${'x <!-- ' * 10000}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 unclosed autolinks are scanned',
      '${'<http://x' * 10000}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '400 backtick runs of growing length are scanned',
      '${List.generate(400, (i) => '${'`' * (i + 1)}a').join()}\n\n'
          '[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      'a 50,000-letter word with no @ is scanned',
      '${'a' * 50000}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 http URL starts after a letter are scanned',
      '${'xhttp://a.b' * 10000}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 www URL starts after a letter are scanned',
      '${'xwww.a.b' * 10000}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 HTML blocks are scanned',
      '${'<div>\n\n' * 10000}[l](b.md)\n',
      [(20001, 'b.md')],
    );

    within(
      '10,000 table rows are scanned',
      '| h |\n|---|\n${'| x |\n' * 10000}\n[l](b.md)\n',
      [(10004, 'b.md')],
    );

    within(
      '10,000 definitions with an unclosed paren title and a setext underline '
          'are scanned',
      '${'[r]: b.md (t\n===\n' * 10000}[l][r]\n',
      [],
    );

    within(
      '10,000 definitions with an unclosed title are scanned',
      '${'[r]: b.md "t\n\n' * 10000}[l](b.md)\n',
      [(20001, 'b.md')],
    );

    within('10,000 list items are scanned', '${'- x\n' * 10000}\n[l](b.md)\n', [
      (10002, 'b.md'),
    ]);

    within(
      '10,000 blockquote lines are scanned',
      '${'> x\n' * 10000}\n[l](b.md)\n',
      [(10002, 'b.md')],
    );
  });

  group('look-alikes in containers', () {
    List<LinkPlace> placesOf(String body) =>
        linkPlacesOf(body, docPath: 'x.md', firstLine: 1)!;

    void placed(String name, String body, List<LinkPlace> expected) {
      test(name, () => expect(placesOf(body), expected));
    }

    test('f04/us02/fr04, LA3: a definition in a blockquote or a list item is '
        'read', () {
      const expected = [
        (target: 'b.md', line: 3, shown: 'b.md'),
        (target: 'b.md', line: 4, shown: 'b.md'),
      ];

      expect(placesOf('> [r]: b.md\n\n[c](b.md)\n[d][r]\n'), expected);
      expect(placesOf('- [r]: b.md\n\n[c](b.md)\n[d][r]\n'), expected);
    });

    placed(
      'f04/us02/fr04, LA3: pin: a lazy line defines nothing',
      '- x\n[r]: b.md\n\n[t][r]\n[c](b.md)\n',
      [(target: 'b.md', line: 5, shown: 'b.md')],
    );

    test('f04/us02/fr04, LA3: list items end the brackets before them', () {
      expect(placesOf('- [a\n- b](b.md)\n- [c](b.md)\n'), [
        (target: 'b.md', line: 3, shown: 'b.md'),
      ]);
      expect(placesOf('x [a\n1. b](b.md)\n\n[c](b.md)\n'), [
        (target: 'b.md', line: 4, shown: 'b.md'),
      ]);
    });

    placed(
      'f04/us02/fr04, LA3: pin: an ordered item numbered 2 does not interrupt '
          'a paragraph',
      'x [a\n2. b](b.md)\n',
      [(target: 'b.md', line: 1, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA3: a checkbox is no shortcut reference',
      '- [x] task\n\n[x]: b.md\n\n[c](b.md)\n',
      [(target: 'b.md', line: 5, shown: 'b.md')],
    );

    placed(
      'f04/us02/fr04, LA3: indented code in a blockquote holds no use',
      '>     [a](b.md)\n\n[c](b.md)\n',
      [(target: 'b.md', line: 3, shown: 'b.md')],
    );

    test('f04/us02/fr04, LA3: pin: blockquote and list lines keep their '
        'links', () {
      expect(placesOf('> ```\n> [a](b.md)\n> ```\n\n[c](b.md)\n'), [
        (target: 'b.md', line: 5, shown: 'b.md'),
      ]);
      expect(placesOf('> [a](b.md\n> "t")\n\n[c](b.md)\n'), [
        (target: 'b.md', line: 1, shown: 'b.md'),
        (target: 'b.md', line: 4, shown: 'b.md'),
      ]);
      expect(placesOf('> [a\nb](b.md)\n'), [
        (target: 'b.md', line: 1, shown: 'b.md'),
      ]);
      expect(placesOf('- x\n\n    [a](b.md)\n'), [
        (target: 'b.md', line: 3, shown: 'b.md'),
      ]);
      expect(placesOf('- a\n  [b](c.md)\n'), [
        (target: 'c.md', line: 2, shown: 'c.md'),
      ]);
    });

    placed(
      'f04/us02/fr04, LA3: pin: links in a nested item and its continuation '
          'keep their lines',
      '- a\n  - [b](c.md)\n    [d](c.md)\n',
      [
        (target: 'c.md', line: 2, shown: 'c.md'),
        (target: 'c.md', line: 3, shown: 'c.md'),
      ],
    );
  });

  group('final-fix label and line folding', () {
    List<LinkPlace> placesOf(String body) =>
        linkPlacesOf(body, docPath: 'x.md', firstLine: 1)!;

    test('f04/us02/fr04, LA1: a label folds the blanks markdown folds and '
        'no other', () {
      expect(linkLabel('  A \t\r\n B  '), 'a b');
      for (final blank in ['\u00A0', '\v', '\f']) {
        expect(linkLabel('a${blank}b'), isNot(linkLabel('a b')), reason: blank);
      }
    });

    test('f04/us02/fr04, LA1: a label with a blank markdown does not fold '
        'matches no definition', () {
      for (final blank in ['\u00A0', '\v', '\f']) {
        expect(placesOf('[a${blank}b]\n[c](b.md)\n\n[a b]: b.md\n'), [
          (target: 'b.md', line: 2, shown: 'b.md'),
        ], reason: blank);
      }
    });

    test(
      'f04/us02/fr04, LA1: a lone CR ends a line as it does for markdown',
      () {
        expect(placesOf('```\r[a](b.md)\r```\n[c](b.md)\n'), [
          (target: 'b.md', line: 2, shown: 'b.md'),
        ]);
        expect(placesOf('    x\r    [a](b.md)\n\n[c](b.md)\n'), [
          (target: 'b.md', line: 3, shown: 'b.md'),
        ]);
        expect(placesOf('x\r[a](b.md)\n'), [
          (target: 'b.md', line: 1, shown: 'b.md'),
        ]);
      },
    );
  });
}
