import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/journeys/journey_answers.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/shipped_pins.dart';

const _slug = 'first_project_to_html';
const _journeyPath = 'docs/prds/journeys/$_slug/JOURNEY.md';
const _story = 'login/email_login';

String _scenario(int n) =>
    '### Scenario $n — [happy] Step $n\n- **Given** a$n\n- **When** b$n\n'
    '- **Then** c$n';

String _lines(int n) => switch (n) {
  1 => loginScenario1.substring(loginScenario1.indexOf('\n') + 1).trimLeft(),
  2 => loginScenario2.substring(loginScenario2.indexOf('\n') + 1).trimLeft(),
  _ => _scenario(n).substring(_scenario(n).indexOf('\n') + 1),
};

// The login story with scenarios 1 to 5; 1 and 2 are the fixture's own.
String _storyText() {
  final base = checkProjectFiles()['docs/$loginStory']!;
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
  String? codeTarget,
  Map<String, String> extra = const {},
}) => _answer(
  steps,
  answer: (index, name) =>
      answerJourneyCode(index, name, codeTarget: codeTarget),
  name: name,
  extra: extra,
);

const _recordLayer =
    'id: implementation\n'
    'description: One feature record per target.\n'
    'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
    'parent: feature\n'
    'per_target: true\n'
    'fields:\n'
    '  - id: statuses\n'
    '    type: record_status\n'
    '    list: true\n'
    '  - id: implements\n'
    '    type: output_ref\n'
    '    list: true\n'
    '    pointer: item_exact\n';

String _record({
  List<String> statuses = const [],
  List<String> code = const [],
}) {
  String list(String key, List<String> lines) => lines.isEmpty
      ? ''
      : '$key:\n${[for (final l in lines) '  - $l\n'].join()}';
  return '---\n${list('statuses', statuses)}${list('implements', code)}---\n\n'
      '# Record\n';
}

/// A project of one unnamed code target, its record holding [code].
Map<String, String> _oneTarget(
  List<String> code, {
  List<String> statuses = const [],
}) => {
  '.specstone/templates/implementation.yaml': _recordLayer,
  '.specstone/config.yaml': '${shippedPinsConfig()}code_root: app\n',
  'docs/specs/f01_login/IMPLEMENTATION.md': _record(
    statuses: statuses,
    code: code,
  ),
};

