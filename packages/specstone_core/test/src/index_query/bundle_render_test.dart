// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/prd_core.dart';

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith());
  ReadAnswer ctxIn(
    DocIndex i,
    String t,
    BundleMode m, {
    bool noProject = false,
    int? budget,
  }) => answerContext(
    i,
    pickBundle(i, t, m, noProject: noProject),
    label: t,
    byCode: false,
    budget: budget,
  );
  ReadAnswer ctx(
    String t,
    BundleMode m, {
    bool noProject = false,
    int? budget,
  }) => ctxIn(index, t, m, noProject: noProject, budget: budget);
  String shown(ReadAnswer a) =>
      a.text.substring(0, a.text.indexOf('\n==> bundle: '));
  const story = 'docs/prds/features/f01_login/us01_email_login';

  test('f01/us05/s1, f01/us05/fr02, s03/inv15: implement order and the closing doc list', () async {
    final a = ctx('login/email_login', BundleMode.implement);
    expect(
      a.text,
      endsWith(
        '==> bundle: 12 docs, ${tokenSizeOf(shown(a))} tokens <==\n- gnfr (gnfr)\n'
        '- project (project)\n- tech_stack (tech_stack)\n- login (feature)\n- login/email_login (user_story)\n'
        '- login/email_login/validate_credentials (fr)\n- login/email_login/lock_after_failures (fr)\n'
        '- login/email_login/login_latency (nf)\n- login (api)\n- login (architecture)\n- login (domain)\n'
        '- login (error)\n- password_rules (reference) · summary · cited\n'
        'Read a summary doc whole with: specstone context <name> --for implement\n',
      ),
    );
    expect(a.json.keys.toList(), ['target', 'for', 'tokens', 'docs']);
    expect(a.json['tokens'], tokenSizeOf(shown(a)));
  });
  test('f01/us05/s2, s03/inv15: design walks each story with its FRs and nfs, spec docs last', () async {
    final list = ctx(
      'login/email_login',
      BundleMode.design,
    ).text.split('==> bundle: ').last.split('\n').skip(1);
    expect(list.skip(3).take(9), [
      '- login (feature)',
      '- login/email_login (user_story)',
      '- login/email_login/validate_credentials (fr)',
      '- login/email_login/lock_after_failures (fr)',
      '- login/email_login/login_latency (nf)',
      '- login/reset_password (user_story) · summary',
      '- login/reset_password/send_reset_link (fr) · summary',
      '- login (api)',
      '- login (architecture)',
    ]);
  });
  test('f01/us05/s2, f01/us05/fr02, s03/inv25, db-r1: a sibling prints marked, title and summary sections only', () {
    final a = ctx('login/email_login', BundleMode.design);
    expect(
      a.text,
      contains(
        '==> login/reset_password (user_story) · prds/features/f01_login/us02_reset_password/USER_STORY.md · summary <==\n'
        '# Agent resets a password\n\n## Use Case\nReset it.\n',
      ),
    );
    expect(
      a.text,
      contains(
        '==> login/reset_password/send_reset_link (fr) · prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md · summary <==\n'
        '# Send a reset link\n\n## Statement\nThe system shall mail a link.\n',
      ),
    );
    expect(
      a.text,
      isNot(contains('slug:\n  - reset\n---\n\n# Agent resets a password')),
    );
    expect(
      a.text,
      endsWith(
        '- login/reset_password (user_story) · summary\n'
        '- login/reset_password/send_reset_link (fr) · summary\n- login (api)\n- login (architecture)\n'
        '- login (domain)\n- login (error)\n- password_rules (reference) · summary · cited\n'
        'Read a summary doc whole with: specstone context <name> --for implement\n',
      ),
    );
    final docs = (a.json['docs']! as List).cast<Map<String, Object?>>();
    expect(
      [
        for (final d in docs)
          if (d['summary'] == true) d['name'],
      ],
      [
        'login/reset_password',
        'login/reset_password/send_reset_link',
        'password_rules',
      ],
    );
  });
  test('f01/us05/fr02/e09: a summary section still holding its starter text leaves banner and title', () async {
    final useCase = sectionOf(
      prdCoreDocType(await resolvePrdCore(), 'user_story'),
      'use_case',
    ).template!;
    final i = await indexWith({
      'docs/prds/features/f01_login/us03_sign_up_later/USER_STORY.md':
          '# Agent signs up later\n\n## Use Case\n$useCase\n\n## Acceptance Criteria\n- Given a guest\n',
    });
    expect(
      ctxIn(i, 'login/email_login', BundleMode.design).text,
      contains(
        '==> login/sign_up_later (user_story) · prds/features/f01_login/us03_sign_up_later/USER_STORY.md · summary <==\n'
        '# Agent signs up later\n\n==> ',
      ),
    );
  });
  test('f01/us05/fr02/e10, db-c6: a doc type whose layer turns every summary section off prints banner and title', () async {
    final i = await indexWith({
      '.specstone/templates/fr.yaml':
          'sections: [{id: statement, summary: false}]\n',
    });
    expect(
      ctxIn(i, 'login/email_login', BundleMode.design).text,
      contains(
        '==> login/reset_password/send_reset_link (fr) · prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md · summary <==\n'
        '# Send a reset link\n\n==> ',
      ),
    );
  });
  test('f01/us05/fr02/e11: a feature with one story prints no summary doc and no next-step line', () {
    final a = ctx('signup/create_account', BundleMode.design);
    expect(a.text, isNot(contains('· summary')));
    expect(a.text, isNot(contains('Read a summary doc whole')));
  });
  test('f01/us05/fr03/e08, db-r1: over budget, a summary doc is listed marked at its printed size', () {
    final whole = ctx('login', BundleMode.design);
    final a = ctx('login/email_login', BundleMode.design, budget: 1);
    final printed =
        (ctx('login/email_login', BundleMode.design).json['docs']! as List)
                .cast<Map<String, Object?>>()
                .firstWhere(
                  (d) => d['name'] == 'login/reset_password',
                )['tokens']!
            as int;
    final full =
        (whole.json['docs']! as List).cast<Map<String, Object?>>().firstWhere(
              (d) => d['name'] == 'login/reset_password',
            )['tokens']!
            as int;
    expect(a.exitStatus, 1);
    expect(
      a.text,
      contains(
        '- login/reset_password (user_story) · summary · $printed tokens\n',
      ),
    );
    expect(printed, lessThan(full));
    final overBudgetDoc = (a.json['docs']! as List)
        .cast<Map<String, Object?>>()
        .firstWhere((d) => d['name'] == 'login/reset_password');
    expect(overBudgetDoc.keys.last, 'summary');
    expect(overBudgetDoc['summary'], true);
  });
  test('s03/inv25, db-c9: a doc a bundle: join adds prints whole, once', () async {
    final i = await indexWith({
      '.specstone/templates/fr.yaml': 'bundle: [design]\n',
    });
    final a = ctxIn(i, 'login/email_login', BundleMode.design);
    const banner =
        '==> login/reset_password/send_reset_link (fr) · prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md <==';
    expect(RegExp(RegExp.escape(banner)).allMatches(a.text), hasLength(1));
    expect(
      a.text,
      isNot(
        contains(
          'send_reset_link (fr) · prds/features/f01_login/us02_reset_password/fr01_send_reset_link.md · summary',
        ),
      ),
    );
  });
  test('f01/us05/s3, f01/us05/fr02/e05: query prints query sections with no frontmatter, then the map', () async {
    final a = ctx('login', BundleMode.query);
    expect(
      shown(a),
      startsWith(
        '==> project (project) · prds/PROJECT.md <==\n## Role\n'
        '- `Owner` — the solo builder who owns the docs.\n\n## Out-of-scope\n- Billing — not planned\n\n'
        '## Domain glossary\n- **Doc** — one markdown file under the docs root\n\n'
        '==> login (feature) · prds/features/f01_login/FEATURE.md <==\n## Problem\n'
        'Users sign in with an email and a password.\n\n## Out-of-scope\n- Social sign-in — not planned\n\n'
        '==> map: login (feature) <==\n- login (feature) · ',
      ),
    );
    expect(a.text, contains('\n  - login/email_login (user_story) · '));
    expect(a.text, contains('==> bundle: 2 docs, '));
  });
  test('f01/us05/s4, f01/us05/fr02/e01, f01/us05/fr02/e03, f01/us05/fr02/e05, f01/us05/fr02/e07: scaffolding and N/A go, every other line stays', () async {
    final text = ctx('login/email_login', BundleMode.implement).text;
    expect(text, isNot(contains('## Tier-2 decisions')));
    expect(text, isNot(contains('<!-- fill in later -->')));
    expect(
      text,
      contains('## Edge cases\n\n1. E01 — A wrong password → refused.'),
    );
    expect(text, isNot(contains('## Rationale')));
    expect(text, isNot(contains('## Performance')));
    expect(text, contains('## Security\n- Store no password in plain text.'));
    expect(text, contains('---\ndraft: true\ngoals:\n'));
  });
  group('comments in code', () {
    const feature = 'docs/prds/features/f01_login/FEATURE.md';
    Future<String> featureWith(String problem) async {
      final i = await indexWith({
        feature:
            '${loginProject[feature]!.split('## Problem').first}'
            '## Problem\n$problem\n',
      });
      return ctxIn(i, 'login/email_login', BundleMode.implement).text;
    }

    test('E03: a comment inside an inline code span stays', () async {
      const line =
          'A block opens with `<!-- BEGIN specstone v1 -->` and closes '
          'with `<!-- END specstone -->`.';
      expect(await featureWith(line), contains('## Problem\n$line'));
    });

    test('E03: a comment inside a fenced code block stays', () async {
      const fenced =
          '```\n<!-- BEGIN specstone v1 -->\nbody\n<!-- END -->\n```';
      expect(await featureWith('Shown:\n$fenced'), contains(fenced));
    });

    test('E03: a comment outside code drops beside a kept span', () async {
      final text = await featureWith(
        'Keep `<!-- kept -->` and drop <!-- dropped --> here.',
      );
      expect(text, contains('Keep `<!-- kept -->` and drop  here.'));
    });

    test('E03: a comment holding a lone backtick still drops', () async {
      final text = await featureWith('a <!-- it`s --> b `c`');

      expect(text, contains('## Problem\na  b `c`'));
      expect(text, isNot(contains('it`s')));
    });

    test('E03: a comment holding a backtick pair still drops', () async {
      final text = await featureWith('<!-- a ` --> b ` c');

      expect(text, isNot(contains('-->')));
      expect(text, contains('## Problem\n b ` c'));
    });

    test('E03: a comment holding a fenced block still drops', () async {
      final text = await featureWith('Before\n<!-- x\n```\ny\n```\n-->\nAfter');

      expect(text, contains('## Problem\nBefore\n\nAfter'));
      expect(text, isNot(contains('```')));
    });

    test('E03: a comment block over several lines drops whole', () async {
      final text = await featureWith('Before\n<!-- one\ntwo\nthree -->\nAfter');
      expect(text, contains('## Problem\nBefore\n\nAfter'));
      expect(text, isNot(contains('two')));
    });

    test(
      'E03: a body of only a comment and starter text stays starter text',
      () async {
        const template =
            'We believe <outcome> will be achieved if <persona> attains '
            '<benefit> with <feature>.';
        final i = await indexWith({
          feature:
              '${loginProject[feature]}\n## Benefit hypothesis\n'
              '<!-- note -->\n$template\n',
        });
        expect(
          ctxIn(i, 'login/email_login', BundleMode.implement).text,
          isNot(contains('## Benefit hypothesis')),
        );
      },
    );
  });
  test('f01/us05/fr02/e02, f01/us05/fr02/e04: template text drops a section; a changed word or a later N/A keeps it', () async {
    const feature = 'docs/prds/features/f01_login/FEATURE.md';
    const template =
        'We believe <outcome> will be achieved if <persona> attains <benefit> with <feature>.';
    final asTemplate = await indexWith({
      feature:
          '${loginProject[feature]}\n## Benefit hypothesis\n$template\n\n'
          '## Success measures\nSign-in time halves; N/A for batch jobs.\n',
    });
    final dropped = ctxIn(
      asTemplate,
      'login/email_login',
      BundleMode.implement,
    ).text;
    expect(dropped, isNot(contains('## Benefit hypothesis')));
    expect(
      dropped,
      contains('## Success measures\nSign-in time halves; N/A for batch jobs.'),
    );
    final oneWord = await indexWith({
      feature:
          '${loginProject[feature]}\n## Benefit hypothesis\n'
          '${template.replaceFirst('We believe', 'We expect')}\n',
    });
    expect(
      ctxIn(oneWord, 'login/email_login', BundleMode.implement).text,
      contains('## Benefit hypothesis\nWe expect'),
    );
  });
  test('f01/us05/fr02/e06, s03/inv15: sections print in template order and the file stays as it is', () async {
    const domain = 'docs/specs/f01_login/DOMAIN.md';
    const outOfOrder =
        '# Login domain\n\n## Invariants\n- one\n\n## Entities\n- Account\n';
    final project = await writeLoginProject(extra: {domain: outOfOrder});
    final session = openSession(project);
    addTearDown(session.close);
    final text = ctxIn(
      session.index,
      'login/email_login',
      BundleMode.implement,
    ).text;
    expect(
      text.indexOf('## Entities'),
      lessThan(text.indexOf('## Invariants')),
    );
    expect(File('${project.path}/$domain').readAsStringSync(), outOfOrder);
  });
  test('f01/us05/s8, f01/us05/fr02/e08: --no-project leaves joined docs out of the text, the list, and the size', () async {
    final a = ctx('login/email_login', BundleMode.implement, noProject: true);
    expect(a.text, isNot(contains('==> project (project)')));
    expect(
      a.text,
      contains('==> bundle: 9 docs, ${tokenSizeOf(shown(a))} tokens <=='),
    );
  });
  test('f01/us05/fr02: a feature target for implement prints its story names after the docs', () async {
    final a = ctx('feature:login', BundleMode.implement);
    expect(
      shown(a),
      contains(
        '==> names: login (feature) <==\n- login/email_login (user_story) · ',
      ),
    );
    expect((a.json['names']! as List).length, 2);
  });
  test('f01/us05/fr02, s03/inv9: each docs[].tokens is the size of its printed block, and the total is the size of all that prints', () async {
    final a = ctx('login/email_login', BundleMode.implement);
    final parts = shown(a).split('\n\n==> ');
    final blocks = [parts.first, for (final part in parts.skip(1)) '==> $part'];
    final docs = a.json['docs']! as List<Object?>;
    expect(docs, hasLength(blocks.length));
    expect(
      [for (final d in docs) (d! as Map)['tokens']],
      [for (final b in blocks) tokenSizeOf(b)],
    );
    final lock = docs.cast<Map<String, Object?>>().singleWhere(
      (d) => d['name'] == 'login/email_login/lock_after_failures',
    );
    final wholeFile = index
        .resolve('login/email_login/lock_after_failures')
        .single
        .tokens;
    expect(lock['tokens'], isNot(wholeFile));
    final sum = [for (final d in docs) (d! as Map)['tokens']! as int]
        .fold(0, (x, y) => x + y);
    expect(a.json['tokens'], tokenSizeOf(shown(a)));
    expect(sum, lessThanOrEqualTo(a.json['tokens']! as int));
  });
  test('review focus 5: a CRLF doc trims its N/A section as on LF', () async {
    final crlf = await indexWith({
      '$story/fr03_crlf.md':
          '# C\r\n\r\n## Statement\r\nx\r\n\r\n## Rationale\r\nN/A\r\n',
    });
    final text = ctxIn(crlf, 'login/email_login', BundleMode.implement).text;
    final block = text.substring(
      text.indexOf('==> login/email_login/crlf (fr)'),
    );
    expect(block, contains('## Statement'));
    expect(
      block.substring(0, block.indexOf('\n==> ')),
      isNot(contains('## Rationale')),
    );
  });
  group('appended parts', () {
    const fr =
        'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
    const specs = '../../../../specs';
    const inv14 = '[INV-14]($specs/f02_signup/DOMAIN.md#invariants)';
    Future<DocIndex> citing(String statement) => indexWith({
      'docs/prds/features/f01_login/us01_email_login/USER_STORY.md':
          '# Agent signs in with email\n\n## Use Case\nSign in.\n',
      fr: '# Validate credentials\n\n## Statement\n$statement\n',
      'docs/specs/f02_signup/DOMAIN.md':
          '# Sign-up domain\n\n## Invariants\n- **INV-13** One email.\n'
          '- **INV-14** Locks after five failures; see [purpose](../topics/rules.md#purpose).\n'
          '  - **Enforcer:** the lock service\n- **INV-15** Mails the owner.\n',
      'docs/specs/topics/rules.md': '# Rules\n\n## Purpose\nHold the rules.\n',
      'docs/specs/topics/terms.md': '# Terms\n\n## Purpose\nName things.\n\n## Examples\n### A note\nShort.\n',
    });
    ReadAnswer implement(DocIndex i, {int? budget}) => ctxIn(
      i,
      'login/email_login/validate_credentials',
      BundleMode.implement,
      budget: budget,
    );

    test('an item part prints after the picked docs, named, with its own lines, and closes the list', () async {
      final a = implement(await citing('Lock, by $inv14.'));
      expect(
        a.text,
        contains(
          '==> signup (domain) · specs/f02_signup/DOMAIN.md#invariants · item INV-14 · cited <==\n'
          '- **INV-14** Locks after five failures; see [purpose](../topics/rules.md#purpose).\n'
          '  - **Enforcer:** the lock service\n\n'
          '==> rules (topic) · specs/topics/rules.md#purpose · cited <==\n## Purpose\nHold the rules.\n'
          '==> bundle: ',
        ),
      );
      expect(
        a.text.indexOf('· cited <=='),
        greaterThan(a.text.indexOf('==> login (error)')),
      );
      expect(
        a.text,
        endsWith(
          '- login (error)\n- signup (domain) · cited invariants [INV-14]\n'
          '- rules (topic) · cited purpose\n',
        ),
      );
      expect(a.text, isNot(contains('INV-13')));
      expect(a.json['tokens'], tokenSizeOf(shown(a)));
    });
    test('a part reached only through another part prints after every part the picked docs reach', () async {
      final a = implement(
        await citing(
          'Lock, by $inv14; see [terms]($specs/topics/terms.md#purpose).',
        ),
      );
      final parts = RegExp(
        r'^==> (\S+) \S+ · (\S+) .*· cited <==$',
        multiLine: true,
      ).allMatches(a.text).map((m) => m[2]).toList();
      expect(parts, [
        'specs/f02_signup/DOMAIN.md#invariants',
        'specs/topics/terms.md#purpose',
        'specs/topics/rules.md#purpose',
      ]);
    });
    test('a doc part prints marked summary and cited, and the list names it with the next step', () async {
      final a = implement(await citing('See [terms]($specs/topics/terms.md).'));
      expect(
        a.text,
        contains(
          '==> terms (topic) · specs/topics/terms.md · summary · cited <==\n# Terms\n==> bundle: ',
        ),
      );
      expect(
        a.text,
        endsWith(
          '- terms (topic) · summary · cited\n'
          'Read a summary doc whole with: specstone context <name> --for implement\n',
        ),
      );
    });
    test('a bundle with no part prints no cited naming line and no cited list line', () async {
      final a = implement(await citing('Check the password.'));
      expect(a.text, isNot(contains(' · cited')));
      expect(
        (a.json['docs']! as List).cast<Map<String, Object?>>().where(
          (d) => d.containsKey('cited'),
        ),
        isEmpty,
      );
    });
    test('under --json each part is a docs object with cited, section, and item after text', () async {
      final a = implement(await citing('Lock, by $inv14.'));
      final docs = (a.json['docs']! as List).cast<Map<String, Object?>>();
      final item = docs.firstWhere((d) => d['cited'] == true);
      expect(item.keys.toList(), [
        'name',
        'docType',
        'path',
        'tokens',
        'text',
        'cited',
        'section',
        'item',
      ]);
      expect(item['name'], 'signup');
      expect(item['path'], 'specs/f02_signup/DOMAIN.md');
      expect(item['section'], 'invariants');
      expect(item['item'], 'INV-14');
      expect(
        item['text'],
        '- **INV-14** Locks after five failures; see [purpose](../topics/rules.md#purpose).\n'
        '  - **Enforcer:** the lock service',
      );
      final section = docs.last;
      expect(section['section'], 'purpose');
      expect(section.containsKey('item'), isFalse);
      final summary =
          (implement(await citing('See [terms]($specs/topics/terms.md).'))
                      .json['docs']!
                  as List)
              .cast<Map<String, Object?>>()
              .last;
      expect(summary.keys.skip(5).toList(), ['summary', 'cited']);
    });
    test('parts that take a bundle over the budget refuse it', () async {
      final a = implement(await citing('Lock, by $inv14.'));
      final docsOnly = tokenSizeOf(
        a.text.substring(0, a.text.indexOf('\n\n==> signup (domain)')),
      );
      final over = implement(
        await citing('Lock, by $inv14.'),
        budget: docsOnly,
      );
      expect(over.exitStatus, 1);
      expect(
        over.text,
        contains('- signup (domain) · cited invariants [INV-14] · '),
      );
      final listed = (over.json['docs']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((d) => d['cited'] == true);
      expect(listed.keys.toList(), [
        'name',
        'docType',
        'path',
        'tokens',
        'cited',
        'section',
        'item',
      ]);
    });
    test('a query bundle appends no part', () async {
      final a = ctxIn(
        await citing('Lock, by $inv14.'),
        'login',
        BundleMode.query,
      );
      expect(a.text, isNot(contains(' · cited')));
    });
    test('a link to an untyped doc prints its path alone, listed, and under --json a path with no text', () async {
      final a = implement(
        await citing('See [the old context](../../../d01_context.md).'),
      );
      expect(
        a.text,
        contains(
          '\n\n==> prds/d01_context.md · cited <==\n==> bundle: 11 docs, ',
        ),
      );
      expect(
        a.text,
        endsWith('- login (error)\n- prds/d01_context.md · cited\n'),
      );
      expect(a.json['tokens'], tokenSizeOf(shown(a)));
      final path = (a.json['docs']! as List).cast<Map<String, Object?>>().last;
      expect(path, {
        'path': 'prds/d01_context.md',
        'tokens': tokenSizeOf('==> prds/d01_context.md · cited <=='),
        'cited': true,
      });
    });
    test('a link to a file that is no .md doc prints its path alone, listed, and under --json a path with no text', () async {
      final a = implement(
        await citing('See [the schema]($specs/schema.dbml).'),
      );
      expect(
        a.text,
        contains(
          '\n\n==> specs/schema.dbml · cited <==\n==> bundle: 11 docs, ',
        ),
      );
      expect(
        a.text,
        endsWith('- login (error)\n- specs/schema.dbml · cited\n'),
      );
      expect(a.json['tokens'], tokenSizeOf(shown(a)));
      expect((a.json['docs']! as List).last, {
        'path': 'specs/schema.dbml',
        'tokens': tokenSizeOf('==> specs/schema.dbml · cited <=='),
        'cited': true,
      });
    });
    test('a ### block that starts no item names its anchor; --json gives its section and heading', () async {
      final a = implement(
        await citing('See [a note]($specs/topics/terms.md#a-note).'),
      );
      expect(
        a.text,
        contains(
          '==> terms (topic) · specs/topics/terms.md#a-note · cited <==\n### A note\nShort.\n',
        ),
      );
      expect(a.text, endsWith('- terms (topic) · cited examples\n'));
      final block = (a.json['docs']! as List).cast<Map<String, Object?>>().last;
      expect(block.keys.skip(5).toList(), ['cited', 'section', 'heading']);
      expect(block['section'], 'examples');
      expect(block['heading'], 'a-note');
    });
  });
  group('cited by', () {
    const specs = '../../../../specs';
    const fr =
        'docs/prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
    const frName = 'login/email_login/validate_credentials';
    const inv14 = '[INV-14]($specs/f02_signup/DOMAIN.md#invariants)';
    const e01 = '1. E01 — A wrong password → refused, by $inv14.';
    const guideLine =
        'See [E02](../../prds/features/f01_login/us01_email_login/fr01_validate_credentials.md#edge-cases).';
    String frWith(String statement) =>
        '---\nverify_method: test\n---\n\n# Validate credentials\n\n'
        '## Statement\n$statement\n\n## Edge cases\n<!-- fill in later -->\n'
        '$e01\n2. E02 — A locked account → refused.\n';
    Future<DocIndex> citedIndex([
      String statement = 'The system shall check the email.',
      Map<String, String> extra = const {},
    ]) => indexWith({
      fr: frWith(statement),
      'docs/specs/f02_signup/DOMAIN.md':
          '# Sign-up domain\n\n## Invariants\n- **INV-13** One email.\n'
          '- **INV-14** Locks after five failures.\n',
      'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\n$guideLine\n',
      ...extra,
    });
    ReadAnswer design(DocIndex i, {int? budget}) => ctxIn(
      i,
      'login/email_login/validate_credentials',
      BundleMode.design,
      budget: budget,
    );
    List<Map<String, Object?>> docsOf(ReadAnswer a) =>
        (a.json['docs']! as List).cast<Map<String, Object?>>();

    test('a picked item prints its cited-by line right after it, past a removed comment', () async {
      final a = design(await citedIndex());
      expect(
        a.text,
        contains(
          '## Edge cases\n\n$e01\n2. E02 — A locked account → refused.\n'
          '  · cited by guide (topic) —: $guideLine\n',
        ),
      );
      expect(a.json['tokens'], tokenSizeOf(shown(a)));
    });
    test(
      'an appended item prints its cited-by line, with the citing item',
      () async {
        final a = design(await citedIndex());
        expect(
          a.text,
          contains(
            '==> signup (domain) · specs/f02_signup/DOMAIN.md#invariants · item INV-14 · cited <==\n'
            '- **INV-14** Locks after five failures.\n'
            '  · cited by $frName (fr) E01: $e01\n',
          ),
        );
      },
    );
    test(
      'an implement or query bundle prints no cited-by line and no citedBy key',
      () async {
        final i = await citedIndex();
        for (final mode in [BundleMode.implement, BundleMode.query]) {
          final a = ctxIn(i, 'login/email_login/validate_credentials', mode);
          expect(a.text, isNot(contains('cited by')), reason: mode.wire);
          expect(
            docsOf(a).where((d) => d.containsKey('citedBy')),
            isEmpty,
            reason: mode.wire,
          );
        }
      },
    );
    test(
      'an item of a doc that joins through bundle: prints no cited-by line',
      () async {
        final a = design(
          await citedIndex(
            'Cites [PV-01](../../../PROJECT.md#project-vision).',
            {
              'docs/prds/PROJECT.md': '---\nowner: Owner\n---\n\n# Project context\n\n## Project vision\n### PV-01 — One system\nText.\n',
            },
          ),
        );
        expect(a.text, contains('### PV-01 — One system'));
        expect(a.text, isNot(contains('PV-01 — One system\nText.\n  · cited')));
        expect(a.text, isNot(contains('cited by $frName (fr) —: Cites')));
      },
    );
    test('under --json a doc object gains citedBy, one object per line, after its other keys', () async {
      final a = design(await citedIndex());
      final docs = docsOf(a);
      final picked = docs.firstWhere((d) => d['name'] == frName);
      expect(picked.keys.toList(), [
        'name',
        'docType',
        'path',
        'tokens',
        'text',
        'citedBy',
      ]);
      expect(picked['citedBy'], [
        {
          'item': 'E02',
          'name': 'guide',
          'docType': 'topic',
          'byItem': null,
          'line': guideLine,
        },
      ]);
      final part = docs.firstWhere((d) => d['item'] == 'INV-14');
      expect(part.keys.last, 'citedBy');
      expect(part['citedBy'], [
        {
          'item': 'INV-14',
          'name': frName,
          'docType': 'fr',
          'byItem': 'E01',
          'line': e01,
        },
      ]);
      final feature = docs.firstWhere(
        (d) => d['name'] == 'login' && d['docType'] == 'feature',
      );
      expect(feature['citedBy'], isEmpty);
      expect(
        docs.where((d) => !d.containsKey('citedBy')),
        isEmpty,
        reason: 'each doc object of a design bundle carries citedBy',
      );
    });
    test('a nested item that ends on its cited parent last line keeps its line in the text', () async {
      final a = design(
        await citedIndex('Lock, by $inv14.', {
          'docs/specs/f02_signup/DOMAIN.md':
              '# Sign-up domain\n\n## Invariants\n- **INV-13** One email.\n'
              '- **INV-14** Locks after five failures.\n'
              '  - **INV-15** Mails its owner.\n',
          'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\nSee [INV-14](../f02_signup/DOMAIN.md#invariants) and [INV-15](../f02_signup/DOMAIN.md#invariants).\n',
        }),
      );
      final text = a.text;
      expect(
        text,
        contains(
          '  - **INV-15** Mails its owner.\n  · cited by guide (topic) —: See [INV-14]',
        ),
      );
      expect(
        RegExp('  · cited by guide').allMatches(text).length,
        2,
        reason: 'one line for INV-14 and one for INV-15',
      );
      final part = docsOf(a).firstWhere((d) => d['item'] == 'INV-14');
      expect(part['citedBy']! as List, hasLength(4));
    });
    test(
      'a summary doc prints its whole-printed items with their cited-by lines',
      () async {
        final a = design(
          await citedIndex(
            'Resets, by [BR-1](../us02_reset_password/USER_STORY.md#rules).',
            {
              'docs/prds/features/f01_login/us02_reset_password/USER_STORY.md': '---\nslug:\n  - reset\n---\n\n# Agent resets a password\n\n## Use Case\nReset it.\n\n## Rules\n- **BR-1** Links expire.\n',
            },
          ),
        );
        expect(
          a.text,
          contains(
            '## Rules\n- **BR-1** Links expire.\n'
            '  · cited by $frName (fr) —: Resets, by [BR-1]',
          ),
        );
        final summary = docsOf(a).firstWhere(
          (d) => d['summary'] == true && d['name'] == 'login/reset_password',
        );
        expect(
          (summary['citedBy']! as List).single,
          containsPair('item', 'BR-1'),
        );
      },
    );
    test('an appended summary doc part prints its items with their cited-by lines', () async {
      final a = design(
        await citedIndex(
          'See [sign-up](../../f02_signup/us01_create_account/USER_STORY.md).',
          {
            'docs/prds/features/f02_signup/us01_create_account/USER_STORY.md': '---\nslug:\n  - signup\n---\n\n# Agent creates an account\n\n## Use Case\nCreate one.\n\n## Rules\n- **BR-1** One email.\n',
            'docs/specs/topics/guide.md': '# Guide\n\n## Purpose\nSee [BR-1](../../prds/features/f02_signup/us01_create_account/USER_STORY.md#rules).\n',
          },
        ),
      );
      expect(
        a.text,
        contains(
          '· summary · cited <==\n# Agent creates an account\n\n## Use Case\nCreate one.\n\n## Rules\n- **BR-1** One email.\n'
          '  · cited by guide (topic) —: See [BR-1]',
        ),
      );
    });
    test('the lines count toward the budget', () async {
      final i = await citedIndex();
      final tokens = design(i).json['tokens']! as int;
      expect(design(i, budget: tokens).exitStatus, 0);
      expect(design(i, budget: tokens - 1).exitStatus, 1);
    });
  });
  group('budget', () {
    test('f01/us05/s5, f01/us05/fr03, f01/us05/fr03/e01, f01/us05/fr03/e03: over budget prints sizes and the next step, no doc text, exit 1', () async {
      final tokens =
          ctx('login/email_login', BundleMode.implement).json['tokens']! as int;
      final a = ctx(
        'login/email_login',
        BundleMode.implement,
        budget: tokens - 1,
      );
      expect(a.exitStatus, 1);
      expect(
        a.text,
        startsWith(
          'The bundle holds $tokens est. tokens, over the budget of ${tokens - 1}; no doc text is printed.\n'
          'Docs it would hold:\n- gnfr (gnfr) · ',
        ),
      );
      expect(
        a.text,
        endsWith(
          'Next step: narrow the target, or run it again with --out and no --budget.\n',
        ),
      );
      expect(a.text, isNot(contains('## Statement')));
    });
    test('a bundle whose size equals the budget prints whole', () async {
      final tokens =
          ctx('login/email_login', BundleMode.implement).json['tokens']! as int;
      final a = ctx('login/email_login', BundleMode.implement, budget: tokens);
      expect(a.exitStatus, 0);
      expect(a.text, contains('## Statement'));
    });
    test('query bundles meet the same budget rule', () async {
      expect(ctx('login', BundleMode.query, budget: 1).exitStatus, 1);
    });
    test('with --no-project the budget counts only what prints', () async {
      final narrow =
          ctx(
                'login/email_login',
                BundleMode.implement,
                noProject: true,
              ).json['tokens']!
              as int;
      expect(
        ctx(
          'login/email_login',
          BundleMode.implement,
          noProject: true,
          budget: narrow,
        ).exitStatus,
        0,
      );
      expect(
        ctx(
          'login/email_login',
          BundleMode.implement,
          budget: narrow,
        ).exitStatus,
        1,
      );
    });
    test('over budget under --json', () async {
      final json = ctx(
        'login/email_login',
        BundleMode.implement,
        budget: 1,
      ).json;
      expect(json.keys.toList(), [
        'target',
        'for',
        'budget',
        'tokens',
        'overBudget',
        'docs',
        'next',
      ]);
      expect(json['overBudget'], isTrue);
      expect(
        json['next'],
        'narrow the target, or run it again with --out and no --budget',
      );
      expect(
        ((json['docs']! as List).first as Map).containsKey('text'),
        isFalse,
      );
    });
    test('over budget with --summary, the next step keeps --summary on the --out call', () {
      const next =
          'narrow the target, or run it again with --summary --out and no --budget';
      final answer = answerContext(
        index,
        pickBundle(
          index,
          'login',
          BundleMode.design,
          noProject: false,
          summary: true,
        ),
        label: 'login',
        byCode: false,
        budget: 1,
      );
      expect(answer.exitStatus, 1);
      expect(answer.text, endsWith('Next step: $next.\n'));
      expect(answer.json['next'], next);
    });
    test('a --budget that is not a positive integer is argument_invalid', () {
      for (final v in ['0', '-5', '5k']) {
        expect(
          () => parsePositiveOption('--budget', v),
          throwsA(
            isA<IndexFault>().having(
              (x) => x.message,
              'message',
              '--budget takes a positive integer, not $v',
            ),
          ),
        );
      }
    });
  });

  group('feature pattern parts', () {
    const feature = 'docs/prds/features/f01_login/FEATURE.md';
    const partHead = '==> sign_in_checks (feature pattern) · login <==\n';
    const partText =
        '${partHead}Sign-in checklist.\n'
        '- **lockout** Name the lockout rule.\n'
        'Pattern sources:\n- Handbook: https://example.com/handbook\n';
    Future<DocIndex> patterned({
      String patterns = '[sign_in_checks, link_notes]',
    }) => indexWith({
      '.specstone/templates/feature.yaml':
          'fields:\n  - id: patterns\n    type: string\n    list: true\n',
      feature:
          '---\nvision:\n  - PV-01\npatterns: $patterns\n---\n\n# Login\n\n## Problem\nUsers sign in.\n',
      '.specstone/templates/patterns/sign_in_checks.yaml':
          'id: sign_in_checks\ndescription: Sign-in checklist.\nitems:\n'
          '  - id: lockout\n    text: Name the lockout rule.\n'
          'reference:\n  - title: Handbook\n    url: https://example.com/handbook\n',
      '.specstone/templates/patterns/link_notes.yaml':
          'id: link_notes\ndescription: Notes.\nitems:\n'
          '  - id: see\n    text: See [components](../../specs/f02_signup/ARCHITECTURE.md#components).\n',
    });
    ContextAnswer designOf(
      DocIndex i, {
      String target = 'login/email_login',
      BundleMode mode = BundleMode.design,
      bool noProject = false,
      bool summary = false,
      int? budget,
    }) => answerContext(
      i,
      pickBundle(i, target, mode, noProject: noProject, summary: summary),
      label: target,
      byCode: false,
      budget: budget,
    );

    test('the part prints right after its doc, before the next doc, and lists in the closing list', () async {
      final a = designOf(await patterned());

      expect(
        a.text,
        contains('$partText\n==> link_notes (feature pattern) · login <==\n'),
      );
      final feature = a.text.indexOf('==> login (feature) · ');
      final story = a.text.indexOf('==> login/email_login (user_story) · ');
      expect(a.text.indexOf(partHead), inInclusiveRange(feature, story));
      expect(
        a.text,
        contains(
          '- login (feature)\n- sign_in_checks (feature pattern)\n- link_notes (feature pattern)\n- login/email_login (user_story)\n',
        ),
      );
      final plain = designOf(await indexWith());
      expect(
        RegExp(r'==> bundle: (\d+) docs').firstMatch(a.text)!.group(1),
        RegExp(r'==> bundle: (\d+) docs').firstMatch(plain.text)!.group(1),
      );
    });
    test('e05: --no-project and --summary keep the parts', () async {
      final i = await patterned();

      expect(designOf(i, noProject: true).text, contains(partText));
      expect(
        designOf(i, target: 'login', summary: true).text,
        contains(partText),
      );
    });
    test('e06: the parts count toward the size, and an over-budget reply lists each with its size', () async {
      final i = await patterned();
      final whole = designOf(i);
      final without = designOf(await indexWith());

      expect(whole.tokens, greaterThan(without.tokens));
      expect(designOf(i, budget: whole.tokens).exitStatus, 0);
      final over = designOf(i, budget: whole.tokens - 1);
      expect(over.exitStatus, 1);
      expect(
        over.text,
        matches(RegExp(r'- sign_in_checks \(feature pattern\) · \d+ tokens\n')),
      );
      final listed = (over.json['featurePatterns']! as List)
          .cast<Map<String, Object?>>();
      expect(
        [for (final p in listed) p['id']],
        ['sign_in_checks', 'link_notes'],
      );
      expect(listed.first['doc'], 'feature:login');
      expect(listed.first['tokens'], isA<int>());
      expect(listed.first.containsKey('items'), isFalse);
    });
    test(
      'e08: a link in a part adds no appended part and no cited-by line',
      () async {
        final a = designOf(await patterned());

        expect(a.text, isNot(contains('==> signup (architecture)')));
        expect(a.text, isNot(contains('==> signup/')));
        final block = a.text.substring(
          a.text.indexOf('==> link_notes (feature pattern)'),
          a.text.indexOf('==> login/email_login (user_story)'),
        );
        expect(block, isNot(contains('cited by')));
        expect(block.trimRight().split('\n').length, 3);
      },
    );
    test('e09: an implement or query bundle prints no part and its JSON no featurePatterns key', () async {
      final i = await patterned();
      for (final mode in [BundleMode.implement, BundleMode.query]) {
        final a = designOf(i, mode: mode);

        expect(a.text, isNot(contains('(feature pattern)')), reason: mode.wire);
        expect(
          a.json.containsKey('featurePatterns'),
          isFalse,
          reason: mode.wire,
        );
      }
    });
    test(
      'e10: a design bundle where no part joins carries featurePatterns: []',
      () async {
        final none = designOf(await indexWith());
        final unknown = designOf(await patterned(patterns: '[nothing]'));

        expect(none.json['featurePatterns'], isEmpty);
        expect(unknown.json['featurePatterns'], isEmpty);
        expect(none.json.containsKey('featurePatterns'), isTrue);
      },
    );
    test('the design JSON carries one entry per part: id, typed doc, description, printed items, reference', () async {
      final a = designOf(await patterned());

      expect((a.json['featurePatterns']! as List).first, {
        'id': 'sign_in_checks',
        'doc': 'feature:login',
        'description': 'Sign-in checklist.',
        'items': [
          {'id': 'lockout', 'text': 'Name the lockout rule.'},
        ],
        'reference': [
          {'title': 'Handbook', 'url': 'https://example.com/handbook'},
        ],
      });
      expect(
        (a.json['docs']! as List).any(
          (d) => (d as Map)['name'] == 'sign_in_checks',
        ),
        isFalse,
      );
    });
    test('the entry of a part names its lister doc and pattern id and spans the part', () async {
      final a = designOf(await patterned());

      final part = a.entries.firstWhere(
        (e) => e.featurePattern == 'sign_in_checks',
      );
      final lines = a.text.split('\n');
      expect(part.doc.name, 'login');
      expect(part.cited, isFalse);
      expect(part.summary, isFalse);
      expect(lines[part.first - 1], partHead.trimRight());
      expect(
        lines.sublist(part.first - 1, part.last).join('\n'),
        partText.trimRight(),
      );
      expect(
        a.entries.where((e) => e.featurePattern == null).length,
        a.entries.length - 2,
      );
    });
  });
}
