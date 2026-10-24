// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

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
        '- login (error)\n',
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
      '- login/reset_password (user_story)',
      '- login/reset_password/send_reset_link (fr)',
      '- login (api)',
      '- login (architecture)',
    ]);
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
    expect(text, contains('---\nstatus: planned\ndraft: true\n'));
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
}
