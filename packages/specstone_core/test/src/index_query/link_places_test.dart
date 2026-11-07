import 'dart:math';

import 'package:specstone_core/src/doc_model/markdown_body.dart'
    show parseMarkdownTree;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show DestinationKind;
import 'package:specstone_core/src/index_query/link_blocks.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/index_query/link_scan.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:test/test.dart';

void main() {
  group('linkScanOf', () {
    const body =
        '[RULE-7a](https://github.com/x/y/blob/main/RULE-7a.md) and '
        '<https://example.com/RULE-7a>\n'
        '[file](./RULE-7a.md) `RULE-7a` <a href="https://x/RULE-7a">RULE-7a</a> '
        '<!-- RULE-7a --> https://example.com/RULE-7a\n'
        '\n'
        '[RULE-7a]: https://example.com/RULE-7a\n'
        '\n'
        '    RULE-7a indented\n'
        '\n'
        'x `a\n'
        'RULE-7a` y [t][RULE-7a]\n';

    test('apply_steps_and_pins E18: prose keeps link text, html element '
        'text, and labels, and blanks destinations, autolinks, bare URLs, '
        'html tags and comments, indented code, and code spans', () {
      final scan = linkScanOf(body, firstLine: 1);

      expect(scan.prose.length, body.length);
      expect('\n'.allMatches(scan.prose).length, '\n'.allMatches(body).length);
      final kept = [
        for (final m in 'RULE-7a'.allMatches(scan.prose))
          body.substring(0, m.start).split('\n').length,
      ];
      expect(kept, [1, 2, 4, 9]);
      expect(scan.sources, linkSourcesOf(body, firstLine: 1));
    });

    test('apply_steps_and_pins E18: destinations are each inline link and '
        'definition destination as written', () {
      final scan = linkScanOf(body, firstLine: 1);

      expect(
        [
          for (final (:start, :end, link: _, kind: _) in scan.destinations)
            body.substring(start, end),
        ]..sort(),
        [
          './RULE-7a.md',
          'https://example.com/RULE-7a',
          'https://github.com/x/y/blob/main/RULE-7a.md',
        ],
      );
    });

    test('apply_steps_and_pins E18: an angle destination is ranged without '
        'its brackets', () {
      const angled = '[a](<b c.md#x> "t")\n';
      final scan = linkScanOf(angled, firstLine: 1);

      expect(
        [
          for (final (:start, :end, link: _, kind: _) in scan.destinations)
            angled.substring(start, end),
        ],
        ['b c.md#x'],
      );
      expect(scan.prose.trimRight(), '[a]');
    });

    test('R73: each inline destination names the index of its link, and a '
        'definition destination or one in an image description names none', () {
      const linked = '[a](a.md) ![i [b](b.md)](c.png) [d][r]\n\n[r]: d.md\n';
      final scan = linkScanOf(linked, firstLine: 1);

      expect(
        {
          for (final (:start, :end, :link, kind: _) in scan.destinations)
            linked.substring(start, end): link,
        },
        {'a.md': 0, 'b.md': null, 'c.png': 1, 'd.md': null},
      );
    });

    test('R74: each destination names how markdown reads it: inline, inline '
        'in angle brackets, or a definition, bare or in angle brackets', () {
      const linked =
          '[a](a.md) [b](<b.md>) ![i [c](c.md)](d.png)\n\n'
          '[r]: r.md\n[s]: <s.md>\n';
      final scan = linkScanOf(linked, firstLine: 1);

      expect(
        {
          for (final (:start, :end, link: _, :kind) in scan.destinations)
            linked.substring(start, end): kind,
        },
        {
          'a.md': DestinationKind.inline,
          'b.md': DestinationKind.angleInline,
          'c.md': DestinationKind.inline,
          'd.png': DestinationKind.inline,
          'r.md': DestinationKind.definition,
          's.md': DestinationKind.definition,
        },
      );
    });
  });

  group('sourceHrefsOf', () {
    List<String?>? hrefsOf(String body) =>
        sourceHrefsOf(body, linkSourcesOf(body, firstLine: 1));

    test('R73: gives each source the href markdown decodes for its link, a '
        'definition destination read in its own grammar', () {
      expect(
        hrefsOf(
          '[a](A\\_B.md) [b](API&#46;md) [c][m] [d](a( "t")b.md)\n\n'
          '[m]: API.md)\n',
        ),
        ['A_B.md', 'API.md', 'API.md)', 'a(b.md'],
      );
    });

    test('R73: gives none for a body with no links, and null when markdown '
        'fails on it', () {
      expect(hrefsOf('No links.\n'), isEmpty);
      expect(hrefsOf('[x](a.md)\n\n[a]:<b\\'), isNull);
    });

    test('R74: pairs the links of a footnote definition where it is written, '
        'those of one no reference names taking none', () {
      expect(
        hrefsOf(
          'See [a](../topics/doc_model.md).\n\n'
          '[^1]: Also [b](other.md).\n',
        ),
        ['../topics/doc_model.md', null],
      );
      expect(
        hrefsOf(
          '[^1]: Also [b](other.md).\n\n'
          'See [a](../topics/doc_model.md) and a note[^1].\n',
        ),
        ['other.md', '../topics/doc_model.md'],
      );
      expect(
        hrefsOf(
          'See [a](../topics/doc_model.md), x[^2] y[^1].\n\n'
          '[^1]: [p](p.md)\n[^2]: [q](q.md)\n',
        ),
        ['../topics/doc_model.md', 'p.md', 'q.md'],
      );
      expect(hrefsOf('[^1]: n [b](other.md)\nx[^1] [c](d.md)\n'), [
        'other.md',
        'd.md',
      ]);
    });

    test('R74: reads a footnote definition as the block markdown makes it: '
        'it ends a paragraph, ends at a block line, and takes an indented one '
        'after a blank', () {
      expect(hrefsOf('[^1]: n\n[ss]: z.md\n\nx [q][ẞ] [a](a.md)\n'), [
        'z.md',
        'a.md',
      ]);
      expect(hrefsOf('x [a](a.md "t\n[^1]: u") [c](c.md)\n\ny[^1]\n'), [
        'c.md',
      ]);
      expect(hrefsOf('[^1]: n\n\n    [c](c.md)\n\n[d](d.md) y[^1]\n'), [
        'c.md',
        'd.md',
      ]);
    });

    test('R74: reads a footnote reference in link text as markdown does: a '
        "[^1] turns the link off, an image's ![^1] keeps it", () {
      expect(hrefsOf('x [s [^1]](b.md) [a](a.md)\n\n[^1]: n\n'), ['a.md']);
      expect(hrefsOf('x [s ![^1]](b.md)\n\n[^1]: n\n'), ['b.md']);
      expect(hrefsOf('x [s [q][^1]](b.md)\n\n[^1]: n\n'), <String>[]);
      expect(hrefsOf('x [s [^2]](b.md)\n\n[^1]: n\n'), ['b.md']);
    });

    test('R73: reads a reference link where markdown folds its label to a '
        'definition label, and only there', () {
      String body(String reference, String definition) =>
          'See [a](t.md) and [q][$reference].\n\n[$definition]: u.md\n';

      expect(hrefsOf(body('Œuvre', 'œuvre')), ['t.md']);
      expect(hrefsOf(body('ẞ', 'ss')), ['t.md', 'u.md']);
      expect(hrefsOf(body('Ĳ', 'ĳ')), ['t.md']);
      expect(hrefsOf(body('𐐨', '𐐀')), ['t.md']);
      expect(hrefsOf(body('ÄRGER', 'ärger')), ['t.md', 'u.md']);
    });
  });

  group('hrefDestinationsOf', () {
    HrefDestinations readOf(String body) =>
        hrefDestinationsOf(body, linkScanOf(body, firstLine: 1));
    List<(String, String)> placedOf(String body) => [
      for (final (:start, :end, :href, kind: _) in readOf(body).destinations)
        (body.substring(start, end), href),
    ];

    test('R73: an inline destination takes its link href and a definition '
        'its own, used or not', () {
      expect(
        placedOf('[a](f01\\_a/A.md#x)\n\n[r]: f01&#95;a/B.md\n[u]: a(b.md\n'),
        [
          (r'f01\_a/A.md#x', 'f01_a/A.md#x'),
          ('f01&#95;a/B.md', 'f01_a/B.md'),
          ('a(b.md', 'a(b.md'),
        ],
      );
    });

    test('R73: a destination of no link and no definition, or a body '
        'markdown fails on, places none', () {
      expect(placedOf('![i [b](b.md)](c.png)\n'), [('c.png', 'c.png')]);
      expect(placedOf('No links.\n'), isEmpty);
      expect(placedOf('[x](a.md)\n\n[a]:<b\\'), isEmpty);
    });

    test('R74: an inline destination of no link borrows no definition href '
        'written alike', () {
      const body = '![i [b](b.md)](c.png)\n\n[d]: b.md\n';

      expect(
        [
          for (final (:start, end: _, href: _, kind: _) in readOf(
            body,
          ).destinations)
            start,
        ],
        [body.indexOf('c.png'), body.lastIndexOf('b.md')],
      );
    });

    test('R74: the links read unless markdown fails on the body', () {
      expect(readOf('[x](a.md)\n').linksRead, isTrue);
      expect(readOf('No links.\n').linksRead, isTrue);
      expect(readOf('[x](a.md)\n\n[a]:<b\\').linksRead, isFalse);
    });
  });

  group('linkPlacesOf', () {
    List<LinkPlace> placesOf(String body) =>
        linkPlacesOf(body, docPath: 'x.md', firstLine: 1)!.docLinks;

    test('R74: says whether the scan and markdown list the same links', () {
      const body = '[^1]: [b](b.md)\n\n[a](a.md) [q][ẞ]\n\n[ss]: c.md\n';
      bool agreeOn(String body, {String? parsed}) => linkPlacesOf(
        body,
        docPath: 'x.md',
        firstLine: 1,
        tree: parsed == null ? null : parseMarkdownTree(parsed),
      )!.readersAgree;

      expect(agreeOn(body), isTrue);
      expect(agreeOn('No links.\n'), isTrue);
      // A tree of other text stands in for a markdown reading the scan misses.
      expect(agreeOn(body, parsed: '[a](a.md)\n'), isFalse);
    });

    test('f04/us02/fr04/e15-e16, e21-e22, PS-R3: each link class carries its '
        'line, shown text, and decoded anchor', () {
      final places = linkPlacesOf(
        '[a](b.md#x)\n[s](#rules)\n[t](x.md)\n'
        '[u](http://h:abc/x.md)\n[f](img.png)\n',
        docPath: 'x.md',
        firstLine: 1,
      )!;

      expect(places.docLinks, [
        (target: 'b.md', line: 1, shown: 'b.md#x', anchor: 'x'),
      ]);
      expect(places.selfLinks, [
        (target: 'x.md', line: 2, shown: '#rules', anchor: 'rules'),
        (target: 'x.md', line: 3, shown: 'x.md', anchor: null),
      ]);
      expect(places.unreadableLinks, [
        (
          target: 'http://h:abc/x.md',
          line: 4,
          shown: 'http://h:abc/x.md',
          anchor: null,
        ),
      ]);
      expect(places.fileLinks, [
        (target: 'img.png', line: 5, shown: 'img.png', anchor: null),
      ]);
    });

    test('resolve_doc_links E18: an empty path with no anchor, [x]() or '
        '[x](?q), is a self link with no anchor', () {
      final places = linkPlacesOf(
        '[a]() and [b](?q)\n',
        docPath: 'x.md',
        firstLine: 1,
      )!;

      expect(places.selfLinks, [
        (target: 'x.md', line: 1, shown: '', anchor: null),
        (target: 'x.md', line: 1, shown: '?q', anchor: null),
      ]);
    });

    test('consistency_check/find_broken_pointers/resolve_doc_links E16: the '
        'links markdown makes for a footnote are no link the author wrote', () {
      final footnoteOnly = linkPlacesOf(
        'A claim.[^1]\n\n[^1]: The source.\n',
        docPath: 'x.md',
        firstLine: 1,
      )!;
      expect(footnoteOnly.selfLinks, isEmpty);

      final written = linkPlacesOf(
        'A claim.[^1] See [x](#fn-1).\n\n[^1]: The source.\n',
        docPath: 'x.md',
        firstLine: 3,
      )!;
      expect(written.selfLinks, [
        (target: 'x.md', line: 3, shown: '#fn-1', anchor: 'fn-1'),
      ]);
    });

    test(
      'f04/us02/fr04/e10-e14, PS-R3: every relative link that is no doc link '
      'is a file link, placed at its line with the path it reaches',
      () {
        final places = linkPlacesOf(
          '[a](b.md)\n\n![f](flow%20chart.png#top) [r](a.png?raw=1)\n\n'
          '[g](../../../x/g.dart) [w](https://e.com) [m](mailto:a@b.c) '
          '[abs](/abs/x.md) [s](#top) [me](FEATURE.md)\n',
          docPath: 'prds/f/FEATURE.md',
          firstLine: 1,
        )!;

        expect(places.docLinks.map((p) => p.target), ['prds/f/b.md']);
        expect(places.fileLinks, [
          (
            target: 'prds/f/flow chart.png',
            line: 3,
            shown: 'flow%20chart.png#top',
            anchor: null,
          ),
          (target: 'prds/f/a.png', line: 3, shown: 'a.png?raw=1', anchor: null),
          (
            target: '../x/g.dart',
            line: 5,
            shown: '../../../x/g.dart',
            anchor: null,
          ),
        ]);
      },
    );

    test('f04/us02/fr04/e14, PS-R3: a .md link above the docs root is a file '
        'link', () {
      final places = linkPlacesOf(
        '[o](../../../o.md)\n',
        docPath: 'prds/f/FEATURE.md',
        firstLine: 1,
      )!;

      expect(places.docLinks, isEmpty);
      expect(places.fileLinks.single.target, '../o.md');
    });

    test('f04/us02/fr04/e10, PS-R3: a link read by use keeps its class', () {
      // `\.` makes the scan and `markdown` disagree, so the nth use of an href
      // places the link.
      final places = linkPlacesOf(
        '[a](b\\.png)\n\n[u](z.md)\n\n[c](b.png)\n',
        docPath: 'x.md',
        firstLine: 1,
      )!;

      expect(places.docLinks.map((p) => p.target), ['z.md']);
      expect(places.fileLinks.map((p) => p.target), ['b.png', 'b.png']);
    });

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
      'final-fix M2: 10,000 links in one body are placed in linear time',
      () {
        String bodyOf(int n) => List.filled(
          n,
          'Some filler prose around the link [l](b.md) and more prose after.',
        ).join('\n\n');

        final places = placesOf(bodyOf(10000));

        expect(places, hasLength(10000));
        expect(places.last.line, 19999);
        expectLinearTime(bodyOf, 10000, placesOf);
      },
    );

    test('final-fix M2: 10,000 unclosed brackets in one body are scanned '
        'in linear time', () {
      String bodyOf(int n) =>
          '${'[unclosed link text on its own line\n' * n}'
          '[l](b.md)\n';

      final places = placesOf(bodyOf(10000));

      expect(places.map((p) => p.target), ['b.md']);
      expectLinearTime(bodyOf, 10000, placesOf);
    });

    test('final-fix M2: 10,000 definitions with an unclosed < destination are '
        'scanned in linear time', () {
      String bodyOf(int n) =>
          [for (var i = 0; i < n; i++) '[x$i]: <', '[l](b.md)', ''].join('\n');

      final places = placesOf(bodyOf(10000));

      expect(places.map((p) => p.target), ['b.md']);
      expectLinearTime(bodyOf, 10000, placesOf);
    });

    test('f04/us02/fr04, f04/nfr-p03, FN4: 10,000 brackets nested around one '
        'link are placed in linear time', () {
      String bodyOf(int n) => '${'[' * n}x](b.md)${']' * (n - 1)}\n';

      final places = placesOf(bodyOf(10000));

      expect(places, [(target: 'b.md', line: 1, shown: 'b.md', anchor: null)]);
      expectLinearTime(bodyOf, 10000, placesOf);
    });

    test('f04/us02/fr04, f04/nfr-p03, FN4: 10,000 nested inline destinations '
        'are scanned in linear time', () {
      String bodyOf(int n) => '${'[a](' * n}x${')' * n}\n\n[l](b.md)\n';

      final places = placesOf(bodyOf(10000));

      expect(places, [(target: 'b.md', line: 3, shown: 'b.md', anchor: null)]);
      expectLinearTime(bodyOf, 10000, placesOf);
    });

    test('f04/us02/fr04, f04/nfr-p03, FN4: 10,000 escaped brackets before one '
        'close are scanned in linear time', () {
      String bodyOf(int n) => '[${r'\[' * n}]\n\n[d]: b.md\n\n[l](b.md)\n';

      final places = placesOf(bodyOf(10000));

      expect(places, [(target: 'b.md', line: 5, shown: 'b.md', anchor: null)]);
      expectLinearTime(bodyOf, 10000, placesOf);
    });

    test('f04/us02/fr04, f04/nfr-p03, FN4: 40,000 escaped openers sharing one '
        'close before a long destination are scanned in linear time', () {
      String bodyOf(int n) => '[${r'\[' * n}](${' ' * n}zzzzz)\n\n[l](b.md)\n';

      final places = placesOf(bodyOf(40000));

      expect(places, [(target: 'b.md', line: 3, shown: 'b.md', anchor: null)]);
      expectLinearTime(bodyOf, 40000, placesOf);
    });

    test('f04/us02/fr04, FN4: a reference whose text has blank runs and '
        'capitals is placed at its use', () {
      final places = placesOf('[foo bar]: b.md\n\n[Foo   Bar]\n');

      expect(places, [(target: 'b.md', line: 3, shown: 'b.md', anchor: null)]);
    });

    test('f04/us02/fr04, FN4: an angle-bracket destination with a space is '
        'placed at its use', () {
      final places = placesOf('x\n\n[a](<b c.md>)\n');

      expect(places, [
        (target: 'b c.md', line: 3, shown: 'b c.md', anchor: null),
      ]);
    });

    test('f04/us02/fr04, FN4: a U+0085 inside an inline destination is not '
        'blank, so the use keeps it', () {
      final places = placesOf('[l](b\u0085c.md)\n');

      expect(places, [
        (target: 'b\u0085c.md', line: 1, shown: 'b\u0085c.md', anchor: null),
      ]);
    });

    test('f04/us02/fr04, FN4: a shortcut use with a whitespace-only label '
        'does not fall back to the link text', () {
      final places = placesOf('[k]: .md\n[k][ ]\n[k]\n');

      expect(places, [(target: '.md', line: 3, shown: '.md', anchor: null)]);
    });

    test('f04/us02/fr04/e08, LP1: a link whose escape is not UTF-8 is placed '
        'at its line as written', () {
      final places = linkPlacesOf(
        'x\n\n[x](%DB.md)\n',
        docPath: 'prds/f/us/fr01.md',
        firstLine: 1,
      );

      expect(places!.docLinks, [
        (
          target: 'prds/f/us/\u{FFFD}.md',
          line: 3,
          shown: '%DB.md',
          anchor: null,
        ),
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

      expect(places!.docLinks, isEmpty);
      expect(places.fileLinks, isEmpty);
    });
  });

  group('look-alikes', () {
    List<LinkPlace> placesOf(String body, {int firstLine = 1}) =>
        linkPlacesOf(body, docPath: 'x.md', firstLine: firstLine)!.docLinks;

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
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA1: a link after an escaped bang is placed at its line',
      'x\n\\![a](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA1: a link inside link text leaves the outer brackets '
          'as text',
      '[a [x](y.md)](b.md)\n[c](b.md)\n',
      [
        (target: 'y.md', line: 1, shown: 'y.md', anchor: null),
        (target: 'b.md', line: 2, shown: 'b.md', anchor: null),
      ],
    );

    placed(
      'f04/us02/fr04, LA1: an opener a link turned off stays off after a '
          'later opener',
      '[a [b](c.md) [d] e](f.md)\n[g](f.md)\n',
      [
        (target: 'c.md', line: 1, shown: 'c.md', anchor: null),
        (target: 'f.md', line: 2, shown: 'f.md', anchor: null),
      ],
    );

    placed(
      'f04/us02/fr04, LA1: brackets inside a destination are no use',
      '[a](x[q](b.md))\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA1: a link in an image description is no use',
      '![x [a](b.md)](i.png)\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA1: a link in an image turns off the link around the '
          'image',
      '[![a [b](c.md)](i.png)](d.md)\n[e](d.md)\n',
      [(target: 'd.md', line: 2, shown: 'd.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA1: parens that hold no valid title make no use',
      '[a](b.md x)\n[d](b.md c.md)\n[c](b.md)\n',
      [(target: 'b.md', line: 3, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA3: brackets never pair across a blank line',
      '[a\n\nb](b.md)\n\n[c](b.md)\n',
      [(target: 'b.md', line: 5, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA1: a failed inline link falls back to its shortcut '
          'reference',
      'x\n[r](no link\n\n[r]: b.md\n',
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA2: a tab stays in a bare destination, as markdown '
          'reads it',
      'x\n[a](b\tc.md)\n',
      [(target: 'b\tc.md', line: 2, shown: 'b\tc.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA2: a title after an open paren keeps the destination '
          'open, as markdown reads it',
      'x\n[a](b(c "t").md)\n',
      [(target: 'b(c.md', line: 2, shown: 'b(c.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA1: pin: emphasis delimiters around brackets change no '
          'link',
      '*[a*](b.md)\n[c](b.md)\n',
      [
        (target: 'b.md', line: 1, shown: 'b.md', anchor: null),
        (target: 'b.md', line: 2, shown: 'b.md', anchor: null),
      ],
    );

    placed(
      'f04/us02/fr04, LA1: pin: collapsed and shortcut references are placed '
          'at their uses',
      '[r][]\n[r]\n\n[r]: b.md\n',
      [
        (target: 'b.md', line: 1, shown: 'b.md', anchor: null),
        (target: 'b.md', line: 2, shown: 'b.md', anchor: null),
      ],
    );

    placed(
      'f04/us02/fr04, LA1: a body that starts after frontmatter keeps each '
          'link on its line',
      '\\[a](b.md)\n[c](b.md)\n',
      [(target: 'b.md', line: 6, shown: 'b.md', anchor: null)],
      firstLine: 5,
    );

    placed(
      'f04/us02/fr04, LA1: a code span of two backticks holds no use',
      '``[a](b.md)``\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA1: a code span over two lines holds no use',
      '`x\n[a](b.md)`\n[c](b.md)\n',
      [(target: 'b.md', line: 3, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA1: an escaped backtick opens no code span',
      '\\`[a](b.md)`\n[c](b.md)\n',
      [
        (target: 'b.md', line: 1, shown: 'b.md', anchor: null),
        (target: 'b.md', line: 2, shown: 'b.md', anchor: null),
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
        (target: 'b.md', line: 1, shown: 'b.md', anchor: null),
        (target: 'b.md', line: 2, shown: 'b.md', anchor: null),
      ],
    );

    placed(
      'f04/us02/fr04, LA2: a line separator may end a code span, as markdown '
          'reads it',
      '`[a](b.md)$lineSeparator`\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
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
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA2: a bare URL runs through the brackets after it, as '
          'markdown reads it',
      'see http://x.y/[a](b.md)\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
    );

    placed(
      "f04/us02/fr04, LA2: a bare URL in link text runs through the link's "
          'close, as markdown reads it',
      '[see http://x.y/](b.md)\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA1: a raw HTML attribute holds no use',
      'x <span title="[a](b.md)">y</span>\n[c](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
    );

    test('f04/us02/fr04, LA1: an HTML comment holds no use, on one line or '
        'over lines', () {
      expect(placesOf('x <!-- [a](b.md) -->\n[c](b.md)\n'), [
        (target: 'b.md', line: 2, shown: 'b.md', anchor: null),
      ]);
      expect(placesOf('x <!--\n[a](b.md)\n-->\n[c](b.md)\n'), [
        (target: 'b.md', line: 4, shown: 'b.md', anchor: null),
      ]);
    });

    placed(
      'f04/us02/fr04, LA4: a destination with an entity is placed at its use',
      'x\n[a](b&#46;md)\n',
      [(target: 'b.md', line: 2, shown: 'b&#46;md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA4: a destination with an escape is placed at its use',
      'x\n[a](b\\_c.md)\n',
      [(target: 'b_c.md', line: 2, shown: r'b\_c.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA4: pin: an email in link text leaves the link at its '
          'line',
      'x\n[a@b.md](c.md)\n',
      [(target: 'c.md', line: 2, shown: 'c.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA4: pin: a doc with a footnote takes the nth-use '
          'fallback',
      'x[^1]\n\n[^1]: see [a](b.md)\n\n[c](b.md)\n',
      [
        (target: 'b.md', line: 3, shown: 'b.md', anchor: null),
        (target: 'b.md', line: 5, shown: 'b.md', anchor: null),
      ],
    );

    placed(
      'f04/us02/fr04, LA4: pin: two forms of one doc keep their own lines and '
          'destinations',
      '[a](./b.md)\n[c](b.md)\n',
      [
        (target: 'b.md', line: 1, shown: './b.md', anchor: null),
        (target: 'b.md', line: 2, shown: 'b.md', anchor: null),
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
      [(target: 'b.md', line: 5, shown: 'b.md', anchor: null)],
    );

    group('f04/us02/fr04, LA3: an HTML block runs to its end condition', () {
      placed(
        'a block of <details> runs to its closing tag',
        '<details>\n[a](b.md)\n</details>\n\n[c](b.md)\n',
        [(target: 'b.md', line: 5, shown: 'b.md', anchor: null)],
      );

      placed(
        'a block of an unknown tag runs to the next blank line',
        '<x-y>\n[a](b.md)\n\n[c](b.md)\n',
        [(target: 'b.md', line: 4, shown: 'b.md', anchor: null)],
      );

      placed(
        'a block of <pre> runs past a blank line to its closing tag',
        '<pre>\n\n[a](b.md)\n</pre>\n\n[c](b.md)\n',
        [(target: 'b.md', line: 6, shown: 'b.md', anchor: null)],
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
      [(target: 'b.md', line: 3, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA3: an indented code block holds no use',
      '    [a](b.md)\n\n[c](b.md)\n',
      [(target: 'b.md', line: 3, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA3: pin: an indented line after a paragraph line is '
          'paragraph text',
      'x\n    [a](b.md)\n',
      [(target: 'b.md', line: 2, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA3: a definition-shaped line inside a paragraph '
          'defines nothing',
      'x\n[r]: b.md\n\n[d][r]\n[c](b.md)\n',
      [(target: 'b.md', line: 5, shown: 'b.md', anchor: null)],
    );

    group('f04/us02/fr04, LA3: a heading and a thematic break end the '
        'brackets before them', () {
      placed('a heading ends them', '# [a\nb](b.md)\n[c](b.md)\n', [
        (target: 'b.md', line: 3, shown: 'b.md', anchor: null),
      ]);

      placed('a thematic break ends them', '[a\n***\nb](b.md)\n[c](b.md)\n', [
        (target: 'b.md', line: 4, shown: 'b.md', anchor: null),
      ]);
    });

    placed(
      'f04/us02/fr04, LA3: pin: a fence ends the brackets before it',
      '[a\n```\nb](b.md)\n```\n[c](b.md)\n',
      [(target: 'b.md', line: 5, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA3: a table cell ends at an unescaped pipe',
      '| [a | b](b.md) |\n|---|---|\n\n[c](b.md)\n',
      [(target: 'b.md', line: 4, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA3: pin: an escaped pipe stays in its cell',
      '| [a \\| b](b.md) |\n|---|\n',
      [(target: 'b.md', line: 1, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA3: pin: a GFM list item takes a lone dash as markdown '
          'does, so the paragraph above it reads no link',
      'x\n\n[a](b.md)\n-\n\n[c](b.md)\n',
      [(target: 'b.md', line: 6, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA3: pin: a setext underline keeps the link above it',
      '[a](b.md)\n===\n[c](b.md)\n',
      [
        (target: 'b.md', line: 1, shown: 'b.md', anchor: null),
        (target: 'b.md', line: 3, shown: 'b.md', anchor: null),
      ],
    );

    placed(
      'f04/us02/fr04, LA3: pin: of two definitions of one label the first '
          'wins',
      '[t][r]\n\n[r]: b.md\n[r]: c.md\n',
      [(target: 'b.md', line: 1, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA3: pin: links in a heading and a table cell keep '
          'their lines',
      '# [a](b.md)\n\n| h |\n|---|\n| [c](b.md) |\n',
      [
        (target: 'b.md', line: 1, shown: 'b.md', anchor: null),
        (target: 'b.md', line: 5, shown: 'b.md', anchor: null),
      ],
    );

    placed(
      "f04/us02/fr04, LA3: pin: a definition's title on the next line is "
          'read with it',
      '[r]: b.md\n"t"\n[d][r]\n',
      [(target: 'b.md', line: 3, shown: 'b.md', anchor: null)],
    );

    void within(
      String name,
      String Function(int n) bodyOf,
      List<(int, String?)> expected, {
      int n = 10000,
    }) {
      test('f04/us02/fr04, f04/nfr-p03, LA6: $name in linear time', () {
        void scan(String body) => linkSourcesOf(body, firstLine: 1);

        final sources = linkSourcesOf(bodyOf(n), firstLine: 1);

        expect(sources.map((s) => (s.line, s.shown)), expected);
        expectLinearTime(bodyOf, n, scan);
      });
    }

    within(
      '10,000 unclosed bare destinations are scanned',
      (n) => '${'[a](b' * n}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 unclosed titles are scanned',
      (n) => '${'[a](b "t' * n}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 unclosed angle destinations are scanned',
      (n) => '${'[a](<b ' * n}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 openers before one close are scanned',
      (n) => 'x ${'[a ' * n}](b.md)\n',
      [(1, 'b.md')],
    );

    within(
      '10,000 links in one image description are dropped',
      (n) => '![${'[x](b.md) ' * n}](i.png)\n\n[l](b.md)\n',
      [(1, 'i.png'), (3, 'b.md')],
    );

    within(
      '10,000 unclosed processing instructions are scanned',
      (n) => '${'x <? ' * n}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 unclosed declarations are scanned',
      (n) => '${'x <!X ' * n}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 unclosed comments are scanned',
      (n) => '${'x <!-- ' * n}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 unclosed autolinks are scanned',
      (n) => '${'<http://x' * n}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '400 backtick runs of growing length are scanned',
      (n) =>
          '${List.generate(n, (i) => '${'`' * (i + 1)}a').join()}\n\n'
          '[l](b.md)\n',
      [(3, 'b.md')],
      n: 400,
    );

    within(
      'a 50,000-letter word with no @ is scanned',
      (n) => '${'a' * n}\n\n[l](b.md)\n',
      [(3, 'b.md')],
      n: 50000,
    );

    within(
      '10,000 http URL starts after a letter are scanned',
      (n) => '${'xhttp://a.b' * n}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 www URL starts after a letter are scanned',
      (n) => '${'xwww.a.b' * n}\n\n[l](b.md)\n',
      [(3, 'b.md')],
    );

    within(
      '10,000 HTML blocks are scanned',
      (n) => '${'<div>\n\n' * n}[l](b.md)\n',
      [(20001, 'b.md')],
    );

    within(
      '10,000 table rows are scanned',
      (n) => '| h |\n|---|\n${'| x |\n' * n}\n[l](b.md)\n',
      [(10004, 'b.md')],
    );

    within(
      '10,000 definitions with an unclosed paren title and a setext underline '
      'are scanned',
      (n) => '${'[r]: b.md (t\n===\n' * n}[l][r]\n',
      [],
    );

    within(
      '10,000 definitions with an unclosed title are scanned',
      (n) => '${'[r]: b.md "t\n\n' * n}[l](b.md)\n',
      [(20001, 'b.md')],
    );

    within(
      '10,000 list items are scanned',
      (n) => '${'- x\n' * n}\n[l](b.md)\n',
      [(10002, 'b.md')],
    );

    within(
      '10,000 blockquote lines are scanned',
      (n) => '${'> x\n' * n}\n[l](b.md)\n',
      [(10002, 'b.md')],
    );
  });

  group('look-alikes in containers', () {
    List<LinkPlace> placesOf(String body) =>
        linkPlacesOf(body, docPath: 'x.md', firstLine: 1)!.docLinks;

    void placed(String name, String body, List<LinkPlace> expected) {
      test(name, () => expect(placesOf(body), expected));
    }

    test('f04/us02/fr04, LA3: a definition in a blockquote or a list item is '
        'read', () {
      const expected = [
        (target: 'b.md', line: 3, shown: 'b.md', anchor: null),
        (target: 'b.md', line: 4, shown: 'b.md', anchor: null),
      ];

      expect(placesOf('> [r]: b.md\n\n[c](b.md)\n[d][r]\n'), expected);
      expect(placesOf('- [r]: b.md\n\n[c](b.md)\n[d][r]\n'), expected);
    });

    placed(
      'f04/us02/fr04, LA3: pin: a lazy line defines nothing',
      '- x\n[r]: b.md\n\n[t][r]\n[c](b.md)\n',
      [(target: 'b.md', line: 5, shown: 'b.md', anchor: null)],
    );

    test('f04/us02/fr04, LA3: list items end the brackets before them', () {
      expect(placesOf('- [a\n- b](b.md)\n- [c](b.md)\n'), [
        (target: 'b.md', line: 3, shown: 'b.md', anchor: null),
      ]);
      expect(placesOf('x [a\n1. b](b.md)\n\n[c](b.md)\n'), [
        (target: 'b.md', line: 4, shown: 'b.md', anchor: null),
      ]);
    });

    placed(
      'f04/us02/fr04, LA3: pin: an ordered item numbered 2 does not interrupt '
          'a paragraph',
      'x [a\n2. b](b.md)\n',
      [(target: 'b.md', line: 1, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA3: a checkbox is no shortcut reference',
      '- [x] task\n\n[x]: b.md\n\n[c](b.md)\n',
      [(target: 'b.md', line: 5, shown: 'b.md', anchor: null)],
    );

    placed(
      'f04/us02/fr04, LA3: indented code in a blockquote holds no use',
      '>     [a](b.md)\n\n[c](b.md)\n',
      [(target: 'b.md', line: 3, shown: 'b.md', anchor: null)],
    );

    test('f04/us02/fr04, LA3: pin: blockquote and list lines keep their '
        'links', () {
      expect(placesOf('> ```\n> [a](b.md)\n> ```\n\n[c](b.md)\n'), [
        (target: 'b.md', line: 5, shown: 'b.md', anchor: null),
      ]);
      expect(placesOf('> [a](b.md\n> "t")\n\n[c](b.md)\n'), [
        (target: 'b.md', line: 1, shown: 'b.md', anchor: null),
        (target: 'b.md', line: 4, shown: 'b.md', anchor: null),
      ]);
      expect(placesOf('> [a\nb](b.md)\n'), [
        (target: 'b.md', line: 1, shown: 'b.md', anchor: null),
      ]);
      expect(placesOf('- x\n\n    [a](b.md)\n'), [
        (target: 'b.md', line: 3, shown: 'b.md', anchor: null),
      ]);
      expect(placesOf('- a\n  [b](c.md)\n'), [
        (target: 'c.md', line: 2, shown: 'c.md', anchor: null),
      ]);
    });

    placed(
      'f04/us02/fr04, LA3: pin: links in a nested item and its continuation '
          'keep their lines',
      '- a\n  - [b](c.md)\n    [d](c.md)\n',
      [
        (target: 'c.md', line: 2, shown: 'c.md', anchor: null),
        (target: 'c.md', line: 3, shown: 'c.md', anchor: null),
      ],
    );
  });

  group('final-fix label and line folding', () {
    List<LinkPlace> placesOf(String body) =>
        linkPlacesOf(body, docPath: 'x.md', firstLine: 1)!.docLinks;

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
          (target: 'b.md', line: 2, shown: 'b.md', anchor: null),
        ], reason: blank);
      }
    });

    test(
      'f04/us02/fr04, LA1: a lone CR ends a line as it does for markdown',
      () {
        expect(placesOf('```\r[a](b.md)\r```\n[c](b.md)\n'), [
          (target: 'b.md', line: 2, shown: 'b.md', anchor: null),
        ]);
        expect(placesOf('    x\r    [a](b.md)\n\n[c](b.md)\n'), [
          (target: 'b.md', line: 3, shown: 'b.md', anchor: null),
        ]);
        expect(placesOf('x\r[a](b.md)\n'), [
          (target: 'b.md', line: 1, shown: 'b.md', anchor: null),
        ]);
      },
    );

    test('f04/us02/fr04, LA1: a CR before an LF that toLf leaves splits no '
        'extra line', () {
      final body = toLf('x\r\r\n[a\r\r\nb](c.md)\r\r\n');

      expect(placesOf(body), [
        (target: 'c.md', line: 2, shown: 'c.md', anchor: null),
      ]);
    });
  });

  group('expectLinearTime', () {
    test('passes a scan that reads each character once', () {
      expectLinearTime(
        (n) => 'a' * n,
        200000,
        (body) => body.codeUnits.where((c) => c == 0x61).length,
      );
    });

    test('fails a scan that reads the rest of the body at each character', () {
      void quadratic(String body) {
        var count = 0;
        for (var i = 0; i < body.length; i++) {
          for (var j = i; j < body.length; j++) {
            if (body.codeUnitAt(j) == 0x61) count++;
          }
        }
        expect(count, isPositive);
      }

      expect(
        () => expectLinearTime((n) => 'a' * n, 5000, quadratic),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}

/// Expects [scan] to take time linear in the length of the body it reads.
///
/// A fixed time budget fails on a slow or busy runner, and under coverage,
/// whatever the scan does. This times [scan] on the bodies [bodyOf] builds for
/// a twentieth of [n] and for [n], in turns, and keeps the fastest of three
/// runs of each. A linear scan's time grows as much as the body, a quadratic
/// one's as the body's square; the time of one scan must grow less than the
/// body's growth to the power 1.5, halfway between the two on a log scale.
/// Each run repeats the scan until it takes 20 ms, so both sizes are timed
/// over as long a stretch and a busy runner slows them alike.
void expectLinearTime(
  String Function(int n) bodyOf,
  int n,
  void Function(String body) scan,
) {
  final small = bodyOf(n ~/ 20);
  final large = bodyOf(n);
  final smallRepeats = _repeatsFor(scan, small);
  final largeRepeats = _repeatsFor(scan, large);
  var smallTime = double.infinity;
  var largeTime = double.infinity;
  for (var round = 0; round < 3; round++) {
    smallTime = min(smallTime, _scanTime(scan, small, smallRepeats));
    largeTime = min(largeTime, _scanTime(scan, large, largeRepeats));
  }
  final bodyGrowth = large.length / small.length;
  final timeGrowth = largeTime / smallTime;

  expect(
    timeGrowth,
    lessThan(pow(bodyGrowth, 1.5)),
    reason:
        'the body grew ${bodyGrowth.toStringAsFixed(1)} times and the time '
        'of one scan ${timeGrowth.toStringAsFixed(1)} times '
        '(${smallTime.round()} µs to ${largeTime.round()} µs)',
  );
}

/// Returns how many scans of [body] in a row take at least 20 ms.
int _repeatsFor(void Function(String body) scan, String body) {
  var repeats = 1;
  while (_microsecondsOf(scan, body, repeats) < 20000) {
    repeats *= 2;
  }
  return repeats;
}

/// Returns the microseconds one scan of [body] takes, over [repeats] scans.
double _scanTime(void Function(String body) scan, String body, int repeats) =>
    _microsecondsOf(scan, body, repeats) / repeats;

int _microsecondsOf(void Function(String body) scan, String body, int repeats) {
  final watch = Stopwatch()..start();
  for (var i = 0; i < repeats; i++) {
    scan(body);
  }
  return watch.elapsedMicroseconds;
}
