// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/consistency_check/tracked_links.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

void main() {
  const fp = fingerprintOf;
  final edited = loginScenario2.replaceFirst('wrong password', 'wrong pass');

  test('f04/us04/s1, f04/us04/s5, f04/us04/fr01/e01, f04/us04/fr02/e03: approved docs whose entries match are clean', () async {
    expect(checkOf(await writeCheckProject()).findings, isEmpty);
  });

  test('f04/us04/s2, f04/us04/fr01/e02, f04/us01/fr02/e06: an edited scenario makes the FR suspect, naming both '
      'fingerprints and the block, at the one finding level', () async {
    final report = checkOf(
      await writeCheckProject(extra: doc(loginStory, loginScenario2, edited)),
    );
    expect(report.exitStatus, 1);
    final finding = report.findings.single;
    expect(
      finding.textLine,
      '$loginFr:9: suspect: S2 changed after it was confirmed: recorded ${fp(loginScenario2)}, current '
      '${fp(edited)}; read Scenario 2 of $loginStory, then record S2 ${fp(edited)}',
    );
    expect(
      finding.toJson(),
      allOf(
        containsPair('link', 'S2'),
        containsPair('recorded', fp(loginScenario2)),
        containsPair('fingerprint', fp(edited)),
        containsPair('upstream', loginStory),
        containsPair('block', 'Scenario 2'),
      ),
    );
  });

  test('f04/us04/fr01/e03, f04/us04/fr01/e06: an edit to another scenario, a blank line, or CRLF changes nothing', () async {
    final story = checkProjectFiles()['docs/$loginStory']!;
    for (final text in [
      story.replaceFirst('sees the home page', 'sees the start page'),
      '$story\n\n',
      story.replaceAll('\n', '\r\n'),
    ]) {
      expect(
        checkOf(await writeCheckProject(extra: {'docs/$loginStory': text}))
            .findings,
        isEmpty,
      );
    }
  });

  test('f04/us04/fr01/e04: an nf turns suspect on its NFR Statement line, not on its Rationale', () async {
    const statement =
        '- **Statement:** The system shall answer a sign-in within 3 s.';
    final suspect = checkOf(
      await writeCheckProject(
        extra: doc(gnfrDoc, loginNfrStatement, statement),
      ),
    );
    expect(spots(suspect), ['$loginNf:6: suspect']);
    expect(suspect.findings.single.toJson()['block'], 'NFR-P01 Statement');
    final rationale = checkOf(
      await writeCheckProject(
        extra: doc(
          gnfrDoc,
          '- **Rationale:** Users wait.',
          '- **Rationale:** People wait.',
        ),
      ),
    );
    expect(rationale.findings, isEmpty);
  });

  test('f04/us04/s6, f04/us04/fr01/e05: an API spec turns suspect for the one row whose FR Statement changed', () async {
    const lock =
        'prds/features/f01_login/us01_email_login/fr02_lock_account.md';
    const lockStatement =
        'The system shall lock the account after 5 failed sign-ins.';
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/$lock':
              '---\nstatus: planned\ntraced_from:\n  - self-derived\nverify_method: test\n---\n\n'
              '# Lock the account\n\n## Statement\n$lockStatement\n\n## Edge cases\n1. E01 — Five failures → locked.\n\n'
              '## Rationale\nIt stops guessing.\n\n## Verification\nTest: five failures lock it.\n',
          ...edit(loginApi, [
            (
              '---\n\n# Login API',
              '  - email_login/lock_account ${fp(lockStatement)}\n---\n\n# Login API',
            ),
            (
              '| `signIn` |\n',
              '| `signIn` |\n| email_login/lock_account | `lock` |\n',
            ),
          ]),
          ...fr(
            checkPasswordStatement,
            'The system shall refuse a wrong password within 2 s.',
          ),
        },
      ),
    );
    expect(spots(report), ['$loginApi:3: suspect']);
    expect(
      report.findings.single.toJson(),
      allOf(
        containsPair('link', 'email_login/check_password'),
        containsPair('block', 'Statement'),
      ),
    );
  });

  test('f04/us04/fr01/e07, f04/us04/fr01/e08: self-derived and a missing scenario track nothing', () async {
    for (final entry in ['self-derived', 'S9']) {
      final report = checkOf(
        await writeCheckProject(extra: fr('  - S2\n', '  - $entry\n')),
      );
      expect(spots(report, FindingKind.suspect), isEmpty);
      expect(spots(report, FindingKind.unconfirmed), isEmpty);
    }
  });

  test('f04/us04/s3, f04/us04/fr02/e01: a tracked link with no entry is unconfirmed at its trace', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr('confirmed:\n  - S2 ${fp(loginScenario2)}\n', ''),
      ),
    );
    final finding = report.findings.single;
    expect(
      finding.textLine,
      startsWith(
        '$loginFr:3: unconfirmed: S2 has no confirmed entry: current ${fp(loginScenario2)}',
      ),
    );
    expect(finding.toJson().containsKey('recorded'), isFalse);
  });

  test('f04/us04/s4, f04/us04/fr02/e02, f04/us04/fr02/e05, f04/us04/fr02/e07, cc-s03/inv6: a matching entry in a '
      "draft waits for the Owner's approve", () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr(
          'status: implemented\n',
          'status: implemented\ndraft: true\n',
        ),
      ),
    );
    expect(
      report.findings.single.textLine,
      "$loginFr:10: unconfirmed: S2 ${fp(loginScenario2)} is recorded in a draft; it waits for the Owner's approve",
    );
  });

  test('f04/us04/fr02/e04: a draft whose entry records an older fingerprint is unconfirmed, never suspect', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: edit(loginFr, [
          ('status: implemented\n', 'status: implemented\ndraft: true\n'),
          ('  - S2 ${fp(loginScenario2)}', '  - S2 000000000000'),
        ]),
      ),
    );
    expect(spots(report), ['$loginFr:10: unconfirmed']);
    expect(
      report.findings.single.toJson(),
      allOf(
        containsPair('recorded', '000000000000'),
        containsPair('fingerprint', fp(loginScenario2)),
      ),
    );
    expect(
      report.findings.single.textLine,
      contains(
        'S2 is not confirmed: the draft records 000000000000, current ${fp(loginScenario2)}; '
        'read Scenario 2 of $loginStory, then record S2 ${fp(loginScenario2)}',
      ),
    );
  });

  test('cc-s03/inv6, review focus 2: a draft whose scenario is missing gets only the US-03 trace finding', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: edit(loginFr, [
          ('status: implemented\n', 'status: implemented\ndraft: true\n'),
          ('  - S2\n', '  - S9\n'),
        ]),
      ),
    );
    expect(spots(report, FindingKind.scenarioTraceUnresolved), [
      '$loginFr:4: scenario_trace_unresolved',
    ]);
    expect(spots(report, FindingKind.unconfirmed), isEmpty);
    expect(spots(report, FindingKind.suspect), isEmpty);
  });

  test('cc-s03/inv4: an FR without a Statement section and an NFR without a Statement line fingerprint the empty text', () async {
    const empty = 'e3b0c44298fc';
    final nfr = checkOf(
      await writeCheckProject(extra: doc(gnfrDoc, '$loginNfrStatement\n', '')),
    );
    expect(spots(nfr), ['$loginNf:6: suspect']);
    expect(nfr.findings.single.toJson(), containsPair('fingerprint', empty));
    final noStatement = checkOf(
      await writeCheckProject(
        extra: doc(loginFr, '## Statement\n$checkPasswordStatement\n\n', ''),
      ),
    );
    expect(spots(noStatement, FindingKind.suspect), ['$loginApi:3: suspect']);
    expect(
      noStatement.findings
          .firstWhere((f) => f.kind == FindingKind.suspect)
          .toJson(),
      containsPair('fingerprint', empty),
    );
  });

  test(
    'cc-s03/inv5: a repeated scenario number fingerprints its first block',
    () async {
      final second = loginScenario2.replaceFirst('Wrong password', 'Locked');
      final story = checkProjectFiles()['docs/$loginStory']!;
      final session = openSession(
        await writeCheckProject(
          extra: {
            'docs/$loginStory': story.replaceFirst(
              '$loginScenario2\n',
              '$loginScenario2\n\n$second\n',
            ),
          },
        ),
      );
      addTearDown(session.close);
      final context = CheckContext(session);
      final blocks = context.scenarioBlocksOf(session.index.at(loginStory)!);
      expect(blocks['S2'], loginScenario2);
      final links = trackedLinksOf(context, session.index.at(loginFr)!);
      expect(links.single.fingerprint, fp(loginScenario2));
    },
  );

  test('cc-s03/inv6: hasSuspectLink is true for a changed link only', () async {
    for (final (story, suspect) in [(loginScenario2, false), (edited, true)]) {
      final session = openSession(
        await writeCheckProject(extra: doc(loginStory, loginScenario2, story)),
      );
      addTearDown(session.close);
      final context = CheckContext(session);
      expect(hasSuspectLink(context, session.index.at(loginFr)!), suspect);
    }
  });

  test('f04/us04/fr03/e01, f04/us04/fr03/e02, f04/us04/fr03/e03: the map form, uppercase hex, and ten characters are '
      'malformed', () async {
    for (final bad in [
      'S2: 047e817f9707',
      'S2 047E817F9707',
      'S2 047e817f97',
    ]) {
      final report = checkOf(
        await writeCheckProject(
          extra: fr('  - S2 ${fp(loginScenario2)}', '  - $bad'),
        ),
      );
      expect(spots(report, FindingKind.confirmedEntryMalformed), [
        '$loginFr:9: confirmed_entry_malformed',
      ]);
      expect(
        report.findings
            .firstWhere((f) => f.kind == FindingKind.confirmedEntryMalformed)
            .toJson()['entry'],
        bad,
      );
    }
  });

  test('f04/us04/s7, f04/us04/fr03/e04: an entry for a link the doc does not trace is stale, in a draft too', () async {
    for (final draft in ['', 'draft: true\n']) {
      final report = checkOf(
        await writeCheckProject(
          extra: edit(loginFr, [
            ('status: implemented\n', 'status: implemented\n$draft'),
            (
              '  - S2 ${fp(loginScenario2)}\n',
              '  - S2 ${fp(loginScenario2)}\n  - S3 ${fp(loginScenario2)}\n',
            ),
          ]),
        ),
      );
      final line = draft.isEmpty ? 10 : 11;
      expect(spots(report, FindingKind.confirmedEntryStale), [
        '$loginFr:$line: confirmed_entry_stale',
      ]);
      expect(
        report.findings
            .firstWhere((f) => f.kind == FindingKind.confirmedEntryStale)
            .toJson()['link'],
        'S3',
      );
    }
  });

  test(
    'f04/us04/fr03/e05: an add nf tracks no link, so its entry is stale',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: edit(loginNf, [
            ('kind: tighten', 'kind: add'),
            ('overrides: NFR-P01\n', ''),
          ]),
        ),
      );
      expect(spots(report), ['$loginNf:5: confirmed_entry_stale']);
    },
  );

  test('f04/us01/fr06/e07: an untyped doc gets no field, section, banned-word, trace, or suspect rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/prds/notes.md':
              '---\npriority: high\ntraced_from:\n  - S9\nconfirmed:\n  - bad\n---\n\n'
              '## Statement\nThis is fast and easy.\n',
        },
      ),
    );
    expect(spots(report), ['prds/notes.md:1: untyped_doc']);
  });

  test(
    'f04/us04/fr03/e06: an API entry with no FR trace row is stale',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: doc(
            loginApi,
            '---\n\n# Login API',
            '  - email_login/send_otp 5d1e0c4b7a92\n---\n\n# Login API',
          ),
        ),
      );
      expect(spots(report), ['$loginApi:4: confirmed_entry_stale']);
    },
  );

  test('f04/us04, cc-s03/inv2: a project layer that disables confirmed on fr runs no link state rule on an fr', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/fr.yaml':
              'fields:\n  - id: confirmed\n    disabled: true\n',
          ...fr('confirmed:\n  - S2 ${fingerprintFor(loginScenario2)}\n', ''),
        },
      ),
    );
    expect(report.findings, isEmpty);
  });

  test('f04/us04/fr01, cc-s03/inv2: a bare confirmed key counts as absent, not as a malformed entry', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr(
          'confirmed:\n  - S2 ${fingerprintFor(loginScenario2)}\n',
          'confirmed:\n',
        ),
      ),
    );
    expect(spots(report, FindingKind.confirmedEntryMalformed), isEmpty);
    expect(spots(report), ['$loginFr:3: unconfirmed']);
  });

  test('f04/us04/fr01, cc-s03/inv6: a scenario with a fenced example heading keeps its whole block, and the example is no scenario', () async {
    const example = '```\n### Scenario 3 — Example\n- **Given** a sketch\n```';
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(
            loginStory,
            '$loginScenario2\n',
            '$loginScenario2\n\n$example\n',
          ),
          ...edit(loginFr, [
            ('traced_from:\n  - S2\n', 'traced_from:\n  - S2\n  - S3\n'),
            (
              fingerprintFor(loginScenario2),
              fingerprintFor('$loginScenario2\n\n$example'),
            ),
          ]),
        },
      ),
    );
    expect(spots(report), ['$loginFr:3: scenario_trace_unresolved']);
  });

  group('journey step links', () {
    const journeyPath = 'prds/journeys/sign_in/JOURNEY.md';
    const label1 = 'login/email_login#S1';
    const label2 = 'login/email_login#S2';
    const stepOne = '### 1. Open\nstep: login/email_login S1';
    const stepTwo = '### 2. Type\nstep: login/email_login S1';

    String journey(
      List<String> steps, {
      List<String> confirmed = const [],
      bool draft = false,
    }) {
      final entries = confirmed.map((e) => '  - $e\n').join();
      return '---\n'
          '${confirmed.isEmpty ? '' : 'confirmed:\n$entries'}'
          '${draft ? 'draft: true\n' : ''}'
          '---\n\n# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n'
          '## Steps\n${steps.join('\n')}\n';
    }

    Future<CheckReport> check(
      String text, {
      Map<String, String> extra = const {},
    }) async => checkOf(
      await writeCheckProject(extra: {'docs/$journeyPath': text, ...extra}),
      docPath: journeyPath,
    );

    test('f04/us04/s9, f04/us04/fr01/e10: an edit of Scenario 1 makes the journey suspect for that step', () async {
      final newScenario = loginScenario1.replaceFirst(
        'signs in',
        'signs in again',
      );
      final report = await check(
        journey([stepOne], confirmed: ['$label1 ${fp(loginScenario1)}']),
        extra: doc(loginStory, loginScenario1, newScenario),
      );
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.suspect,
      );
      expect(
        finding.toJson(),
        allOf(
          containsPair('link', label1),
          containsPair('upstream', loginStory),
          containsPair('block', 'Scenario 1'),
          containsPair('recorded', fp(loginScenario1)),
          containsPair('fingerprint', fp(newScenario)),
        ),
      );
    });

    test('f04/us04/fr01: a matching entry is clean; no entry is unconfirmed; a draft journey is unconfirmed', () async {
      final clean = await check(
        journey([stepOne], confirmed: ['$label1 ${fp(loginScenario1)}']),
      );
      expect(clean.findings, isEmpty);

      final missing = await check(journey([stepOne]));
      expect(
        missing.findings.single.textLine,
        startsWith(
          '$journeyPath:13: unconfirmed: $label1 has no confirmed entry: current ${fp(loginScenario1)}',
        ),
      );

      final draft = await check(
        journey(
          [stepOne],
          confirmed: ['$label1 ${fp(loginScenario1)}'],
          draft: true,
        ),
      );
      expect(
        draft.findings.single.message,
        "$label1 ${fp(loginScenario1)} is recorded in a draft; it waits for the Owner's approve",
      );
    });

    test('f04/us04/fr01/e09: a journey has no parent, and its step links still run', () async {
      final report = await check(journey([stepOne]));
      expect(spots(report, FindingKind.unconfirmed), hasLength(1));
    });

    test('f04/us04/fr01: two steps naming one scenario track one link and need one entry', () async {
      final entry = ['$label1 ${fp(loginScenario1)}'];
      final report = await check(journey([stepOne, stepTwo], confirmed: entry));
      expect(report.findings, isEmpty);

      final bare = await check(journey([stepOne, stepTwo]));
      expect(spots(bare, FindingKind.unconfirmed), hasLength(1));
    });

    test('f04/us04/fr03/e07: an entry for a scenario no step names is confirmed_entry_stale', () async {
      final report = await check(
        journey(
          [stepOne],
          confirmed: [
            '$label1 ${fp(loginScenario1)}',
            '$label2 ${fp(loginScenario2)}',
          ],
        ),
      );
      final finding = report.findings.single;
      expect(finding.kind, FindingKind.confirmedEntryStale);
      expect(finding.toJson(), containsPair('link', label2));
    });

    test('f04/us04/fr03/e09, f04/us02/fr06/e06: a step whose scenario was deleted keeps its link', () async {
      final report = await check(
        journey(
          ['### 1. Open\nstep: login/email_login S9'],
          confirmed: ['login/email_login#S9 ${fp(loginScenario1)}'],
        ),
      );
      expect(spots(report, FindingKind.confirmedEntryStale), isEmpty);
      expect(spots(report, FindingKind.suspect), isEmpty);
      expect(report.findings.single.kind, FindingKind.journeyStepUnresolved);
    });

    test('f04/us04/fr03: login/email_login#S1: 047e817f9707 (map form) is confirmed_entry_malformed', () async {
      final report = await check(
        journey([stepOne], confirmed: ['"login/email_login#S1: 047e817f9707"']),
      );
      expect(spots(report, FindingKind.confirmedEntryMalformed), hasLength(1));
    });
  });
}
