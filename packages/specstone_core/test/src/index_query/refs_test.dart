// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/refs.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_doc_fixture.dart';

const _journeyDoc = 'docs/prds/journeys/sign_in/JOURNEY.md';

/// The login record path, the one doc type that holds `covers`.
const _recordPath = '.specstone/records/f01_login/IMPLEMENTATION.md';

/// The login record with [covers] as its one `covers` entry.
Map<String, String> _record([String covers = 'app/lib/src/login/']) => {
  _recordPath: '---\ncovers:\n  - $covers\n---\n\n# Login implementation\n',
};

String _journey(List<String> stepLines) =>
    '# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n'
    '${stepLines.join('\n')}\n';

Future<DocIndex> _withJourney(List<String> stepLines) =>
    indexWith({_journeyDoc: _journey(stepLines)});

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith());

  test(
    "a story's outbound doc_ref, link, and pointer, and its inbound link",
    () async {
      expect(
        answerRefs(index, 'login/email_login').text,
        '==> login/email_login (user_story) · prds/features/f01_login/us01_email_login/USER_STORY.md <==\n'
        'Outbound\n- persona: buyer (persona)\n- link: password_rules (reference)\n'
        'Inbound\n- link: login/email_login/validate_credentials (fr)\n'
        'Mentions\n- none\nUntyped mentions\n- none\n',
      );
    },
  );
  test("a doc_ref targets its field's doc types only, and shows inbound on the target", () async {
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
    'depends_on is '
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

  test('a traced_from '
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
  test('a story of another feature is listed, one that resolves to no story is not', () async {
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
  });
  test(
    'a repeated depends_on value prints one outbound and one inbound line',
    () async {
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
    },
  );
  test(
    'a depends_on '
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
  test(
    'one doc in depends_on and reference prints one line per field',
    () async {
      final both = await indexWith({
        'docs/prds/features/f02_signup/FEATURE.md': '---\nstatus: planned\ndepends_on:\n  - login\nreference:\n  - login\n---\n\n# Sign up\n\n## Problem\nNew users.\n',
      });
      final text = answerRefs(both, 'feature:signup').text;
      expect(text, contains('- depends_on: login (feature)\n'));
      expect(text, contains('- reference: login (feature)\n'));
    },
  );
  test('an empty depends_on '
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
  test('pointers are outbound only; an empty group prints - none', () async {
    expect(
      answerRefs(await indexWith(_record()), 'implementation:login').text,
      '==> login (implementation) · $_recordPath <==\nOutbound\n- covers: app/lib/src/login/\nInbound\n- none\nMentions\n- none\nUntyped mentions\n- none\n',
    );
  });
  test('a name or an ID in text is no reference', () async {
    final mentions = await indexWith({
      'docs/notes.md': '# Notes\n\nSee login/email_login and PG-01.\n',
    });
    expect(
      answerRefs(mentions, 'login/email_login').text,
      isNot(contains('notes.md')),
    );
  });
  test('broken, external, and non-md links are left out', () async {
    final links = await indexWith({
      'docs/notes.md': '# Notes\n\n[gone](missing.md) [web](https://x.org) [schema](specs/schema.dbml)\n',
    });
    expect(
      answerRefs(links, 'notes.md').text,
      '==> notes.md · notes.md <==\nOutbound\n- none\nInbound\n- none\nMentions\n- none\nUntyped mentions\n- none\n',
    );
  });
  test('a shared name gives each doc its own group', () async {
    expect('==> '.allMatches(answerRefs(index, 'login').text), hasLength(4));
  });
  test('a name no doc carries is doc_not_found', () async {
    expect(() => answerRefs(index, 'logn'), throwsA(isA<IndexFault>()));
  });
  test('--json gives kind and either name and docType or pointer', () async {
    final doc =
        (answerRefs(index, 'login/email_login').json['docs']! as List).single
            as Map;
    expect(doc['outbound'], [
      {'kind': 'persona', 'name': 'buyer', 'docType': 'persona'},
      {'kind': 'link', 'name': 'password_rules', 'docType': 'reference'},
    ]);
    expect(doc['inbound'], [
      {
        'kind': 'link',
        'name': 'login/email_login/validate_credentials',
        'docType': 'fr',
      },
    ]);
    final record =
        (answerRefs(
                      await indexWith(_record()),
                      'implementation:login',
                    ).json['docs']!
                    as List)
                .single
            as Map;
    expect(record['outbound'], [
      {'kind': 'covers', 'pointer': 'app/lib/src/login/'},
    ]);
  });
  test(
    'steps 3 and 3x naming one story give one outbound and one inbound step',
    () async {
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
    },
  );
  test('refs feature:login has no step line', () async {
    final withJourney = await _withJourney([
      '### 1. Enter details',
      'step: login/email_login S1',
    ]);
    expect(
      answerRefs(withJourney, 'feature:login').text,
      isNot(contains('step')),
    );
  });
  test('a step naming no story is not listed', () async {
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
  test('a step naming a missing scenario of a story is listed', () async {
    final withJourney = await _withJourney([
      '### 1. Enter details',
      'step: login/email_login S9',
    ]);
    expect(
      answerRefs(withJourney, 'journey:sign_in').text,
      contains('- step: login/email_login (user_story)\n'),
    );
  });
  test('the groups print doc_ref, link, step, then implements and covers', () async {
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

    test('a backticked file name and a bare DocPath are listed with their line; fenced code and a linking line are not', () async {
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
    test('--json lists each mention by path and line', () async {
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
    test('a path or a link to a doc of the same file name elsewhere is no mention; nor is a bare shared file name', () async {
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
    test('a bare file name several docs carry names none of them', () async {
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
    });
    test('a path from the mentioning doc, the docs root, or the project root, or a tail one doc alone ends in, names that doc', () async {
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

      test('lists_untyped_doc_mentions_apart_when_typed_and_untyped_docs_mention_the_doc', () async {
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
      test('json_holds_untyped_doc_mentions_under_untypedMentions', () async {
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
      });
      test('prints_untyped_mentions_none_when_only_typed_docs_mention_the_doc', () async {
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
    test('a longer path names the deepest doc it matches', () async {
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
    });
  });
  test('a doc that '
      'writes the name in plain words is no mention, and one that writes it '
      'in a code span is a mention, never a reference', () async {
    final mentions = await indexWith({
      'docs/specs/f01_login/notes_plain.md':
          '# Plain\n\nSee login/email_login in words.\n',
      'docs/specs/f01_login/notes_code.md':
          '# Code\n\nSee `login/email_login` and `login`.\n',
      'docs/prds/personas/buyer/PERSONA.md':
          '# Buyer\n\n## Profile\nUses `feature:login` daily.\n',
    });
    expect(
      answerRefs(mentions, 'login/email_login').text,
      endsWith(
        'Mentions\n- none\nUntyped mentions\n- specs/f01_login/notes_code.md:3\n',
      ),
    );
    final feature = answerRefs(mentions, 'feature:login');
    expect(
      feature.text,
      contains('Mentions\n- prds/personas/buyer/PERSONA.md:4\n'),
    );
    final json = feature.json['docs']! as List;
    expect((json.single as Map)['mentions'], [
      {'path': 'prds/personas/buyer/PERSONA.md', 'line': 4},
    ]);
  });
  test('a mermaid node naming the doc is listed at its line, and a fenced '
      'block of another language is not', () async {
    final mentions = await indexWith({
      'docs/prds/personas/buyer/PERSONA.md':
          '# Buyer\n\n## Profile\n```mermaid\nflowchart LR\n'
          '  N[login/email_login E06]\n```\n\n'
          '```text\nN[login/email_login E06]\n```\n',
    });
    final answer = answerRefs(mentions, 'login/email_login');
    expect(
      answer.text,
      contains('Mentions\n- prds/personas/buyer/PERSONA.md:6\n'),
    );
    final json = answer.json['docs']! as List;
    expect((json.single as Map)['mentions'], [
      {'path': 'prds/personas/buyer/PERSONA.md', 'line': 6},
    ]);
  });
  test('a longer code span naming the doc is left out', () async {
    final mentions = await indexWith({
      'docs/prds/personas/buyer/PERSONA.md':
          '# Buyer\n\n## Profile\nUses `login/email_login E06` daily.\n',
    });
    expect(
      answerRefs(mentions, 'login/email_login').text,
      contains('Mentions\n- none\n'),
    );
  });
  test(
    'refs user_story:shop/cart/add_item lists the API that links it',
    () async {
      final nested = await nestedIndexWith();
      final text = answerRefs(nested, 'user_story:shop/cart/add_item').text;
      expect(text, contains('Inbound\n- link: shop (api)'));
      expect(text, contains(cartAdd));
    },
  );

  group('record code paths, two targets', () {
    const recordType =
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

    Future<DocIndex> twoTargets() => indexWith({
      '.specstone/templates/implementation.yaml': recordType,
      '.specstone/config.yaml':
          '${shippedPinsConfig()}targets:\n'
          '  flutter:\n    code_root: flutter_lib\n'
          '  jaspr:\n    code_root: jaspr_lib\n',
      'flutter_lib/.keep': '',
      'jaspr_lib/.keep': '',
      'docs/specs/flutter/f01_login/IMPLEMENTATION.md':
          '---\nstatuses:\n  - email_login:implemented\n'
          'implements:\n'
          '  - email_login:lib/sign_in_page.dart:SignInPage\n'
          '  - email_login/validate_credentials:lib/validator.dart\n---\n\n'
          '# Record\n',
      'docs/specs/jaspr/f01_login/IMPLEMENTATION.md':
          '---\nstatuses:\n  - email_login:planned\n'
          'implements:\n  - email_login:lib/web_page.dart\n---\n\n# Record\n',
    });

    test('a record lists each entry code path outbound as written, kind implements, no item beside it', () async {
      final twin = await twoTargets();

      final answer = answerRefs(
        twin,
        'specs/flutter/f01_login/IMPLEMENTATION.md',
      );

      expect(
        answer.text,
        contains(
          'Outbound\n'
          '- implements: lib/sign_in_page.dart:SignInPage\n'
          '- implements: lib/validator.dart\n'
          'Inbound\n',
        ),
      );
      final doc = (answer.json['docs']! as List).single as Map;
      expect(doc['outbound'], [
        {'kind': 'implements', 'pointer': 'lib/sign_in_page.dart:SignInPage'},
        {'kind': 'implements', 'pointer': 'lib/validator.dart'},
      ]);
    });

    test('a record lists its code paths in its implements line order, whatever its statuses order', () async {
      final shuffled = await indexWith({
        '.specstone/templates/implementation.yaml': recordType,
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n'
            '  flutter:\n    code_root: flutter_lib\n'
            '  jaspr:\n    code_root: jaspr_lib\n',
        'flutter_lib/.keep': '',
        'jaspr_lib/.keep': '',
        'docs/specs/flutter/f01_login/IMPLEMENTATION.md':
            '---\nstatuses:\n'
            '  - reset_password:implemented\n'
            '  - email_login:implemented\n'
            'implements:\n'
            '  - email_login:lib/first.dart\n'
            '  - reset_password:lib/second.dart\n'
            '  - email_login:lib/third.dart\n---\n\n# Record\n',
      });

      final doc =
          (answerRefs(
                        shuffled,
                        'specs/flutter/f01_login/IMPLEMENTATION.md',
                      ).json['docs']!
                      as List)
                  .single
              as Map;

      expect(doc['outbound'], [
        {'kind': 'implements', 'pointer': 'lib/first.dart'},
        {'kind': 'implements', 'pointer': 'lib/second.dart'},
        {'kind': 'implements', 'pointer': 'lib/third.dart'},
      ]);
    });

    test('a record with no code path prints - none outbound', () async {
      final bare = await indexWith({
        '.specstone/templates/implementation.yaml': recordType,
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n'
            '  flutter:\n    code_root: flutter_lib\n',
        'flutter_lib/.keep': '',
        'docs/specs/flutter/f01_login/IMPLEMENTATION.md':
            '---\nstatuses:\n  - email_login:planned\n---\n\n# Record\n',
      });

      expect(
        answerRefs(bare, 'specs/flutter/f01_login/IMPLEMENTATION.md').text,
        contains('Outbound\n- none\nInbound\n'),
      );
    });

    test('a record has no inbound pointer from the code it names', () async {
      final twin = await twoTargets();

      expect(
        answerRefs(twin, 'specs/jaspr/f01_login/IMPLEMENTATION.md').text,
        contains(
          'Outbound\n- implements: lib/web_page.dart\nInbound\n- none\n',
        ),
      );
    });

    test('a record lists each tests line outbound with the kind tests, the name aside', () async {
      final withTests = await indexWith({
        '.specstone/templates/implementation.yaml': recordType,
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n'
            '  flutter:\n    code_root: flutter_lib\n'
            '  jaspr:\n    code_root: jaspr_lib\n',
        'flutter_lib/.keep': '',
        'jaspr_lib/.keep': '',
        'docs/specs/flutter/f01_login/IMPLEMENTATION.md':
            '---\nstatuses:\n  - email_login:implemented\n'
            'implements:\n'
            '  - email_login:lib/sign_in_page.dart:SignInPage\n'
            'tests:\n'
            '  - email_login:lib/sign_in_page_test.dart\n'
            '  - "email_login:lib/web_page_test.dart:locks: after 5 #1"\n'
            '---\n\n# Record\n',
        'docs/specs/jaspr/f01_login/IMPLEMENTATION.md':
            '---\nstatuses:\n  - email_login:planned\n---\n\n# Record\n',
      });

      final answer = answerRefs(
        withTests,
        'specs/flutter/f01_login/IMPLEMENTATION.md',
      );

      expect(
        answer.text,
        contains(
          'Outbound\n'
          '- implements: lib/sign_in_page.dart:SignInPage\n'
          '- tests: lib/sign_in_page_test.dart\n'
          '- tests: lib/web_page_test.dart\n'
          'Inbound\n- none\n',
        ),
      );
      final doc = (answer.json['docs']! as List).single as Map;
      expect(doc['outbound'], [
        {'kind': 'implements', 'pointer': 'lib/sign_in_page.dart:SignInPage'},
        {'kind': 'tests', 'pointer': 'lib/sign_in_page_test.dart'},
        {'kind': 'tests', 'pointer': 'lib/web_page_test.dart'},
      ]);
    });

    test(
      'a record that declares a tests field prints each tests line once',
      () async {
        final declared = await indexWith({
          '.specstone/templates/implementation.yaml':
              '$recordType'
              '  - id: tests\n'
              '    type: output_ref\n'
              '    list: true\n'
              '    pointer: item_test\n',
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_lib\n'
              '  jaspr:\n    code_root: jaspr_lib\n',
          'flutter_lib/.keep': '',
          'jaspr_lib/.keep': '',
          'docs/specs/flutter/f01_login/IMPLEMENTATION.md':
              '---\nstatuses:\n  - email_login:implemented\n'
              'tests:\n  - email_login:lib/a_test.dart:locks\n'
              '---\n\n# Record\n',
        });

        expect(
          answerRefs(
            declared,
            'specs/flutter/f01_login/IMPLEMENTATION.md',
          ).text,
          contains('Outbound\n- tests: lib/a_test.dart\nInbound\n'),
        );
      },
    );

    test(
      'a record with no tests line prints none beside its implements lines',
      () async {
        final twin = await twoTargets();

        expect(
          answerRefs(twin, 'specs/jaspr/f01_login/IMPLEMENTATION.md').text,
          contains('- implements: lib/web_page.dart\n'),
        );
        expect(
          answerRefs(twin, 'specs/jaspr/f01_login/IMPLEMENTATION.md').text,
          isNot(contains('tests')),
        );
      },
    );

    test(
      'a name two records share groups each, and a code target keeps one',
      () async {
        final twin = await twoTargets();

        final both = answerRefs(twin, 'implementation:login').text;
        final jaspr = answerRefs(
          twin,
          'implementation:login',
          codeTarget: 'jaspr',
        ).text;

        expect('==> '.allMatches(both), hasLength(2));
        expect(
          both,
          contains('- implements: lib/sign_in_page.dart:SignInPage\n'),
        );
        expect('==> '.allMatches(jaspr), hasLength(1));
        expect(jaspr, contains('- implements: lib/web_page.dart\n'));
        expect(jaspr, isNot(contains('sign_in_page')));
      },
    );

    test(
      'a code target the config does not hold is argument_invalid',
      () async {
        final twin = await twoTargets();

        expect(
          () => answerRefs(twin, 'implementation:login', codeTarget: 'web'),
          throwsA(
            isA<IndexFault>().having(
              (f) => f.code,
              'code',
              IndexFaultCode.argumentInvalid,
            ),
          ),
        );
      },
    );

    test(
      'journey-step references print as before beside a record doc type',
      () async {
        final twin = await indexWith({
          '.specstone/templates/implementation.yaml': recordType,
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_lib\n',
          'flutter_lib/.keep': '',
          _journeyDoc: _journey([
            '### 1. Enter details',
            'step: login/email_login S1',
          ]),
        });

        expect(
          answerRefs(twin, 'journey:sign_in').text,
          contains(
            'Outbound\n- step: login/email_login (user_story)\nInbound\n',
          ),
        );
      },
    );
  });

  test('a code pointer stays outbound as written, and a mention in a code file is no inbound pointer', () async {
    final withCode = await indexWith({
      ..._record(),
      'app/lib/src/login/sign_in_page.dart':
          '/// Lays out `login/email_login`.\nclass SignInPage {}\n',
    });
    expect(
      answerRefs(withCode, 'implementation:login').text,
      contains('- covers: app/lib/src/login/\n'),
    );
    expect(
      answerRefs(withCode, 'login/email_login').text,
      contains('Mentions\n- none\nUntyped mentions\n- none\n'),
    );
  });

  test(
    'a covers entry lists the pointer alone, without the fingerprint',
    () async {
      const fingerprint = '0123456789ab';
      final recorded = await indexWith(
        _record('app/lib/src/login/ $fingerprint'),
      );

      final text = answerRefs(recorded, 'implementation:login').text;

      expect(text, contains('- covers: app/lib/src/login/\n'));
      expect(text, isNot(contains(fingerprint)));
    },
  );

  test('a record lists each covers entry outbound as covers, in written order, fingerprint dropped', () async {
    const fingerprint = '0123456789ab';
    final recorded = await indexWith({
      'app/lib/src/signup/form.dart': '',
      _recordPath:
          '---\ncovers:\n'
          '  - app/lib/src/login/ $fingerprint\n'
          '  - app/lib/src/signup/form.dart\n'
          '---\n\n# Login implementation\n',
    });

    final answer = answerRefs(recorded, 'implementation:login');

    expect(
      answer.text,
      '==> login (implementation) · $_recordPath <==\n'
      'Outbound\n'
      '- covers: app/lib/src/login/\n'
      '- covers: app/lib/src/signup/form.dart\n'
      'Inbound\n- none\nMentions\n- none\nUntyped mentions\n- none\n',
    );
    final doc = (answer.json['docs']! as List).single as Map;
    expect(doc['outbound'], [
      {'kind': 'covers', 'pointer': 'app/lib/src/login/'},
      {'kind': 'covers', 'pointer': 'app/lib/src/signup/form.dart'},
    ]);
    expect(doc['inbound'], isEmpty);
  });
  test('a root: project covers entry lists its path from the project root, '
      'without the fingerprint', () async {
    const fingerprint = '5d1e0c4b7a92';
    final session = openSession(
      await writeLoginProject(
        extra: {
          '.specstone/config.yaml': skillPinsConfig(),
          ...skillDocFile(['$skillFile $fingerprint']),
        },
      ),
    );
    addTearDown(session.close);

    final text = answerRefs(session.index, 'skill:review').text;

    expect(text, contains('- covers: $skillFile\n'));
    expect(text, isNot(contains(fingerprint)));
  });

  test(
    'an implements line lists the pointer alone, without the fingerprint',
    () async {
      const fingerprint = '0123456789ab';
      final recorded = await indexWith({
        '.specstone/templates/implementation.yaml':
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
            '    pointer: item_exact\n',
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n'
            '  flutter:\n    code_root: flutter_lib\n'
            '  jaspr:\n    code_root: jaspr_lib\n',
        'flutter_lib/.keep': '',
        'jaspr_lib/.keep': '',
        'docs/specs/flutter/f01_login/IMPLEMENTATION.md':
            '---\nstatuses:\n  - email_login:implemented\n'
            'implements:\n'
            '  - email_login:lib/sign_in_page.dart:SignInPage $fingerprint\n'
            '---\n\n# Record\n',
      });

      final text = answerRefs(
        recorded,
        'specs/flutter/f01_login/IMPLEMENTATION.md',
      ).text;

      expect(
        text,
        contains('- implements: lib/sign_in_page.dart:SignInPage\n'),
      );
      expect(text, isNot(contains(fingerprint)));
    },
  );

  group('record matrix rows', () {
    const recordPath = '.specstone/records/f01_login/IMPLEMENTATION.md';
    const item = 'email_login/validate_credentials';
    const front =
        "---\nstatuses:\n  - '$item:implemented'\n"
        "implements:\n  - '$item:app/lib/src/login/credential_validator.dart'\n"
        "tests:\n  - '$item:app/test/credential_validator_test.dart'\n---\n\n"
        '# Login implementation\n\n';

    Future<DocIndex> recordWith(String body) =>
        indexWith({recordPath: '$front$body'});

    Map<Object?, Object?> recordOf(DocIndex index) =>
        (answerRefs(index, 'implementation:login').json['docs']! as List).single
            as Map<Object?, Object?>;

    test('lists a matrix row as an outbound verifies line', () async {
      final recorded = await recordWith(
        '## Verification matrix\n\n'
        '- $item E02: `refuses a wrong password`\n'
        '- $item E03 skipped: needs a clock\n',
      );

      final answer = answerRefs(recorded, 'implementation:login');

      expect(
        answer.text,
        contains(
          'Outbound\n'
          '- implements: app/lib/src/login/credential_validator.dart\n'
          '- tests: app/test/credential_validator_test.dart\n'
          '- verifies: $item E02: `refuses a wrong password`\n'
          '- verifies: $item E03 skipped: needs a clock\n'
          'Inbound\n',
        ),
      );
      expect(recordOf(recorded)['outbound'], [
        {
          'kind': 'implements',
          'pointer': 'app/lib/src/login/credential_validator.dart',
        },
        {'kind': 'tests', 'pointer': 'app/test/credential_validator_test.dart'},
        {
          'kind': 'verifies',
          'pointer': '$item E02: `refuses a wrong password`',
        },
        {'kind': 'verifies', 'pointer': '$item E03 skipped: needs a clock'},
      ]);
    });

    test('adds no inbound line to the FR a row names', () async {
      final recorded = await recordWith(
        '## Verification matrix\n\n- $item E02: `refuses a wrong password`\n',
      );

      final answer = answerRefs(recorded, 'login/$item');

      expect(answer.text, isNot(contains('verifies')));
      final doc =
          (answer.json['docs']! as List).single as Map<Object?, Object?>;
      expect(
        (doc['inbound']! as List).where(
          (ref) => (ref as Map)['kind'] == 'verifies',
        ),
        isEmpty,
      );
    });

    test('prints a row as written less its fingerprint', () async {
      const fingerprint = '5d1e0c4b7a92';
      final stamped = await recordWith(
        '## Verification matrix\n\n'
        '- $item E02: `refuses a wrong password` $fingerprint\n'
        '- $item E03 skipped: needs a clock $fingerprint\n',
      );
      final bare = await recordWith(
        '## Verification matrix\n\n'
        '- $item E02: `refuses a wrong password`\n'
        '- $item E03 skipped: needs a clock\n',
      );

      final text = answerRefs(stamped, 'implementation:login').text;

      expect(text, isNot(contains(fingerprint)));
      expect(text, answerRefs(bare, 'implementation:login').text);
    });

    test(
      'prints a per-FR row as one verifies line less its fingerprint',
      () async {
        const fingerprint = '5d1e0c4b7a92';
        const written =
            '$item: `refuses a wrong password`, `refuses no password`';
        final stamped = await recordWith(
          '## Verification matrix\n\n- $written $fingerprint\n',
        );

        final answer = answerRefs(stamped, 'implementation:login');

        expect(answer.text, contains('- verifies: $written\n'));
        expect(answer.text, isNot(contains(fingerprint)));
        final verifies = [
          for (final ref in recordOf(stamped)['outbound']! as List)
            if ((ref as Map)['kind'] == 'verifies') ref['pointer'],
        ];
        expect(verifies, [written]);
      },
    );

    test(
      'prints a code span as written, whatever its fence and padding',
      () async {
        const spans = [
          '`` refuses `x` ``',
          '``refuses a wrong password``',
          '`  padded  `',
        ];
        final recorded = await recordWith(
          '## Verification matrix\n\n'
          '- $item E02: ${spans[0]} 5d1e0c4b7a92\n'
          '- $item E03: ${spans[1]} 5d1e0c4b7a92\n'
          '- $item E04: ${spans[2]}\n',
        );

        final verifies = [
          for (final ref in recordOf(recorded)['outbound']! as List)
            if ((ref as Map)['kind'] == 'verifies') ref['pointer'],
        ];

        expect(verifies, [
          '$item E02: ${spans[0]}',
          '$item E03: ${spans[1]}',
          '$item E04: ${spans[2]}',
        ]);
      },
    );

    test('lists no line for a malformed matrix line', () async {
      final recorded = await recordWith(
        '## Verification matrix\n\n'
        'stray text\n'
        '- $item E02: `refuses a wrong password`\n',
      );

      final verifies = [
        for (final ref in recordOf(recorded)['outbound']! as List)
          if ((ref as Map)['kind'] == 'verifies') ref['pointer'],
      ];

      expect(verifies, ['$item E02: `refuses a wrong password`']);
    });

    for (final (label, body) in [
      ('holds no matrix section', '## Notes\n\nNothing here.\n'),
      ('holds an empty matrix section', '## Verification matrix\n'),
    ]) {
      test('lists no verifies line for a record that $label', () async {
        final recorded = await recordWith(body);

        expect(
          answerRefs(recorded, 'implementation:login').text,
          isNot(contains('verifies')),
        );
        expect(
          recordOf(recorded)['outbound'],
          isNot(contains(containsPair('kind', 'verifies'))),
        );
      });
    }
  });

  group('references and mentions of one doc', () {
    const buyer = 'docs/prds/personas/buyer/PERSONA.md';
    const buyerPath = 'prds/personas/buyer/PERSONA.md';
    const specsIndex = 'docs/specs/INDEX.md';

    test("a doc's body link to its story is an outbound link and the story's inbound link", () async {
      final story = answerRefs(index, 'login/email_login').text;
      expect(story, contains('Inbound\n- link: $frName (fr)\n'));
      final fr = answerRefs(index, frName).text;
      expect(
        fr,
        contains('Outbound\n- link: login/email_login (user_story)\nInbound\n'),
      );
    });

    test('a vision or goal ID cited in a doc is no reference and no mention of the doc that states it', () async {
      final cited = await indexWith({
        'docs/prds/PROJECT.md': '# Project context\n\n## Project vision\n\n### PV-01 — One system\n',
        'docs/prds/GOAL.md':
            '# Project goals\n\n## Mid-term goals\n\n### PG-01 — Cost\n\n'
            '- **Serves:** PV-01\n',
        buyer:
            '# Buyer\n\n## Snapshot\nServes PV-01 and `PG-01`, PG-01 again.\n',
      });
      expect(
        answerRefs(cited, 'prds/GOAL.md').text,
        '==> goal (goal) · prds/GOAL.md <==\n'
        'Outbound\n- none\nInbound\n- none\nMentions\n- none\n'
        'Untyped mentions\n- none\n',
      );
      expect(
        answerRefs(cited, 'prds/PROJECT.md').text,
        endsWith(
          'Outbound\n- none\nInbound\n- none\nMentions\n- none\n'
          'Untyped mentions\n- none\n',
        ),
      );
    });

    test('a doc the markdown parser fails on lists no link but keeps its doc_ref and the others link', () async {
      const unparsed = '\n[a]:<b\\';
      final parsed = await indexWith({
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md':
            '${loginProject['docs/prds/features/f01_login/us01_email_login/USER_STORY.md']}$unparsed',
        emailFr: '${loginProject[emailFr.replaceFirst('docs/', '')]}$unparsed',
      });
      final story = answerRefs(parsed, 'login/email_login').text;
      expect(
        story,
        contains('Outbound\n- persona: buyer (persona)\nInbound\n- none\n'),
      );
      expect(
        answerRefs(parsed, 'password_rules').text,
        contains('Inbound\n- none\n'),
      );
      expect(
        answerRefs(parsed, 'persona:buyer').text,
        contains('Inbound\n- persona: login/email_login (user_story)\n'),
      );
    });

    test('a typed doc naming a doc by plain path or in a code span, frontmatter included, lists each line under Mentions', () async {
      final mentions = await indexWith({
        specsIndex: '# Spec map\n\nThe old index.\n',
        buyer:
            '---\nrole: Buyer\npriority: primary\nbasis: specs/INDEX.md\n---\n\n'
            '# Buyer\n\n## Snapshot\nSee specs/INDEX.md in words.\n'
            'Also `specs/INDEX.md` here.\n',
      });
      final answer = answerRefs(mentions, 'specs/INDEX.md');
      expect(
        answer.text,
        contains(
          'Mentions\n- $buyerPath:4\n- $buyerPath:10\n- $buyerPath:11\n'
          'Untyped mentions\n- none\n',
        ),
      );
      expect(
        (answer.json['docs']! as List).single as Map,
        containsPair('mentions', [
          {'path': buyerPath, 'line': 4},
          {'path': buyerPath, 'line': 10},
          {'path': buyerPath, 'line': 11},
        ]),
      );
    });

    test('a path inside fenced code or a link destination is no mention and a linking line gives its inbound link only', () async {
      final mentions = await indexWith({
        specsIndex: '# Spec map\n\nThe old index.\n',
        buyer:
            '# Buyer\n\n## Snapshot\n```text\nspecs/INDEX.md\n```\n'
            'Open [the map](../../../specs/INDEX.md); specs/INDEX.md has it.\n'
            'Also [the copy](specs/INDEX.md), a destination that reaches no doc.\n',
      });
      expect(
        answerRefs(mentions, 'specs/INDEX.md').text,
        '==> specs/INDEX.md · specs/INDEX.md <==\n'
        'Outbound\n- none\nInbound\n- link: buyer (persona)\n'
        'Mentions\n- none\nUntyped mentions\n- none\n',
      );
    });

    test('a path with a folder slash after the file name is no mention while a bare file name one doc carries is', () async {
      final mentions = await indexWith({
        specsIndex: '# Spec map\n\nThe old index.\n',
        buyer:
            '# Buyer\n\n## Snapshot\nSee INDEX.md/ and specs/INDEX.md/ and '
            'OLD_INDEX.md and INDEX.md.bak here.\n'
            'Control: INDEX.md names it.\n',
      });
      expect(
        answerRefs(mentions, 'specs/INDEX.md').text,
        contains('Mentions\n- $buyerPath:5\nUntyped mentions\n- none\n'),
      );
    });

    test('a code span naming a doc is a mention under Mentions and adds no inbound line', () async {
      final mentions = await indexWith({
        buyer: '# Buyer\n\n## Snapshot\nUses `login/reset_password` daily.\n',
      });
      expect(
        answerRefs(mentions, 'login/reset_password').text,
        '==> login/reset_password (user_story) · prds/features/f01_login/us02_reset_password/USER_STORY.md <==\n'
        'Outbound\n- none\nInbound\n- none\n'
        'Mentions\n- $buyerPath:4\nUntyped mentions\n- none\n',
      );
    });
  });
}
