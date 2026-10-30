import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/journeys/journey_answers.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

const _slug = 'first_project_to_html';
const _journeyPath = 'docs/prds/journeys/$_slug/JOURNEY.md';
const _story = 'login/email_login';

String _scenario(int n) =>
    '### Scenario $n — [happy] Step $n\n- **Given** a$n\n- **When** b$n\n'
    '- **Then** c$n';

String _lines(int n) => switch (n) {
  1 => loginScenario1.substring(loginScenario1.indexOf('\n') + 1),
  2 => loginScenario2.substring(loginScenario2.indexOf('\n') + 1),
  _ => _scenario(n).substring(_scenario(n).indexOf('\n') + 1),
};

// The login story with scenarios 1 to 5; 1 and 2 are the fixture's own.
String _storyText({String implements = '  - app/lib/login.dart:SignInPage\n'}) {
  final base = checkProjectFiles()['docs/$loginStory']!.replaceFirst(
    'implements:\n  - app/lib/login.dart:SignInPage\n',
    implements.isEmpty ? '' : 'implements:\n$implements',
  );
  return '$base\n${[for (var n = 3; n <= 5; n++) _scenario(n)].join('\n\n')}\n';
}

String _step(String number, int scenario, {String? after}) =>
    '### $number. Heading $number\nstep: $_story S$scenario\n'
    '${after == null ? '' : 'after: $after\n'}';

String _journey(List<String> steps, {String front = ''}) =>
    '$front# First project to html\n\n## Goal\nReach html.\n\n## Flow\n\n'
    '## Steps\n${steps.join('\n')}';

List<String> _mainAndBranch() => [
  for (var n = 1; n <= 5; n++) _step('$n', n),
  _step('3x', 3, after: '2'),
];

Future<ReadAnswer> _answer(
  List<String> steps, {
  required ReadAnswer Function(DocIndex index, String name) answer,
  String name = 'journey:$_slug',
  String front = '',
  Map<String, String> extra = const {},
}) async {
  final session = openSession(
    await writeCheckProject(
      extra: {
        'docs/$loginStory': _storyText(),
        _journeyPath: _journey(steps, front: front),
        ...extra,
      },
    ),
  );
  addTearDown(session.close);
  return answer(session.index, name);
}

Future<ReadAnswer> _paths(
  List<String> steps, {
  String name = 'journey:$_slug',
  String front = '',
  Map<String, String> extra = const {},
}) => _answer(
  steps,
  answer: answerJourneyPaths,
  name: name,
  front: front,
  extra: extra,
);

Future<ReadAnswer> _code(
  List<String> steps, {
  String name = 'journey:$_slug',
  Map<String, String> extra = const {},
}) => _answer(steps, answer: answerJourneyCode, name: name, extra: extra);

Matcher _refused(IndexFaultCode code, String message) => throwsA(
  isA<IndexFault>()
      .having((f) => f.code, 'code', code)
      .having((f) => f.message, 'message', message),
);

String _stepLine(String number, int scenario) =>
    '$number. Heading $number — $_story S$scenario';

