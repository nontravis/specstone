import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:test/test.dart';

/// The stored facts of [text], as refresh computes them.
DocContent _contentOf(String text) => parseIndexedDoc(
  docPath: 'doc.md',
  bytes: utf8.encode(text),
  match: const NoDocType(),
).content;

LineFacts _factsOf(String text) => _contentOf(text).lineFacts;

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
    test('f04/nfr-p03: a doc with frontmatter, title, sections, and a fence hiding a ## has 1-based file lines', () {
      final facts = _factsOf(text);
      expect(facts.bodyLine, 4);
      expect(facts.titleLine, 5);
      expect(facts.sectionLines, [7, 13]);
      expect(facts.fenced, [(first: 9, last: 11)]);
      expect(facts.lineCount, 14);
      expect(facts.charCount, text.runes.length);
      expect(facts.frontmatterErrorLine, isNull);
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

    test('f04/nfr-p03: a CRLF file has the facts of its LF twin', () {
      final lf = _factsOf(text);
      final crlf = _factsOf(text.replaceAll('\n', '\r\n'));
      expect(crlf.toJson(), lf.toJson());
      expect(crlf.sectionCounts, lf.sectionCounts);
      expect(crlf.charCount, text.runes.length);
    });

    test('f04/nfr-p03: a doc without frontmatter starts its body on line 1, and an empty doc has no lines', () {
      final bare = _factsOf('# T\n\n## S\nx\n');
      expect(bare.bodyLine, 1);
      expect(bare.titleLine, 1);
      expect(bare.sectionLines, [3]);
      final empty = _factsOf('');
      expect(empty.bodyLine, 1);
      expect(empty.titleLine, isNull);
      expect(empty.sectionLines, isEmpty);
      expect(empty.lineCount, 0);
      expect(empty.charCount, 0);
    });

    test('f04/nfr-p03: a final line without a line break counts as a line', () {
      expect(_factsOf('# T\n\n## S\nx').lineCount, 4);
      expect(_factsOf('# T\n\n## S\nx\n\n').lineCount, 5);
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

  group('LineFacts JSON', () {
    test('f04/nfr-p03: the JSON round-trips every fact but the section counts, which the section rows keep', () {
      final facts = _factsOf(text);
      final back = LineFacts.fromJson(
        jsonDecode(jsonEncode(facts.toJson())) as Map<String, Object?>,
        sectionCounts: facts.sectionCounts,
      );
      expect(back.toJson(), facts.toJson());
      expect(back.sectionCounts, facts.sectionCounts);
      expect(back.bodyLine, 4);
      expect(back.titleLine, 5);
      expect(back.sectionLines, [7, 13]);
      expect(back.fenced, [(first: 9, last: 11)]);
      expect(back.isFenced(10), isTrue);
      expect(back.isFenced(12), isFalse);
    });
  });
}
