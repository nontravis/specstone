import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _frLayer = '.specstone/templates/fr.yaml';
const _storyLayer = '.specstone/templates/user_story.yaml';
const Set<FindingKind> _shapeKinds = {
  FindingKind.sentencesOverLimit,
  FindingKind.itemCountOutOfRange,
  FindingKind.prefixCountMismatch,
  FindingKind.linesUnderLimit,
  FindingKind.subsectionsOverLimit,
  FindingKind.itemLinesOverLimit,
  FindingKind.codeBlocksOverLimit,
};

String _sectionLint(String section, String lint) =>
    'sections:\n  - id: $section\n    lint:\n$lint';

Future<List<Finding>> _found(
  String layerPath,
  String layer, {
  Map<String, String> edits = const {},
}) async {
  final project = await writeCheckProject(extra: {layerPath: layer, ...edits});
  _project = project;
  return [
    for (final f in (await checkOf(project)).findings)
      if (_shapeKinds.contains(f.kind)) f,
  ];
}

late Directory _project;

Map<String, String> _frWith(String edgeCases) =>
    fr('1. E01 — An empty password → refused.', edgeCases);

const _oneSentence = '''
      max_sentences:
        - count: 1
''';

void main() {
  test('an item of two sentences under a count of 1 reports its line, limit, '
      'and actual', () async {
    final edits = _frWith('1. E01 — Refuse it. Log it.');
    final found = await _found(
      _frLayer,
      _sectionLint('edge_cases', _oneSentence),
      edits: edits,
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.sentencesOverLimit);
    expect(found.single.line, lineOfFirst(_project, loginFr, 'Refuse it.'));
    expect(
      found.single.toJson(),
      allOf(containsPair('limit', 1), containsPair('actual', 2)),
    );
    expect(found.single.waitsFor, WaitsFor.agent);
  });

  test('a sentence that wraps over two lines is counted whole', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('edge_cases', _oneSentence),
      edits: _frWith('1. E01 — Refuse the\n   password. Then log it.'),
    );
    expect(found.map((f) => f.toJson()['actual']), [2]);
  });

  test('a nested item does not count toward its parent', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('edge_cases', _oneSentence),
      edits: _frWith('1. E01 — Refuse it.\n   - Enforcer: one. Two.'),
    );
    expect(found, isEmpty);
  });

  test(
    'a line_prefix limits the count to the items that open with it',
    () async {
      final edits = fr(
        'A wrong password must not sign in.',
        '- **Why:** One. Two.\n- **Evidence:** One. Two. Three.',
      );
      final found = await _found(
        _frLayer,
        _sectionLint('rationale', '''
      max_sentences:
        - count: 1
          line_prefix: "- **Why:**"
'''),
        edits: edits,
      );
      expect(found, hasLength(1));
      expect(found.single.line, lineOfFirst(_project, loginFr, '- **Why:**'));
    },
  );

  test(
    'a column limits the sentences of each cell under that header',
    () async {
      final edits = fr(
        'A wrong password must not sign in.',
        '| Part | Responsibility |\n|---|---|\n'
            '| Form | Takes input. Sends it. |\n| Store | Keeps it. |',
      );
      final found = await _found(
        _frLayer,
        _sectionLint('rationale', '''
      max_sentences:
        - count: 1
          column: Responsibility
'''),
        edits: edits,
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.sentencesOverLimit);
      expect(found.single.line, lineOfFirst(_project, loginFr, '| Form |'));
    },
  );

  test('closing note leaves count at one', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('edge_cases', _oneSentence),
      edits: _frWith('1. E01 — Refuse it. (PV-01)'),
    );
    expect(found, isEmpty);
  });

  test('paragraph beside a sub-list counts', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('statement', _oneSentence),
      edits: fr(checkPasswordStatement, '- A list item.\n\nRefuse it. Log it.'),
    );
    expect(
      found.map((f) => f.kind),
      unorderedEquals([
        FindingKind.sentencesOverLimit,
        FindingKind.itemCountOutOfRange,
      ]),
    );
    final over = found.singleWhere(
      (f) => f.kind == FindingKind.sentencesOverLimit,
    );
    expect(over.line, lineOfFirst(_project, loginFr, 'Refuse it. Log it.'));
  });

  test('two statement paragraphs give item_count_out_of_range', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('statement', '''
      max_sentences:
        - count: 1
      item_count:
        max: 1
'''),
      edits: fr(checkPasswordStatement, 'Refuse it.\n\nLog it.'),
    );
    expect(found.map((f) => f.kind), [FindingKind.itemCountOutOfRange]);
    expect(found.single.line, lineOfFirst(_project, loginFr, '## Statement'));
    expect(found.single.toJson(), containsPair('actual', 2));
  });

  test('nine edge cases over an owner cap give an owner finding', () async {
    String cases(int count) =>
        [for (var i = 1; i <= count; i++) '$i. E0$i — Case $i → refused.']
            .join('\n');
    Future<List<Finding>> foundFor(String lint, int count) => _found(
      _frLayer,
      _sectionLint('edge_cases', lint),
      edits: _frWith(cases(count)),
    );

    final owner = await foundFor(
      '      item_count:\n        max: 8\n        waits_for: owner\n',
      9,
    );
    expect(owner.map((f) => f.kind), [FindingKind.itemCountOutOfRange]);
    expect(owner.single.line, lineOfFirst(_project, loginFr, '## Edge cases'));
    expect(
      owner.single.toJson(),
      allOf(
        containsPair('limit', 8),
        containsPair('actual', 9),
        containsPair('waitsFor', 'owner'),
      ),
    );
    expect(owner.single.message, isNot(contains('waits for')));
    expect(owner.single.textLines.first, endsWith(' (waits for the Owner)'));

    final agent = await foundFor('      item_count:\n        max: 8\n', 9);
    expect(agent.single.toJson(), containsPair('waitsFor', 'agent'));
    expect(agent.single.textLines.first, isNot(contains('waits for')));

    expect(
      await foundFor(
        '      item_count:\n        max: 8\n        waits_for: owner\n',
        8,
      ),
      isEmpty,
    );

    final under = await foundFor(
      '      item_count:\n        min: 3\n        waits_for: owner\n',
      2,
    );
    expect(under.map((f) => f.kind), [FindingKind.itemCountOutOfRange]);
    expect(under.single.toJson(), containsPair('waitsFor', 'owner'));

    final prefix = await foundFor('''
      item_count:
        waits_for: owner
        prefixes:
          - line_prefix: "1. E01"
            count: 2
''', 2);
    expect(prefix.map((f) => f.kind), [FindingKind.prefixCountMismatch]);
    expect(prefix.single.toJson(), containsPair('waitsFor', 'agent'));
  });

  test('split why bullet gives item_count_out_of_range', () async {
    final found = await _found(
      '.specstone/templates/project.yaml',
      _sectionLint('vision', '''
      item_count:
        per_subsection: true
        max: 3
'''),
      edits: doc(
        projectDoc,
        '> en: One sign-in for every app.\n'
            '- **Why:** One sign-in saves every user a password.\n'
            '- **Problem:** Each app asks for its own password.\n'
            '- **Audience:** The people who use the apps.\n',
        '> en: One sign-in for every app.\n\n- **Why:** a.\n- b.\n'
            '- **Problem:** c.\n- **Audience:** d.\n',
      ),
    );
    expect(found.map((f) => f.kind), [FindingKind.itemCountOutOfRange]);
    expect(found.single.line, lineOfFirst(_project, projectDoc, '### PV-01'));
    expect(found.single.toJson(), containsPair('actual', 4));
  });

  test('error cases line counts as a step', () async {
    final found = await _found(
      _storyLayer,
      _sectionLint('acceptance_criteria', '''
      item_count:
        max: 3
        per_subsection: true
'''),
      edits: doc(
        loginStory,
        loginScenario2,
        '$loginScenario2\n\nError cases: N/A',
      ),
    );
    expect(found.map((f) => f.kind), [FindingKind.itemCountOutOfRange]);
    expect(
      found.single.line,
      lineOfFirst(_project, loginStory, '### Scenario 2'),
    );
    expect(found.single.toJson(), containsPair('actual', 4));
  });

  test('table row with no column sums its cells', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('rationale', '''
      max_sentences:
        - count: 2
'''),
      edits: fr(
        'A wrong password must not sign in.',
        '| Part | Responsibility |\n|---|---|\n'
            '| Form | Takes input. Sends it. |',
      ),
    );
    expect(found.map((f) => f.kind), [FindingKind.sentencesOverLimit]);
    expect(found.single.line, lineOfFirst(_project, loginFr, '| Form |'));
    expect(found.single.toJson(), containsPair('actual', 3));
  });

  test('heading item over the limit cites the heading line', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('rationale', _oneSentence),
      edits: fr(
        'A wrong password must not sign in.',
        '### Group\n\nRefuse it. Log it.',
      ),
    );
    expect(found.map((f) => f.kind), [FindingKind.sentencesOverLimit]);
    expect(found.single.line, lineOfFirst(_project, loginFr, '### Group'));
    expect(found.single.toJson(), containsPair('actual', 2));
  });

  test('a section of one sentence under a count of 1 has no finding', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('statement', _oneSentence),
    );
    expect(found, isEmpty);
  });

  test('a scenario with two When steps under a count of 1 mismatches at its '
      'heading', () async {
    final edits = doc(
      loginStory,
      '- **When** the Agent signs in\n',
      '- **When** the Agent signs in\n- **When** the Agent signs in again\n',
    );
    final found = await _found(
      _storyLayer,
      _sectionLint('acceptance_criteria', '''
      item_count:
        per_subsection: true
        prefixes:
          - line_prefix: "- **When**"
            count: 1
'''),
      edits: edits,
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.prefixCountMismatch);
    expect(
      found.single.line,
      lineOfFirst(_project, loginStory, '### Scenario 1'),
    );
    expect(
      found.single.toJson(),
      allOf(
        containsPair('line_prefix', '- **When**'),
        containsPair('limit', 1),
        containsPair('actual', 2),
      ),
    );
  });

  test('a scenario of 2 steps under a floor of 3 reports the floor', () async {
    final found = await _found(
      _storyLayer,
      _sectionLint('acceptance_criteria', '''
      item_count:
        min: 4
        per_subsection: true
'''),
    );
    expect(found.map((f) => f.toJson()['limit']), [4, 4]);
    expect(found.map((f) => f.toJson()['actual']), [3, 3]);
  });

  test('a blank required section skips min_lines', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('rationale', '      min_lines: 2\n'),
      edits: fr('A wrong password must not sign in.', ''),
    );
    expect(found, isEmpty);
  });

  test('a blank required section skips the item_count minimum', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('rationale', '''
      item_count:
        min: 3
'''),
      edits: fr('A wrong password must not sign in.', ''),
    );
    expect(found, isEmpty);
  });

  test('a blank optional section keeps its min_lines result', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('input_output', '      min_lines: 2\n'),
      edits: fr('## Edge cases', '## Input / Output\n\n## Edge cases'),
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.linesUnderLimit);
    expect(
      found.single.line,
      lineOfFirst(_project, loginFr, '## Input / Output'),
    );
    expect(found.single.toJson(), containsPair('actual', 0));
  });

  test('one body line under a min_lines floor of 2 reports actual 1, the '
      'header line counting none', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('rationale', '      min_lines: 2\n'),
    );
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.linesUnderLimit);
    expect(found.single.line, lineOfFirst(_project, loginFr, '## Rationale'));
    expect(
      found.single.toJson(),
      allOf(
        containsPair('section', 'rationale'),
        containsPair('limit', 2),
        containsPair('actual', 1),
      ),
    );
  });

  test('a persona snapshot of one body line under min_lines 2 reports actual '
      '1, the header line counting none', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/prds/personas/buyer/PERSONA.md':
            '---\nrole: Agent\npriority: primary\nbasis: proto\n---\n\n'
            '# Buyer\n\n## Snapshot\nA buyer line.\n',
      },
    );
    final found = [
      for (final f in (await checkOf(project)).findings)
        if (f.kind == FindingKind.linesUnderLimit) f,
    ];
    expect(found, hasLength(1));
    expect(
      found.single.toJson(),
      allOf(
        containsPair('section', 'snapshot'),
        containsPair('limit', 2),
        containsPair('actual', 1),
      ),
    );
  });

  test(
    'a blank section made required by required_when skips both floors',
    () async {
      final found = await _found(
        _frLayer,
        '''
sections:
  - id: behavior
    lint:
      min_lines: 2
      item_count:
        min: 3
      required_when:
        section: rationale
        field: Consistency
        value: eventual
''',
        edits: edit(loginFr, [
          (
            'A wrong password must not sign in.',
            '- **R1** Refuse it.\n  - **Consistency:** eventual',
          ),
          ('## Rationale', '## Behavior\n\n## Rationale'),
        ]),
      );
      expect(found, isEmpty);
    },
  );

  test('a blank persona snapshot reports the section and no floor', () async {
    const personaPath = 'prds/personas/buyer/PERSONA.md';
    final project = await writeCheckProject(
      extra: {
        'docs/$personaPath':
            '---\nrole: Agent\npriority: primary\nbasis: proto\n---\n\n'
            '# Buyer\n\n## Snapshot\n',
      },
    );
    final findings = (await checkOf(project)).findings
        .where((f) => f.path == personaPath)
        .toList();
    final missing = findings.where(
      (f) =>
          f.kind == FindingKind.requiredSectionMissing &&
          f.toJson()['section'] == 'snapshot',
    );
    expect(missing, hasLength(1));
    expect(
      missing.single.line,
      lineOfFirst(project, personaPath, '## Snapshot'),
    );
    expect(
      findings.map((f) => f.kind),
      isNot(contains(FindingKind.linesUnderLimit)),
    );
  });

  test(
    'a section of 2 body lines at its min_lines floor has no finding',
    () async {
      final found = await _found(
        _frLayer,
        _sectionLint('rationale', '      min_lines: 2\n'),
        edits: fr(
          'A wrong password must not sign in.',
          'A wrong password must not sign in.\n\nIt stays refused.',
        ),
      );
      expect(found, isEmpty);
    },
  );

  test(
    'a doc type that sets none of the count keys runs no count rule',
    () async {
      final project = await writeCheckProject(
        extra: fr(
          '1. E01 — An empty password → refused.',
          '1. E01 — a. b. c.\n   d.\n   e.',
        ),
      );
      expect(
        (await checkOf(project)).findings
            .where((f) => _shapeKinds.contains(f.kind)),
        isEmpty,
      );
    },
  );

  group('max_item_lines', () {
    const cap = '      max_item_lines: 1\n';

    test('an item past its line cap is reported', () async {
      final found = await _found(
        _frLayer,
        _sectionLint('edge_cases', cap),
        edits: _frWith('1. E01 — Refuse it\n   twice.'),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.itemLinesOverLimit);
      expect(found.single.line, lineOfFirst(_project, loginFr, 'Refuse it'));
      expect(
        found.single.toJson(),
        allOf(
          containsPair('section', 'edge_cases'),
          containsPair('limit', 1),
          containsPair('actual', 2),
          containsPair('message', 'item has 2 lines; the limit is 1'),
        ),
      );
      expect(found.single.waitsFor, WaitsFor.agent);
    });

    test('nested items and a fenced block add no line', () async {
      for (final item in [
        '1. E01 — Refuse it.\n   - one\n   - two',
        '1. E01 — Refuse it.\n```\ncode\n```',
      ]) {
        final found = await _found(
          _frLayer,
          _sectionLint('edge_cases', cap),
          edits: _frWith(item),
        );
        expect(found, isEmpty, reason: item);
      }
    });

    test('an indented fenced block adds no line', () async {
      final found = await _found(
        _frLayer,
        _sectionLint('edge_cases', cap),
        edits: _frWith('1. E01 — Refuse it.\n   ```\n   code\n   ```'),
      );
      expect(found, isEmpty);
    });

    test(
      'a table row counts its own line, not its header or delimiter row',
      () async {
        final found = await _found(
          _frLayer,
          _sectionLint('rationale', cap),
          edits: fr(
            'A wrong password must not sign in.',
            '| Part | Responsibility |\n|---|---|\n'
                '| Form | Takes input. |\n| Store | Keeps it. |',
          ),
        );
        expect(found, isEmpty);
      },
    );

    test('a quote mark with no text after it adds no line', () async {
      const intro = 'A wrong password must not sign in.';
      final quotedHeading = await _found(
        _frLayer,
        _sectionLint('rationale', cap),
        edits: fr(intro, '> ### Group\n>\n> Refuse it.'),
      );
      expect(quotedHeading, isEmpty);
      final quotedItem = await _found(
        _frLayer,
        _sectionLint('edge_cases', cap),
        edits: _frWith('> - E01 — Refuse it\n>   twice.'),
      );
      expect(quotedItem.map((f) => f.kind), [FindingKind.itemLinesOverLimit]);
      expect(quotedItem.single.toJson(), containsPair('actual', 2));
    });

    test('a heading item counts its paragraph alone', () async {
      final lint = _sectionLint('rationale', cap);
      const intro = 'A wrong password must not sign in.';
      final one = await _found(
        _frLayer,
        lint,
        edits: fr(intro, '### Group\n\nRefuse it.'),
      );
      expect(one, isEmpty);
      final two = await _found(
        _frLayer,
        lint,
        edits: fr(intro, '### Group\n\nRefuse it\ntwice.'),
      );
      expect(two.map((f) => f.kind), [FindingKind.itemLinesOverLimit]);
      expect(two.single.line, lineOfFirst(_project, loginFr, '### Group'));
      expect(two.single.toJson(), containsPair('actual', 2));
    });
  });

  test('a doc type that sets none of the five keys runs no shape rule while '
      'the fr type runs its own', () async {
    final project = await writeCheckProject(
      extra: {
        ...fr(checkPasswordStatement, 'Refuse it. Log it.'),
        ...doc(
          'prds/FEATURES.md',
          '- Login\n',
          '- Login — One. Two. Three.\n  - Nested one.\n  - Nested two.\n'
              '- Owner — Four.\n  Five.\n- User — Six.\n',
        ),
      },
    );
    final found = [
      for (final f in (await checkOf(project)).findings)
        if (_shapeKinds.contains(f.kind)) f,
    ];
    expect(found.map((f) => f.path).toSet(), {loginFr});
    expect(found.map((f) => f.kind), contains(FindingKind.sentencesOverLimit));
  });

  test('a blockquoted item is counted and cut like any other item', () async {
    final edits = _frWith('> - E01 — Refuse it. Log it.');
    final found = await _found(
      _frLayer,
      _sectionLint('edge_cases', _oneSentence),
      edits: edits,
    );
    expect(found, hasLength(1));
    expect(found.single.line, lineOfFirst(_project, loginFr, 'Refuse it.'));
    expect(found.single.toJson(), containsPair('actual', 2));
  });

  group('a closed generated block', () {
    const body =
        '### Group\n\n1. E01 — one.\n'
        '<!-- specstone:generated scenario_copy (do not edit) -->\n'
        '- **Given** a\n- **Given** b\n'
        '<!-- specstone:generated end -->\n';
    const perSubsection = '''
      item_count:
        max: 1
        per_subsection: true
''';

    test('holds no item under a per_subsection count', () async {
      final found = await _found(
        _frLayer,
        'generators: [scenario_copy]\n'
        '${_sectionLint('edge_cases', perSubsection)}',
        edits: _frWith(body),
      );
      expect(found, isEmpty);
    });

    test('is read as items when the doc type lists no generator', () async {
      final found = await _found(
        _frLayer,
        _sectionLint('edge_cases', perSubsection),
        edits: _frWith(body),
      );
      expect(found.map((f) => f.kind), [FindingKind.itemCountOutOfRange]);
    });
  });

  test('a table header that opens like a list item is no item', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('edge_cases', '''
      item_count:
        max: 1
'''),
      edits: _frWith('- a | b\n- | -\n| x | y |'),
    );
    expect(found, isEmpty);
  });

  group('max_subsections', () {
    const cap = '      max_subsections: 6\n';

    String scenario(int n) =>
        '\n\n### Scenario $n — [error] Case $n\n\n'
        '- **Given** a\n- **When** b\n- **Then** c';

    Map<String, String> storyWith(int scenarios, {String after = ''}) => doc(
      loginStory,
      loginScenario2,
      '$loginScenario2$after'
      '${[for (var n = 3; n <= scenarios; n++) scenario(n)].join()}',
    );

    test('seven subsections under a cap of 6 report the section, limit, and '
        'actual at its header', () async {
      final found = await _found(
        _storyLayer,
        _sectionLint('acceptance_criteria', cap),
        edits: storyWith(7),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.subsectionsOverLimit);
      expect(
        found.single.line,
        lineOfFirst(_project, loginStory, '## Acceptance Criteria'),
      );
      expect(
        found.single.toJson(),
        allOf(
          containsPair('section', 'acceptance_criteria'),
          containsPair('limit', 6),
          containsPair('actual', 7),
        ),
      );
      expect(found.single.waitsFor, WaitsFor.agent);
    });

    test('six subsections under a cap of 6 have no finding', () async {
      final found = await _found(
        _storyLayer,
        _sectionLint('acceptance_criteria', cap),
        edits: storyWith(6),
      );
      expect(found, isEmpty);
    });

    test('a fenced ### line counts as no subsection', () async {
      final found = await _found(
        _storyLayer,
        _sectionLint('acceptance_criteria', cap),
        edits: storyWith(6, after: '\n\n```\n### Scenario 9\n```'),
      );
      expect(found, isEmpty);
    });
  });

  group('max_code_blocks', () {
    String blocks(int n, {List<String> infos = const ['', 'dart', 'yaml']}) =>
        [for (var k = 0; k < n; k++) '```${infos[k % infos.length]}\nx$k\n```']
            .join('\n\n');

    String lint({bool perSubsection = false}) =>
        '      max_code_blocks:\n        count: 2\n'
        '${perSubsection ? '        per_subsection: true\n' : ''}';

    Map<String, String> story(String tail) =>
        doc(loginStory, loginScenario2, '$loginScenario2\n\n$tail');

    test('3 fenced blocks of mixed info strings under a cap of 2 report the '
        'section at its header', () async {
      final found = await _found(
        _storyLayer,
        _sectionLint('acceptance_criteria', lint()),
        edits: story('${blocks(2)}\n\n~~~text\nz\n~~~'),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.codeBlocksOverLimit);
      expect(
        found.single.line,
        lineOfFirst(_project, loginStory, '## Acceptance Criteria'),
      );
      expect(
        found.single.toJson(),
        allOf(
          containsPair('section', 'acceptance_criteria'),
          containsPair('limit', 2),
          containsPair('actual', 3),
        ),
      );
      expect(found.single.waitsFor, WaitsFor.agent);
    });

    test('2 fenced blocks under a cap of 2 have no finding', () async {
      final found = await _found(
        _storyLayer,
        _sectionLint('acceptance_criteria', lint()),
        edits: story(blocks(2)),
      );
      expect(found, isEmpty);
    });

    test('with per_subsection, a subsection of 3 blocks reports at its '
        'heading and a sibling of 2 gives none', () async {
      final found = await _found(
        _storyLayer,
        _sectionLint('acceptance_criteria', lint(perSubsection: true)),
        edits: story(
          '${blocks(3)}\n\n### Scenario 3 — [error] Locked\n\n'
          '- **Given** a\n- **When** b\n- **Then** c\n\n${blocks(2)}',
        ),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.codeBlocksOverLimit);
      expect(
        found.single.line,
        lineOfFirst(_project, loginStory, '### Scenario 2'),
      );
      expect(
        found.single.toJson(),
        allOf(
          containsPair('subsection', 'Scenario 2 — [error] Wrong password'),
          containsPair('limit', 2),
          containsPair('actual', 3),
        ),
      );
    });

    test('3 fenced blocks that touch under a cap of 2 are reported, one '
        'finding', () async {
      final found = await _found(
        _storyLayer,
        _sectionLint('acceptance_criteria', lint()),
        edits: story('```\na\n```\n~~~\nb\n~~~\n```dart\nc\n```'),
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.codeBlocksOverLimit);
      expect(found.single.toJson(), containsPair('actual', 3));
    });
  });
}
