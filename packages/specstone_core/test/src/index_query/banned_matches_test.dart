import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/banned_matches.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/banned_match.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

final _type = MergedDocType(
  id: 'note',
  fields: const [],
  sections: [
    MergedSection(
      id: 'goal',
      header: 'Goal',
      linePrefix: '- ',
      bannedPatterns: [PatternEntry(id: 'own', pattern: 'x', message: 'm')],
    ),
  ],
  lint: MergedLint(
    bannedPatterns: [
      PatternEntry(
        id: 'fast',
        pattern: r'fast\w*',
        message: 'm',
        except: const ['fastest'],
      ),
      PatternEntry(id: 'empty', pattern: 'z*', message: 'm'),
      PatternEntry(
        id: 'code',
        pattern: r'\S+',
        message: 'm',
        scope: PatternScope.code,
      ),
    ],
  ),
  files: const [],
);

const _text =
    '# T\n'
    '\n'
    '## Goal\n'
    'fast and fastest, see `docs/fast`\n'
    '```\n'
    'fast\n'
    '```\n'
    '- x\n'
    '\n'
    '## Other\n'
    'fastly\n';

DocContent _parsed(String text, DocTypeMatch match) => parseIndexedDoc(
  docPath: 'n.md',
  bytes: utf8.encode(text),
  match: match,
  statusesOutside: true,
).content;

void main() {
  // `docs/fast` names folders; the check, not the refresh, tests it (E07).
  test('the refresh keeps each banned match with '
      'its section, line, entry, and text', () {
    expect(_parsed(_text, MatchedDocType(_type)).bannedMatches, [
      const BannedMatch(section: 0, line: 4, entry: 0, match: 'fast'),
      const BannedMatch(section: 0, line: 4, entry: 2, match: 'docs/fast'),
      const BannedMatch(section: 0, line: 8, entry: 3, match: 'x'),
      const BannedMatch(section: 1, line: 11, entry: 0, match: 'fastly'),
    ]);
  });

  group('a prose field value', () {
    final proseType = MergedDocType(
      id: 'note',
      fields: const [
        MergedField(
          id: 'summary',
          type: FieldType.string,
          lint: FieldCaps(maxSentences: 1),
        ),
        MergedField(id: 'plain', type: FieldType.string),
      ],
      sections: const [],
      lint: MergedLint(
        bannedPatterns: [
          PatternEntry(id: 'fast', pattern: r'fast\w*', message: 'm'),
        ],
      ),
      generators: const ['feature_catalog'],
      files: const [],
    );
    final open = generatedOpenMarker('feature_catalog');

    List<BannedMatch> matchesOf(String text) =>
        _parsed(text, MatchedDocType(proseType)).bannedMatches;

    test('stores its doc-level hit under its field, on the key line', () {
      expect(
        matchesOf('---\nstatus: draft\nsummary: A fast tool.\n---\n\n# T\n'),
        [const BannedMatch(field: 'summary', line: 3, entry: 0, match: 'fast')],
      );
    });

    test('stores a hit on the second line of a block scalar on the key '
        'line', () {
      expect(
        matchesOf(
          '---\nstatus: draft\nsummary: |\n  A tool.\n  Very fast too.\n'
          '---\n\n# T\n',
        ),
        [const BannedMatch(field: 'summary', line: 3, entry: 0, match: 'fast')],
      );
    });

    test('applies no section-level entry to a field value', () {
      final sectionOnly = MergedDocType(
        id: 'note',
        fields: const [
          MergedField(
            id: 'summary',
            type: FieldType.string,
            lint: FieldCaps(maxSentences: 1),
          ),
        ],
        sections: [
          MergedSection(
            id: 'goal',
            header: 'Goal',
            bannedPatterns: [
              PatternEntry(id: 'slow', pattern: r'slow\w*', message: 'm'),
            ],
          ),
        ],
        lint: const MergedLint(),
        files: const [],
      );

      expect(
        _parsed(
          '---\nsummary: A slow tool.\n---\n\n# T\n\n## Goal\nslow here\n',
          MatchedDocType(sectionOnly),
        ).bannedMatches.map((m) => (m.section, m.field)),
        [(0, null)],
      );
    });

    test('stores no hit for a field that sets no lint', () {
      expect(matchesOf('---\nplain: A fast tool.\n---\n\n# T\n'), isEmpty);
    });

    test('stores no hit for a value that is not a string', () {
      expect(matchesOf('---\nsummary: [fast, faster]\n---\n\n# T\n'), isEmpty);
      expect(matchesOf('---\nsummary: 42\n---\n\n# T\n'), isEmpty);
    });

    test('stores a hit on a plain section line and none between the '
        'markers of a generated block', () {
      final text =
          '# T\n\n## Notes\nfast one\n$open\nfast two\n$generatedEndMarker\n'
          'fast three\n';

      expect(matchesOf(text).map((m) => (m.line, m.match)), [
        (4, 'fast'),
        (8, 'fast'),
      ]);
    });

    test('round-trips its field through the match JSON', () {
      final matches = matchesOf('---\nsummary: A fast tool.\n---\n\n# T\n');

      expect(
        bannedMatchesFromJson(
          jsonDecode(jsonEncode(bannedMatchesToJson(matches))) as List<Object?>,
        ),
        matches,
      );
    });
  });

  test('an untyped doc keeps no banned match', () {
    expect(_parsed(_text, const NoDocType()).bannedMatches, isEmpty);
  });

  test('the matches round-trip through their JSON', () {
    final matches = _parsed(_text, MatchedDocType(_type)).bannedMatches;
    expect(
      bannedMatchesFromJson(
        jsonDecode(jsonEncode(bannedMatchesToJson(matches))) as List<Object?>,
      ),
      matches,
    );
  });

  test('a code span closes on a backtick run of its own '
      'length', () {
    final line = SearchLine('a ``b`c`` d ``e` f', 1);
    expect(line.code, ['b`c']);
    expect(line.prose, 'a ${' ' * 7} d ``e` f');
  });

  test('a line reads its prose, its code spans, or itself by scope', () {
    final line = SearchLine('a `b` c', 1);
    expect(line.readAs(PatternScope.text), ['a     c']);
    expect(line.readAs(PatternScope.code), ['b']);
    expect(line.readAs(PatternScope.all), ['a `b` c']);
  });

  test('the entries of a held section are the doc type '
      "entries, then the section's own", () {
    final entries = bannedEntriesOf(_type, _type.sections.single);
    expect(entries.map((e) => e.id), ['fast', 'empty', 'code', 'own']);
    expect(bannedEntriesOf(_type, null).map((e) => e.id), [
      'fast',
      'empty',
      'code',
    ]);
  });
}
