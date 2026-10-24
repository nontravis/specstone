// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/refs.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

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
}
