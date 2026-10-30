import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _journeyPath = 'prds/journeys/sign_in/JOURNEY.md';
const _story = 'login/email_login';

// The steps section starts at line 8; its body begins on the next line.
const _firstStepLine = 9;

String _journey(List<String> stepLines, {String frontmatter = ''}) =>
    '$frontmatter# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n'
    '${stepLines.join('\n')}\n';

Future<List<Finding>> _check(
  List<String> stepLines, {
  String frontmatter = '',
  Map<String, String> extra = const {},
}) async {
  final report = checkOf(
    await writeCheckProject(
      extra: {
        'docs/$_journeyPath': _journey(stepLines, frontmatter: frontmatter),
        ...extra,
      },
    ),
    docPath: _journeyPath,
  );
  // These journeys record no confirmed entry; tracked_links_test.dart owns
  // the link-state findings.
  return [
    for (final f in report.findings)
      if (f.kind != FindingKind.unconfirmed) f,
  ];
}

List<Finding> _of(List<Finding> findings, FindingKind kind) => [
  for (final f in findings)
    if (f.kind == kind) f,
];

void main() {
  test('f04/us02/s10, f04/us02/fr06/e01, f10/us01/s6: step: login/email_login '
      'S9 is journey_step_unresolved at its step: line', () async {
    final found = await _check(['### 1. Sign in', 'step: $_story S9']);
    expect(found, hasLength(1));
    final finding = found.single;
    expect(finding.kind, FindingKind.journeyStepUnresolved);
    expect(finding.path, _journeyPath);
    expect(finding.line, _firstStepLine + 1);
    expect(finding.message, 'step: $_story S9 names no scenario a story holds');
    expect(finding.toJson(), containsPair('step', '$_story S9'));
  });

  test(
    'f04/us02/fr06/e02: a step naming no story is journey_step_unresolved',
    () async {
      final found = await _check(['### 1. Sign in', 'step: nope/none S1']);
      expect(_of(found, FindingKind.journeyStepUnresolved).map((f) => f.line), [
        _firstStepLine + 1,
      ]);
    },
  );

  test('f04/us02/fr06/e03: a step heading with no step: line is '
      'journey_step_unresolved at the heading, step empty', () async {
    final found = await _check(['### 1. Sign in']);
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.journeyStepUnresolved);
    expect(found.single.line, _firstStepLine);
    expect(found.single.message, 'the step has no step: line');
    expect(found.single.toJson(), containsPair('step', ''));
  });

  test('f04/us02/s11, f04/us02/fr06/e04, f10/us01/fr02/e05: after: 7 in a '
      'journey of steps 1 to 5 is journey_after_unresolved', () async {
    final found = await _check([
      for (var n = 1; n <= 5; n++) ...['### $n. Step $n', 'step: $_story S1'],
      '### 6. Branch',
      'step: $_story S1',
      'after: 7',
    ]);
    final after = _of(found, FindingKind.journeyAfterUnresolved);
    expect(after, hasLength(1));
    expect(after.single.line, _firstStepLine + 12);
    expect(after.single.message, 'after: 7 names no step written above it');
    expect(after.single.toJson(), containsPair('after', '7'));
    expect(found, hasLength(1));
  });

  test('f04/us02/fr06/e05: an after: naming a step written below is '
      'journey_after_unresolved', () async {
    final found = await _check([
      '### 1. One',
      'step: $_story S1',
      'after: 2',
      '### 2. Two',
      'step: $_story S1',
    ]);
    expect(_of(found, FindingKind.journeyAfterUnresolved), hasLength(1));
  });

  test('f04/us02/s12, f04/us02/fr06/e08, f10/us01/fr02/e08: a second '
      '### 3. heading is journey_step_duplicate at that heading', () async {
    final found = await _check([
      '### 3. First',
      'step: $_story S1',
      '### 3. Second',
      'step: $_story S1',
    ]);
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.journeyStepDuplicate);
    expect(found.single.line, _firstStepLine + 2);
    expect(found.single.message, 'step number 3 is carried by a step above');
    expect(found.single.toJson(), containsPair('number', '3'));
  });

  test('f04/us02/fr06/e09: an after: 3 below two step 3s gives the duplicate '
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

  test('f04/us02/fr06, f10/us01/fr02/e06: a step: that does not read as '
      '<story identity> S<N> is journey_step_unresolved', () async {
    final found = await _check(['### 1. Sign in', 'step: login']);
    expect(found, hasLength(1));
    expect(found.single.kind, FindingKind.journeyStepUnresolved);
    expect(found.single.line, _firstStepLine + 1);
    expect(found.single.toJson(), containsPair('step', 'login'));
  });

  test(
    'f04/us02/fr06: an approved journey is checked as a draft one is',
    () async {
      final found = await _check([
        '### 1. Sign in',
        'step: $_story S9',
      ], frontmatter: '---\nstatus: approved\n---\n\n');
      expect(_of(found, FindingKind.journeyStepUnresolved), hasLength(1));
    },
  );

  test('f04/us01/fr01: check journey:sign_in reports an untyped file in the '
      "journey's folder", () async {
    final report = checkOf(
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

    test('f10/us01/s4, f10/us01/fr01/e03: a journey with no persona key has '
        'no persona finding', () async {
      expect(await _check(steps), isEmpty);
    });

    test('f10/us01/fr01/e02: three personas, none unresolved', () async {
      const names = ['buyer', 'seller', 'admin'];
      final found = await _check(
        steps,
        frontmatter: '---\npersona: [${names.join(', ')}]\n---\n\n',
        extra: {
          for (final name in names)
            'docs/prds/personas/$name/PERSONA.md':
                '---\nrole: Agent\npriority: primary\nbasis: proto\n---\n\n'
                '# $name\n',
        },
      );
      expect(_of(found, FindingKind.docRefUnresolved), isEmpty);
    });

    test('f10/us01/fr01/e04: 40 steps raise no count finding', () async {
      final found = await _check([
        for (var n = 1; n <= 40; n++) ...[
          '### $n. Step $n',
          'step: $_story S1',
        ],
      ]);
      expect(found, isEmpty);
    });

    test('f10/us01/fr01/e05: persona: [buyer] with no persona buyer is '
        'doc_ref_unresolved', () async {
      final found = await _check(
        steps,
        frontmatter: '---\npersona: [buyer]\n---\n\n',
      );
      expect(found.map((f) => f.kind), [FindingKind.docRefUnresolved]);
      expect(found.single.toJson(), containsPair('value', 'buyer'));
    });
  });
}
