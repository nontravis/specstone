// The expected texts are plan literals kept as written.

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/item_id_rules.dart';
import 'package:specstone_core/src/doc_model/doc_items.dart'
    show opensHeadingItem;
import 'package:specstone_core/src/doc_model/models/id_read.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

const _topicPath = 'docs/specs/topics/doc_model.md';

Map<String, String> _topicRules(
  String rules, {
  String covers = 'lib',
  String retired = '',
}) => {
  _topicPath:
      '---\ncovers:\n  - $covers\n$retired---\n\n# Doc model\n\n'
      '## Purpose\n\nx\n\n## Rules\n\n$rules\n',
};

Map<String, String> _scenarios(String more) =>
    doc(loginStory, loginScenario2, '$loginScenario2\n\n$more');

Iterable<Map<String, Object?>> _keysOf(List<Finding> found) =>
    found.map((f) => f.toJson());

Future<List<Finding>> _itemIdFindings(
  Map<String, String> edits, {
  FindingKind kind = FindingKind.itemIdMissing,
}) async {
  final report = await checkOf(await writeCheckProject(extra: edits));
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
  test(
    'an item with no prefix ID reports its line, message, and keys',
    () async {
      final found = await _itemIdFindings(
        _storyRules('- **BR-01** — a\n1. BR-02 — b\n- a rule with no ID'),
      );
      expect(found, hasLength(1));
      expect(
        found.single.path,
        'prds/features/f01_login/us01_email_login/USER_STORY.md',
      );
      expect(found.single.line, 19);
      expect(found.single.message, 'the item opens with no BR- ID');
      expect(
        found.single.toJson(),
        allOf(containsPair('section', 'rules'), containsPair('prefix', 'BR-')),
      );
    },
  );

  test(
    'a heading item lacks its ID; quote and Serves lines are no items',
    () async {
      final found = await _itemIdFindings(
        doc(
          projectDoc,
          '### PV-01 — One sign-in\n\n> en: One sign-in for every app.',
          '### One sign-in\n\n> en: One sign-in for every app.\n**Serves:** x',
        ),
      );
      expect(found, hasLength(1));
      expect(found.single.toJson(), containsPair('section', 'vision'));
      expect(found.single.toJson(), containsPair('prefix', 'PV-'));
      expect(found.single.message, 'the item opens with no PV- ID');
    },
  );

  test('N/A items and nested bullets are no items', () async {
    final found = await _itemIdFindings({
      ...doc(
        gnfrDoc,
        '## Security\n\nN/A — none applies.',
        '## Security\n\n- N/A — no target applies',
      ),
      ..._storyRules('- **BR-01** — a\n  - detail of the rule'),
    });
    expect(found, isEmpty);
  });

  test('a repeated ID reports the second item with the first line', () async {
    final found = await _itemIdFindings(
      doc(projectDoc, '## Role', '### PV-01 — Again\n\n## Role'),
      kind: FindingKind.itemIdDuplicate,
    );
    expect(found, hasLength(1));
    expect(found.single.line, 23);
    expect(found.single.message, 'PV-01 is already held at line 16');
    expect(
      found.single.toJson(),
      allOf(containsPair('id', 'PV-01'), containsPair('section', 'vision')),
    );
  });

  test("two scenarios of one number's value in a story are "
      'a duplicate, Scenario 2 twice or Scenario 02 after Scenario 2; '
      'Scenario 20 is none', () async {
    for (final repeat in ['Scenario 2', 'Scenario 02']) {
      final found = await _itemIdFindings(
        _scenarios('### $repeat — [edge] Again\n\n- a'),
        kind: FindingKind.itemIdDuplicate,
      );
      expect(found, hasLength(1), reason: repeat);
      expect(found.single.line, 29);
      expect(found.single.message, '$repeat is already held at line 23');
      expect(
        found.single.toJson(),
        allOf(
          containsPair('id', repeat),
          containsPair('section', 'acceptance_criteria'),
        ),
      );
    }

    expect(
      await _itemIdFindings(
        _scenarios('### Scenario 20 — [edge] Other\n\n- a'),
        kind: FindingKind.itemIdDuplicate,
      ),
      isEmpty,
    );
  });

  test(
    'every list marker with no ID opens an item with a missing ID',
    () async {
      final found = await _itemIdFindings(
        _storyRules(
          '- **BR-01** — a\n- BR-02 Rule text\n* **BR-03** — c\n+ BR-04 — d\n'
          '1) BR-05 — e\n* star with no ID\n+ plus with no ID\n'
          '1) paren with no ID\n- dash with no ID',
        ),
      );
      expect(found.map((f) => f.toJson()['section']), everyElement('rules'));
      expect(
        found.map((f) => f.message),
        everyElement('the item opens with no BR- ID'),
      );
      final lines = found.map((f) => f.line).toList();
      expect(lines, hasLength(4));
      expect(lines.toSet(), hasLength(4));
    },
  );

  group('a table row is an item', () {
    const header = '| ID | Rule |\n| --- | --- |\n';
    const indentedCodeRow =
        '- **BR-01** a\n\n$header| BR-02 | d |\n    | c | d |';

    test('two rows of one ID, written with and without outer pipes, are a '
        'duplicate at the second row; the header rows are no item', () async {
      final found = await _itemIdFindings(
        _storyRules('$header| BR-01 | a |\nBR-01 | b |\n|BR-02|c|'),
        kind: FindingKind.itemIdDuplicate,
      );

      expect(found, hasLength(1));
      final held = RegExp(r'BR-01 is already held at line (\d+)')
          .firstMatch(found.single.message)!;
      expect(found.single.line, int.parse(held[1]!) + 1);
      expect(found.single.toJson(), containsPair('id', 'BR-01'));
    });

    test(
      'a row with no ID is missing it, with or without outer pipes',
      () async {
        final found = await _itemIdFindings(
          _storyRules('$header| BR-01 | a |\n| no ID | b |\nno ID | c |'),
        );

        expect(found, hasLength(2));
        expect(
          found.map((f) => f.message),
          everyElement('the item opens with no BR- ID'),
        );
      },
    );

    test('a table indented under a list item belongs to that item, and an '
        'indented-code line is no row', () async {
      for (final rules in const [
        '- **BR-01** a\n  | ID | Rule |\n  | --- | --- |\n  | c | d |',
        indentedCodeRow,
      ]) {
        final found = await _itemIdFindings(_storyRules(rules));

        expect(found, isEmpty, reason: rules);
      }
    });

    test('a lettered or unreadable ID in a row is read as in a list', () async {
      final lettered = await _itemIdFindings(
        _storyRules('$header| BR-1a | a |'),
        kind: FindingKind.itemIdLettered,
      );
      final unreadable = await _itemIdFindings(
        _storyRules('$header| BR-1a1 | a |'),
        kind: FindingKind.referenceMalformed,
      );

      expect(lettered, hasLength(1));
      expect(unreadable, hasLength(1));
    });
  });

  // A heading starts an item exactly when `opensHeadingItem` reads it so.
  for (final (form, startsItem) in const <(String, bool)>[
    ('### Another sign-in', true),
    ('> ### Another sign-in', true),
    ('###', true),
    ('> ###', true),
    (' ### Another sign-in', false),
    ('###\tAnother sign-in', false),
  ]) {
    test('the heading ${form.replaceAll('\t', r'\t')} '
        '${startsItem ? 'starts' : 'starts no'} an item', () async {
      expect(opensHeadingItem(form), startsItem);
      final found = await _itemIdFindings(
        doc(
          projectDoc,
          '### PV-01 — One sign-in',
          '### PV-01 — One sign-in\n\n$form',
        ),
      );
      expect(found, hasLength(startsItem ? 1 : 0));
    });
  }

  test('a list item with no ID under a ### heading is no item', () async {
    final found = await _itemIdFindings(
      doc(
        projectDoc,
        '> en: One sign-in for every app.',
        '> en: One sign-in for every app.\n\n- a list item with no ID\n'
            '* another with no ID\n1. a numbered one with no ID',
      ),
    );
    expect(found, isEmpty);
  });

  test('a bullet nested under an N/A item is no item', () async {
    final found = await _itemIdFindings({
      ...doc(
        gnfrDoc,
        '## Security\n\nN/A — none applies.',
        '## Security\n\n- N/A — no target applies\n'
            '  - a nested bullet with no ID\n    - a deeper bullet with no ID',
      ),
      ..._storyRules(
        '- N/A — no rule applies\n  - a nested bullet with no ID\n'
        '  * a starred bullet with no ID',
      ),
    });
    expect(found, isEmpty);
  });

  test(
    'a lettered scenario heading opens no scenario for a trace to name',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            ..._scenarios('### Scenario 6a — [edge] Renew early\n\n- a'),
            ...fr('  - S2\n', '  - S2\n  - S6a\n'),
          },
        ),
      );
      final unresolved = [
        for (final f in report.findings)
          if (f.kind == FindingKind.scenarioTraceUnresolved)
            f.toJson()['entry'],
      ];
      expect(unresolved, ['S6a']);
      expect(spots(report, FindingKind.suspect), isEmpty);
      expect(spots(report, FindingKind.unconfirmed), isEmpty);
    },
  );

  test('a domain invariant with a bold ID passes', () async {
    final found = await _itemIdFindings({
      'docs/specs/f01_login/DOMAIN.md':
          '# Login domain\n\n## Entities\n- Account\n\n'
          '## Invariants\n- **INV-1** — an email is unique\n',
    });
    expect(found, isEmpty);
  });

  test('item whose id its doc retired is item_id_retired', () async {
    final found = await _itemIdFindings(
      _topicRules(
        '- **RULE-1** — a\n- **RULE-3** — b',
        retired: 'retired_ids:\n  - RULE-3\n',
      ),
      kind: FindingKind.itemIdRetired,
    );
    expect(found, hasLength(1));
    expect(found.single.line, 18);
    expect(found.single.waitsFor, WaitsFor.agent);
    expect(
      found.single.toJson(),
      allOf(containsPair('id', 'RULE-3'), containsPair('section', 'rules')),
    );
  });

  test('edge case listed as retired is no item_id_retired', () async {
    final found = await _itemIdFindings(
      fr(
        'verify_method: test\n',
        'verify_method: test\nretired_ids:\n  - E01\n',
      ),
      kind: FindingKind.itemIdRetired,
    );
    expect(found, isEmpty);
  });

  group('item_id_lettered', () {
    test('a lettered rule names the next free number and '
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

    test('lettered scenarios take their position, with no next', () async {
      final lettered = await _itemIdFindings(
        _scenarios(
          '### Scenario 6a — [edge] Renew early\n\n- a\n\n'
          '### Scenario 6b — [edge] Renew late\n\n- a',
        ),
        kind: FindingKind.itemIdLettered,
      );
      expect(_keysOf(lettered), [
        allOf(
          containsPair('id', 'Scenario 6a'),
          containsPair('section', 'acceptance_criteria'),
          isNot(contains('next')),
        ),
        allOf(containsPair('id', 'Scenario 6b'), isNot(contains('next'))),
      ]);
    });

    test('IDs out of number order raise no finding', () async {
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
    });

    test('a digit after an item or scenario letter run is '
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

    test('lettered next skips a retired number', () async {
      final lettered = await _itemIdFindings(
        _topicRules(
          '- **RULE-30** — a\n- **RULE-7a** Rule text',
          retired: 'retired_ids:\n  - RULE-45\n',
        ),
        kind: FindingKind.itemIdLettered,
      );
      expect(_keysOf(lettered), [containsPair('next', 'RULE-46')]);
    });

    test('RULE-12 beside RULE-1 is no duplicate', () async {
      final found = await _itemIdFindings(
        _topicRules('- **RULE-1** — a\n- **RULE-12** — b'),
        kind: FindingKind.itemIdDuplicate,
      );
      expect(found, isEmpty);
    });

    test('fenced, code-span, mid-line, and frontmatter text '
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

  test('a 25-digit ID counts without a throw', () async {
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
    test('lists items and scenario headings with their line '
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
