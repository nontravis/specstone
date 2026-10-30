import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/list_docs.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/journeys/unwalked.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

const _story = 'login/email_login';
const _other = 'login/other_story';
const _otherPath =
    'docs/prds/features/f01_login/us02_other_story/USER_STORY.md';

String _scenario(int n) =>
    '### Scenario $n — [happy] Step $n\n- **Given** a$n\n- **When** b$n\n'
    '- **Then** c$n';

// The login story with scenarios 1 to 3; 1 and 2 are the fixture's own.
String _threeScenarios() {
  final base = checkProjectFiles()['docs/$loginStory']!;
  return '$base\n${_scenario(3)}\n';
}

String _journey(List<String> stepTargets, {bool draft = false}) {
  final front = draft ? '---\ndraft: true\n---\n\n' : '';
  final steps = [
    for (var i = 0; i < stepTargets.length; i++)
      '### ${i + 1}. Heading ${i + 1}\nstep: ${stepTargets[i]}\n',
  ];
  return '$front# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n'
      '## Steps\n${steps.join('\n')}';
}

Map<String, String> _files(
  List<String> stepTargets, {
  bool draft = false,
  Map<String, String> extra = const {},
}) => {
  'docs/$loginStory': _threeScenarios(),
  if (stepTargets.isNotEmpty)
    'docs/prds/journeys/sign_in/JOURNEY.md': _journey(
      stepTargets,
      draft: draft,
    ),
  ...extra,
};

Future<ReadAnswer> _unwalked(
  Map<String, String> extra, {
  String docType = 'user_story',
  ListFilters filters = const ListFilters(),
}) async {
  final session = openSession(await writeCheckProject(extra: extra));
  addTearDown(session.close);
  final index = session.index;
  return answerListUnwalked(
    index,
    docType,
    answerList(index, docType, filters),
  );
}

List<String> _lines(ReadAnswer answer) =>
    answer.text.split('\n').where((l) => l.isNotEmpty).toList();

void main() {
  test('f10/us04/s1, f10/us04/fr01/e01: a three-scenario story whose '
      'Scenario 1 one step names lists S2 and S3', () async {
    final answer = await _unwalked(_files(['$_story S1']));
    final lines = _lines(answer);
    expect(lines, hasLength(3));
    expect(lines.first, startsWith('$_story (user_story)'));
    expect(lines[1], '  S2 [error] Wrong password');
    expect(lines[2], '  S3 [happy] Step 3');
    final docs = answer.json['docs']! as List;
    expect((docs.single as Map)['unwalked'], ['S2', 'S3']);
  });

  test('f10/us04/s2, f10/us04/fr01/e06: a story whose scenarios are all '
      'walked is not listed', () async {
    final answer = await _unwalked(
      _files(['$_story S1', '$_story S2', '$_story S3']),
    );
    expect(answer.text, isEmpty);
    expect(answer.json, {'docs': <Object?>[]});
    expect(answer.exitStatus, 0);
  });

  test('f10/us04/fr01/e02: with no journey every story with a scenario lists '
      'each one', () async {
    final answer = await _unwalked(_files([]));
    expect(_lines(answer).skip(1), [
      '  S1 [happy] Sign in',
      '  S2 [error] Wrong password',
      '  S3 [happy] Step 3',
    ]);
  });

  test(
    'f10/us04/fr01/e03: a step of a draft journey walks its scenario',
    () async {
      final answer = await _unwalked(
        _files(['$_story S1', '$_story S2'], draft: true),
      );
      expect(_lines(answer).skip(1), ['  S3 [happy] Step 3']);
    },
  );

  test(
    'f10/us04/fr01/e04: a step naming a missing scenario walks nothing',
    () async {
      final answer = await _unwalked(_files(['$_story S1', '$_story S9']));
      expect(_lines(answer).skip(1), [
        '  S2 [error] Wrong password',
        '  S3 [happy] Step 3',
      ]);
    },
  );

  test(
    'f10/us04/fr01: a step naming another story walks nothing here',
    () async {
      final answer = await _unwalked(_files(['$_other S1']));
      expect(_lines(answer).skip(1), hasLength(3));
    },
  );

  test('f10/us04/s4, f10/us04/fr01/e05: list feature --unwalked is '
      'argument_invalid, exit 64', () async {
    await expectLater(
      _unwalked(_files([]), docType: 'feature'),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
            .having(
              (f) => f.message,
              'message',
              '--unwalked lists user_story docs only, not feature',
            ),
      ),
    );
  });

  test(
    'f10/us04/s3: check reports no finding about unwalked scenarios',
    () async {
      final project = await writeCheckProject(extra: _files([]));
      expect(checkOf(project).findings, isEmpty);
    },
  );

  test('f10/us04/fr01: --unwalked combines with --under', () async {
    final extra = _files(
      [],
      extra: {
        _otherPath:
            '# Other story\n\n## Story\nAs an Agent I want x so that y.\n\n'
            '## Acceptance criteria\n${_scenario(1)}\n',
      },
    );
    final all = await _unwalked(extra);
    final under = await _unwalked(
      extra,
      filters: const ListFilters(under: _story),
    );
    final allNames = (all.json['docs']! as List).map((d) => (d as Map)['name']);
    final underNames = (under.json['docs']! as List).map(
      (d) => (d as Map)['name'],
    );
    expect(underNames, [_story]);
    expect(allNames, containsAll([_story]));
    expect(allNames.length, greaterThanOrEqualTo(underNames.length));
  });
}
