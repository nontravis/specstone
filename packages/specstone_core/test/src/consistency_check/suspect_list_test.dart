// The expected values are plan literals kept as written.
// ignore_for_file: avoid_escaping_inner_quotes

import 'package:specstone_core/specstone_core.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

void main() {
  final edited = loginScenario2.replaceFirst('wrong password', 'wrong pass');

  test('f04/us04/fr04, cc-s03/inv6: the suspect filter keeps answerList\'s order and line form', () async {
    final session = openSession(
      await writeCheckProject(extra: doc(loginStory, loginScenario2, edited)),
    );
    addTearDown(session.close);
    final answer = answerListSuspect(session, 'fr', const ListFilters());
    final fr = session.index.at(loginFr)!;
    expect(answer.text, '${docLine(session.index, fr)}\n');
    expect(answer.json, {
      'docs': [docJson(session.index, fr)],
    });
  });

  test('cc-s03/inv2: a project layer that disables confirmed on fr lists no suspect fr', () async {
    final session = openSession(
      await writeCheckProject(
        extra: {
          '.specstone/templates/fr.yaml':
              'fields:\n  - id: confirmed\n    disabled: true\n',
          ...doc(loginStory, loginScenario2, edited),
        },
      ),
    );
    addTearDown(session.close);
    final answer = answerListSuspect(session, 'fr', const ListFilters());
    expect(answer.json, {'docs': <Object?>[]});
  });

  group('a record', () {
    const item = 'email_login/check_password';
    const edgeCase = '1. E01 — An empty password → refused.';
    const older = '3f9a1c0b7e2d';

    Future<ReadSession> sessionWith(String row) async {
      final session = openSession(
        await writeCheckProject(
          extra: {
            loginRecord:
                "---\nstatuses:\n  - '$item:implemented'\n---\n\n# Record\n\n"
                '## Verification matrix\n\n$row\n',
          },
        ),
      );
      addTearDown(session.close);
      return session;
    }

    test(
      'list implementation suspect lists a record with a suspect row',
      () async {
        final session = await sessionWith('- $item E01: `refuses it` $older');

        final answer = answerListSuspect(
          session,
          'implementation',
          const ListFilters(),
        );

        final record = session.index.at(loginRecord)!;
        expect(answer.json, {
          'docs': [docJson(session.index, record)],
        });
      },
    );

    test('a row that is clean or has no fingerprint lists no record', () async {
      final clean = await sessionWith(
        '- $item E01: `refuses it` ${fingerprintOf(edgeCase)}',
      );
      final unstamped = await sessionWith('- $item E01: `refuses it`');

      for (final session in [clean, unstamped]) {
        final answer = answerListSuspect(
          session,
          'implementation',
          const ListFilters(),
        );

        expect(answer.json, {'docs': <Object?>[]});
      }
    });
  });
}
