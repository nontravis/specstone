// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/refs.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';

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
      'Inbound\n- link: login/email_login/validate_credentials (fr)\n'
      'Mentions\n- none\nUntyped mentions\n- none\n',
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
  test(
    'index_query/follow_references/list_doc_references E01, E05: depends_on is '
    'outbound to each feature it names and inbound on that feature',
    () async {
      final withDeps = await indexWith({
        'docs/prds/features/f02_signup/FEATURE.md': '---\nstatus: planned\ndepends_on:\n  - login\n  - payments\n---\n\n# Sign up\n\n## Problem\nNew users.\n',
      });
      expect(
        answerRefs(withDeps, 'feature:signup').text,
        contains('Outbound\n- depends_on: login (feature)\nInbound\n'),
      );
      expect(
        answerRefs(withDeps, 'feature:login').text,
        contains('Inbound\n- depends_on: signup (feature)\n'),
      );
      final signup =
          (answerRefs(withDeps, 'feature:signup').json['docs']! as List).single
              as Map;
      expect(signup['outbound'], [
        {'kind': 'depends_on', 'name': 'login', 'docType': 'feature'},
      ]);
    },
  );
  const emailFr =
      'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
  String frTracing(List<String> entries) =>
      '---\ntraced_from:\n${[for (final e in entries) '  - $e'].join('\n')}\n---\n\n'
      '# Validate credentials\n\n## Statement\nThe system shall check.\n';
  Future<DocIndex> withFrTracing(List<String> entries) =>
      indexWith({emailFr: frTracing(entries)});
  const frName = 'login/email_login/validate_credentials';

  test('index_query/follow_references/list_doc_references E22: a traced_from '
      'entry is outbound once per story and inbound on it; S<N> is no reference', () async {
    final traced = await withFrTracing([
      'S1',
      'login/reset_password#S2',
      'login/reset_password#S3',
    ]);
    expect(
      answerRefs(traced, frName).text,
      contains(
        'Outbound\n- traced_from: login/reset_password (user_story)\nInbound\n',
      ),
    );
    expect(
      answerRefs(traced, 'login/reset_password').text,
      contains('Inbound\n- traced_from: $frName (fr)\n'),
    );
  });
  test(
    'index_query/follow_references/list_doc_references E22: a story of '
    'another feature is listed, one that resolves to no story is not',
    () async {
      final traced = await withFrTracing([
        'signup/create_account#S1',
        'nowhere/story#S1',
      ]);
      final text = answerRefs(traced, frName).text;
      expect(
        text,
        contains('- traced_from: signup/create_account (user_story)\n'),
      );
      expect(text, isNot(contains('nowhere')));
      expect(
        answerRefs(traced, 'signup/create_account').text,
        contains('- traced_from: $frName (fr)\n'),
      );
    },
  );
  test('index_query/follow_references/list_doc_references E19: a repeated '
      'depends_on value prints one outbound and one inbound line', () async {
    final repeated = await indexWith({
      'docs/prds/features/f02_signup/FEATURE.md': '---\nstatus: planned\ndepends_on:\n  - login\n  - login\n---\n\n# Sign up\n\n## Problem\nNew users.\n',
    });
    expect(
      answerRefs(repeated, 'feature:signup').text,
      contains('Outbound\n- depends_on: login (feature)\nInbound\n'),
    );
    expect(
      answerRefs(repeated, 'feature:login').text,
      contains('Inbound\n- depends_on: signup (feature)\nMentions\n'),
    );
  });
  test(
    'index_query/follow_references/list_doc_references E20: a depends_on '
    'value naming the doc itself is no reference, outbound or inbound',
    () async {
      final self = await indexWith({
        featureKey:
            '---\nvision:\n  - PV-01\nslug:\n  - sign-in\ndepends_on:\n  - login\n---\n\n# Login\n\n'
            '## Problem\nUsers sign in with an email and a password.\n\n## Out-of-scope\n- Social sign-in — not planned\n',
      });
      expect(
        answerRefs(self, 'feature:login').text,
        isNot(contains('depends_on')),
      );
    },
  );
  test('index_query/follow_references/list_doc_references E21: one doc in '
      'depends_on and reference prints one line per field', () async {
    final both = await indexWith({
      'docs/prds/features/f02_signup/FEATURE.md': '---\nstatus: planned\ndepends_on:\n  - login\nreference:\n  - login\n---\n\n# Sign up\n\n## Problem\nNew users.\n',
    });
    final text = answerRefs(both, 'feature:signup').text;
    expect(text, contains('- depends_on: login (feature)\n'));
    expect(text, contains('- reference: login (feature)\n'));
  });
  test('index_query/follow_references/list_doc_references E05: an empty depends_on '
      'list or an empty item prints - none', () async {
    for (final value in ['[]', '\n  - ""']) {
      final withDeps = await indexWith({
        'docs/prds/features/f02_signup/FEATURE.md':
            '---\nstatus: planned\ndepends_on: $value\n---\n\n# Sign up\n\n## Problem\nNew users.\n',
      });
      expect(
        answerRefs(withDeps, 'feature:signup').text,
        contains('Outbound\n- none\n'),
        reason: value,
      );
    }
  });
  test('f01/us07/s2, f01/us07/fr01/e03, f01/us07/fr01/e10: pointers are outbound only; an empty group prints - none', () async {
    expect(
      answerRefs(index, 'architecture:login').text,
      '==> login (architecture) · specs/f01_login/ARCHITECTURE.md <==\nOutbound\n- covers: app/lib/src/login/\nInbound\n- none\nMentions\n- none\nUntyped mentions\n- none\n',
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
      '==> notes.md · notes.md <==\nOutbound\n- none\nInbound\n- none\nMentions\n- none\nUntyped mentions\n- none\n',
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
  group('mentions', () {
    const index = 'docs/specs/INDEX.md';
    const summary = 'docs/specs/tools/summary.md';
    const summaryText =
        '# Summary\n'
        '\n'
        'The map sits in `INDEX.md`.\n'
        'Old notes: specs/INDEX.md, kept for now.\n'
        '\n'
        '```text\n'
        'INDEX.md\n'
        '```\n'
        '\n'
        'Back to the [map](../INDEX.md); INDEX.md has it.\n';

    test('f01/us07/fr01: a backticked file name and a bare DocPath are listed with their line; fenced code and a linking line are not', () async {
      final mentions = await indexWith({
        index: '# Spec map\n\nThe old index.\n',
        summary: summaryText,
      });
      expect(
        answerRefs(mentions, 'specs/INDEX.md').text,
        '==> specs/INDEX.md · specs/INDEX.md <==\n'
        'Outbound\n- none\n'
        'Inbound\n- link: specs/tools/summary.md\n'
        'Mentions\n- none\n'
        'Untyped mentions\n- specs/tools/summary.md:3\n- specs/tools/summary.md:4\n',
      );
    });
    test('f01/us07/fr01: --json lists each mention by path and line', () async {
      final mentions = await indexWith({
        index: '# Spec map\n\nThe old index.\n',
        summary: summaryText,
      });
      final doc =
          (answerRefs(mentions, 'specs/INDEX.md').json['docs']! as List).single
              as Map;
      expect(doc['untypedMentions'], [
        {'path': 'specs/tools/summary.md', 'line': 3},
        {'path': 'specs/tools/summary.md', 'line': 4},
      ]);
    });
    test('f01/us07/fr01: a path or a link to a doc of the same file name elsewhere is no mention; nor is a bare shared file name', () async {
      final mentions = await indexWith({
        index: '# Spec map\n\nThe old index.\n',
        'docs/prds/INDEX.md': '# PRD map\n\nThe old PRD index.\n',
        'docs/notes.md':
            '# Notes\n\n'
            'See prds/INDEX.md and [the PRD map](prds/INDEX.md).\n'
            'Each tree kept an INDEX.md.\n'
            'MY_INDEX.md and INDEX.md.bak are other files.\n',
      });
      expect(
        answerRefs(mentions, 'specs/INDEX.md').text,
        endsWith('Mentions\n- none\nUntyped mentions\n- none\n'),
      );
    });
    test(
      'f01/us07/fr01: a bare file name several docs carry names none of them',
      () async {
        final mentions = await indexWith({
          'docs/superpowers/ledger.md':
              '# Ledger\n\n'
              'Each story keeps its USER_STORY.md under its `FEATURE.md`.\n',
        });

        for (final name in [
          'prds/features/f01_login/us01_email_login/USER_STORY.md',
          'prds/features/f01_login/us02_reset_password/USER_STORY.md',
          featureDoc,
        ]) {
          expect(
            answerRefs(mentions, name).text,
            endsWith('Mentions\n- none\nUntyped mentions\n- none\n'),
            reason: name,
          );
        }
      },
    );
    test('f01/us07/fr01: a path from the mentioning doc, the docs root, or the project root, or a tail one doc alone ends in, names that doc', () async {
      final mentions = await indexWith({
        'docs/superpowers/ledger.md':
            '# Ledger\n\n'
            'From here: ../prds/features/f01_login/us01_email_login/USER_STORY.md.\n'
            'From the docs root: prds/features/f01_login/us01_email_login/USER_STORY.md.\n'
            'From the project: `docs/prds/features/f01_login/us01_email_login/USER_STORY.md`.\n'
            'A tail: us01_email_login/USER_STORY.md.\n'
            'Another story: us02_reset_password/USER_STORY.md.\n',
        'docs/prds/features/f01_login/us01_email_login/notes.md':
            '# Notes\n\nRead USER_STORY.md first.\n',
      });

      expect(
        answerRefs(
          mentions,
          'prds/features/f01_login/us01_email_login/USER_STORY.md',
        ).text,
        endsWith(
          'Untyped mentions\n'
          '- prds/features/f01_login/us01_email_login/notes.md:3\n'
          '- superpowers/ledger.md:3\n'
          '- superpowers/ledger.md:4\n'
          '- superpowers/ledger.md:5\n'
          '- superpowers/ledger.md:6\n',
        ),
      );
      expect(
        answerRefs(
          mentions,
          'prds/features/f01_login/us02_reset_password/USER_STORY.md',
        ).text,
        endsWith('Untyped mentions\n- superpowers/ledger.md:7\n'),
      );
    });
    group('in untyped docs', () {
      final typedAndUntyped = {
        'docs/prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md':
            '# Send a reset link\n\n'
            '## Statement\nThe system shall mail a link, as `../us01_email_login/USER_STORY.md` signs in.\n',
        'docs/superpowers/plans/plan.md': '# Plan\n\nEdit `docs/prds/features/f01_login/us01_email_login/USER_STORY.md`.\n',
      };

      test('f01/us07/fr01: lists_untyped_doc_mentions_apart_when_typed_and_untyped_docs_mention_the_doc', () async {
        final mentions = await indexWith(typedAndUntyped);

        final text = answerRefs(mentions, 'login/email_login').text;

        expect(
          text,
          endsWith(
            'Mentions\n'
            '- prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md:4\n'
            'Untyped mentions\n'
            '- superpowers/plans/plan.md:3\n',
          ),
        );
      });
      test(
        'f01/us07/fr01: json_holds_untyped_doc_mentions_under_untypedMentions',
        () async {
          final mentions = await indexWith(typedAndUntyped);

          final doc =
              (answerRefs(mentions, 'login/email_login').json['docs']! as List)
                      .single
                  as Map;

          expect(doc['mentions'], [
            {
              'path': 'prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md',
              'line': 4,
            },
          ]);
          expect(doc['untypedMentions'], [
            {'path': 'superpowers/plans/plan.md', 'line': 3},
          ]);
        },
      );
      test('f01/us07/fr01/e10: prints_untyped_mentions_none_when_only_typed_docs_mention_the_doc', () async {
        final mentions = await indexWith({
          'docs/prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md':
              typedAndUntyped['docs/prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md']!,
        });

        final answer = answerRefs(mentions, 'login/email_login');

        expect(answer.text, endsWith('Untyped mentions\n- none\n'));
        expect(
          ((answer.json['docs']! as List).single as Map)['untypedMentions'],
          isEmpty,
        );
      });
    });
    test(
      'f01/us07/fr01: a longer path names the deepest doc it matches',
      () async {
        final mentions = await indexWith({
          index: '# Spec map\n\nThe old index.\n',
          'docs/INDEX.md': '# Top map\n\nThe top index.\n',
          'docs/notes.md':
              '# Notes\n\n'
              'See docs/specs/INDEX.md.\n'
              'See docs/INDEX.md.\n',
        });
        expect(
          answerRefs(mentions, 'INDEX.md').text,
          endsWith('Untyped mentions\n- notes.md:4\n'),
        );
        expect(
          answerRefs(mentions, 'specs/INDEX.md').text,
          endsWith('Untyped mentions\n- notes.md:3\n'),
        );
      },
    );
  });
  test('f01/us07/fr01: refs user_story:shop/cart/add_item lists the API that links it', () async {
    final nested = await nestedIndexWith();
    final text = answerRefs(nested, 'user_story:shop/cart/add_item').text;
    expect(text, contains('Inbound\n- link: shop (api)'));
    expect(text, contains(cartAdd));
  });
}
