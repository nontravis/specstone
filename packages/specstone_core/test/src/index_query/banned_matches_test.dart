import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/banned_matches.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pattern_entry.dart';
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
).content;

void main() {
  // `docs/fast` names folders; the check, not the refresh, tests it (E07).
  test('f04/us01/fr08, f04/nfr-p03: the refresh keeps each banned match with '
      'its section, line, entry, and text', () {
    expect(_parsed(_text, MatchedDocType(_type)).bannedMatches, [
      (section: 0, line: 4, entry: 0, match: 'fast'),
      (section: 0, line: 4, entry: 2, match: 'docs/fast'),
      (section: 0, line: 8, entry: 3, match: 'x'),
      (section: 1, line: 11, entry: 0, match: 'fastly'),
    ]);
  });

  test('f04/us01/fr08, f04/nfr-p03: an untyped doc keeps no banned match', () {
    expect(_parsed(_text, const NoDocType()).bannedMatches, isEmpty);
  });

  test('f04/nfr-p03: the matches round-trip through their JSON', () {
    final matches = _parsed(_text, MatchedDocType(_type)).bannedMatches;
    expect(
      bannedMatchesFromJson(
        jsonDecode(jsonEncode(bannedMatchesToJson(matches))) as List<Object?>,
      ),
      matches,
    );
  });

  test('f04/us01/fr08/e02: a code span closes on a backtick run of its own '
      'length', () {
    final line = SearchLine('a ``b`c`` d ``e` f', 1);
    expect(line.code, ['b`c']);
    expect(line.prose, 'a ${' ' * 7} d ``e` f');
  });

  test('f04/us01/fr08/e05: the entries of a held section are the doc type '
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
