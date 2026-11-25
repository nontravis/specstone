import 'package:specstone_core/src/templates/guide_limits.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/shared_lines.dart';

MergedSection _section({
  int? minLines,
  int? maxLines,
  int? maxChars,
  int? maxItemLines,
  int? maxSubsections,
  ItemCountLint? itemCount,
  List<SentenceLimit>? maxSentences,
  MaxCodeBlocks? maxCodeBlocks,
}) => MergedSection(
  id: 's',
  header: 'S',
  minLines: minLines,
  maxLines: maxLines,
  maxChars: maxChars,
  maxItemLines: maxItemLines,
  maxSubsections: maxSubsections,
  itemCount: itemCount,
  maxSentences: maxSentences,
  maxCodeBlocks: maxCodeBlocks,
);

void main() {
  group('docLimitsLine', () {
    test('the doc-level clauses come in key order', () {
      const lint = MergedLint(
        maxLines: 300,
        maxChars: 12000,
        maxItemChars: 400,
      );

      expect(
        docLimitsLine(lint),
        'Limits: ≤ 300 lines; ≤ 12,000 characters; '
        '≤ 400 characters per item; $builtInSentenceLimitClauses',
      );
    });

    test('a doc type that sets no limit still prints the three built-in '
        'clauses', () {
      expect(docLimitsLine(const MergedLint()), 'Limits: $builtInLimitClauses');
    });

    test('a doc line holds all five clauses in key order', () {
      const lint = MergedLint(maxLines: 10, maxChars: 500, maxItemChars: 50);

      expect(
        docLimitsLine(lint),
        'Limits: ≤ 10 lines; ≤ 500 characters; ≤ 50 characters per item; '
        '$builtInSentenceLimitClauses',
      );
    });

    test('a sentence map lists every entry but default in merged order', () {
      final lint = MergedLint(
        maxSentenceWords: builtInSentenceWords.mergedWith({'vi': 30, 'ko': 20}),
        maxSentenceChars: const SentenceCaps({'default': 80}),
      );

      expect(
        docLimitsLine(lint),
        'Limits: ≤ 600 characters per item; '
        '≤ 25 words per sentence (ko 20, vi 30); '
        '≤ 80 characters per sentence in a no-space script.',
      );
    });
  });

  group('sectionLimitsClause', () {
    final cases = <String, (MergedSection, String)>{
      'min_lines': (_section(minLines: 2), '≥ 2 lines'),
      'max_lines': (_section(maxLines: 4), '≤ 4 lines'),
      'max_chars': (_section(maxChars: 1500), '≤ 1,500 characters'),
      'max_item_lines': (_section(maxItemLines: 1), '≤ 1 line per item'),
      'max_subsections': (_section(maxSubsections: 6), '≤ 6 subsections'),
      'item_count with min equal to max': (
        _section(itemCount: const ItemCountLint(min: 2, max: 2)),
        'exactly 2 items',
      ),
      'item_count with a min and a max': (
        _section(itemCount: const ItemCountLint(min: 3, max: 5)),
        '3 to 5 items',
      ),
      'item_count with a min': (
        _section(itemCount: const ItemCountLint(min: 1)),
        '≥ 1 item',
      ),
      'item_count with a max': (
        _section(itemCount: const ItemCountLint(max: 7)),
        '≤ 7 items',
      ),
      'item_count prefixes': (
        _section(
          itemCount: const ItemCountLint(
            prefixes: [
              LinePrefixCount(linePrefix: '- **When**', count: 1),
              LinePrefixCount(linePrefix: '- **Then**', count: 2),
            ],
          ),
        ),
        'exactly 1 `- **When**` item; exactly 2 `- **Then**` items',
      ),
      'item_count per_subsection': (
        _section(
          itemCount: const ItemCountLint(
            min: 3,
            max: 5,
            perSubsection: true,
            prefixes: [LinePrefixCount(linePrefix: '- **When**', count: 1)],
          ),
        ),
        'in each subsection, 3 to 5 items and exactly 1 `- **When**` item',
      ),
      'max_sentences with no prefix or column': (
        _section(maxSentences: const [SentenceLimit(count: 1)]),
        '≤ 1 sentence per item',
      ),
      'max_sentences with a line_prefix': (
        _section(
          maxSentences: const [
            SentenceLimit(count: 2, linePrefix: '- **Why:**'),
          ],
        ),
        '≤ 2 sentences per `- **Why:**` item',
      ),
      'max_sentences with a column': (
        _section(
          maxSentences: const [SentenceLimit(count: 2, column: 'Notes')],
        ),
        '≤ 2 sentences per `Notes` cell',
      ),
      'max_sentences with both': (
        _section(
          maxSentences: const [
            SentenceLimit(count: 3, column: 'Notes', linePrefix: '| A'),
          ],
        ),
        '≤ 3 sentences per `Notes` cell opening with `| A`',
      ),
      'max_code_blocks': (
        _section(maxCodeBlocks: const MaxCodeBlocks(count: 1)),
        '≤ 1 code block',
      ),
      'max_code_blocks per_subsection': (
        _section(
          maxCodeBlocks: const MaxCodeBlocks(count: 2, perSubsection: true),
        ),
        'in each subsection, ≤ 2 code blocks',
      ),
    };
    for (final MapEntry(key: name, value: (section, clause)) in cases.entries) {
      test('a section clause follows the key order and wording: $name', () {
        expect(sectionLimitsClause(section), clause);
      });
    }

    test('a section clause follows the key order and wording across every '
        'key', () {
      final section = _section(
        minLines: 2,
        maxLines: 40,
        maxChars: 2000,
        maxItemLines: 3,
        maxSubsections: 6,
        itemCount: const ItemCountLint(min: 3, max: 5, perSubsection: true),
        maxSentences: const [SentenceLimit(count: 1)],
        maxCodeBlocks: const MaxCodeBlocks(count: 2, perSubsection: true),
      );

      expect(
        sectionLimitsClause(section),
        '≥ 2 lines; ≤ 40 lines; '
        '≤ 2,000 characters; ≤ 3 lines per item; '
        '≤ 6 subsections; in each subsection, 3 to 5 items; '
        '≤ 1 sentence per item; in each subsection, ≤ 2 code blocks',
      );
    });

    test('per-subsection item clauses sit under one lead', () {
      final section = _section(
        itemCount: const ItemCountLint(
          min: 3,
          max: 5,
          perSubsection: true,
          prefixes: [
            LinePrefixCount(linePrefix: '- **When**', count: 1),
            LinePrefixCount(linePrefix: '- **Then**', count: 1),
          ],
        ),
      );

      expect(
        sectionLimitsClause(section),
        'in each subsection, 3 to 5 items, exactly 1 `- **When**` item, '
        'and exactly 1 `- **Then**` item',
      );
    });

    test('a section that sets no size key prints no clause', () {
      expect(sectionLimitsClause(_section()), isNull);
      expect(
        sectionLimitsClause(_section(itemCount: const ItemCountLint())),
        isNull,
      );
      expect(sectionLimitsClause(_section(maxSentences: const [])), isNull);
    });
  });

  group('fieldLimitsLine', () {
    test('a field limits line holds its sentence count and its two maps', () {
      const caps = FieldCaps(
        maxSentences: 1,
        maxSentenceWords: {'default': 15, 'ko': 10},
        maxSentenceChars: {'default': 60, 'th': 60, 'ja': 36, 'zh': 27},
      );

      expect(
        fieldLimitsLine(caps),
        '  Limits: ≤ 1 sentence; ≤ 15 words per sentence (ko 10); '
        '≤ 60 characters per sentence in a no-space script '
        '(th 60, ja 36, zh 27).',
      );
    });

    test('a field that caps sentences alone prints that clause alone', () {
      expect(
        fieldLimitsLine(const FieldCaps(maxSentences: 3)),
        '  Limits: ≤ 3 sentences.',
      );
    });

    test('a field line holds its three clauses in no-space wording', () {
      const caps = FieldCaps(
        maxSentences: 2,
        maxSentenceWords: {'default': 20},
        maxSentenceChars: {'default': 80},
      );

      expect(
        fieldLimitsLine(caps),
        '  Limits: ≤ 2 sentences; ≤ 20 words per sentence; '
        '≤ 80 characters per sentence in a no-space script.',
      );
    });

    test('a field with no caps prints no line', () {
      expect(fieldLimitsLine(null), isNull);
      expect(fieldLimitsLine(const FieldCaps()), isNull);
    });
  });

  group('countWord', () {
    final cases = <(int, String, String)>[
      (0, 'line', '0 lines'),
      (1, 'line', '1 line'),
      (2, 'sentence', '2 sentences'),
      (999, 'item', '999 items'),
      (1000, 'character', '1,000 characters'),
      (20000, 'character', '20,000 characters'),
      (1234567, 'word', '1,234,567 words'),
      (1, 'subsection', '1 subsection'),
    ];
    for (final (n, unit, worded) in cases) {
      test('a number takes commas above 999 and one of a unit is singular: '
          '$worded', () {
        expect(countWord(n, unit), worded);
      });
    }
  });
}
