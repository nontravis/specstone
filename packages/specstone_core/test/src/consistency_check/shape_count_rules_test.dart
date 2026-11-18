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

  test(
    'a dot or a question mark inside a code span ends no sentence',
    () async {
      final found = await _found(
        _frLayer,
        _sectionLint('edge_cases', _oneSentence),
        edits: _frWith('1. E01 — Refuse `a.b` and `what?` at once.'),
      );
      expect(found, isEmpty);
    },
  );

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

  test('statement finding cites paragraph line', () async {
    final edits = fr(checkPasswordStatement, 'Refuse it. Log it.');
    final found = await _found(
      _frLayer,
      _sectionLint('statement', _oneSentence),
      edits: edits,
    );
    expect(found, hasLength(1));
    expect(found.single.line, lineOfFirst(_project, loginFr, 'Refuse it.'));
    expect(found.single.toJson(), containsPair('actual', 2));
  });

  test('semicolon rules give sentences_over_limit', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('edge_cases', _oneSentence),
      edits: _frWith('1. E01 — Refuse it; log it.'),
    );
    expect(found.map((f) => f.kind), [FindingKind.sentencesOverLimit]);
    expect(found.single.line, lineOfFirst(_project, loginFr, 'Refuse it;'));
    expect(found.single.toJson(), containsPair('actual', 2));
  });

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

  test('heading sentence adds none', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('rationale', _oneSentence),
      edits: fr(
        'A wrong password must not sign in.',
        '### Group\n\nRefuse it.',
      ),
    );
    expect(found, isEmpty);
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

  test(
    'a scenario of 6 steps under 3 to 5 is out of range at its heading',
    () async {
      final edits = doc(
        loginStory,
        '- **Then** the Agent sees the home page',
        '- **Then** the Agent sees the home page\n'
            '- **And** a\n- **And** b\n- **And** c',
      );
      final found = await _found(
        _storyLayer,
        _sectionLint('acceptance_criteria', '''
      item_count:
        min: 3
        max: 5
        per_subsection: true
'''),
        edits: edits,
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.itemCountOutOfRange);
      expect(
        found.single.line,
        lineOfFirst(_project, loginStory, '### Scenario 1'),
      );
      expect(
        found.single.toJson(),
        allOf(containsPair('limit', 5), containsPair('actual', 6)),
      );
    },
  );

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

  test(
    'without per_subsection the section counts its own items at its header',
    () async {
      final edits = fr(
        '1. E01 — An empty password → refused.',
        '1. E01 — a.\n2. E02 — b.\n3. E03 — c.',
      );
      final found = await _found(
        _frLayer,
        _sectionLint('edge_cases', '''
      item_count:
        max: 2
'''),
        edits: edits,
      );
      expect(found, hasLength(1));
      expect(
        found.single.line,
        lineOfFirst(_project, loginFr, '## Edge cases'),
      );
    },
  );

  test(
    'a section with an empty body under its min_lines floor reports actual 0',
    () async {
      final edits = fr('A wrong password must not sign in.', '');
      final found = await _found(
        _frLayer,
        _sectionLint('rationale', '      min_lines: 2\n'),
        edits: edits,
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.linesUnderLimit);
      expect(found.single.line, lineOfFirst(_project, loginFr, '## Rationale'));
      expect(
        found.single.toJson(),
        allOf(
          containsPair('section', 'rationale'),
          containsPair('limit', 2),
          containsPair('actual', 0),
        ),
      );
    },
  );

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
    'a doc type that sets none of the three keys runs no shape rule',
    () async {
      final project = await writeCheckProject(
        extra: fr('1. E01 — An empty password → refused.', '1. E01 — a. b. c.'),
      );
      expect(
        (await checkOf(project)).findings
            .where((f) => _shapeKinds.contains(f.kind)),
        isEmpty,
      );
    },
  );

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
}
