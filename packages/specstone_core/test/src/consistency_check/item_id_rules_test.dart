// The expected texts are plan literals kept as written.

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/item_id_rules.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

const _topicPath = 'docs/specs/topics/doc_model.md';

Map<String, String> _topicRules(String rules, {String covers = 'lib'}) => {
  _topicPath:
      '---\ncovers:\n  - $covers\n---\n\n# Doc model\n\n## Purpose\n\nx\n\n'
      '## Rules\n\n$rules\n',
};

Map<String, String> _scenarios(String more) =>
    doc(loginStory, loginScenario2, '$loginScenario2\n\n$more');

Iterable<Map<String, Object?>> _keysOf(List<Finding> found) =>
    found.map((f) => f.toJson());

Future<List<Finding>> _itemIdFindings(
  Map<String, String> edits, {
  FindingKind kind = FindingKind.itemIdMissing,
}) async {
  final report = checkOf(await writeCheckProject(extra: edits));
  return [
    for (final f in report.findings)
      if (f.kind == kind) f,
  ];
}

Map<String, String> _storyRules(String body) => doc(
  loginStory,
  '## Acceptance Criteria',
  '## Rules\n\n$body\n\n## Acceptance Criteria',
);

void main() {
  test('f04/us01/fr09/e01: an item with no prefix ID reports its line, message, and keys', () async {
    final found = await _itemIdFindings(
      _storyRules('- **BR-01** — a\n1. BR-02 — b\n- a rule with no ID'),
    );
    expect(found, hasLength(1));
    expect(
      found.single.path,
      'prds/features/f01_login/us01_email_login/USER_STORY.md',
    );
    expect(found.single.line, 21);
    expect(found.single.message, 'the item opens with no BR- ID');
    expect(
      found.single.toJson(),
      allOf(containsPair('section', 'rules'), containsPair('prefix', 'BR-')),
    );
  });

  test('f04/us01/fr09/e02: a heading item lacks its ID; quote and Serves lines are no items', () async {
    final found = await _itemIdFindings(
      doc(
        projectDoc,
        '### PV-01 — One sign-in\n\n> en: One sign-in for every app.',
        '### One sign-in\n\n> en: One sign-in for every app.\n**Serves:** x',
      ),
    );
    expect(found, hasLength(1));
    expect(found.single.toJson(), containsPair('section', 'vision'));
    expect(found.single.message, 'the item opens with no PV- ID');
  });

  test(
    'f04/us01/fr09/e03: N/A items and nested bullets are no items',
    () async {
      final found = await _itemIdFindings({
        ...doc(
          gnfrDoc,
          '## Security\n\nN/A — none applies.',
          '## Security\n\n- N/A — no target applies',
        ),
        ..._storyRules('- **BR-01** — a\n  - detail of the rule'),
      });
      expect(found, isEmpty);
    },
  );

  test('f04/us01/fr09/e04: a repeated ID reports the second item with the first line', () async {
    final found = await _itemIdFindings(
      doc(
        projectDoc,
        '## Project goals',
        '### PV-01 — Again\n\n## Project goals',
      ),
      kind: FindingKind.itemIdDuplicate,
    );
    expect(found, hasLength(1));
    expect(found.single.line, 17);
    expect(found.single.message, 'PV-01 is already held at line 13');
    expect(
      found.single.toJson(),
      allOf(containsPair('id', 'PV-01'), containsPair('section', 'vision')),
    );
  });

  test('f04/us01/fr09/e01: a domain invariant with a bold ID passes', () async {
    final found = await _itemIdFindings({
      'docs/specs/f01_login/DOMAIN.md':
          '# Login domain\n\n## Entities\n- Account\n\n'
          '## Invariants\n- **INV-1** — an email is unique\n',
    });
    expect(found, isEmpty);
  });

  group('item_id_lettered', () {
    test('f04/us01/fr09/e05: a lettered rule names the next free number and '
        'raises no missing or duplicate', () async {
      final extra = _topicRules(
        '- **RULE-30** — a\n- **RULE-7** — b\n- **RULE-7a** Rule text',
      );
      final lettered = await _itemIdFindings(
        extra,
        kind: FindingKind.itemIdLettered,
      );
      expect(lettered, hasLength(1));
      expect(
        lettered.single.toJson(),
        allOf(
          containsPair('id', 'RULE-7a'),
          containsPair('section', 'rules'),
          containsPair('next', 'RULE-31'),
        ),
      );
      expect(await _itemIdFindings(extra), isEmpty);
      expect(
        await _itemIdFindings(extra, kind: FindingKind.itemIdDuplicate),
        isEmpty,
      );
    });

    test('f04/us01/fr09/e06: lettered scenarios take the next numbers in '
        'document order', () async {
      final lettered = await _itemIdFindings(
        _scenarios(
          '### Scenario 8 — [edge] Late\n\n- a\n\n'
          '### Scenario 6a — [edge] Renew early\n\n- a\n\n'
          '### Scenario 6b — [edge] Renew late\n\n- a',
        ),
        kind: FindingKind.itemIdLettered,
      );
      expect(_keysOf(lettered), [
        allOf(
          containsPair('id', 'Scenario 6a'),
          containsPair('section', 'acceptance_criteria'),
          containsPair('next', 'Scenario 9'),
        ),
        allOf(
          containsPair('id', 'Scenario 6b'),
          containsPair('next', 'Scenario 10'),
        ),
      ]);
    });

    test(
      'f04/us01/fr09/e07: IDs out of number order raise no finding',
      () async {
        final extra = {
          ..._topicRules('- **RULE-12** — a\n- **RULE-3** — b'),
          ..._scenarios(
            '### Scenario 8 — [edge] A\n\n- a\n\n'
            '### Scenario 5 — [edge] B\n\n- a',
          ),
        };
        for (final kind in [
          FindingKind.itemIdLettered,
          FindingKind.itemIdMissing,
          FindingKind.itemIdDuplicate,
        ]) {
          expect(
            await _itemIdFindings(extra, kind: kind),
            isEmpty,
            reason: '$kind',
          );
        }
      },
    );

    test('f04/us01/fr09: a digit after an item or scenario letter run is '
        'reference_malformed with no next, and takes no next number', () async {
      final extra = {
        ..._topicRules(
          '- **RULE-30** — a\n- **RULE-7a1** — b\n- **RULE-7a** — c',
        ),
        ..._scenarios('### Scenario 6a2 — [edge] Odd\n\n- a'),
      };
      final malformed = await _itemIdFindings(
        extra,
        kind: FindingKind.referenceMalformed,
      );
      expect(_keysOf(malformed), [
        allOf(
          containsPair('form', 'item_id'),
          containsPair('text', 'Scenario 6a2'),
          isNot(contains('next')),
        ),
        allOf(
          containsPair('form', 'item_id'),
          containsPair('text', 'RULE-7a1'),
          isNot(contains('next')),
        ),
      ]);
      final lettered = await _itemIdFindings(
        extra,
        kind: FindingKind.itemIdLettered,
      );
      expect(_keysOf(lettered), [
        allOf(containsPair('id', 'RULE-7a'), containsPair('next', 'RULE-31')),
      ]);
      expect(await _itemIdFindings(extra), isEmpty);
    });

    test('f04/us01/fr09/e04: RULE-12 beside RULE-1 is no duplicate', () async {
      final found = await _itemIdFindings(
        _topicRules('- **RULE-1** — a\n- **RULE-12** — b'),
        kind: FindingKind.itemIdDuplicate,
      );
      expect(found, isEmpty);
    });

    test('f04/us01/fr09: fenced, code-span, mid-line, and frontmatter text '
        'raises no ID finding', () async {
      final extra = {
        ..._topicRules(
          '- **RULE-1** — a\n```\n- RULE-7a fenced\n```\n'
          '- **RULE-2** see `RULE-7a` and RULE-8a mid-line',
          covers: 'RULE-7a',
        ),
        ..._scenarios(
          '```\n### Scenario 6a — fenced\n```\n'
          '`### Scenario 6a` in a code span\nsee ### Scenario 6a mid-line',
        ),
      };
      for (final kind in [
        FindingKind.itemIdLettered,
        FindingKind.itemIdMissing,
        FindingKind.itemIdDuplicate,
      ]) {
        expect(
          await _itemIdFindings(extra, kind: kind),
          isEmpty,
          reason: '$kind',
        );
      }
    });
  });

  test('f04/us01/fr09/e06: a 25-digit ID counts without a throw', () async {
    final found = await _itemIdFindings(
      _topicRules(
        '- **RULE-1234567890123456789012345** — a\n'
        '- **RULE-7a** — b\n- **RULE-8b** — c',
      ),
      kind: FindingKind.itemIdLettered,
    );
    expect(_keysOf(found), [
      containsPair('next', 'RULE-1234567890123456789012346'),
      containsPair('next', 'RULE-1234567890123456789012347'),
    ]);
  });

  group('idsInDoc', () {
    test('f04/us01/fr09: lists items and scenario headings with their line '
        'spans, a null id for an item with no ID', () async {
      final session = openSession(
        await writeCheckProject(
          extra: _topicRules(
            '- **RULE-1** — a\n  - detail\n\n- no id\n- **RULE-3a** — c',
          ),
        ),
      );
      addTearDown(session.close);
      final index = session.index;
      final topic = index.docs.singleWhere(
        (d) => d.docPath == 'specs/topics/doc_model.md',
      );
      final ids = idsInDoc(index.contentOf(topic), index.typeOf(topic)!);

      expect(
        [for (final at in ids) at.id?.written],
        ['RULE-1', null, 'RULE-3a'],
      );
      expect(
        ids.every((at) => at.sectionKey == 'rules' && at.prefix == 'RULE-'),
        isTrue,
      );
      expect(ids.first.endLine - ids.first.line, 1);
      expect(ids[2].id, isA<LetteredId>());

      final story = index.docs.singleWhere((d) => d.docPath == loginStory);
      final scenarios = idsInDoc(
        index.contentOf(story),
        index.typeOf(story)!,
      ).where((at) => at.sectionKey == 'acceptance_criteria');
      expect(
        [for (final at in scenarios) at.id?.written],
        ['Scenario 1', 'Scenario 2'],
      );
      expect(scenarios.first.prefix, scenarioIdPrefix);
    });
  });
}
