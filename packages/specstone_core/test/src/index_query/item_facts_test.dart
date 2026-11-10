import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/software_tech.dart';

const _frPath =
    'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
const _storyPath = 'prds/features/f01_login/us01_email_login/USER_STORY.md';

void main() {
  late DocTypeMatcher matcher;

  setUpAll(() async {
    matcher = DocTypeMatcher(await resolveSoftwareTech());
  });

  ParsedDoc parse(String path, String text, {List<int>? bytes}) =>
      parseIndexedDoc(
        docPath: path,
        bytes: bytes ?? utf8.encode(text),
        match: matcher.match(path),
      );
  ItemFacts factsOf(String path, String text) =>
      parse(path, text).content.itemFacts;
  MergedDocType typeOf(String path) =>
      (matcher.match(path) as MatchedDocType).docType;

  group('index_query/read_current_docs/index_each_doc', () {
    test('E21: a lead paragraph is a _lead count and an item with no ID, '
        'and each edge case holds its ID, line, and characters', () {
      const text =
          '---\nstatus: planned\n---\n\n# Validate credentials\n\n'
          'Check the pair.\n\n## Statement\n\nThe system shall check it.\n\n'
          '## Edge cases\n\n1. E01 — A wrong password → refused\n'
          '2. E02 — An unknown email → refused\n';
      final parsed = parse(_frPath, text);
      final lines = text.split('\n');
      final facts = parsed.content.itemFacts;

      expect(parsed.doc.formatted, isTrue);
      expect(facts.lead, (lines: 1, chars: 15));
      expect(facts.leadItems, [(id: null, line: 7, chars: 15)]);
      expect(facts.sectionItems, [
        [(id: null, line: 11, chars: lines[10].length)],
        [
          (id: 'E01', line: 15, chars: lines[14].length),
          (id: 'E02', line: 16, chars: lines[15].length),
        ],
      ]);
    });

    test('E08: text before the first ## is a lead of its own, apart from '
        'the sections', () {
      final facts = factsOf('README.md', '# T\n\nLead text.\n\n## Notes\nx\n');

      expect(facts.lead, (lines: 1, chars: 10));
      expect(facts.leadItems, [(id: null, line: 3, chars: 10)]);
      expect(facts.sectionItems, [
        [(id: null, line: 6, chars: 1)],
      ]);
    });

    test('E18: a padded table row and an item under a ### heading count as '
        'the laid-out text, and their lines are its lines', () {
      const text =
          '# V\n\n## Input / Output\n\n| Field | Type |\n|---|---|\n'
          '| a      | text   |\n\n## Statement\n### Heading\nBody text.\n';
      final parsed = parse(_frPath, text);
      final laid = layOutDoc(text, typeOf(_frPath)).split('\n');
      final facts = parsed.content.itemFacts;
      final row = facts.sectionItems.first.single;
      final heading = facts.sectionItems.last.single;

      expect(parsed.doc.formatted, isFalse);
      expect(laid[row.line - 1], startsWith('| a'));
      expect(row.chars, laid[row.line - 1].length);
      expect(row.chars, lessThan('| a      | text   |'.length));
      expect(laid[heading.line - 1], '### Heading');
      expect(
        heading.chars,
        '### Heading'.length + 1 + 0 + 1 + 'Body text.'.length,
      );
    });

    test('E18: a doc with sections out of template order has each section '
        'take the items of its laid-out twin', () {
      const text =
          '# Validate credentials\n\n## Edge cases\n'
          '1. E01 — A wrong password → refused\n\n'
          '## Statement\nThe system shall check it.\n';
      final parsed = parse(_frPath, text);
      final laid = layOutDoc(text, typeOf(_frPath)).split('\n');
      final facts = parsed.content.itemFacts;

      expect(parsed.doc.formatted, isFalse);
      expect(parsed.content.sections.map((s) => s.key), [
        'edge_cases',
        'statement',
      ]);
      expect(facts.sectionItems, [
        [
          (
            id: 'E01',
            line: 9,
            chars: '1. E01 — A wrong password → refused'.length,
          ),
        ],
        [(id: null, line: 5, chars: 'The system shall check it.'.length)],
      ]);
      expect(laid[8], startsWith('1. E01'));
      expect(laid[4], startsWith('The system'));
    });

    test('E19: a doc the format command refuses for a repeated header gives '
        'each of its two sections its own items, counted on disk', () {
      const text =
          '# Validate credentials\n\n## Statement\nfirst one\n\n'
          '## Statement\nsecond one is longer\n';
      final parsed = parse(_frPath, text);

      expect(parsed.doc.formatted, isNull);
      expect(parsed.content.itemFacts.sectionItems, [
        [(id: null, line: 4, chars: 'first one'.length)],
        [(id: null, line: 7, chars: 'second one is longer'.length)],
      ]);
    });

    test('E19: a doc the format command refuses for an unknown header counts '
        'its items as on disk, trailing spaces included', () {
      const text =
          '# V\n\n## Statement\nShall.\n\n## Mystery\nx  \n\n'
          '## Edge cases\n1. E01 — a\n';
      final parsed = parse(_frPath, text);
      final facts = parsed.content.itemFacts;

      expect(parsed.doc.formatted, isNull);
      expect(parsed.content.sections.map((s) => s.key), [
        'statement',
        'mystery',
        'edge_cases',
      ]);
      expect(facts.sectionItems[1], [(id: null, line: 7, chars: 3)]);
      expect(facts.sectionItems[2], [
        (id: 'E01', line: 10, chars: '1. E01 — a'.length),
      ]);
    });

    test('E20: a doc whose bytes are invalid text counts its items as decoded, '
        'a replacement character once', () {
      final bytes = [
        ...utf8.encode('# V\n\n## Statement\nab'),
        0xFF,
        ...utf8.encode('cd\n'),
      ];
      final parsed = parse(_frPath, '', bytes: bytes);

      expect(parsed.doc.formatted, isNull);
      expect(parsed.content.itemFacts.sectionItems, [
        [(id: null, line: 4, chars: 5)],
      ]);
    });

    test('E18: a ### Scenario heading of acceptance_criteria holds the key '
        'check holds it by, its number by value', () {
      const text =
          '# Email login\n\n## Acceptance Criteria\n### Scenario 01\n'
          'Given a user\n\n### Scenario 2\nGiven another\n';
      final laid = layOutDoc(text, typeOf(_storyPath)).split('\n');
      final items = factsOf(_storyPath, text).sectionItems.single;

      expect([for (final item in items) item.id], ['Scenario 1', 'Scenario 2']);
      for (final item in items) {
        expect(laid[item.line - 1], startsWith('### Scenario'));
      }
    });

    test('a section with a prefix_id gives each item the ID at its start, '
        'and a paragraph with none gives it null', () {
      const text =
          '# V\n\n## Edge cases\nA note first.\n\n1. E01 — a\n\n'
          '**E02** — b\n\nE03a — c\n';
      final items = factsOf(_frPath, text).sectionItems.single;

      expect([for (final item in items) item.id], [null, 'E01', 'E02', null]);
    });
  });

  group('index_query/read_current_docs/index_each_doc lead', () {
    test('E08: a doc with no title line takes its whole head as the lead', () {
      final facts = factsOf(
        'README.md',
        'Intro line\n\n- a\n- b\n\n## Notes\nx\n',
      );

      expect(facts.lead, (lines: 4, chars: 19));
      expect(facts.leadItems, [
        (id: null, line: 1, chars: 10),
        (id: null, line: 3, chars: 3),
        (id: null, line: 4, chars: 3),
      ]);
    });

    test('E08: text above the title line is neither title nor lead', () {
      final facts = factsOf(
        'README.md',
        'Above\n# T\nlead text\n\n## Notes\nx\n',
      );

      expect(facts.lead, (lines: 1, chars: 9));
      expect(facts.leadItems, [(id: null, line: 3, chars: 9)]);
    });

    test('print_docs_tree E12: a lead of blank lines only holds no count '
        'and no item', () {
      final facts = factsOf('README.md', '# T\n\n\n## Notes\nx\n');

      expect(facts.lead, isNull);
      expect(facts.leadItems, isEmpty);
      expect(facts.sectionItems, [
        [(id: null, line: 5, chars: 1)],
      ]);
    });

    test('a doc with no section keeps the lead, and an empty doc has none', () {
      expect(factsOf('README.md', '# T\n\nonly lead\n').sectionItems, isEmpty);
      final empty = factsOf('README.md', '');
      expect(empty.lead, isNull);
      expect(empty.leadItems, isEmpty);
    });

    test(
      'a fenced block in the lead counts toward the lead and is no item',
      () {
        final facts = factsOf(
          'README.md',
          '# T\n\n```\n- not an item\n```\n\nreal\n',
        );

        expect(facts.lead, (lines: 5, chars: 27));
        expect(facts.leadItems, [(id: null, line: 7, chars: 4)]);
      },
    );

    test('a lead counts from its first line of text to its last, leading and '
        'trailing blank lines left out', () {
      final facts = factsOf(
        'README.md',
        '# T\n\n\n\nfirst\n\nlast\n\n## N\nx\n',
      );

      expect(facts.lead, (lines: 3, chars: 'first'.length + 1 + 1 + 4));
      expect(facts.leadItems.map((i) => i.line), [5, 7]);
    });

    test(
      'the lead of a doc with frontmatter takes its lines from the file',
      () {
        final facts = factsOf('README.md', '---\na: b\n---\n# T\nlead\n');

        expect(facts.leadItems, [(id: null, line: 5, chars: 4)]);
      },
    );
  });

  group('itemFactsOf', () {
    test('a text that equals the laid-out text needs no parse of its own', () {
      const text = '# T\n\nLead.\n\n## Notes\nx\n';
      final doc = Doc.parse(text);
      final facts = itemFactsOf(
        doc: doc,
        lfText: text,
        countedText: text,
        type: null,
      );

      expect(facts.lead, (lines: 1, chars: 5));
      expect(facts.sectionItems, [
        [(id: null, line: 6, chars: 1)],
      ]);
    });

    test('a doc type that defines no prefix_id gives no ID', () {
      const text = '# T\n\n## Statement\nE01 — a\n';
      final facts = itemFactsOf(
        doc: Doc.parse(text),
        lfText: text,
        countedText: text,
        type: typeOf(_frPath),
      );

      expect(facts.sectionItems.single.single.id, isNull);
    });
  });

  group('ItemFacts JSON', () {
    test('a round trip through JSON text gives the same facts', () {
      final facts = factsOf(
        _frPath,
        '# V\n\nLead.\n\n## Edge cases\n1. E01 — a\n2. E02 — b\n',
      );
      final back = ItemFacts.fromJson(jsonDecode(jsonEncode(facts.toJson())));

      expect(back.lead, facts.lead);
      expect(back.leadItems, facts.leadItems);
      expect(back.sectionItems, facts.sectionItems);
      expect(jsonEncode(back.toJson()), jsonEncode(facts.toJson()));
    });

    test('a round trip keeps a null lead and a section with no item', () {
      final facts = factsOf(
        'README.md',
        '# T\n\n## Notes\n\n## More\n```\n```\n',
      );
      final back = ItemFacts.fromJson(jsonDecode(jsonEncode(facts.toJson())));

      expect(facts.lead, isNull);
      expect(back.lead, isNull);
      expect(back.leadItems, isEmpty);
      expect(back.sectionItems, [isEmpty, isEmpty]);
    });

    test('toJson writes each item as one compact array', () {
      final facts = factsOf('README.md', '# T\n\nLead.\n\n## Notes\nx\n');

      expect(jsonEncode(facts.toJson()), contains('[null,6,1]'));
    });
  });
}
