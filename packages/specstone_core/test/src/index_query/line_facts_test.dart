import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_anchors.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/markdown_body.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/link_places.dart';
import 'package:specstone_core/src/index_query/mermaid_blocks.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

/// The stored facts of [text], as refresh computes them.
DocContent _contentOf(String text, {String docPath = 'doc.md'}) =>
    parseIndexedDoc(
      docPath: docPath,
      bytes: utf8.encode(text),
      match: const NoDocType(),
      statusesOutside: true,
    ).content;

LineFacts _factsOf(String text, {String docPath = 'doc.md'}) =>
    _contentOf(text, docPath: docPath).lineFacts;

void main() {
  // Line numbers are in the comments: the fence on 9-11 hides the `##` on 10.
  const text =
      '---\n' // 1
      'status: planned\n' // 2
      '---\n' // 3
      '\n' // 4
      '# Title\n' // 5
      '\n' // 6
      '## Statement\n' // 7
      'Body.\n' // 8
      '```\n' // 9
      '## not a section\n' // 10
      '```\n' // 11
      '\n' // 12
      '## Second\n' // 13
      'héllo \u{1F600}\n'; // 14

  group('LineFacts.of', () {
    test('the '
        'body labels are found once at index time, at their file lines, and '
        'stored', () {
      const labelled =
          '---\nnote: FR-01\n---\n# T\n\nSee F-01 US-02 and `FR-03` FR-04.\n'
          '```dart\n// FR-05\n```\n';
      final facts = _factsOf(labelled);
      expect(facts.numberLabels, [
        (line: 6, written: 'F-01 US-02'),
        (line: 6, written: 'FR-04'),
      ]);
      expect(
        LineFacts.fromJson(
          jsonDecode(jsonEncode(facts.toJson())) as Map<String, Object?>,
          sectionCounts: facts.sectionCounts,
        ).numberLabels,
        facts.numberLabels,
      );
    });

    test('each TBR '
        'marker of the body is stored at its file line and survives a JSON '
        'round trip', () {
      const marked =
          '---\nnote: TBR \u2014 in the frontmatter\n---\n# T\n\n'
          'A gap TBR \u2014 pick a value.\n'
          '```\nTBR \u2014 in code\n```\n'
          'And `TBR \u2014 x` then TBR \u2014 later.\n';
      final facts = _factsOf(marked);
      expect(facts.tbrMarkers, [
        (line: 6, rest: 'pick a value.'),
        (line: 10, rest: 'later.'),
      ]);
      expect(
        LineFacts.fromJson(
          jsonDecode(jsonEncode(facts.toJson())) as Map<String, Object?>,
          sectionCounts: facts.sectionCounts,
        ).tbrMarkers,
        facts.tbrMarkers,
      );
      expect(facts.toJson()['tbr_markers'], [
        [6, 'pick a value.'],
        [10, 'later.'],
      ]);
    });

    test('a link in the first block and long link-free prose after it store '
        'the facts the full parse gives', () {
      final body =
          '# Title\n\nSee [other](other.md#part).\n\n'
          '${List.filled(60, 'Plain words, no link mark in them. ').join()}'
          '\n\n## Second heading\n\nMore plain prose.\n';

      final facts = _factsOf(body);

      final tree = parseMarkdownTree(body)!;
      final links = linkPlacesOf(
        body,
        docPath: 'doc.md',
        firstLine: 1,
        tree: tree,
      )!;
      expect(facts.links, links.docLinks);
      expect(facts.fileLinks, links.fileLinks);
      expect(facts.linkTexts, links.texts);
      expect(facts.anchors!.toJson(), anchorsOf(tree.nodes).toJson());
    });

    test('a body with no link syntax whose block pass throws stores no '
        'warning and no links', () {
      final parsed = parseIndexedDoc(
        docPath: 'doc.md',
        bytes: utf8.encode('${'>' * 20000}x\n'),
        match: const NoDocType(),
        statusesOutside: true,
      );

      expect(parsed.doc.warnings, isEmpty);
      expect(parsed.content.lineFacts.links, isEmpty);
    });

    test('a '
        'marker in a frontmatter value is not stored', () {
      const doc = '---\nnote: TBR \u2014 in the frontmatter\n---\n# T\n';
      expect(_factsOf(doc).tbrMarkers, isEmpty);
    });

    test('a CRLF '
        'doc stores the markers of its LF text', () {
      const lf = '---\na: 1\n---\n# T\n\nTBR \u2014 gap\n';
      expect(_factsOf(lf.replaceAll('\n', '\r\n')).tbrMarkers, [
        (line: 6, rest: 'gap'),
      ]);
    });

    test('a doc with frontmatter, title, sections, and a fence hiding a ## has '
        '1-based file lines', () {
      final facts = _factsOf(text);
      expect(facts.sectionLines, [7, 13]);
      expect(facts.fenced, [(first: 9, last: 11)]);
      expect(facts.lineCount, 8);
      expect(facts.charCount, text.runes.length);
      expect(facts.frontmatterErrorLine, isNull);
    });

    test("line facts hold each doc link's target, line, and destination as "
        'written', () {
      const linked =
          '---\na: 1\n---\n# T\n\nSee [s](us01_x/USER_STORY.md).\n\n'
          '[w](https://e.com) [t](#top)\n';
      const docPath = 'prds/f01_a/FEATURE.md';
      const expected = [
        (
          target: 'prds/f01_a/us01_x/USER_STORY.md',
          line: 6,
          shown: 'us01_x/USER_STORY.md',
          anchor: null,
        ),
      ];
      expect(_factsOf(linked, docPath: docPath).links, expected);
      expect(
        _factsOf(linked.replaceAll('\n', '\r\n'), docPath: docPath).links,
        expected,
      );
    });

    test('line facts hold each file link apart from the doc links', () {
      const linked =
          '---\na: 1\n---\n# T\n\nSee [s](us01_x/USER_STORY.md) ![f](flow.png).\n';
      const docPath = 'prds/f01_a/FEATURE.md';
      final facts = _factsOf(linked, docPath: docPath);
      expect(facts.links.map((p) => p.target), [
        'prds/f01_a/us01_x/USER_STORY.md',
      ]);
      expect(facts.fileLinks, [
        (
          target: 'prds/f01_a/flow.png',
          line: 6,
          shown: 'flow.png',
          anchor: null,
        ),
      ]);
    });

    test(
      'isFenced is true on a fence line and its content and false elsewhere',
      () {
        final facts = _factsOf(text);
        expect(
          [for (var i = 0; i <= 15; i++) facts.isFenced(i)],
          [for (var i = 0; i <= 15; i++) i >= 9 && i <= 11],
        );
      },
    );

    test('a section count is what split and runes count on its text, a '
        'surrogate pair counting once', () {
      final content = _contentOf(text);
      final counts = content.lineFacts.sectionCounts;
      expect(counts, hasLength(2));
      for (final (i, section) in content.sections.indexed) {
        expect(counts[i].lines, section.text.split('\n').length);
        expect(counts[i].chars, section.text.runes.length);
      }
      expect(counts[0].lines, 5);
      expect(counts[1], (lines: 2, chars: 17));
    });

    test(
      'a section count is the non-blank lines of its header line and body',
      () {
        final counts = _contentOf(text).lineFacts.sectionCounts;
        expect(counts[0].lines, 5);
        expect(counts[1].lines, 2);
        final blanks = _factsOf('---\na: 1\n---\n# T\n\n## S\n\n\nx\n\n\n');
        expect(blanks.sectionCounts.single.lines, 2);
      },
    );

    test('a CRLF file has the facts of its LF twin', () {
      final lf = _factsOf(text);
      final crlf = _factsOf(text.replaceAll('\n', '\r\n'));
      expect(crlf.toJson(), lf.toJson());
      expect(crlf.sectionCounts, lf.sectionCounts);
      expect(crlf.charCount, text.runes.length);
    });

    test('a doc without frontmatter has its sections from line 1, and an empty '
        'doc has no lines', () {
      final bare = _factsOf('# T\n\n## S\nx\n');
      expect(bare.sectionLines, [3]);
      expect(bare.lineCount, 3);
      final empty = _factsOf('');
      expect(empty.sectionLines, isEmpty);
      expect(empty.lineCount, 0);
      expect(empty.charCount, 0);
    });

    test('a final line without a line break counts as a line', () {
      expect(_factsOf('# T\n\n## S\nx').lineCount, 3);
      expect(_factsOf('# T\n\n## S\nx\n\n').lineCount, 3);
    });

    test(
      'the doc count is the non-blank lines of the body after the frontmatter',
      () {
        expect(_factsOf(text).lineCount, 8);
        expect(
          _factsOf('---\nstatus: planned\n\n---\n\n# T\n\n\n## S\nx\n\n\n')
              .lineCount,
          3,
        );
      },
    );

    test(
      'invalid frontmatter still counts its body from the closing delimiter',
      () {
        expect(
          _factsOf('---\ntitle: "open\n---\n\n# T\n\nx\n\n\n').lineCount,
          2,
        );
      },
    );

    test('a doc with no closed frontmatter counts its whole text as body', () {
      expect(_factsOf('---\nstatus: planned\n# T\n\nx\n\n').lineCount, 4);
    });

    test('an unclosed fence runs to the end of the file', () {
      final facts = _factsOf('# T\n\n```\n## hidden\nmore\n');
      expect(facts.fenced, [(first: 3, last: 5)]);
      expect(facts.sectionLines, isEmpty);
    });

    test('invalid frontmatter YAML stores the parser line, a non-mapping '
        'stores 1, valid or absent stores none', () {
      expect(
        _factsOf('---\ntitle: "open\n---\n\n# T\n').frontmatterErrorLine,
        3,
      );
      expect(_factsOf('---\n- a list\n---\n').frontmatterErrorLine, 1);
      expect(_factsOf('---\n---\n').frontmatterErrorLine, isNull);
      expect(
        _factsOf('---\n# only a comment\n---\n').frontmatterErrorLine,
        isNull,
      );
      expect(_factsOf('# No frontmatter\n').frontmatterErrorLine, isNull);
    });
  });

  group('LineFacts sizes', () {
    final texts = {
      'empty': '',
      'one line break': '\n',
      'no final break': 'a',
      'one line': 'a\n',
      'blank last line': 'a\n\n',
      'frontmatter only': '---\n---\n',
      'frontmatter, no final break': '---\n---',
      'frontmatter, then a blank line': '---\n---\n\n',
      'frontmatter, body, no final break': '---\na: 1\n---\nbody',
      'frontmatter, body, blank line': '---\na: 1\n---\n\nbody\n\n',
      'surrogate pairs': '# \u{1F600}\u{1F600}\n\n## \u{1F600}\nx \uD83D\n',
      'tilde fence': '# T\n~~~\n## no\n~~~\n## yes\n',
      'CRLF with a fence':
          '---\r\na: 1\r\n---\r\n# T\r\n```\r\n## no\r\n```\r\n',
    };
    for (final MapEntry(key: name, value: raw) in texts.entries) {
      test('$name: the line count is the non-blank body lines, the code points '
          'those of runes', () {
        final lf = raw.replaceAll('\r\n', '\n');
        final facts = _factsOf(raw);
        expect(
          facts.lineCount,
          nonBlankLinesOf(lfLinesOf(Doc.parse(lf).afterFrontmatter)),
        );
        expect(facts.charCount, lf.runes.length);
      });
    }

    test('a link is placed from the line after the frontmatter, whatever ends '
        'the file', () {
      const docPath = 'prds/f01_a/FEATURE.md';
      const link = '[s](x.md)';
      final links = [
        for (final (frontmatter, line) in [
          ('---\n---\n', 3),
          ('---\n---\n\n', 4),
          ('---\na: 1\nb: 2\n---\n', 5),
        ])
          _factsOf('$frontmatter$link', docPath: docPath).links.single.line -
              line,
      ];
      expect(links, [0, 0, 0]);
      expect(_factsOf(link, docPath: docPath).links.single.line, 1);
    });

    test('a fence indented up to three spaces counts, four spaces is code, and '
        'the last line may open one', () {
      expect(_factsOf('# T\n   ```\n## no\n   ```\n').fenced, [
        (first: 2, last: 4),
      ]);
      expect(_factsOf('# T\n    ```\n## yes\n').fenced, isEmpty);
      expect(_factsOf('# T\n```').fenced, [(first: 2, last: 2)]);
    });

    test('a tilde fence and a CRLF fence hide their ## lines', () {
      final tilde = _factsOf('# T\n~~~\n## no\n~~~\n## yes\n');
      expect(tilde.fenced, [(first: 2, last: 4)]);
      expect(tilde.sectionLines, [5]);
      final crlf = _factsOf(
        '---\r\na: 1\r\n---\r\n# T\r\n```\r\n## no\r\n```\r\n',
      );
      expect(crlf.fenced, [(first: 5, last: 7)]);
      expect(crlf.sectionLines, isEmpty);
    });
  });

  group('LineFacts JSON', () {
    test('the JSON round-trips every fact but the section counts, which the '
        'section rows keep', () {
      final facts = _factsOf(text);
      final back = LineFacts.fromJson(
        jsonDecode(jsonEncode(facts.toJson())) as Map<String, Object?>,
        sectionCounts: facts.sectionCounts,
      );
      expect(back.toJson(), facts.toJson());
      expect(back.sectionCounts, facts.sectionCounts);
      expect(back.links, facts.links);
      expect(back.fileLinks, facts.fileLinks);
      expect(back.sectionLines, [7, 13]);
      expect(back.fenced, [(first: 9, last: 11)]);
      expect(back.isFenced(10), isTrue);
      expect(back.isFenced(12), isFalse);
    });

    test('the JSON round-trips the file links', () {
      final facts = _factsOf('# T\n\n![f](flow%20a.png) [c](../x.dart)\n');
      expect(facts.fileLinks, hasLength(2));
      final back = LineFacts.fromJson(
        jsonDecode(jsonEncode(facts.toJson())) as Map<String, Object?>,
        sectionCounts: facts.sectionCounts,
      );
      expect(back.fileLinks, facts.fileLinks);
    });

    test('the JSON round-trips the self links and '
        'the anchor set', () {
      final facts = _factsOf(
        '# T\n\n[a](b.md#x) [s](#rules)\n'
        '## Rules\n',
        docPath: 'doc.md',
      );
      expect(facts.selfLinks, [
        (target: 'doc.md', line: 3, shown: '#rules', anchor: 'rules'),
      ]);
      expect(facts.anchors, isNotNull);
      expect(facts.anchors!.holds('t'), isTrue);
      expect(facts.anchors!.holds('rules'), isTrue);
      final back = LineFacts.fromJson(
        jsonDecode(jsonEncode(facts.toJson())) as Map<String, Object?>,
        sectionCounts: facts.sectionCounts,
      );
      expect(back.selfLinks, facts.selfLinks);
      expect(back.anchors!.toJson(), facts.anchors!.toJson());
    });

    test('a malformed autolink is in no link class, whatever else the body '
        'holds', () {
      for (final (body, shown) in [
        ('Autolink only <http://h:99999/> here.', <String>[]),
        ('Both <http://h:99999/> and [x](y.md).', ['y.md']),
      ]) {
        final facts = _factsOf('# T\n\n$body\n');
        expect([for (final l in facts.links) l.shown], shown, reason: body);
        expect(facts.fileLinks, isEmpty, reason: body);
        expect(facts.selfLinks, isEmpty, reason: body);
      }
    });

    test('a body the markdown parser fails on has no links '
        'and an unknown anchor set, stored as null', () {
      final facts = _factsOf('# T\n\n[a](b.md)\n\n[a]:<b\\');
      expect(facts.links, isEmpty);
      expect(facts.fileLinks, isEmpty);
      expect(facts.selfLinks, isEmpty);
      expect(facts.anchors, isNull);
    });
  });

  group('LineFacts cite candidates, link texts, headings', () {
    const type = MergedDocType(
      id: 'topic',
      path: 'specs/topics/{slug}.md',
      isPerTarget: false,
      fields: [],
      sections: [],
      lint: MergedLint(),
      files: [],
    );

    LineFacts typedFactsOf(String text) => parseIndexedDoc(
      docPath: 'specs/topics/a.md',
      bytes: utf8.encode(text),
      match: MatchedDocType(type),
      statusesOutside: true,
      idPrefixes: const {'INV-'},
    ).content.lineFacts;

    LineFacts roundTrip(LineFacts facts) => LineFacts.fromJson(
      jsonDecode(jsonEncode(facts.toJson())) as Map<String, Object?>,
      sectionCounts: facts.sectionCounts,
    );

    test('a typed doc stores each cite candidate '
        'at its file line, and the JSON round trip keeps it', () {
      final facts = typedFactsOf(
        '---\nx: 1\n---\n\n# T\n\n`domain:login#invariants` INV-6 and INV-7.\n',
      );

      expect(facts.citeCandidates, hasLength(1));
      final cite = facts.citeCandidates.single;
      expect(cite.line, 7);
      expect(cite.written, 'domain:login');
      expect(cite.sectionKey, 'invariants');
      expect(cite.itemIds, ['INV-6', 'INV-7']);
      expect(roundTrip(facts).toJson(), facts.toJson());
      expect(roundTrip(facts).citeCandidates.single.itemIds, cite.itemIds);
    });

    test('an untyped doc stores no candidate', () {
      expect(_factsOf('# T\n\n`domain:login` INV-6\n').citeCandidates, isEmpty);
    });

    test('each doc or self link whose text reads '
        'as an item ID stores its text and where it sits, and the JSON '
        'round trip keeps them', () {
      const line =
          'See [RULE-14](doc_model.md#rules) to [RULE-19](doc_model.md#rules) '
          'and [x](y.md) [S1](#s1) ![RULE-2](a.png).';
      final facts = _factsOf('# T\n\n$line\n');

      final first = line.indexOf('[RULE-14]');
      final second = line.indexOf('[RULE-19]');
      expect(facts.linkTexts, [
        (
          line: 3,
          column: first,
          endLine: 3,
          endColumn: first + '[RULE-14](doc_model.md#rules)'.length,
          text: 'RULE-14',
          target: 'doc_model.md',
          anchor: 'rules',
          shown: 'doc_model.md#rules',
        ),
        (
          line: 3,
          column: second,
          endLine: 3,
          endColumn: second + '[RULE-19](doc_model.md#rules)'.length,
          text: 'RULE-19',
          target: 'doc_model.md',
          anchor: 'rules',
          shown: 'doc_model.md#rules',
        ),
        (
          line: 3,
          column: line.indexOf('[S1]'),
          endLine: 3,
          endColumn: line.indexOf('[S1]') + '[S1](#s1)'.length,
          text: 'S1',
          target: 'doc.md',
          anchor: 's1',
          shown: '#s1',
        ),
      ]);
      expect(roundTrip(facts).linkTexts, facts.linkTexts);
    });

    test('each heading stores its level, and '
        'its file line when every heading is a line of ATX text', () {
      final facts = _factsOf(
        '---\nx: 1\n---\n\n# T\n\n## A\n\n```\n## no\n```\n\n### B\n\n## A\n',
      );

      expect(facts.anchors!.headingSlugs, ['t', 'a', 'b', 'a-1']);
      expect(facts.anchors!.headingLevels, [1, 2, 3, 2]);
      expect(facts.headingLines, [5, 7, 13, 15]);
      final back = roundTrip(facts);
      expect(back.anchors!.headingLevels, [1, 2, 3, 2]);
      expect(back.headingLines, [5, 7, 13, 15]);
    });

    test('a heading the line scan cannot '
        'place leaves the lines unknown, never a stand-in', () {
      final setext = _factsOf('# T\n\nSetext\n------\n\n## A\n');

      expect(setext.anchors!.headingLevels, [1, 2, 2]);
      expect(setext.headingLines, isNull);
      expect(roundTrip(setext).headingLines, isNull);
      expect(_factsOf('# T\n\n> ## Quoted\n').headingLines, isNull);
    });

    test(
      'a quoted heading that cancels a '
      '## line inside an HTML block keeps no line, since the slugs differ',
      () {
        final facts = _factsOf('# T\n> ## Note\n\n<!--\n## guide\n-->\n');

        expect(facts.anchors!.headingSlugs, ['t', 'note']);
        expect(facts.headingLines, isNull);
      },
    );

    test('a heading with inline markup is '
        'paired by the slug the parser gives it', () {
      final facts = _factsOf('# T\n> ## Note\n\n<!--\n## `guide`\n-->\n');

      expect(facts.anchors!.headingSlugs, ['t', 'note']);
      expect(facts.headingLines, isNull);
    });

    test('a repeated heading and one with '
        'inline markup still pair with their lines', () {
      final facts = _factsOf('# T\n\n## A\n\n## A\n\n## `code` _x_\n');

      expect(facts.headingLines, [1, 3, 5, 7]);
    });
  });

  group('LineFacts mermaid blocks', () {
    test('mermaidBlocks survives toJson and fromJson as pairs', () {
      const blocks = [
        MermaidBlock(fenceLine: 3, hash: 'aa'),
        MermaidBlock(fenceLine: 9, hash: 'bb'),
      ];
      final facts = LineFacts.of(
        lfText: '# T\n',
        countedText: '# T\n',
        docPath: 'doc.md',
        doc: Doc.parse('# T\n'),
        sectionCounts: const [],
        frontmatterErrorLine: null,
        bodyNumberLabels: const [],
        bodyTbrMarkers: const [],
        citeCandidates: const [],
        mermaidBlocks: blocks,
        warnings: [],
      );
      final json =
          jsonDecode(jsonEncode(facts.toJson())) as Map<String, Object?>;

      expect(json['mermaid_blocks'], [
        [3, 'aa'],
        [9, 'bb'],
      ]);
      final read = LineFacts.fromJson(json, sectionCounts: const []);
      expect(
        [for (final b in read.mermaidBlocks) (b.fenceLine, b.hash)],
        [(3, 'aa'), (9, 'bb')],
      );
    });

    test('structureOf stores no block', () {
      const text = '# T\n\n```mermaid\npie\n```\n';
      final facts = LineFacts.structureOf(lfText: text, doc: Doc.parse(text));

      expect(facts.mermaidBlocks, isEmpty);
    });
  });

  group('LineFacts.of counted text', () {
    test('lineCount and charCount measure countedText '
        'while every line number stays the file line', () {
      const disk = '# T\n\n## A\nx\n\n\n## B\ny\n';
      final facts = LineFacts.of(
        lfText: disk,
        countedText: 'one\ntwo\n\nthree\n',
        docPath: 'doc.md',
        doc: Doc.parse(disk),
        sectionCounts: const [(lines: 3, chars: 9), (lines: 2, chars: 4)],
        frontmatterErrorLine: null,
        bodyNumberLabels: const [],
        bodyTbrMarkers: const [],
        citeCandidates: const [],
        mermaidBlocks: const [],
        warnings: [],
      );
      expect(facts.sectionLines, [3, 7]);
      expect(facts.lineCount, 3);
      expect(facts.charCount, 15);
      expect(facts.sectionCounts, [(lines: 3, chars: 9), (lines: 2, chars: 4)]);
    });
  });
}

/// The non-blank lines of [lines], the expected doc count of the body.
int nonBlankLinesOf(List<String> lines) =>
    lines.where((line) => line.trim().isNotEmpty).length;