/// A project of the code targets `flutter` and `jaspr`, with the records of
/// each.
Map<String, String> _twoTargets({
  List<String> flutter = const [],
  List<String> flutterStatuses = const [],
  List<String> jaspr = const [],
  List<String> jasprStatuses = const [],
}) => {
  '.specstone/templates/implementation.yaml': _recordLayer,
  '.specstone/config.yaml':
      '${shippedPinsConfig()}targets:\n'
      '  flutter:\n    code_root: app\n'
      '  jaspr:\n    code_root: jaspr_lib\n',
  'jaspr_lib/.keep': '',
  'docs/specs/flutter/f01_login/IMPLEMENTATION.md': _record(
    statuses: flutterStatuses,
    code: flutter,
  ),
  'docs/specs/jaspr/f01_login/IMPLEMENTATION.md': _record(
    statuses: jasprStatuses,
    code: jaspr,
  ),
};

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

    test('a step naming a missing scenario prints its line '
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

    test('a bare name that also resolves to a persona is '
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

    test('one step is one path', () async {
      final answer = await _paths([_step('1', 1)]);

      expect(
        answer.text,
        contains('journey:$_slug path 1\n${_stepLine('1', 1)}\n'),
      );
      expect('path '.allMatches(answer.text), hasLength(1));
    });

    test('a step on no path prints under no path, with a '
        'warning', () async {
      final answer = await _paths([_step('1', 1), _step('2', 2, after: '7')]);

      expect(
        answer.text,
        contains(
          'journey:$_slug path 1\n${_stepLine('1', 1)}\n${_lines(1)}\n'
          'journey:$_slug no path\n${_stepLine('2', 2)}\n${_lines(2)}\n',
        ),
      );
      expect('path '.allMatches(answer.text), hasLength(1));
      expect(answer.warnings, [
        '$_slug: step 2 follows no step above it, so it is on no path',
      ]);
    });

    test('a step that follows an off-path step is warned as '
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

    test('a draft journey prints', () async {
      final answer = await _paths([
        _step('1', 1),
      ], front: '---\ndraft: true\n---\n\n');

      expect(answer.text, contains('journey:$_slug path 1\n'));
    });

    test('a second ### 3. prints the paths and one '
        'warning naming 3', () async {
      final answer = await _paths([
        _step('1', 1),
        _step('3', 3),
        _step('3', 4),
      ]);

      expect(answer.text, contains('journey:$_slug path 3\n'));
      expect(answer.warnings, ['$_slug: step number 3 is written twice']);
    });

    test('--json holds journeys, paths with id, cite, and '
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
    const storyCode = 'email_login:app/lib/login.dart:SignInPage';
    const frCode =
        'email_login/check_password:app/lib/login.dart:checkPassword';
    const storyEntry =
        '  $_story (user_story)\n'
        '  - implements: app/lib/login.dart:SignInPage\n';
    const frName = 'login/email_login/check_password';
    final single = _oneTarget([storyCode, frCode]);

    test('f10/us03/s1, f10/us03/fr01/e01: a step naming S2 lists the '
        "story's entries and the FR traced from S2 only", () async {
      final answer = await _code([_step('1', 1), _step('2', 2)], extra: single);

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

    test(
      'f10/us03/s2, f10/us03/fr01/e02: with no record doc type each step '
      'prints its FRs and - none, whatever the docs hold in implements',
      () async {
        final answer = await _code(
          [_step('1', 1)],
          extra: {
            '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
          },
        );

        expect(
          answer.text,
          endsWith('${_stepLine('1', 1)}\n  $_story (user_story)\n  - none\n'),
        );
        expect(answer.warnings, isEmpty);
      },
    );

    test('an FR traced from S2 and S4 is listed under '
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

    test(
      'FRs of a sibling story and of another feature '
      "tracing the step are listed after the story's own, in tree order",
      () async {
        String fr(String title, String entry) =>
            '---\ntraced_from:\n  - S1\n  - $entry\n---\n\n# $title\n\n'
            '## Statement\nThe system shall.\n';
        const sibling = 'docs/prds/features/f01_login/us02_reset_password';
        const other = 'docs/prds/features/f02_billing/us01_invoice';
        final answer = await _code(
          [_step('1', 2)],
          extra: {
            '$sibling/USER_STORY.md': '# Reset\n\n## Use Case\nReset.\n',
            '$sibling/fr01_send_link.md': fr('sendLink', '$_story#S2'),
            '$other/USER_STORY.md': '# Invoice\n\n## Use Case\nInvoice.\n',
            '$other/fr01_charge.md': fr('charge', '$_story#S2'),
          },
        );

        final order = [
          frName,
          'login/reset_password/send_link (fr)',
          'billing/invoice/charge (fr)',
        ].map(answer.text.indexOf).toList();
        expect(order, everyElement(isNonNegative));
        expect(order, [...order]..sort());
      },
    );

    test('a record code path naming a missing file '
        'prints as written', () async {
      final answer = await _code([
        _step('1', 1),
      ], extra: _oneTarget(['email_login:app/lib/missing.dart:Ghost']));

      expect(
        answer.text,
        contains('  - implements: app/lib/missing.dart:Ghost\n'),
      );
      expect(answer.warnings, isEmpty);
    });

    test('a story and an FR entry holding a code fingerprint '
        'print the pointer alone', () async {
      final answer = await _code(
        [_step('2', 2)],
        extra: _oneTarget(['$storyCode 5d1e0c4b7a92', '$frCode 0a1b2c3d4e5f']),
      );

      expect(
        answer.text,
        endsWith(
          '${_stepLine('2', 2)}\n$storyEntry'
          '  $frName (fr)\n'
          '  - implements: app/lib/login.dart:checkPassword\n',
        ),
      );
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

    test('--json holds journeys with steps, story, and frs', () async {
      final answer = await _code([_step('2', 2)], extra: single);

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
    });

    group('skips and a single named target', () {
      test('a skipped item holding paths prints skipped '
          'and gives [] in JSON', () async {
        final answer = await _code(
          [_step('1', 1)],
          extra: _twoTargets(
            flutter: [storyCode],
            flutterStatuses: ['email_login:skipped:no flutter'],
          ),
        );

        expect(
          answer.text,
          endsWith('  $_story (user_story)\n  - flutter: skipped\n'),
        );
        final step =
            (((answer.json['journeys']! as List).single as Map)['steps']!
                        as List)
                    .single
                as Map;
        expect((step['story']! as Map)['implementsByTarget'], {
          'flutter': <String>[],
          'jaspr': <String>[],
        });
      });

      test('a skip of the whole feature skips its story '
          'and FRs in that target', () async {
        final answer = await _code(
          [_step('2', 2)],
          extra: _twoTargets(
            jaspr: [storyCode],
            jasprStatuses: [':skipped:no web'],
          ),
        );

        expect(
          answer.text,
          endsWith(
            '  $_story (user_story)\n  - jaspr: skipped\n'
            '  $frName (fr)\n  - jaspr: skipped\n',
          ),
        );
      });

      test('one named target prints with no target '
          'name, a skip as - skipped', () async {
        Map<String, String> one(List<String> statuses) => {
          '.specstone/templates/implementation.yaml': _recordLayer,
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: app\n',
          'docs/specs/f01_login/IMPLEMENTATION.md': _record(
            statuses: statuses,
            code: [storyCode],
          ),
        };

        final plain = await _code([_step('1', 1)], extra: one([]));
        final skipped = await _code([
          _step('1', 1),
        ], extra: one(['email_login:skipped:no app']));

        expect(
          plain.text,
          endsWith('  - implements: app/lib/login.dart:SignInPage\n'),
        );
        expect(skipped.text, endsWith('  $_story (user_story)\n  - skipped\n'));
      });
    });

    group('two code targets', () {
      final twin = _twoTargets(
        flutter: [storyCode, frCode],
        jaspr: ['email_login:jaspr_lib/web_login.dart:WebLogin'],
        jasprStatuses: ['email_login/check_password:skipped:no web check'],
      );

      test(
        'each story and FR lists its flutter code '
        'paths, then its jaspr ones; a skip reads <target>: skipped',
        () async {
          final answer = await _code([_step('2', 2)], extra: twin);

          expect(
            answer.text,
            endsWith(
              '${_stepLine('2', 2)}\n'
              '  $_story (user_story)\n'
              '  - flutter: app/lib/login.dart:SignInPage\n'
              '  - jaspr: jaspr_lib/web_login.dart:WebLogin\n'
              '  $frName (fr)\n'
              '  - flutter: app/lib/login.dart:checkPassword\n'
              '  - jaspr: skipped\n',
            ),
          );
        },
      );

      test('entries holding a code fingerprint print each target line '
          'with the pointer alone', () async {
        final answer = await _code(
          [_step('2', 2)],
          extra: _twoTargets(
            flutter: ['$storyCode 5d1e0c4b7a92', '$frCode 0a1b2c3d4e5f'],
            jaspr: [
              'email_login:jaspr_lib/web_login.dart:WebLogin 9f8e7d6c5b4a',
            ],
          ),
        );

        expect(
          answer.text,
          endsWith(
            '${_stepLine('2', 2)}\n'
            '  $_story (user_story)\n'
            '  - flutter: app/lib/login.dart:SignInPage\n'
            '  - jaspr: jaspr_lib/web_login.dart:WebLogin\n'
            '  $frName (fr)\n'
            '  - flutter: app/lib/login.dart:checkPassword\n',
          ),
        );
      });

      test('--target jaspr keeps the one target, printed '
          'with no target name', () async {
        final answer = await _code(
          [_step('2', 2)],
          extra: twin,
          codeTarget: 'jaspr',
        );

        expect(
          answer.text,
          endsWith(
            '${_stepLine('2', 2)}\n'
            '  $_story (user_story)\n'
            '  - implements: jaspr_lib/web_login.dart:WebLogin\n'
            '  $frName (fr)\n'
            '  - skipped\n',
          ),
        );
      });

      test('a target whose record holds no path prints '
          'nothing, and - none when no target holds one', () async {
        final answer = await _code([
          _step('1', 1),
        ], extra: _twoTargets(flutter: [storyCode]));
        final bare = await _code([_step('1', 1)], extra: _twoTargets());

        expect(
          answer.text,
          endsWith(
            '  $_story (user_story)\n  - flutter: app/lib/login.dart:SignInPage\n',
          ),
        );
        expect(bare.text, endsWith('  $_story (user_story)\n  - none\n'));
      });

      test(
        '--json holds implementsByTarget in targets: '
        'order in place of implements; --target brings implements back',
        () async {
          final both = await _code([_step('2', 2)], extra: twin);
          final jaspr = await _code(
            [_step('2', 2)],
            extra: twin,
            codeTarget: 'jaspr',
          );

          final step =
              (((both.json['journeys']! as List).single as Map)['steps']!
                          as List)
                      .single
                  as Map;
          expect(step['story'], {
            'name': _story,
            'implementsByTarget': {
              'flutter': ['app/lib/login.dart:SignInPage'],
              'jaspr': ['jaspr_lib/web_login.dart:WebLogin'],
            },
          });
          expect((step['frs']! as List).single, {
            'name': frName,
            'implementsByTarget': {
              'flutter': ['app/lib/login.dart:checkPassword'],
              'jaspr': <String>[],
            },
          });
          final one =
              (((jaspr.json['journeys']! as List).single as Map)['steps']!
                          as List)
                      .single
                  as Map;
          expect(one['story'], {
            'name': _story,
            'implements': ['jaspr_lib/web_login.dart:WebLogin'],
          });
        },
      );
    });
  });
}
