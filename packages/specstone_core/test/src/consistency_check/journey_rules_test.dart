import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _journeyPath = 'prds/journeys/sign_in/JOURNEY.md';
const _story = 'login/email_login';

// The first step heading sits on line 17, below the four lines the approval
// stamp opens a doc with; its step: line two below.
const _firstStepLine = 17;

// A journey with a scenario 1 step has a front matter of its own, so the stamp
// adds one line to its five.
const _entryLines = 2;

String _journey(List<String> stepLines, {String frontmatter = ''}) =>
    '$frontmatter# Sign in\n\n## Goal\n\nGet in.\n\n'
    '## Flow\n\nSign in.\n\n## Steps\n\n'
    '${_withBlankUnderHeadings(stepLines)}\n';

// Lays out the step lines: a blank line under each step heading.
String _withBlankUnderHeadings(List<String> stepLines) => stepLines
    .expand((l) => l.startsWith('### ') ? [l, ''] : [l])
    .join('\n')
    .trimRight();

// Records the confirmed entry of scenario 1 when a step names it, so a valid
// journey yields no finding of any kind.
String _frontmatter(List<String> stepLines, List<String> fields) {
  final entry = stepLines.contains('step: $_story S1')
      ? 'confirmed:\n  - $_story#S1 ${fingerprintOf(loginScenario1)}\n'
      : '';
  final body = '${fields.map((f) => '$f\n').join()}$entry';
  return body.isEmpty ? '' : '---\n$body---\n\n';
}

Future<List<Finding>> _check(
  List<String> stepLines, {
  List<String> fields = const [],
  Map<String, String> extra = const {},
}) async {
  final report = await checkOf(
    await writeCheckProject(
      extra: {
        'docs/$_journeyPath': _journey(
          stepLines,
          frontmatter: _frontmatter(stepLines, fields),
        ),
        ...extra,
      },
    ),
    docPath: _journeyPath,
  );
  return report.findings;
}

List<Finding> _of(List<Finding> findings, FindingKind kind) => [
  for (final f in findings)
    if (f.kind == kind) f,
];

