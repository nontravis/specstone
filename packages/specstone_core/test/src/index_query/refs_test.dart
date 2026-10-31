// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/refs.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

const _journeyDoc = 'docs/prds/journeys/sign_in/JOURNEY.md';

String _journey(List<String> stepLines) =>
    '# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n'
    '${stepLines.join('\n')}\n';

Future<DocIndex> _withJourney(List<String> stepLines) =>
    indexWith({_journeyDoc: _journey(stepLines)});

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith());

  test("f01/us07/s1, f01/us07/fr01, f01/us07/fr01/e02: a story's outbound doc_ref, link, and pointer, and its inbound link", () async {
    expect(
      answerRefs(index, 'login/email_login').text,
      '==> login/email_login (user_story) · prds/features/f01_login/us01_email_login/USER_STORY.md <==\n'
      'Outbound\n- persona: buyer (persona)\n- link: password_rules (reference)\n'
      '- implements: app/lib/src/login/sign_in_page.dart:SignInPage\n'
      'Inbound\n- link: login/email_login/validate_credentials (fr)\n',
    );
  });
  test("f01/us07/fr01/e01: a doc_ref targets its field's doc types only, and shows inbound on the target", () async {
    expect(
      answerRefs(index, 'persona:buyer').text,
      contains('Inbound\n- persona: login/email_login (user_story)\n'),
    );
    expect(
      answerRefs(index, 'anti_persona:buyer').text,
      contains('Inbound\n- none\n'),
    );
  });
  test('f01/us07/s2, f01/us07/fr01/e03, f01/us07/fr01/e10: pointers are outbound only; an empty group prints - none', () async {
    expect(
      answerRefs(index, 'architecture:login').text,
      '==> login (architecture) · specs/f01_login/ARCHITECTURE.md <==\nOutbound\n- covers: app/lib/src/login/\nInbound\n- none\n',
    );
  });
  test(
    'f01/us07/s3, f01/us07/fr01/e04: a name or an ID in text is no reference',
    () async {
      final mentions = await indexWith({
        'docs/notes.md': '# Notes\n\nSee login/email_login and PG-01.\n',
      });
      expect(
        answerRefs(mentions, 'login/email_login').text,
        isNot(contains('notes.md')),
      );
    },
  );
  test('f01/us07/s4, f01/us07/fr01/e05, f01/us07/fr01/e06, f01/us07/fr01/e10: broken, external, and non-md links are left out', () async {
    final links = await indexWith({
      'docs/notes.md': '# Notes\n\n[gone](missing.md) [web](https://x.org) [schema](specs/schema.dbml)\n',
    });
    expect(
      answerRefs(links, 'notes.md').text,
      '==> notes.md · notes.md <==\nOutbound\n- none\nInbound\n- none\n',
    );
  });
  test(
    'f01/us07/fr01/e07: a shared name gives each doc its own group',
    () async {
      expect('==> '.allMatches(answerRefs(index, 'login').text), hasLength(5));
    },
  );
  test(
    'f01/us07/s5, f01/us07/fr01/e08: a name no doc carries is doc_not_found',
    () async {
      expect(() => answerRefs(index, 'logn'), throwsA(isA<IndexFault>()));
    },
  );
  test(
    'f01/us07/fr01: --json gives kind and either name and docType or pointer',
    () async {
      final doc =
          (answerRefs(index, 'login/email_login').json['docs']! as List).single
              as Map;
      expect(doc['outbound'], [
        {'kind': 'persona', 'name': 'buyer', 'docType': 'persona'},
        {'kind': 'link', 'name': 'password_rules', 'docType': 'reference'},
        {
          'kind': 'implements',
          'pointer': 'app/lib/src/login/sign_in_page.dart:SignInPage',
        },
      ]);
      expect(doc['inbound'], [
        {
          'kind': 'link',
          'name': 'login/email_login/validate_credentials',
          'docType': 'fr',
        },
      ]);
    },
  );
  test('f01/us07/s7, f01/us07/fr02/e01: steps 3 and 3x naming one story give one outbound and one inbound step', () async {
    final withJourney = await _withJourney([
      '### 3. Enter details',
      'step: login/email_login S1',
      '### 3x. Wrong password',
      'after: 3',
      'step: login/email_login S2',
    ]);
    expect(
      answerRefs(withJourney, 'journey:sign_in').text,
      contains('Outbound\n- step: login/email_login (user_story)\nInbound\n'),
    );
    expect(
      answerRefs(withJourney, 'login/email_login').text,
      contains('- step: sign_in (journey)\n'),
    );
    final story =
        (answerRefs(withJourney, 'login/email_login').json['docs']! as List)
                .single
            as Map;
    expect(
      [
        for (final ref in story['inbound']! as List)
          if ((ref as Map)['kind'] == 'step') ref,
      ],
      [
        {'kind': 'step', 'name': 'sign_in', 'docType': 'journey'},
      ],
    );
  });
  test('f01/us07/fr02/e02: refs feature:login has no step line', () async {
    final withJourney = await _withJourney([
      '### 1. Enter details',
      'step: login/email_login S1',
    ]);
    expect(
      answerRefs(withJourney, 'feature:login').text,
      isNot(contains('step')),
    );
  });
  test('f01/us07/fr02/e03: a step naming no story is not listed', () async {
    final withJourney = await _withJourney([
      '### 1. Enter details',
      'step: nope/none S1',
      '### 2. Wander',
      'no step line here',
    ]);
    expect(
      answerRefs(withJourney, 'journey:sign_in').text,
      contains('Outbound\n- none\n'),
    );
  });
  test(
    'f01/us07/fr02/e04: a step naming a missing scenario of a story is listed',
    () async {
      final withJourney = await _withJourney([
        '### 1. Enter details',
        'step: login/email_login S9',
      ]);
      expect(
        answerRefs(withJourney, 'journey:sign_in').text,
        contains('- step: login/email_login (user_story)\n'),
      );
    },
  );
  test('f01/us07/fr01: the groups print doc_ref, link, step, then implements and covers', () async {
    final steps = ['### 1. Enter details', 'step: login/email_login S1'];
    final withJourney = await indexWith({
      _journeyDoc:
          '---\npersona:\n  - buyer\n---\n\n${_journey(steps)}\n[rules](../../references/password_rules/REFERENCE.md)\n',
    });
    expect(
      answerRefs(withJourney, 'journey:sign_in').text,
      contains(
        'Outbound\n- persona: buyer (persona)\n- link: password_rules (reference)\n- step: login/email_login (user_story)\n',
      ),
    );
    expect(
      answerRefs(withJourney, 'login/email_login').text,
      contains(
        'Inbound\n- link: login/email_login/validate_credentials (fr)\n- step: sign_in (journey)\n',
      ),
    );
  });
}
