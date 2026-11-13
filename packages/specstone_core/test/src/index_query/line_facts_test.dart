import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:test/test.dart';

/// The stored facts of [text], as refresh computes them.
DocContent _contentOf(String text, {String docPath = 'doc.md'}) =>
    parseIndexedDoc(
      docPath: docPath,
      bytes: utf8.encode(text),
      match: const NoDocType(),
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
    test('consistency_check/find_broken_pointers/report_number_labels: the '
        'body labels are found once at index time, at their file lines, and '
        'stored', () {
      const labelled =
          '---\nnote: FR-01\n---\n# T\n\nSee F-01 US-02 and `FR-03`.\n'
          '```dart\n// FR-04\n```\n';
      final facts = _factsOf(labelled);
      expect(facts.numberLabels, [
        (line: 6, written: 'F-01 US-02'),
        (line: 6, written: 'FR-03'),
      ]);
      expect(
        LineFacts.fromJson(
          jsonDecode(jsonEncode(facts.toJson())) as Map<String, Object?>,
          sectionCounts: facts.sectionCounts,
        ).numberLabels,
        facts.numberLabels,
      );
    });

    test('consistency_check/find_template_breaks/report_open_tbrs: each TBR '
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

    test('consistency_check/find_template_breaks/report_open_tbrs E08: a '
        'marker in a frontmatter value is not stored', () {
      const doc = '---\nnote: TBR \u2014 in the frontmatter\n---\n# T\n';
      expect(_factsOf(doc).tbrMarkers, isEmpty);
    });

    test('consistency_check/find_template_breaks/report_open_tbrs: a CRLF '
        'doc stores the markers of its LF text', () {
      const lf = '---\na: 1\n---\n# T\n\nTBR \u2014 gap\n';
      expect(_factsOf(lf.replaceAll('\n', '\r\n')).tbrMarkers, [
        (line: 6, rest: 'gap'),
      ]);
    });

    test('f04/nfr-p03: a doc with frontmatter, title, sections, and a fence hiding a ## has 1-based file lines', () {
      final facts = _factsOf(text);
      expect(facts.sectionLines, [7, 13]);
      expect(facts.fenced, [(first: 9, last: 11)]);
      expect(facts.lineCount, 8);
      expect(facts.charCount, text.runes.length);
      expect(facts.frontmatterErrorLine, isNull);
    });

    test("f04/nfr-p03, f04/us02/fr04, FM5: line facts hold each doc link's target, line, and destination as written", () {
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

    test('f04/us02/fr04, PS-R3: line facts hold each file link apart from the doc links', () {
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

    test('f04/nfr-p03: isFenced is true on a fence line and its content and false elsewhere', () {
      final facts = _factsOf(text);
      expect(
        [for (var i = 0; i <= 15; i++) facts.isFenced(i)],
        [for (var i = 0; i <= 15; i++) i >= 9 && i <= 11],
      );
    });

    test('f04/nfr-p03: a section count is what split and runes count on its text, a surrogate pair counting once', () {
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

    test('f04/nfr-p03: a section count is the non-blank lines of its header line and body', () {
      final counts = _contentOf(text).lineFacts.sectionCounts;
      expect(counts[0].lines, 5);
      expect(counts[1].lines, 2);
      final blanks = _factsOf('---\na: 1\n---\n# T\n\n## S\n\n\nx\n\n\n');
      expect(blanks.sectionCounts.single.lines, 2);
    });

    test('f04/nfr-p03: a CRLF file has the facts of its LF twin', () {
      final lf = _factsOf(text);
      final crlf = _factsOf(text.replaceAll('\n', '\r\n'));
      expect(crlf.toJson(), lf.toJson());
      expect(crlf.sectionCounts, lf.sectionCounts);
      expect(crlf.charCount, text.runes.length);
    });

    test('f04/nfr-p03: a doc without frontmatter has its sections from line 1, and an empty doc has no lines', () {
      final bare = _factsOf('# T\n\n## S\nx\n');
      expect(bare.sectionLines, [3]);
      expect(bare.lineCount, 3);
      final empty = _factsOf('');
      expect(empty.sectionLines, isEmpty);
      expect(empty.lineCount, 0);
      expect(empty.charCount, 0);
    });

    test('f04/nfr-p03: a final line without a line break counts as a line', () {
      expect(_factsOf('# T\n\n## S\nx').lineCount, 3);
      expect(_factsOf('# T\n\n## S\nx\n\n').lineCount, 3);
    });

    test('f04/nfr-p03: the doc count is the non-blank lines of the body after the frontmatter', () {
      expect(_factsOf(text).lineCount, 8);
      expect(
        _factsOf('---\nstatus: planned\n\n---\n\n# T\n\n\n## S\nx\n\n\n')
            .lineCount,
        3,
      );
    });

    test('f04/nfr-p03: invalid frontmatter still counts its body from the closing delimiter', () {
      expect(_factsOf('---\ntitle: "open\n---\n\n# T\n\nx\n\n\n').lineCount, 2);
    });

    test('f04/nfr-p03: a doc with no closed frontmatter counts its whole text as body', () {
      expect(_factsOf('---\nstatus: planned\n# T\n\nx\n\n').lineCount, 4);
    });

    test('f04/nfr-p03: an unclosed fence runs to the end of the file', () {
      final facts = _factsOf('# T\n\n```\n## hidden\nmore\n');
      expect(facts.fenced, [(first: 3, last: 5)]);
      expect(facts.sectionLines, isEmpty);
    });

    test('f04/nfr-p03: invalid frontmatter YAML stores the parser line, a non-mapping stores 1, valid or absent stores none', () {
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
      test(
        'f04/nfr-p03: $name: the line count is the non-blank body lines, the code points those of runes',
        () {
          final lf = raw.replaceAll('\r\n', '\n');
          final facts = _factsOf(raw);
          expect(
            facts.lineCount,
            nonBlankLinesOf(lfLinesOf(Doc.parse(lf).afterFrontmatter)),
          );
          expect(facts.charCount, lf.runes.length);
        },
      );
    }

    test('f04/nfr-p03, f04/us02/fr04, FM5: a link is placed from the line after the frontmatter, whatever ends the file', () {
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

    test('f04/nfr-p03: a fence indented up to three spaces counts, four spaces is code, and the last line may open one', () {
      expect(_factsOf('# T\n   ```\n## no\n   ```\n').fenced, [
        (first: 2, last: 4),
      ]);
      expect(_factsOf('# T\n    ```\n## yes\n').fenced, isEmpty);
      expect(_factsOf('# T\n```').fenced, [(first: 2, last: 2)]);
    });

    test('f04/nfr-p03: a tilde fence and a CRLF fence hide their ## lines', () {
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
    test('f04/nfr-p03: the JSON round-trips every fact but the section counts, which the section rows keep', () {
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

    test('f04/us02/fr04, PS-R3: the JSON round-trips the file links', () {
      final facts = _factsOf('# T\n\n![f](flow%20a.png) [c](../x.dart)\n');
      expect(facts.fileLinks, hasLength(2));
      final back = LineFacts.fromJson(
        jsonDecode(jsonEncode(facts.toJson())) as Map<String, Object?>,
        sectionCounts: facts.sectionCounts,
      );
      expect(back.fileLinks, facts.fileLinks);
    });

    test('f04/us02/fr04, PS-R3, P11: the JSON round-trips the self links, the '
        'unreadable links, and the anchor set', () {
      final facts = _factsOf(
        '# T\n\n[a](b.md#x) [s](#rules) [u](http://h:abc/x.md)\n'
        '## Rules\n',
        docPath: 'doc.md',
      );
      expect(facts.selfLinks, [
        (target: 'doc.md', line: 3, shown: '#rules', anchor: 'rules'),
      ]);
      expect(facts.unreadableLinks, [
        (
          target: 'http://h:abc/x.md',
          line: 3,
          shown: 'http://h:abc/x.md',
          anchor: null,
        ),
      ]);
      expect(facts.anchors, isNotNull);
      expect(facts.anchors!.holds('t'), isTrue);
      expect(facts.anchors!.holds('rules'), isTrue);
      final back = LineFacts.fromJson(
        jsonDecode(jsonEncode(facts.toJson())) as Map<String, Object?>,
        sectionCounts: facts.sectionCounts,
      );
      expect(back.selfLinks, facts.selfLinks);
      expect(back.unreadableLinks, facts.unreadableLinks);
      expect(back.anchors!.toJson(), facts.anchors!.toJson());
    });

    test('resolve_doc_links E21: an unreadable autolink is an unreadable link '
        'whatever else the body holds, so one link reads one way', () {
      const autolink = (
        target: 'http://h:99999/',
        line: 3,
        shown: 'http://h:99999/',
        anchor: null,
      );
      for (final body in [
        'Autolink only <http://h:99999/> here.',
        'Both <http://h:99999/> and [x](y.md).',
      ]) {
        expect(_factsOf('# T\n\n$body\n').unreadableLinks, [
          autolink,
        ], reason: body);
      }
    });

    test(
      's03/inv24, LP2, P11: a body the markdown parser fails on has no links '
      'and an unknown anchor set, stored as null',
      () {
        final facts = _factsOf('# T\n\n[a](b.md)\n\n[a]:<b\\');
        expect(facts.links, isEmpty);
        expect(facts.fileLinks, isEmpty);
        expect(facts.selfLinks, isEmpty);
        expect(facts.unreadableLinks, isEmpty);
        expect(facts.anchors, isNull);
      },
    );
  });

  group('LineFacts.of counted text', () {
    test('f04/nfr-p03: lineCount and charCount measure countedText '
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
