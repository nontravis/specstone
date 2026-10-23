import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:test/test.dart';

List<String> _keys(Doc doc) => [for (final b in doc.frontmatter!) b.key];

List<String> _texts(Doc doc) => [for (final b in doc.frontmatter!) b.text];

List<String> _headers(Doc doc) => [for (final s in doc.sections) s.headerText];

void main() {
  group('Doc.parse', () {
    test('doc_model/s03/inv4: frontmatter, head, and sections in file '
        'order', () {
      final doc = Doc.parse(
        '---\nstatus: planned\n---\n\n# T\n\nlead\n\n## A\na1\n### A.1\na2\n'
        '\n## B\nb\n',
      );

      expect(_keys(doc), ['status']);
      expect(doc.head, '\n# T\n\nlead\n');
      expect(_headers(doc), ['A', 'B']);
      expect(doc.sections[0].body, 'a1\n### A.1\na2\n');
      expect(doc.sections[1].body, 'b\n');
      expect(doc.title, 'T');
    });

    test('doc_model/s03/inv4: afterFrontmatter is the text after the closing '
        'line', () {
      final doc = Doc.parse('---\nstatus: planned\n---\n\n# T\n\n## A\na\n');

      expect(doc.afterFrontmatter, '\n# T\n\n## A\na\n');
    });

    test('doc_model/s03/inv4: a section keeps its header line as written and '
        'the text after ## trimmed', () {
      final doc = Doc.parse('##   Spaced  Title \t\n   ## Indented\n##\nend\n');

      expect(
        [for (final s in doc.sections) s.headerLine],
        ['##   Spaced  Title \t', '   ## Indented', '##'],
      );
      expect(_headers(doc), ['Spaced  Title', 'Indented', '']);
    });

    test('doc_model/s03/inv4: a line that is not a ## header opens no '
        'section', () {
      final doc = Doc.parse('##x\n    ## four spaces\n#### deep\n# one\n');

      expect(doc.sections, isEmpty);
      expect(doc.head, '##x\n    ## four spaces\n#### deep\n# one\n');
    });

    test('doc_model/s03/inv5: a section body keeps inner bytes and drops '
        'trailing blank lines', () {
      final doc = Doc.parse('## A\nx  \n\n\ty\n\n\n');

      expect(doc.sections.single.body, 'x  \n\n\ty\n');
    });

    test('doc_model/s03/inv5: a section with only blank lines has an empty '
        'body', () {
      final doc = Doc.parse('## A\n\n  \n## B\nb\n');

      expect(doc.sections[0].body, '');
      expect(doc.sections[1].body, 'b\n');
    });

    test('doc_model/s03/inv5: a last line without a newline is kept', () {
      final doc = Doc.parse('## A\na\nlast');

      expect(doc.sections.single.body, 'a\nlast');
    });

    test(
      'doc_model/s03/inv6, f05/us01/fr03/e03: key blocks keep their text byte '
      'for byte',
      () {
        final doc = Doc.parse(
          '---\n# owner note\nvision:\n  - PV-01\n  # inner\n# date note\n'
          'date: 2026-10-23 # c\nq: "x"\n# tail\n---\n',
        );

        expect(_keys(doc), ['vision', 'date', 'q']);
        expect(_texts(doc), [
          '# owner note\nvision:\n  - PV-01\n  # inner\n',
          '# date note\ndate: 2026-10-23 # c\n',
          'q: "x"\n# tail\n',
        ]);
        expect(doc.frontmatter![1].valueText, '2026-10-23 # c');
        expect(doc.frontmatter![0].valueText, '- PV-01');
        expect(doc.frontmatter![2].valueText, '"x"');
      },
    );

    test('doc_model/s03/inv6: blank lines above a key join that key and '
        'the blocks cover every line', () {
      const inner = 'a: 1\n\n# about b\n\nb: 2\n  more\nc:\n\n';
      final doc = Doc.parse('---\n$inner---\n');

      expect(_texts(doc), [
        'a: 1\n',
        '\n# about b\n\nb: 2\n  more\n',
        'c:\n\n',
      ]);
      expect(_texts(doc).join(), inner);
    });

    test('doc_model/s03/inv6: a quoted key and a key holding a colon start '
        'blocks', () {
      final doc = Doc.parse('---\n"a b": 1\nurl: http://x\n\'q\': 2\n---\n');

      expect(_keys(doc), ['"a b"', 'url', "'q'"]);
    });

    test('doc_model/s03/inv6: an empty frontmatter has no blocks', () {
      final doc = Doc.parse('---\n---\n# T\n');

      expect(doc.frontmatter, isEmpty);
      expect(doc.title, 'T');
    });

    test('doc_model/s03/inv6 (controller ruling): frontmatter with no key '
        'line forms one keyless block', () {
      final list = Doc.parse('---\n- a\n- b\n---\n# T\n');
      final comment = Doc.parse('---\n# note\n---\n');

      expect(_keys(list), ['']);
      expect(_texts(list), ['- a\n- b\n']);
      expect(list.frontmatter!.single.valueText, '');
      expect(_keys(comment), ['']);
      expect(_texts(comment), ['# note\n']);
    });

    test('doc_model/s03/inv6 (controller ruling): a stray line above the '
        'first key forms a leading keyless block', () {
      final doc = Doc.parse(
        '---\n- a\n# stray note\n\n  indented\n# owns k\nk: 1\nj: 2\n---\n',
      );

      expect(_keys(doc), ['', 'k', 'j']);
      expect(_texts(doc), [
        '- a\n# stray note\n\n  indented\n',
        '# owns k\nk: 1\n',
        'j: 2\n',
      ]);
    });

    test('doc_model/s03/inv6 (controller ruling): comments directly above '
        'the first key stay with that key', () {
      final doc = Doc.parse('---\n# one\n\n# two\nk: 1\n---\n');

      expect(_keys(doc), ['k']);
      expect(_texts(doc), ['# one\n\n# two\nk: 1\n']);
    });

    test('f05/us01/fr03/e04: no leading --- means no frontmatter', () {
      final doc = Doc.parse('\n---\nstatus: planned\n---\n# T\n');

      expect(doc.frontmatter, isNull);
      expect(doc.afterFrontmatter, '\n---\nstatus: planned\n---\n# T\n');
    });

    test('f05/us01/fr03/e04: --- with trailing space does not open or close '
        'frontmatter', () {
      expect(Doc.parse('--- \nk: v\n---\n').frontmatter, isNull);
      expect(Doc.parse('---\nk: v\n--- \n').frontmatter, isNull);
    });

    test(
      'f05/us01/fr03/e04: no closing line means no frontmatter and all text is '
      'head',
      () {
        final doc = Doc.parse('---\nstatus: planned\n');

        expect(doc.frontmatter, isNull);
        expect(doc.head, '---\nstatus: planned\n');
        expect(doc.sections, isEmpty);
      },
    );

    test('f05/us01/fr03/e01: a ### heading stays in the ## body', () {
      final doc = Doc.parse('## A\n### sub\ntext\n#### deeper\n## B\n');

      expect(_headers(doc), ['A', 'B']);
      expect(doc.sections[0].body, '### sub\ntext\n#### deeper\n');
    });

    test(
      'review focus 1: a ## line inside a fenced block is not a section',
      () {
        final doc = Doc.parse('## A\n```md\n## not a section\n```\n');

        expect(_headers(doc), ['A']);
        expect(doc.sections.single.body, '```md\n## not a section\n```\n');
      },
    );

    test('review focus 1: a fence closes on the same character and at least '
        'as many', () {
      final doc = Doc.parse(
        '## A\n````\n```\n## in\n~~~~\n````\n## B\n~~~\n## in\n```\n'
        '~~~~\n## C\n',
      );

      expect(_headers(doc), ['A', 'B', 'C']);
    });

    test('review focus 1: an unclosed fence runs to the end of the text', () {
      final doc = Doc.parse('## A\n   ```\n## in\n## in too\n');

      expect(_headers(doc), ['A']);
    });

    test('review focus 1: a backtick fence whose info string holds a '
        'backtick is not a fence', () {
      final doc = Doc.parse('## A\n```a`b\n## B\n');

      expect(_headers(doc), ['A', 'B']);
    });

    test('review focus 1: a fenced block in the head hides its ## line', () {
      final doc = Doc.parse('~~~\n## x\n~~~\n## A\n');

      expect(_headers(doc), ['A']);
      expect(doc.head, '~~~\n## x\n~~~\n');
    });

    test('title is the text after "# " on the first such head line', () {
      expect(Doc.parse('# List doc types\n\n## A\n').title, 'List doc types');
      expect(Doc.parse('lead\n#  Spaced \n# second\n').title, ' Spaced ');
    });

    test('title is null without a "# " head line', () {
      expect(Doc.parse('lead\n## A\n# not in head\n').title, isNull);
      expect(Doc.parse('#nospace\n').title, isNull);
      expect(Doc.parse('').title, isNull);
    });

    test('title ignores a "# " line inside a fenced block', () {
      expect(Doc.parse('```sh\n# comment\n```\n# Real\n').title, 'Real');
    });

    test('isDraft reads the draft key as a YAML boolean', () {
      expect(Doc.parse('---\ndraft: true\n---\n').isDraft, isTrue);
      expect(Doc.parse('---\ndraft: false\n---\n').isDraft, isFalse);
      expect(Doc.parse('---\ndraft: [\n---\n').isDraft, isFalse);
    });

    test('isDraft is false without a draft key, without frontmatter, or for '
        'a non-boolean value', () {
      expect(Doc.parse('---\nstatus: planned\n---\n').isDraft, isFalse);
      expect(Doc.parse('draft: true\n').isDraft, isFalse);
      expect(Doc.parse('---\ndraft: "true"\n---\n').isDraft, isFalse);
      expect(Doc.parse('---\ndraft:\n---\n').isDraft, isFalse);
    });

    test('isDraft ignores comments around the draft key', () {
      final doc = Doc.parse('---\n# flag\ndraft: true # now\n# tail\n---\n');

      expect(doc.isDraft, isTrue);
    });

    test('an empty text parses to an empty doc', () {
      final doc = Doc.parse('');

      expect(doc.frontmatter, isNull);
      expect(doc.head, '');
      expect(doc.sections, isEmpty);
      expect(doc.afterFrontmatter, '');
    });
  });
}
