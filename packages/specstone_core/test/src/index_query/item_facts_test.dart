import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/held_sections.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_facts.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart'
    show FieldType;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/plain_items.dart';
import '../../helpers/software_tech.dart';

const _frPath =
    'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
const _journeyPath = 'prds/journeys/shop/JOURNEY.md';
const _storyPath = 'prds/features/f01_login/us01_email_login/USER_STORY.md';

void main() {
  late DocTypeMatcher matcher;

  setUpAll(() async {
    matcher = DocTypeMatcher(
      await resolveSoftwareTech(),
      targetNames: const [],
    );
  });

  ParsedDoc parse(
    String path,
    String text, {
    List<int>? bytes,
    Set<String> idPrefixes = const {},
  }) => parseIndexedDoc(
    docPath: path,
    bytes: bytes ?? utf8.encode(text),
    match: matcher.match(path),
    statusesOutside: true,
    idPrefixes: idPrefixes,
  );
  ItemFacts factsOf(String path, String text) =>
      parse(path, text).content.itemFacts;
  MergedDocType typeOf(String path) =>
      (matcher.match(path) as MatchedDocType).docType;

  group('Index each doc', () {
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
      expect(plainItems(facts.leadItems), [(id: null, line: 7, chars: 15)]);
      expect(plainSections(facts), [
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
      expect(plainItems(facts.leadItems), [(id: null, line: 3, chars: 10)]);
      expect(plainSections(facts), [
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
      expect(row.visibleChars, laid[row.line - 1].length);
      expect(row.visibleChars, lessThan('| a      | text   |'.length));
      expect(laid[heading.line - 1], '### Heading');
      expect(
        heading.visibleChars,
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
      expect(plainSections(facts), [
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

    test('E18: a lead that differs between the laid-out and the on-disk text '
        'takes its items from the laid-out head', () {
      const text =
          '# V\n\n| A | B |\n|---|---|\n| x     | y     |\n\n'
          '## Statement\n\nShall.\n';
      final parsed = parse(_frPath, text);
      final laid = layOutDoc(text, typeOf(_frPath)).split('\n');
      final facts = parsed.content.itemFacts;
      final row = facts.leadItems.single;

      expect(parsed.doc.formatted, isFalse);
      expect(laid[row.line - 1], '| x | y |');
      expect(row.visibleChars, '| x | y |'.length);
      expect(facts.lead, (lines: 3, chars: 9 + 1 + 9 + 1 + 9));
    });

    test('E18: a drifted doc whose section holds a fenced ## line gives each '
        'section its own items', () {
      const text =
          '# V\n\n## Edge cases\n1. E01 — a\n\n```\n## not a header\n```\n\n'
          '## Statement\nShall.\n';
      final parsed = parse(_frPath, text);
      final laid = layOutDoc(text, typeOf(_frPath)).split('\n');
      final facts = parsed.content.itemFacts;

      expect(parsed.doc.formatted, isFalse);
      expect(parsed.content.sections.map((s) => s.key), [
        'edge_cases',
        'statement',
      ]);
      expect(plainSections(facts), [
        [(id: 'E01', line: 9, chars: '1. E01 — a'.length)],
        [(id: null, line: 5, chars: 'Shall.'.length)],
      ]);
      expect(laid[8], '1. E01 — a');
      expect(laid[4], 'Shall.');
    });

    test('E19: a doc the format command refuses for a repeated header gives '
        'each of its two sections its own items, counted on disk', () {
      const text =
          '# Validate credentials\n\n## Statement\nfirst one\n\n'
          '## Statement\nsecond one is longer\n';
      final parsed = parse(_frPath, text);

      expect(parsed.doc.formatted, isNull);
      expect(plainSections(parsed.content.itemFacts), [
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
      expect(plainItems(facts.sectionItems[1]), [
        (id: null, line: 7, chars: 3),
      ]);
      expect(plainItems(facts.sectionItems[2]), [
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
      expect(plainSections(parsed.content.itemFacts), [
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

  group('lead', () {
    test('E08: a doc with no title line takes its whole head as the lead', () {
      final facts = factsOf(
        'README.md',
        'Intro line\n\n- a\n- b\n\n## Notes\nx\n',
      );

      expect(facts.lead, (lines: 4, chars: 19));
      expect(plainItems(facts.leadItems), [
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
      expect(plainItems(facts.leadItems), [(id: null, line: 3, chars: 9)]);
    });

    test('print_docs_tree E12: a lead of blank lines only holds no count '
        'and no item', () {
      final facts = factsOf('README.md', '# T\n\n\n## Notes\nx\n');

      expect(facts.lead, isNull);
      expect(plainItems(facts.leadItems), isEmpty);
      expect(plainSections(facts), [
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
        expect(plainItems(facts.leadItems), [(id: null, line: 7, chars: 4)]);
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

        expect(plainItems(facts.leadItems), [(id: null, line: 5, chars: 4)]);
      },
    );
  });

  group('Index each doc', () {
    test('a layout that would turn a body line into a frontmatter close '
        'leaves the doc counted on disk and the reindex whole', () {
      const text = '---\n# V\n\n## Statement\nThe system shall.\n--- \n';

      final parsed = parse(_frPath, text);

      expect(parsed.doc.formatted, isNull);
      expect(parsed.content.itemFacts.sectionItems, hasLength(1));
      expect(plainItems(parsed.content.itemFacts.sectionItems.single), [
        (id: null, line: 5, chars: 'The system shall.'.length),
      ]);
    });
  });

  group('generated blocks', () {
    final open = generatedOpenMarker('scenario_copy');
    final copied = '- **Given** ${'x' * 40}';

    test('the lines of a closed generated block in a section are no item, '
        'and the section still counts them', () {
      final text =
          '# Shop\n\n## Steps\n\n### 1. Start\nstep: a/b S1\n'
          '$open\n$copied\n- **When** go\n$generatedEndMarker\n';

      final parsed = parse(_journeyPath, text);
      final steps = parsed.content.itemFacts.sectionItems.single;

      expect(steps.map((item) => item.line), [5]);
      expect(
        parsed.content.lineFacts.sectionCounts.single.chars,
        greaterThan(copied.length),
      );
    });

    test('the lines of a closed generated block in the lead are no item, '
        'and the lead still counts them', () {
      final text =
          '# Shop\n\nLead.\n\n$open\n$copied\n$generatedEndMarker\n\n'
          '## Goal\nx\n';

      final facts = factsOf(_journeyPath, text);

      expect(facts.leadItems.map((item) => item.line), [3]);
      expect(facts.lead!.chars, greaterThan(copied.length));
    });

    test('an opening marker with no end marker changes no item', () {
      final text = '# Shop\n\n## Steps\n\n$open\n$copied\n';

      final facts = factsOf(_journeyPath, text);

      expect(facts.sectionItems.single.map((item) => item.line), [5, 6]);
    });
  });

  group('itemFactsOf', () {
    test('a doc with no layout counts its text as it is', () {
      const text = '# T\n\nLead.\n\n## Notes\nx\n';
      final doc = Doc.parse(text);
      final facts = itemFactsOf(
        doc: doc,
        lfText: text,
        lineFacts: LineFacts.structureOf(lfText: text, doc: doc),
        laid: null,
        type: null,
      );

      expect(facts.lead, (lines: 1, chars: 5));
      expect(plainSections(facts), [
        [(id: null, line: 6, chars: 1)],
      ]);
    });

    test('a doc type that defines no prefix_id gives no ID', () {
      const text = '# T\n\n## Statement\nE01 — a\n';
      final doc = Doc.parse(text);
      final facts = itemFactsOf(
        doc: doc,
        lfText: text,
        lineFacts: LineFacts.structureOf(lfText: text, doc: doc),
        laid: null,
        type: typeOf(_frPath),
      );

      expect(facts.sectionItems.single.single.id, isNull);
    });
  });

  group('readability facts', () {
    const idPrefixes = {'E', 'RULE-'};
    ItemFact only(ItemFacts facts, int section) =>
        facts.sectionItems[section].single;

    test('table row stores facts per cell', () {
      const text =
          '# V\n\n## Input / Output\n\n| Field | Type | Note |\n|---|---|---|\n'
          '| a | one two | three four five |\n';

      final row = only(factsOf(_frPath, text), 0);

      expect(row.readability.cells.map((cell) => cell.single.words), [1, 2, 3]);
      expect(row.readability.notes, isEmpty);
    });

    test('misplaced note text is stored', () {
      const text =
          '# V\n\n## Edge cases\n\n'
          '1. E01 — Check the pair (RULE-10) before the second clause.\n';

      final item = only(
        parse(_frPath, text, idPrefixes: idPrefixes).content.itemFacts,
        0,
      );

      expect(item.readability.notes, [(text: '(RULE-10)', closes: false)]);
      expect(item.readability.cells.single.single.words, 8);
    });

    test('item and fact counts agree on an unformatted doc', () {
      const bodies = [
        'Para one\n1. ordered under para\n2. second\n\n\n\n### H\nright\n- b\n',
        '> quote\n> - qi\n>\n> para\n\n| a | b |\n|---|---|\n| 1 | 2 |\n',
        'a | b\n--|--\n1 | 2\n',
        '* star\n+ plus\n\n   indented para\n\n```\ncode\n```\n- after\n',
        '- after\n   - nested\n',
        '### H\n> en: x\n> > deeper\n\n> ### QH\n> > deeper\n',
        '- a\nlazy\n- b\n\n  cont\n\n10. ten\n11) eleven\n',
      ];
      for (final body in bodies) {
        final content = parse(
          _frPath,
          '# V\n\n## Statement\n\n$body\n## Edge cases\n\n1. E01 — a\n',
        ).content;
        for (var i = 0; i < content.sections.length; i++) {
          final items = sectionItemsOf(
            sectionBodyLines(content.sections, content.lineFacts, i),
          );
          expect(
            content.itemFacts.sectionItems[i],
            hasLength(items.length),
            reason: body,
          );
        }
      }
    });

    test('closing note counts no sentence', () {
      const text = '# V\n\n## Statement\n\nShall check it. (RULE-10).\n';

      final item = only(
        parse(_frPath, text, idPrefixes: idPrefixes).content.itemFacts,
        0,
      );

      expect(item.readability.notes, [(text: '', closes: true)]);
      expect(item.readability.cells.single, hasLength(1));
    });

    test('pipe-less row with an id first cell keeps one list per column', () {
      const text =
          '# V\n\n## Edge cases\n\nID | One | Two\n---|---|---\n'
          'E01 | one word | two\n';

      final item = only(factsOf(_frPath, text), 0);

      expect(item.id, 'E01');
      expect(item.readability.cells, hasLength(3));
      expect(item.readability.cells[0], isEmpty);
      expect(item.readability.cells[1].single.words, 2);
      expect(item.readability.cells[2].single.words, 1);
    });

    test('scenario heading number stays in the text', () {
      const text =
          '# S\n\n## Acceptance criteria\n\n### Scenario 01\n\nGiven it.\n';

      final sentences = only(
        factsOf(_storyPath, text),
        0,
      ).readability.cells.single;

      expect(sentences.first.isHeading, isTrue);
      expect(sentences.first.words, 2);
    });

    test('bold id is stripped', () {
      const text = '# V\n\n## Edge cases\n\n1. **E01** — one two three\n';

      final item = only(factsOf(_frPath, text), 0);

      expect(item.id, 'E01');
      expect(item.readability.cells.single.single.words, 3);
    });

    test('note that took the id place leaves the text whole', () {
      const text = '# V\n\n## Edge cases\n\n1. E01 owns the thing.\n';

      final item = only(
        parse(_frPath, text, idPrefixes: idPrefixes).content.itemFacts,
        0,
      );

      expect(item.readability.notes, [(text: '', closes: true)]);
      expect(item.readability.cells.single.every((s) => s.words == 0), isTrue);
    });

    test('thai sentence stores th chars and runs', () {
      const text = '# V\n\n## Statement\n\nทุกครั้ง `check`\n';

      final sentence = only(
        factsOf(_frPath, text),
        0,
      ).readability.cells.single.single;

      expect(sentence.language, 'th');
      expect(sentence.countsChars, isTrue);
      expect(sentence.chars, 5);
      expect(sentence.runs, 1);
      expect(sentence.isHeading, isFalse);
    });

    test('heading sentence is marked', () {
      const text =
          '# V\n\n## Statement\n\n### A heading\n\nThe paragraph here.\n';

      final sentences = only(
        factsOf(_frPath, text),
        0,
      ).readability.cells.single;

      expect(sentences.map((sentence) => sentence.isHeading), [true, false]);
      expect(sentences.map((sentence) => sentence.words), [2, 3]);
    });

    test('leading id is stripped', () {
      const text = '# V\n\n## Edge cases\n\n1. E01 — one two three\n';

      final item = only(factsOf(_frPath, text), 0);

      expect(item.id, 'E01');
      expect(item.readability.cells.single.single.words, 3);
    });

    test('leading language marker counts no word', () {
      const text =
          '# V\n\n## Statement\n\n### A heading\n\n> en: one two three\n';

      final sentences = only(
        factsOf(_frPath, text),
        0,
      ).readability.cells.single;

      expect(sentences.map((sentence) => sentence.words), [2, 3]);
    });

    test('leading language marker counts no character', () {
      const text = '# V\n\n## Statement\n\n> th: ทุกครั้ง\n';

      final sentence = only(
        factsOf(_frPath, text),
        0,
      ).readability.cells.single.single;

      expect(sentence.language, 'th');
      expect(sentence.chars, 5);
      expect(sentence.runs, 0);
    });

    test('a marker-like word on a later quote line still counts', () {
      const text = '# V\n\n## Statement\n\n> see below\n> to: finish\n';

      final sentence = only(
        factsOf(_frPath, text),
        0,
      ).readability.cells.single.single;

      expect(sentence.words, 4);
    });

    test('a marker on each of chained quote lines counts no word', () {
      const text = '# V\n\n## Statement\n\n> en: one two.\n> th: three\n';

      final sentences = only(
        factsOf(_frPath, text),
        0,
      ).readability.cells.single;

      expect(sentences.map((sentence) => sentence.words), [2, 1]);
    });

    test('a colon after a longer word is no language marker', () {
      const text = '# V\n\n## Statement\n\n> note: one two\n';

      final sentence = only(
        factsOf(_frPath, text),
        0,
      ).readability.cells.single.single;

      expect(sentence.words, 3);
    });

    test('untyped doc stores no readability facts', () {
      final item = factsOf(
        'README.md',
        '# T\n\n## Notes\nsome words\n',
      ).sectionItems.single.single;

      expect(item.readability.cells, isEmpty);
      expect(item.readability.notes, isEmpty);
    });

    test('crlf doc stores the same readability facts', () {
      const text =
          '# V\n\n## Input / Output\n\n| Field | Type |\n|---|---|\n'
          '| a | one two |\n\n## Edge cases\n\n'
          '1. E01 — Check the pair (RULE-10) before it.\n\n'
          '## Statement\n\nทุกครั้ง `check`\n';

      final lf = parse(_frPath, text, idPrefixes: idPrefixes);
      final crlf = parse(
        _frPath,
        text,
        bytes: utf8.encode(text.replaceAll('\n', '\r\n')),
        idPrefixes: idPrefixes,
      );

      expect(
        jsonEncode(crlf.content.itemFacts.toJson()),
        jsonEncode(lf.content.itemFacts.toJson()),
      );
      expect(crlf.content.itemFacts.sectionItems.first, isNotEmpty);
    });
  });

  group('visible counts', () {
    const rule = '- See [the rule](a/b.md#rules).';

    List<int> visibleOf(List<ItemFact> items) => [
      for (final item in items) item.visibleChars,
    ];

    int sectionCharsOf(ParsedDoc parsed) =>
        parsed.content.lineFacts.sectionCounts.single.chars;

    test('link item stores its visible count while its section stays raw', () {
      final parsed = parse(_frPath, '# V\n\n## Statement\n\n$rule\n');

      expect(visibleOf(parsed.content.itemFacts.sectionItems.single), [15]);
      expect(sectionCharsOf(parsed), '## Statement\n\n$rule'.length);
    });

    test('definition line adds nothing to its paragraph', () {
      const paragraph = '[r]: a/b.md\nSee [the rule][r].';
      final parsed = parse(_frPath, '# V\n\n## Statement\n\n$paragraph\n');

      expect(visibleOf(parsed.content.itemFacts.sectionItems.single), [13]);
      expect(sectionCharsOf(parsed), '## Statement\n\n$paragraph'.length);
    });

    test('code span link counts whole', () {
      const item = '- Run `[a](b.md)` once.';
      final parsed = parse(_frPath, '# V\n\n## Statement\n\n$item\n');

      expect(visibleOf(parsed.content.itemFacts.sectionItems.single), [23]);
      expect(sectionCharsOf(parsed), '## Statement\n\n$item'.length);
    });

    test('failed parse stores raw item counts', () {
      const item = '- See [a](b.md).';
      final parsed = parse(_frPath, '# V\n\n## Statement\n\n$item\n\n[a]:<b\\');

      expect(parsed.doc.warnings, [markdownUnparsedWarning(_frPath)]);
      expect(
        visibleOf(parsed.content.itemFacts.sectionItems.single).first,
        item.length,
      );
    });

    // No body makes `readersAgree` false, so the link the scan alone lists is
    // one in a footnote definition, which the parser drops.
    test('disagreeing readers drop parser links only: a link the scan alone '
        'lists counts whole', () {
      const read = 'See [y](y.md).';
      const scanOnly = '[^1]: Also [b](b.md).';
      final parsed = parse(
        _frPath,
        '# V\n\n## Statement\n\n$read\n\n$scanOnly\n',
      );

      expect(visibleOf(parsed.content.itemFacts.sectionItems.single), [
        'See y.'.length,
        scanOnly.length,
      ]);
    });

    test('unformatted doc with frontmatter counts links on the lines its '
        'layout moves them to', () {
      const lead = 'Lead [x](lead/l.md) here.';
      const edge = '1. E01 — See [a](b.md).';
      const statement = 'The [rule](rules/r.md) shall hold.';
      const text =
          '---\nstatus: planned\n---\n\n# V\n\n$lead\n\n'
          '## Edge cases\n$edge\n\n## Statement\n$statement\n';
      final parsed = parse(_frPath, text);
      final laid = layOutDoc(text, typeOf(_frPath)).split('\n');
      final facts = parsed.content.itemFacts;
      final edgeItem = facts.sectionItems.first.single;
      final statementItem = facts.sectionItems.last.single;

      expect(parsed.doc.formatted, isFalse);
      expect(laid[edgeItem.line - 1], edge);
      expect(laid[statementItem.line - 1], statement);
      expect(edgeItem.line, isNot(text.split('\n').indexOf(edge) + 1));
      expect(edgeItem.visibleChars, '1. E01 — See a.'.length);
      expect(statementItem.visibleChars, 'The rule shall hold.'.length);
      expect(visibleOf(facts.leadItems), ['Lead x here.'.length]);
    });

    test('shortcut reference stores its label', () {
      const paragraph = '[r]: a/b.md\nSee [r].';
      final parsed = parse(_frPath, '# V\n\n## Statement\n\n$paragraph\n');

      expect(visibleOf(parsed.content.itemFacts.sectionItems.single), [6]);
      expect(sectionCharsOf(parsed), '## Statement\n\n$paragraph'.length);
    });

    test('undefined shortcut stores every character', () {
      const item = '- See [x].';
      final parsed = parse(_frPath, '# V\n\n## Statement\n\n$item\n');

      expect(visibleOf(parsed.content.itemFacts.sectionItems.single), [10]);
    });

    test('definition after paragraph text counts', () {
      const paragraph = 'See this.\n[r]: a/b.md';
      final parsed = parse(_frPath, '# V\n\n## Statement\n\n$paragraph\n');

      expect(visibleOf(parsed.content.itemFacts.sectionItems.single), [
        paragraph.length,
      ]);
    });

    test('lead item drops its link markup', () {
      const lead = 'See [the rule](a/b.md#rules).';
      final parsed = parse(_frPath, '# V\n\n$lead\n\n## Statement\n\nShall.\n');
      final facts = parsed.content.itemFacts;

      expect(visibleOf(facts.leadItems), ['See the rule.'.length]);
      expect(facts.lead, (lines: 1, chars: lead.length));
    });

    test('crlf doc stores the same visible counts', () {
      const text =
          '# V\n\n$rule\n\n## Statement\n\n[r]: a/b.md\nSee [the rule][r].\n'
          '\n## Edge cases\n\n1. E01 — A [link](x.md) here.\n';

      final lf = parse(_frPath, text);
      final crlf = parse(
        _frPath,
        text,
        bytes: utf8.encode(text.replaceAll('\n', '\r\n')),
      );

      expect(
        jsonEncode(crlf.content.itemFacts.toJson()),
        jsonEncode(lf.content.itemFacts.toJson()),
      );
      expect(visibleOf(crlf.content.itemFacts.leadItems), [15]);
      expect(visibleOf(crlf.content.itemFacts.sectionItems.first), [13]);
      expect(visibleOf(crlf.content.itemFacts.sectionItems.last), [
        '1. E01 — A link here.'.length,
      ]);
    });
  });

  group('prose fields', () {
    const noteType = MergedDocType(
      id: 'note',
      fields: [
        MergedField(
          id: 'summary',
          type: FieldType.string,
          lint: FieldCaps(maxSentences: 2),
        ),
        MergedField(id: 'plain', type: FieldType.string),
      ],
      sections: [],
      lint: MergedLint(),
      files: [],
    );

    ItemFacts noteFacts(String text) => parseIndexedDoc(
      docPath: 'n.md',
      bytes: utf8.encode(text),
      match: MatchedDocType(noteType),
      statusesOutside: true,
    ).content.itemFacts;

    test('a string value stores its sentences as one item and adds no item '
        'count', () {
      final facts = noteFacts(
        '---\nsummary: One two three. Four five.\n---\n\n# T\n',
      );

      final cells = facts.fieldItems['summary']!.readability.cells;
      expect(cells, hasLength(1));
      expect(cells.single.map((s) => (s.language, s.words)), [
        ('default', 3),
        ('default', 2),
      ]);
      expect(facts.fieldItems.keys, ['summary']);
      expect(facts.leadItems, isEmpty);
      expect(facts.sectionItems, isEmpty);
    });

    test('a field that sets no lint gets no facts', () {
      expect(
        noteFacts('---\nplain: One two.\n---\n\n# T\n').fieldItems,
        isEmpty,
      );
    });

    test('a value that is not a string gets no facts', () {
      expect(
        noteFacts('---\nsummary: [a, b]\n---\n\n# T\n').fieldItems,
        isEmpty,
      );
      expect(noteFacts('---\nsummary: 42\n---\n\n# T\n').fieldItems, isEmpty);
    });

    test('an untyped doc gets no facts', () {
      expect(
        factsOf('README.md', '---\nsummary: One two.\n---\n\n# T\n').fieldItems,
        isEmpty,
      );
    });

    test('the field facts round-trip through JSON', () {
      final facts = noteFacts('---\nsummary: One two. Three.\n---\n\n# T\n');
      final back = ItemFacts.fromJson(jsonDecode(jsonEncode(facts.toJson())));

      expect(
        back.fieldItems['summary']!.readability.cells,
        facts.fieldItems['summary']!.readability.cells,
      );
      expect(jsonEncode(back.toJson()), jsonEncode(facts.toJson()));
    });
  });

  group('ItemFacts JSON', () {
    test('a round trip keeps the visible count of a link item', () {
      final facts = factsOf(
        _frPath,
        '# V\n\nLead [a](b.md).\n\n## Statement\n\n'
        '- See [the rule](a/b.md#rules).\n',
      );
      final back = ItemFacts.fromJson(jsonDecode(jsonEncode(facts.toJson())));

      expect(plainItems(back.leadItems), [(id: null, line: 3, chars: 7)]);
      expect(plainSections(back), [
        [(id: null, line: 7, chars: 15)],
      ]);
      expect(jsonEncode(back.toJson()), jsonEncode(facts.toJson()));
    });

    test('a round trip through JSON text gives the same facts', () {
      final facts = factsOf(
        _frPath,
        '# V\n\nLead.\n\n## Edge cases\n1. E01 — a\n2. E02 — b\n',
      );
      final back = ItemFacts.fromJson(jsonDecode(jsonEncode(facts.toJson())));

      expect(back.lead, facts.lead);
      expect(plainItems(back.leadItems), plainItems(facts.leadItems));
      expect(plainSections(back), plainSections(facts));
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

    test('readability facts round-trip through JSON', () {
      const text =
          '# V\n\n## Input / Output\n\n| Field | Type |\n|---|---|\n'
          '| a | one two (RULE-10) after |\n\n## Edge cases\n\n'
          '1. E01 — Check (RULE-10) before it.\n\n'
          '## Statement\n\n### Head\n\nทุกครั้ง `check` (RULE-10).\n';
      final facts = parse(
        _frPath,
        text,
        idPrefixes: const {'E', 'RULE-'},
      ).content.itemFacts;
      final back = ItemFacts.fromJson(jsonDecode(jsonEncode(facts.toJson())));

      for (var i = 0; i < facts.sectionItems.length; i++) {
        for (var k = 0; k < facts.sectionItems[i].length; k++) {
          final was = facts.sectionItems[i][k].readability;
          final now = back.sectionItems[i][k].readability;
          expect(now.cells, was.cells);
          expect(now.notes, was.notes);
        }
      }
      expect(facts.sectionItems.expand((items) => items).length, 3);
      expect(
        facts.sectionItems.last.single.readability.cells.single.first.isHeading,
        isTrue,
      );
    });

    test('toJson writes each item as one compact array', () {
      final facts = factsOf('README.md', '# T\n\nLead.\n\n## Notes\nx\n');

      expect(jsonEncode(facts.toJson()), contains('[null,6,1,'));
    });
  });
}