void main() {
  group('answerJourneyPaths', () {
    test('f10/us02/s1, f10/us02/fr01/e01: paths 5 and 3x print in that order '
        "with each step's scenario lines", () async {
      final answer = await _paths(_mainAndBranch());

      final text = answer.text;
      expect(
        text,
        startsWith(
          '==> $_slug (journey) · prds/journeys/$_slug/JOURNEY.md <==\n'
          'journey:$_slug path 5\n',
        ),
      );
      expect(
        text,
        contains(
          'journey:$_slug path 5\n'
          '${_stepLine('1', 1)}\n${_lines(1)}\n'
          '${_stepLine('2', 2)}\n${_lines(2)}\n'
          '${_stepLine('3', 3)}\n${_lines(3)}\n'
          '${_stepLine('4', 4)}\n${_lines(4)}\n'
          '${_stepLine('5', 5)}\n${_lines(5)}\n'
          'journey:$_slug path 3x\n'
          '${_stepLine('1', 1)}\n${_lines(1)}\n'
          '${_stepLine('2', 2)}\n${_lines(2)}\n'
          '${_stepLine('3x', 3)}\n${_lines(3)}\n',
        ),
      );
      expect(answer.warnings, isEmpty);
    });

    test('f10/us02/s2, f10/us02/fr01/e02: a pasted copy older than its story '
        "prints the story's lines", () async {
      final answer = await _paths([
        '### 1. Heading 1\nstep: $_story S1\n',
        [
          generatedOpenMarker('scenario_copy'),
          'OLD COPY LINE',
          generatedEndMarker,
        ].join('\n'),
      ]);

      expect(answer.text, contains(_lines(1)));
      expect(answer.text, isNot(contains('OLD COPY LINE')));
    });

    test('f10/us02/s3: a step naming a missing scenario prints its line '
        'alone and one warning', () async {
      final answer = await _paths([_step('1', 1), _step('2', 9)]);

      expect(answer.text, contains('${_stepLine('2', 9)}\n'));
      expect(
        answer.text.split('\n'),
        isNot(contains(_lines(9))),
        reason: 'no scenario lines for S9',
      );
      expect(answer.text, endsWith('${_stepLine('2', 9)}\n'));
      expect(answer.warnings, ['$_slug: step 2 names no scenario']);
    });

    test('f10/us02/s4, f10/us02/fr01/e03: user_story:login/email_login is '
        'argument_invalid, exit 64', () async {
      await expectLater(
        _paths([_step('1', 1)], name: 'user_story:$_story'),
        _refused(
          IndexFaultCode.argumentInvalid,
          'user_story:$_story is not a journey; --paths reads journeys only',
        ),
      );
    });

    test('f10/us02/fr01/e03: a bare name that also resolves to a persona is '
        'refused too', () async {
      await expectLater(
        _paths(
          [_step('1', 1)],
          name: _slug,
          extra: {'docs/prds/personas/$_slug/PERSONA.md': '# Same name\n'},
        ),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.argumentInvalid,
          ),
        ),
      );
    });

    test('f10/us02/fr01/e05: one step is one path', () async {
      final answer = await _paths([_step('1', 1)]);

      expect(
        answer.text,
        contains('journey:$_slug path 1\n${_stepLine('1', 1)}\n'),
      );
      expect('path '.allMatches(answer.text), hasLength(1));
    });

    test('f10/us02/fr01/e06: a step on no path prints under no path, with a '
        'warning', () async {
      final answer = await _paths([_step('1', 1), _step('2', 2, after: '7')]);

      expect(answer.text, contains('path 1\n${_stepLine('1', 1)}\n'));
      expect(answer.text, endsWith('${_stepLine('2', 2)}\n${_lines(2)}\n'));
      expect('path '.allMatches(answer.text), hasLength(1));
      expect(answer.warnings, [
        '$_slug: step 2 follows no step above it, so it is on no path',
      ]);
    });

    test('f10/us02/fr01: a step that follows an off-path step is warned as '
        'such', () async {
      final answer = await _paths([
        _step('1', 1),
        _step('2', 2, after: '7'),
        _step('3', 3),
      ]);

      expect(answer.warnings, [
        '$_slug: step 2 follows no step above it, so it is on no path',
        '$_slug: step 3 follows step 2, which is on no path',
      ]);
    });

    test('f10/us02/fr01/e07: a draft journey prints', () async {
      final answer = await _paths([
        _step('1', 1),
      ], front: '---\ndraft: true\n---\n\n');

      expect(answer.text, contains('journey:$_slug path 1\n'));
    });

    test('f10/us02/fr01/e08: a second ### 3. prints the paths and one '
        'warning naming 3', () async {
      final answer = await _paths([
        _step('1', 1),
        _step('3', 3),
        _step('3', 4),
      ]);

      expect(answer.text, contains('journey:$_slug path 3\n'));
      expect(answer.warnings, ['$_slug: step number 3 is written twice']);
    });

    test('f10/us02/fr01: --json holds journeys, paths with id, cite, and '
        'steps, and warnings', () async {
      final answer = await _paths([_step('1', 1), _step('2', 9)]);

      expect(answer.json, {
        'journeys': [
          {
            'name': _slug,
            'path': 'prds/journeys/$_slug/JOURNEY.md',
            'paths': [
              {
                'id': '2',
                'cite': 'journey:$_slug path 2',
                'steps': [
                  {
                    'number': '1',
                    'heading': 'Heading 1',
                    'step': '$_story S1',
                    'scenario': _lines(1),
                  },
                  {
                    'number': '2',
                    'heading': 'Heading 2',
                    'step': '$_story S9',
                    'scenario': null,
                  },
                ],
              },
            ],
          },
        ],
      });
      expect(answer.warnings, ['$_slug: step 2 names no scenario']);
    });
  });

  group('answerJourneyCode', () {
    const storyEntry =
        '  $_story (user_story)\n'
        '  - implements: app/lib/login.dart:SignInPage\n';
    const frName = 'login/email_login/check_password';

    test('f10/us03/s1, f10/us03/fr01/e01: a step naming S2 lists the '
        "story's entries and the FR traced from S2 only", () async {
      final answer = await _code([_step('1', 1), _step('2', 2)]);

      expect(
        answer.text,
        '==> $_slug (journey) · prds/journeys/$_slug/JOURNEY.md <==\n'
        '${_stepLine('1', 1)}\n$storyEntry'
        '${_stepLine('2', 2)}\n$storyEntry'
        '  $frName (fr)\n'
        '  - implements: app/lib/login.dart:checkPassword\n',
      );
      expect(answer.warnings, isEmpty);
    });

    test('f10/us03/s2, f10/us03/fr01/e02: with prd-core alone each step '
        'prints its FRs and - none', () async {
      final answer = await _code(
        [_step('1', 1)],
        extra: {
          'docs/$loginStory': _storyText(implements: ''),
          'docs/$loginFr': checkProjectFiles()['docs/$loginFr']!.replaceFirst(
            'traced_from:\n  - S2\n',
            'traced_from:\n  - S5\n',
          ),
        },
      );

      expect(
        answer.text,
        endsWith('${_stepLine('1', 1)}\n  $_story (user_story)\n  - none\n'),
      );
    });

    test('f10/us03/fr01/e03: an FR traced from S2 and S4 is listed under '
        'each step naming either', () async {
      final answer = await _code(
        [_step('1', 2), _step('2', 4)],
        extra: {
          'docs/$loginFr': checkProjectFiles()['docs/$loginFr']!.replaceFirst(
            'traced_from:\n  - S2\n',
            'traced_from:\n  - S2\n  - S4\n',
          ),
        },
      );

      expect('  $frName (fr)'.allMatches(answer.text), hasLength(2));
    });

    test('f10/us03/fr01/e04: an implements entry naming a missing file '
        'prints as written', () async {
      final answer = await _code(
        [_step('1', 1)],
        extra: {
          'docs/$loginStory': _storyText(
            implements: '  - app/lib/missing.dart:Ghost\n',
          ),
        },
      );

      expect(
        answer.text,
        contains('  - implements: app/lib/missing.dart:Ghost\n'),
      );
      expect(answer.warnings, isEmpty);
    });

    test('f10/us03/s3, f10/us03/fr01/e05: get feature:login --code is '
        'argument_invalid', () async {
      await expectLater(
        _code([_step('1', 1)], name: 'feature:login'),
        _refused(
          IndexFaultCode.argumentInvalid,
          'feature:login is not a journey; --code reads journeys only',
        ),
      );
    });

    test('f10/us03/fr01/e06, f10/us03/fr01/e07: a step naming a missing '
        'story, or S9 of a five-scenario story, prints its line with no '
        'entries and a warning', () async {
      final answer = await _code([
        _step('1', 9),
        '### 2. Heading 2\nstep: nobody/home S1\n',
      ]);

      expect(
        answer.text,
        endsWith(
          '${_stepLine('1', 9)}\n'
          '2. Heading 2 — nobody/home S1\n',
        ),
      );
      expect(answer.warnings, [
        '$_slug: step 1 names no scenario',
        '$_slug: step 2 names no scenario',
      ]);
    });

    test(
      'f10/us03/fr01: --json holds journeys with steps, story, and frs',
      () async {
        final answer = await _code([_step('2', 2)]);

        expect(answer.json, {
          'journeys': [
            {
              'name': _slug,
              'path': 'prds/journeys/$_slug/JOURNEY.md',
              'steps': [
                {
                  'number': '2',
                  'heading': 'Heading 2',
                  'step': '$_story S2',
                  'story': {
                    'name': _story,
                    'implements': ['app/lib/login.dart:SignInPage'],
                  },
                  'frs': [
                    {
                      'name': frName,
                      'implements': ['app/lib/login.dart:checkPassword'],
                    },
                  ],
                },
              ],
            },
          ],
        });
      },
    );
  });
}
