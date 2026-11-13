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
    for (final f in checkOf(project).findings)
      if (_shapeKinds.contains(f.kind)) f,
  ];
}

late Directory _project;

// The file line of the first line of [docPath] holding [needle], in the project
// the last _found call wrote.
int _lineOf(String docPath, String needle) =>
    File('${_project.path}/docs/$docPath')
        .readAsLinesSync()
        .indexWhere((line) => line.contains(needle)) +
    1;

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
    expect(found.single.line, _lineOf(loginFr, 'Refuse it.'));
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
      expect(found.single.line, _lineOf(loginFr, '- **Why:**'));
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
      expect(found.single.line, _lineOf(loginFr, '| Form |'));
    },
  );

  test(
    'a section with no item counts its text as one item at its header',
    () async {
      final edits = fr(checkPasswordStatement, 'Refuse it. Log it.');
      final found = await _found(
        _frLayer,
        _sectionLint('statement', _oneSentence),
        edits: edits,
      );
      expect(found, hasLength(1));
      expect(found.single.line, _lineOf(loginFr, '## Statement'));
      expect(found.single.toJson(), containsPair('actual', 2));
    },
  );

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
    expect(found.single.line, _lineOf(loginStory, '### Scenario 1'));
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
      expect(found.single.line, _lineOf(loginStory, '### Scenario 1'));
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
      expect(found.single.line, _lineOf(loginFr, '## Edge cases'));
    },
  );

  test(
    'a section under its min_lines floor reports section, limit, and actual',
    () async {
      final edits = fr('A wrong password must not sign in.', '');
      final found = await _found(
        _frLayer,
        _sectionLint('rationale', '      min_lines: 2\n'),
        edits: edits,
      );
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.linesUnderLimit);
      expect(found.single.line, _lineOf(loginFr, '## Rationale'));
      expect(
        found.single.toJson(),
        allOf(
          containsPair('section', 'rationale'),
          containsPair('limit', 2),
          containsPair('actual', 1),
        ),
      );
    },
  );

  test('a section at its min_lines floor has no finding', () async {
    final found = await _found(
      _frLayer,
      _sectionLint('rationale', '      min_lines: 2\n'),
    );
    expect(found, isEmpty);
  });

  test(
    'a doc type that sets none of the three keys runs no shape rule',
    () async {
      final project = await writeCheckProject(
        extra: fr('1. E01 — An empty password → refused.', '1. E01 — a. b. c.'),
      );
      expect(
        checkOf(project).findings.where((f) => _shapeKinds.contains(f.kind)),
        isEmpty,
      );
    },
  );
}