void main() {
  test('step: login/email_login '
      'S9 is journey_step_unresolved at its step: line', () async {
    final found = await _check(['### 1. Sign in', 'step: $_story S9']);
    expect(found, hasLength(1));
    final finding = found.single;
    expect(finding.kind, FindingKind.journeyStepUnresolved);
    expect(finding.path, _journeyPath);
    expect(finding.line, _firstStepLine + 2);
    expect(finding.message, 'step: $_story S9 names no scenario a story holds');
    expect(finding.toJson(), containsPair('step', '$_story S9'));
  });

  test('a step naming no story is journey_step_unresolved', () async {
    // A readable story part that names no story reaches the same branch.
    for (final step in ['nope/none S1', 'Login/email S1']) {
      final found = await _check(['### 1. Sign in', 'step: $step']);
      expect(_of(found, FindingKind.journeyStepUnresolved).map((f) => f.line), [
        _firstStepLine + 2,
      ], reason: step);
    }
  });

  test('a step heading with no step: line is '
      'journey_step_unresolved at the heading, step empty', () async {
    final found = await _check(['### 1. Sign in']);
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.journeyStepUnresolved);
    expect(found.single.line, _firstStepLine);
    expect(found.single.message, 'the step has no step: line');
    expect(found.single.toJson(), containsPair('step', ''));
  });

  test('after: 7 in a '
      'journey of steps 1 to 5 is journey_after_unresolved', () async {
    final found = await _check([
      for (var n = 1; n <= 5; n++) ...['### $n. Step $n', 'step: $_story S1'],
      '### 6. Branch',
      'step: $_story S1',
      'after: 7',
    ]);
    final after = _of(found, FindingKind.journeyAfterUnresolved);
    expect(after, hasLength(1));
    expect(after.single.line, _firstStepLine + _entryLines + 18);
    expect(after.single.message, 'after: 7 names no step written above it');
    expect(after.single.toJson(), containsPair('after', '7'));
    expect(found, hasLength(1));

    final below = {
      'a step written below': [
        '### 1. One',
        'step: $_story S1',
        'after: 2',
        '### 2. Two',
        'step: $_story S1',
      ],
      'step 3x with after: 4 below it': [
        '### 3x. Branch',
        'step: $_story S1',
        'after: 4',
        '### 4. Four',
        'step: $_story S1',
      ],
    };
    for (final MapEntry(:key, :value) in below.entries) {
      final belowFound = await _check(value);
      expect(
        _of(belowFound, FindingKind.journeyAfterUnresolved),
        hasLength(1),
        reason: key,
      );
    }
  });

  test(
    'a second ### 3. heading is journey_step_duplicate at that heading',
    () async {
      final found = await _check([
        '### 3. First',
        'step: $_story S1',
        '### 3. Second',
        'step: $_story S1',
      ]);
      expect(found, hasLength(1));
      expect(found.single.kind, FindingKind.journeyStepDuplicate);
      expect(found.single.line, _firstStepLine + _entryLines + 3);
      expect(found.single.message, 'step number 3 is carried by a step above');
      expect(found.single.toJson(), containsPair('number', '3'));
    },
  );

  test('an after: 3 below two step 3s gives the duplicate '
      'finding only', () async {
    final found = await _check([
      '### 3. First',
      'step: $_story S1',
      '### 3. Second',
      'step: $_story S1',
      '### 4. Fourth',
      'step: $_story S1',
      'after: 3',
    ]);
    expect(found.map((f) => f.kind), [FindingKind.journeyStepDuplicate]);
  });

  test('a step: that does not read as '
      '<story identity> S<N> is journey_step_unresolved', () async {
    // A lettered scenario number leaves `step.target` null as `login` does.
    for (final step in ['login', '$_story S1a']) {
      final found = await _check(['### 1. Sign in', 'step: $step']);
      expect(found, hasLength(1), reason: step);
      expect(found.single.kind, FindingKind.journeyStepUnresolved);
      expect(found.single.line, _firstStepLine + 2);
      expect(found.single.toJson(), containsPair('step', step));
    }
  });

  test('an approved journey is checked as a draft one is', () async {
    final found = await _check(
      ['### 1. Sign in', 'step: $_story S9'],
      fields: ['status: approved'],
    );
    expect(_of(found, FindingKind.journeyStepUnresolved), hasLength(1));
  });

  test('check journey:sign_in reports an untyped file in the '
      "journey's folder", () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/$_journeyPath': _journey([
            '### 1. Sign in',
            'step: $_story S1',
          ]),
          'docs/prds/journeys/sign_in/notes.md': '# Notes\n',
        },
      ),
      target: 'journey:sign_in',
    );
    expect(spots(report, FindingKind.untypedDoc), [
      'prds/journeys/sign_in/notes.md:1: untyped_doc',
    ]);
  });

  group('persona', () {
    final steps = ['### 1. Sign in', 'step: $_story S1'];

    test('a journey with no persona key has '
        'no persona finding', () async {
      final cases = {
        'one step': steps,
        '40 steps': [
          for (var n = 1; n <= 40; n++) ...[
            '### $n. Step $n',
            'step: $_story S1',
          ],
        ],
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(await _check(value), isEmpty, reason: key);
      }
    });

    test('a journey of three resolved personas raises no finding', () async {
      const names = ['buyer', 'seller', 'admin'];
      final found = await _check(
        steps,
        fields: ['persona: [${names.join(', ')}]'],
        extra: {
          for (final name in names)
            'docs/prds/personas/$name/PERSONA.md':
                '---\nrole: Agent\npriority: primary\nbasis: proto\n---\n\n'
                '# $name\n',
        },
      );
      expect(found, isEmpty);
    });

    test('persona: [buyer] with no persona buyer is '
        'doc_ref_unresolved', () async {
      final found = await _check(steps, fields: ['persona: [buyer]']);
      expect(found.map((f) => f.kind), [FindingKind.docRefUnresolved]);
      expect(found.single.toJson(), containsPair('value', 'buyer'));
    });
  });
}
