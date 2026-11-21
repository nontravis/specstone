// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/consistency_check/tracked_links.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/index_query/matrix_rows.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/matrix_record_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/override_link_fixture.dart';
import '../../helpers/record_fixture.dart' show recordText;
import '../../helpers/shipped_pins.dart' show shippedPinsConfig;
import '../../helpers/write_fixture.dart' show getDoc, readDoc, writeIn;

/// The config that sets `verification_coverage:` to [mode].
String _coverageConfig(String mode) =>
    '${shippedPinsConfig()}verification_coverage: $mode\n';

void main() {
  const fp = fingerprintOf;
  final edited = loginScenario2.replaceFirst('wrong password', 'wrong pass');

  test('approved docs whose entries match are clean', () async {
    expect((await checkOf(await writeCheckProject())).findings, isEmpty);
  });

  test('a scenario is named by the value of its number, so S02 '
      'and Scenario 02 name Scenario 2 alike, in traces and in confirmed '
      'entries', () async {
    final padded = loginScenario2.replaceFirst('Scenario 2', 'Scenario 02');
    for (final extra in [
      edit(loginFr, [('  - S2\n', '  - S02\n'), ('  - S2 ', '  - S02 ')]),
      edit(loginFr, [('  - S2 ', '  - S02 ')]),
      {
        ...doc(loginStory, loginScenario2, padded),
        ...edit(loginFr, [
          ('  - S2 ${fp(loginScenario2)}', '  - S2 ${fp(padded)}'),
        ]),
      },
    ]) {
      expect(
        (await checkOf(await writeCheckProject(extra: extra))).findings,
        isEmpty,
      );
    }
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          ...doc(loginStory, loginScenario2, edited),
          ...edit(loginFr, [
            ('  - S2\n', '  - S02\n'),
            ('  - S2 ', '  - S02 '),
          ]),
        },
      ),
    );
    expect(
      report.findings.single.toJson(),
      allOf(containsPair('link', 'S02'), containsPair('block', 'Scenario 2')),
    );
  });

  test('traces S2 and S02 are one link, so an edit of Scenario 2 raises one suspect', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          ...doc(loginStory, loginScenario2, edited),
          ...fr('  - S2\n', '  - S2\n  - S02\n'),
        },
      ),
    );

    expect(
      report.findings.single.toJson(),
      allOf(containsPair('kind', 'suspect'), containsPair('link', 'S2')),
    );
  });

  test('an edited scenario makes the FR suspect, naming both '
      'fingerprints and the block, at the one finding level', () async {
    final report = await checkOf(
      await writeCheckProject(extra: doc(loginStory, loginScenario2, edited)),
    );
    expect(report.exitStatus, 1);
    final finding = report.findings.single;
    expect(
      finding.textLine,
      '$loginFr:7: suspect: S2 changed after it was confirmed, recorded ${fp(loginScenario2)}; '
      'read Scenario 2 of $loginStory below, then record S2 with the fingerprint after it',
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

  group('Report suspect links', () {
    final block = printedBlockOf(edited);

    test(
      'a suspect finding prints the block, then the fingerprint, '
      'each indented 4 spaces, and its message holds no fingerprint',
      () async {
        final finding = (await checkOf(
          await writeCheckProject(
            extra: doc(loginStory, loginScenario2, edited),
          ),
        )).findings.single;

        expect(
          finding.message,
          'S2 changed after it was confirmed, recorded ${fp(loginScenario2)}; '
          'read Scenario 2 of $loginStory below, then record S2 with the '
          'fingerprint after it',
        );
        expect(finding.keys.keys, [
          'link',
          'recorded',
          'upstream',
          'block',
          'text',
          'fingerprint',
        ]);
        expect(finding.keys['text'], block);
        expect(finding.textLines, [
          finding.textLine,
          for (final line in block.split('\n')) '    $line',
          '    fingerprint ${fp(edited)}',
        ]);
        expect(finding.textLines.first, isNot(contains(fp(edited))));
      },
    );

    test(
      'no line before the last block line holds the current '
      'fingerprint, and under --json text comes before fingerprint',
      () async {
        final finding = (await checkOf(
          await writeCheckProject(
            extra: doc(loginStory, loginScenario2, edited),
          ),
        )).findings.single;

        for (final line in finding.textLines.take(
          finding.textLines.length - 1,
        )) {
          expect(line, isNot(contains(fp(edited))));
        }
        final keys = finding.toJson().keys.toList();
        expect(keys.indexOf('text'), lessThan(keys.indexOf('fingerprint')));
        expect(keys.indexOf('text'), greaterThan(keys.indexOf('waitsFor')));
      },
    );

    test(
      'a block whose last line ends in a no-break space keeps it in text, '
      'and text plus its line break is the block the fingerprint hashes',
      () async {
        final report = await checkOf(
          await writeCheckProject(
            extra: fr(checkPasswordStatement, '$checkPasswordStatement\u00A0'),
          ),
        );
        final finding = report.findings.singleWhere(
          (f) => f.kind == FindingKind.suspect,
        );

        final text = finding.keys['text']! as String;
        expect(text, endsWith('\u00A0'));
        expect(fp('$text\n'), finding.keys['fingerprint']);
      },
    );

    test('a block with an empty line and a line opening with fingerprint '
        'prints every block line indented, the empty one as 4 spaces, and the '
        'real fingerprint last', () async {
      final tricky = loginScenario2.replaceFirst(
        'sign-in refused',
        'sign-in refused\n\nfingerprint 000000000000 is spelled out here',
      );
      final finding = (await checkOf(
        await writeCheckProject(extra: doc(loginStory, loginScenario2, tricky)),
      )).findings.single;

      final lines = finding.textLines;
      expect(lines.last, '    fingerprint ${fp(tricky)}');
      expect(lines, contains('    '));
      expect(
        lines,
        contains('    fingerprint 000000000000 is spelled out here'),
      );
      expect(
        lines.skip(1).take(lines.length - 2),
        printedBlockOf(tricky).split('\n').map((l) => '    $l'),
      );
      for (final line in lines.skip(1)) {
        expect(line, startsWith('    '));
      }
      expect(
        lines.where((l) => l == '    fingerprint ${fp(tricky)}'),
        hasLength(1),
      );
    });
  });

  group('Report unconfirmed links', () {
    test('a link with no entry carries the block text before the '
        'fingerprint and prints them indented', () async {
      final finding = (await checkOf(
        await writeCheckProject(
          extra: fr('confirmed:\n  - S2 ${fp(loginScenario2)}\n', ''),
        ),
      )).findings.single;

      expect(
        finding.message,
        'S2 has no confirmed entry; read Scenario 2 of $loginStory below, '
        'then record S2 with the fingerprint after it',
      );
      expect(finding.keys.keys, [
        'link',
        'upstream',
        'block',
        'text',
        'fingerprint',
      ]);
      expect(finding.keys['text'], printedBlockOf(loginScenario2));
      final keys = finding.toJson().keys.toList();
      expect(keys.indexOf('text'), lessThan(keys.indexOf('fingerprint')));
      expect(finding.textLines.last, '    fingerprint ${fp(loginScenario2)}');
      expect(finding.textLines[1], startsWith('    ### Scenario 2'));
      expect(finding.textLines.first, isNot(contains(fp(loginScenario2))));
    });

    test('a draft whose entry records an older fingerprint carries the '
        'block text before the fingerprint', () async {
      final finding = (await checkOf(
        await writeCheckProject(
          extra: edit(loginFr, [
            ('traced_from:\n', 'draft: true\ntraced_from:\n'),
            ('  - S2 ${fp(loginScenario2)}', '  - S2 000000000000'),
          ]),
        ),
      )).findings.single;

      expect(
        finding.message,
        'S2 is not confirmed: the draft records 000000000000; read '
        'Scenario 2 of $loginStory below, then record S2 with the fingerprint '
        'after it',
      );
      expect(finding.keys.keys, [
        'link',
        'upstream',
        'block',
        'recorded',
        'text',
        'fingerprint',
      ]);
      expect(finding.keys['text'], printedBlockOf(loginScenario2));
      final keys = finding.toJson().keys.toList();
      expect(keys.indexOf('text'), lessThan(keys.indexOf('fingerprint')));
      expect(finding.textLines.last, '    fingerprint ${fp(loginScenario2)}');
    });

    test('an owner finding carries no text and prints one line', () async {
      final finding = (await checkOf(
        await writeCheckProject(
          extra: fr('traced_from:\n', 'draft: true\ntraced_from:\n'),
        ),
      )).findings.single;

      expect(finding.waitsFor, WaitsFor.owner);
      expect(finding.keys.containsKey('text'), isFalse);
      expect(finding.keys['fingerprint'], fp(loginScenario2));
      expect(finding.textLines, hasLength(1));
    });
  });

  test(
    'an edit to another scenario, a blank line, or CRLF changes nothing',
    () async {
      final story = checkProjectFiles()['docs/$loginStory']!;
      for (final text in [
        story.replaceFirst('sees the home page', 'sees the start page'),
        '$story\n\n',
        story.replaceAll('\n', '\r\n'),
      ]) {
        final report = await checkOf(
          await writeCheckProject(extra: {'docs/$loginStory': text}),
        );
        expect(
          report.findings.where((f) => f.kind != FindingKind.formatDrift),
          isEmpty,
        );
      }
    },
  );

  test('a table padded to its widest cell and a dropped gap under the heading give no finding', () async {
    const table = '| a | b |\n|---|---|\n| longer cell | c |';
    const padded =
        '| a           | b |\n| ----------- | - |\n| longer cell | c |';
    const unpadded = '$loginScenario2\n\n$table';
    const paddedBlock = '$loginScenario2\n\n$padded';
    final noGap = loginScenario2.replaceFirst(
      'Wrong password\n\n',
      'Wrong password\n',
    );
    expect(noGap, isNot(loginScenario2));
    final projects = [
      {
        ...doc(loginStory, loginScenario2, paddedBlock),
        ...fr('  - S2 ${fp(loginScenario2)}', '  - S2 ${fp(unpadded)}'),
      },
      {
        ...doc(loginStory, loginScenario2, unpadded),
        ...fr('  - S2 ${fp(loginScenario2)}', '  - S2 ${fp(paddedBlock)}'),
      },
      doc(loginStory, loginScenario2, noGap),
    ];
    for (final extra in projects) {
      final report = await checkOf(await writeCheckProject(extra: extra));
      expect(
        report.findings.where((f) => f.kind != FindingKind.formatDrift),
        isEmpty,
      );
    }
  });

  test(
    'an nf turns suspect on its NFR Statement line, not on its Rationale',
    () async {
      const statement =
          '- **Statement:** The system shall answer a sign-in within 3 s.';
      final suspect = await checkOf(
        await writeCheckProject(
          extra: doc(gnfrDoc, loginNfrStatement, statement),
        ),
      );
      expect(spots(suspect), ['$loginNf:7: suspect']);
      expect(suspect.findings.single.toJson()['block'], 'NFR-P01 Statement');
      final rationale = await checkOf(
        await writeCheckProject(
          extra: doc(
            gnfrDoc,
            '- **Rationale:** Users wait.',
            '- **Rationale:** People wait.',
          ),
        ),
      );
      expect(rationale.findings, isEmpty);
    },
  );

  test('an API spec turns suspect for the one row whose FR Statement changed', () async {
    const lock =
        'prds/features/f01_login/us01_email_login/fr02_lock_account.md';
    const lockStatement =
        'The system shall lock the account after 5 failed sign-ins.';
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/$lock':
              '---\ntraced_from:\n  - self-derived\nverify_method: test\n---\n\n'
              '# Lock the account\n\n## Statement\n\n$lockStatement\n\n## Edge cases\n\n1. E01 — Five failures → locked.\n\n'
              '## Rationale\n\nIt stops guessing.\n\n## Verification\n\nTest: five failures lock it.\n\n$verificationLines',
          ...edit(loginApi, [
            (
              '---\n\n# Login API',
              '  - email_login/lock_account ${fp('\n$lockStatement')}\n---\n\n# Login API',
            ),
            (
              '| `signIn` |\n',
              '| `signIn` |\n| email_login/lock_account | `lock` |\n',
            ),
            (
              '### signIn\n\nSigns the Agent in.',
              '### signIn\n\nSigns the Agent in.\n\n**Response example — success**\n\n**Response example — error**\n\n### `lock`\n\nLocks it.',
            ),
          ]),
          ...fr(
            checkPasswordStatement,
            'The system shall refuse a wrong password within 2 s.',
          ),
        },
      ),
    );
    expect(spots(report), ['$loginApi:4: suspect']);
    expect(
      report.findings.single.toJson(),
      allOf(
        containsPair('link', 'email_login/check_password'),
        containsPair('block', 'Statement'),
      ),
    );
  });

  test('self-derived and a missing scenario track nothing', () async {
    for (final entry in ['self-derived', 'S9']) {
      final report = await checkOf(
        await writeCheckProject(extra: fr('  - S2\n', '  - $entry\n')),
      );
      expect(spots(report, FindingKind.suspect), isEmpty);
      expect(spots(report, FindingKind.unconfirmed), isEmpty);
    }
  });

  test('a tracked link with no entry is unconfirmed at its trace', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: fr('confirmed:\n  - S2 ${fp(loginScenario2)}\n', ''),
      ),
    );
    final finding = report.findings.single;
    expect(
      finding.textLine,
      startsWith(
        '$loginFr:3: unconfirmed: S2 has no confirmed entry; read Scenario 2 of $loginStory below, then record S2 with the fingerprint after it',
      ),
    );
    expect(finding.toJson().containsKey('recorded'), isFalse);
  });

  test('a matching entry in a '
      "draft waits for the Owner's approve", () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: fr('traced_from:\n', 'draft: true\ntraced_from:\n'),
      ),
    );
    expect(
      report.findings.single.textLine,
      "$loginFr:7: unconfirmed: S2 ${fp(loginScenario2)} is recorded in a draft; it waits for the Owner's approve",
    );
  });

  test(
    'a draft '
    'whose entry matches the current fingerprint waits for the Owner',
    () async {
      final finding = (await checkOf(
        await writeCheckProject(
          extra: fr('traced_from:\n', 'draft: true\ntraced_from:\n'),
        ),
      )).findings.single;
      expect(finding.kind, FindingKind.unconfirmed);
      expect(finding.waitsFor, WaitsFor.owner);
      expect(finding.toJson()['waitsFor'], 'owner');
      expect(finding.textLines.single, endsWith(' (waits for the Owner)'));
    },
  );

  test('in a draft with one entry at the current fingerprint, that link waits for the Owner and a link with no entry waits for the Agent', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: edit(loginFr, [
          (
            'traced_from:\n  - S2\n',
            'draft: true\ntraced_from:\n  - S1\n  - S2\n',
          ),
        ]),
      ),
    );
    final byLink = {
      for (final f in report.findings)
        if (f.kind == FindingKind.unconfirmed) f.keys['link']: f,
    };
    expect(byLink['S2']!.waitsFor, WaitsFor.owner);
    expect(byLink['S1']!.waitsFor, WaitsFor.agent);
    expect(
      byLink['S1']!.textLines.first,
      isNot(contains('waits for the Owner)')),
    );
  });

  test('a draft whose entry records an older fingerprint waits for the Agent, and so does a link with no entry outside a draft', () async {
    final older = (await checkOf(
      await writeCheckProject(
        extra: edit(loginFr, [
          ('traced_from:\n', 'draft: true\ntraced_from:\n'),
          ('  - S2 ${fp(loginScenario2)}', '  - S2 000000000000'),
        ]),
      ),
    )).findings.single;
    final none = (await checkOf(
      await writeCheckProject(
        extra: fr('confirmed:\n  - S2 ${fp(loginScenario2)}\n', ''),
      ),
    )).findings.single;
    expect(older.waitsFor, WaitsFor.agent);
    expect(none.waitsFor, WaitsFor.agent);
  });

  test('a suspect '
      'finding waits for the Agent', () async {
    final finding = (await checkOf(
      await writeCheckProject(extra: doc(loginStory, loginScenario2, edited)),
    )).findings.single;
    expect(finding.kind, FindingKind.suspect);
    expect(finding.waitsFor, WaitsFor.agent);
  });

  group('an Agent set of confirmed on a suspect FR', () {
    const target = 'fr:login/email_login/check_password';

    Future<Directory> reconfirm() async {
      final project = await writeCheckProject(
        extra: doc(loginStory, loginScenario2, edited),
      );
      final bases = getDoc(project, target)['bases']! as Map;
      final base = (bases['fields']! as Map)['confirmed']! as String;
      writeIn(
        project,
        (s) => answerSet(
          s,
          SetRequest.parse(target, field: 'confirmed', base: base),
          '- S2 ${fp(edited)}\n',
        ),
      );
      return project;
    }

    test(
      'marks the FR draft, and check then reports the link for the Owner',
      () async {
        final project = await reconfirm();

        expect(readDoc(project, loginFr), contains('draft: true\n'));
        final finding = (await checkOf(project)).findings.single;
        expect(finding.kind, FindingKind.unconfirmed);
        expect(finding.waitsFor, WaitsFor.owner);
        expect(finding.keys['link'], 'S2');
      },
    );

    test(
      'leaves the S2 link reported, so a set of confirmed alone clears nothing',
      () async {
        final report = await checkOf(await reconfirm());

        final finding = report.findings.single;
        expect(finding.kind, FindingKind.unconfirmed);
        expect(finding.keys['link'], 'S2');
        expect(report.exitStatus, 1);
      },
    );
  });

  test('a draft whose entry records an older fingerprint is unconfirmed, never suspect', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: edit(loginFr, [
          ('traced_from:\n', 'draft: true\ntraced_from:\n'),
          ('  - S2 ${fp(loginScenario2)}', '  - S2 000000000000'),
        ]),
      ),
    );
    expect(spots(report), ['$loginFr:7: unconfirmed']);
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
        'S2 is not confirmed: the draft records 000000000000; '
        'read Scenario 2 of $loginStory below, then record S2 with the fingerprint after it',
      ),
    );
  });

  test(
    'a draft whose scenario is missing gets only the trace finding',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: edit(loginFr, [
            ('traced_from:\n', 'draft: true\ntraced_from:\n'),
            ('  - S2\n', '  - S9\n'),
          ]),
        ),
      );
      expect(spots(report, FindingKind.scenarioTraceUnresolved), [
        '$loginFr:3: scenario_trace_unresolved',
      ]);
      expect(spots(report, FindingKind.unconfirmed), isEmpty);
      expect(spots(report, FindingKind.suspect), isEmpty);
    },
  );

  test('an FR without a Statement section and an NFR without a Statement line fingerprint the empty text', () async {
    const empty = 'e3b0c44298fc';
    final nfr = await checkOf(
      await writeCheckProject(extra: doc(gnfrDoc, '$loginNfrStatement\n', '')),
    );
    expect(spots(nfr), ['$loginNf:7: suspect']);
    expect(nfr.findings.single.toJson(), containsPair('fingerprint', empty));
    final noStatement = await checkOf(
      await writeCheckProject(
        extra: doc(loginFr, '## Statement\n\n$checkPasswordStatement\n\n', ''),
      ),
    );
    expect(spots(noStatement, FindingKind.suspect), ['$loginApi:4: suspect']);
    expect(
      noStatement.findings
          .firstWhere((f) => f.kind == FindingKind.suspect)
          .toJson(),
      containsPair('fingerprint', empty),
    );
  });

  test('a repeated scenario number fingerprints its first block', () async {
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
  });

  test('hasSuspectLink is true for a changed link only', () async {
    for (final (story, suspect) in [(loginScenario2, false), (edited, true)]) {
      final session = openSession(
        await writeCheckProject(extra: doc(loginStory, loginScenario2, story)),
      );
      addTearDown(session.close);
      final context = CheckContext(session);
      expect(hasSuspectLink(context, session.index.at(loginFr)!), suspect);
    }
  });

  test('the map form, uppercase hex, and ten characters are '
      'malformed', () async {
    for (final bad in [
      'S2: 047e817f9707',
      'S2 047E817F9707',
      'S2 047e817f97',
    ]) {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr('  - S2 ${fp(loginScenario2)}', '  - $bad'),
        ),
      );
      expect(spots(report, FindingKind.confirmedEntryMalformed), [
        '$loginFr:7: confirmed_entry_malformed',
      ]);
      expect(
        report.findings
            .firstWhere((f) => f.kind == FindingKind.confirmedEntryMalformed)
            .toJson()['entry'],
        bad,
      );
    }
  });

  test(
    'an entry for a link the doc does not trace is stale, in a draft too',
    () async {
      for (final draft in ['', 'draft: true\n']) {
        final report = await checkOf(
          await writeCheckProject(
            extra: edit(loginFr, [
              ('traced_from:\n', '${draft}traced_from:\n'),
              (
                '  - S2 ${fp(loginScenario2)}\n',
                '  - S2 ${fp(loginScenario2)}\n  - S3 ${fp(loginScenario2)}\n',
              ),
            ]),
          ),
        );
        const line = 8;
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
    },
  );

  group('repeated confirmed entries', () {
    const secondFingerprint = '9a1c03be55d2';
    const thirdFingerprint = '5d1e0c4b7a92';
    final firstEntry = '  - S2 ${fp(loginScenario2)}';

    List<Finding> repeatedIn(CheckReport report) => [
      for (final finding in report.findings)
        if (finding.kind == FindingKind.confirmedEntryRepeated) finding,
    ];

    test('two entries naming one scenario give one finding at the second, '
        'whatever the fingerprints', () async {
      for (final second in [secondFingerprint, fp(loginScenario2)]) {
        final report = await checkOf(
          await writeCheckProject(
            extra: fr(firstEntry, '$firstEntry\n  - S2 $second'),
          ),
        );
        final found = repeatedIn(report);
        expect(found, hasLength(1));
        expect(found.single.line, 8);
        expect(found.single.waitsFor, WaitsFor.agent);
        expect(found.single.keys, {
          'entry': 'S2 $second',
          'link': 'S2',
          'first': 7,
        });
        expect(
          spots(report),
          isNot(contains('$loginFr:8: confirmed_entry_stale')),
        );
      }
    });

    test('three entries give two findings, each naming the first', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr(
            firstEntry,
            '$firstEntry\n  - S2 $secondFingerprint\n  - S2 $thirdFingerprint',
          ),
        ),
      );
      final found = repeatedIn(report);
      expect(found.map((f) => f.line), [8, 9]);
      expect(found.map((f) => f.keys['first']), [7, 7]);
      expect(found.map((f) => f.keys['link']), ['S2', 'S2']);
    });

    test('two overrides entries naming one address give one finding at the '
        'second', () async {
      final files = overrideFiles(
        extra: {
          'docs/$loginDomain': domainDoc(
            [overrideOfRoot],
            entries: [
              '$rootAddress $rootFingerprint',
              '$rootAddress $secondFingerprint',
            ],
          ),
        },
      );
      final report = await checkOf(
        await writeCheckProject(extra: files, unstamped: files.keys.toSet()),
        docPath: loginDomain,
      );
      final found = repeatedIn(report);
      expect(found, hasLength(1));
      expect(
        found.single.line,
        lineOf(files['docs/$loginDomain']!, secondFingerprint),
      );
      expect(found.single.keys, {
        'entry': '$rootAddress $secondFingerprint',
        'link': rootAddress,
        'first': lineOf(files['docs/$loginDomain']!, rootFingerprint),
      });
    });

    test('two confirmed entries naming one scenario in one flow list give one '
        'finding naming that line', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr(
            'confirmed:\n$firstEntry\n',
            'confirmed: [S2 ${fp(loginScenario2)}, S2 $secondFingerprint]\n',
          ),
        ),
      );
      final found = repeatedIn(report);
      expect(found, hasLength(1));
      expect(found.single.keys, {
        'entry': 'S2 $secondFingerprint',
        'link': 'S2',
        'first': found.single.line,
      });
    });

    test('two overrides entries naming one address in one flow list give one '
        'finding', () async {
      final domain =
          domainDoc(
            [overrideOfRoot],
            entries: [
              '$rootAddress $rootFingerprint',
              '$rootAddress $secondFingerprint',
            ],
          ).replaceFirst(
            'overrides:\n  - $rootAddress $rootFingerprint\n'
                '  - $rootAddress $secondFingerprint\n',
            'overrides: [$rootAddress $rootFingerprint, '
                '$rootAddress $secondFingerprint]\n',
          );
      final files = overrideFiles(extra: {'docs/$loginDomain': domain});
      final report = await checkOf(
        await writeCheckProject(extra: files, unstamped: files.keys.toSet()),
        docPath: loginDomain,
      );
      final found = repeatedIn(report);
      expect(found, hasLength(1));
      expect(found.single.keys['entry'], '$rootAddress $secondFingerprint');
    });

    test('a repeated entry for an untraced link is stale at the first copy '
        'and repeated at the later copy', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr(
            firstEntry,
            '$firstEntry\n  - S3 ${fp(loginScenario2)}\n'
            '  - S3 $secondFingerprint',
          ),
        ),
      );
      expect(spots(report, FindingKind.confirmedEntryStale), [
        '$loginFr:8: confirmed_entry_stale',
      ]);
      expect(spots(report, FindingKind.confirmedEntryRepeated), [
        '$loginFr:9: confirmed_entry_repeated',
      ]);
    });

    test('a map-form, a ten-character, and an address-less overrides entry are never counted as repeats', () async {
      final confirmed = await checkOf(
        await writeCheckProject(
          extra: fr(
            firstEntry,
            '$firstEntry\n  - S2: 047e817f9707\n  - S2: 047e817f9707\n'
            '  - S2 047e817f97\n  - S2 047e817f97',
          ),
        ),
      );
      expect(repeatedIn(confirmed), isEmpty);
      expect(
        spots(confirmed, FindingKind.confirmedEntryMalformed),
        hasLength(4),
      );

      final files = overrideFiles(
        extra: {
          'docs/$loginDomain': domainDoc(
            [overrideOfRoot],
            entries: [
              'INV-3 $rootFingerprint',
              'INV-3 $rootFingerprint',
              rootAddress,
              rootAddress,
            ],
          ),
        },
      );
      final overrides = await checkOf(
        await writeCheckProject(extra: files, unstamped: files.keys.toSet()),
        docPath: loginDomain,
      );
      expect(repeatedIn(overrides), isEmpty);
      expect(
        spots(overrides, FindingKind.confirmedEntryMalformed),
        hasLength(4),
      );
    });

    test('a malformed entry is never counted as a repeat', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr(firstEntry, '$firstEntry\n  - S2 047E817F9707'),
        ),
      );
      expect(repeatedIn(report), isEmpty);
      expect(spots(report, FindingKind.confirmedEntryMalformed), hasLength(1));
    });
  });

  test('an add nf tracks no link, so its entry is stale', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: edit(loginNf, [
          ('kind: tighten', 'kind: add'),
          ('overrides: NFR-P01\n', ''),
        ]),
      ),
    );
    expect(spots(report), ['$loginNf:6: confirmed_entry_stale']);
  });

  test('an untyped doc gets no field, section, banned-word, trace, or suspect rule', () async {
    final report = await checkOf(
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

  test('an API entry with no FR trace row is stale', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: doc(
          loginApi,
          '---\n\n# Login API',
          '  - email_login/send_otp 5d1e0c4b7a92\n---\n\n# Login API',
        ),
      ),
    );
    expect(spots(report), ['$loginApi:5: confirmed_entry_stale']);
  });

  test('a project layer that disables confirmed on fr runs no link state rule on an fr', () async {
    final report = await checkOf(
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

  test(
    'a bare confirmed key counts as absent, not as a malformed entry',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr(
            'confirmed:\n  - S2 ${fingerprintFor(loginScenario2)}\n',
            'confirmed:\n',
          ),
        ),
      );
      expect(spots(report, FindingKind.confirmedEntryMalformed), isEmpty);
      expect(spots(report), ['$loginFr:3: unconfirmed']);
    },
  );

  test('a scenario with a fenced example heading keeps its whole block, and the example is no scenario', () async {
    const example = '```\n### Scenario 3 — Example\n- **Given** a sketch\n```';
    final report = await checkOf(
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

  test(
    'an api entry naming a nested FR by three segments is well-formed',
    () async {
      final report = await checkOf(
        await writeNestedProject(),
        docPath: shopApi,
      );

      expect(spots(report, FindingKind.confirmedEntryMalformed), isEmpty);
      expect(spots(report, FindingKind.confirmedEntryStale), isEmpty);
      expect(spots(report, FindingKind.suspect), isEmpty);
      expect(spots(report, FindingKind.unconfirmed), isEmpty);
    },
  );

  group('journey step links', () {
    const journeyPath = 'prds/journeys/sign_in/JOURNEY.md';
    const label1 = 'login/email_login#S1';
    const label2 = 'login/email_login#S2';
    const stepOne = '### 1. Open\n\nstep: login/email_login S1';
    const stepTwo = '### 2. Type\n\nstep: login/email_login S1';

    String journey(
      List<String> steps, {
      List<String> confirmed = const [],
      bool draft = false,
    }) {
      final entries = confirmed.map((e) => '  - $e\n').join();
      return '---\n'
          '${draft ? 'draft: true\n' : ''}'
          '${confirmed.isEmpty ? '' : 'confirmed:\n$entries'}'
          '---\n\n# Sign in\n\n## Goal\n\nGet in.\n\n## Flow\n\nSign in.\n\n'
          '## Steps\n\n${steps.join('\n')}\n';
    }

    Future<CheckReport> check(
      String text, {
      Map<String, String> extra = const {},
    }) async => await checkOf(
      await writeCheckProject(extra: {'docs/$journeyPath': text, ...extra}),
      docPath: journeyPath,
    );

    test(
      'an edit of Scenario 1 makes the journey suspect for that step',
      () async {
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
      },
    );

    test('a matching entry is clean; no entry is unconfirmed; a draft journey is unconfirmed', () async {
      final clean = await check(
        journey([stepOne], confirmed: ['$label1 ${fp(loginScenario1)}']),
      );
      expect(clean.findings, isEmpty);

      final missing = await check(journey([stepOne]));
      expect(
        missing.findings.single.textLine,
        startsWith(
          '$journeyPath:19: unconfirmed: $label1 has no confirmed entry; read Scenario 1 of $loginStory below, then record $label1 with the fingerprint after it',
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

    test('a journey has no parent, and its step links still run', () async {
      final report = await check(journey([stepOne]));
      expect(spots(report, FindingKind.unconfirmed), hasLength(1));
    });

    test(
      'two steps naming one scenario track one link and need one entry',
      () async {
        final entry = ['$label1 ${fp(loginScenario1)}'];
        final report = await check(
          journey([stepOne, stepTwo], confirmed: entry),
        );
        expect(report.findings, isEmpty);

        final bare = await check(journey([stepOne, stepTwo]));
        expect(spots(bare, FindingKind.unconfirmed), hasLength(1));
      },
    );

    test("a journey entry names its scenario by story Name and the number's value, so "
        'login/email_login#S01 confirms a step on S1 or S01 and is no stale entry', () async {
      const padded = 'login/email_login#S01';
      for (final step in [
        stepOne,
        '### 1. Open\n\nstep: login/email_login S01',
      ]) {
        final report = await check(
          journey([step], confirmed: ['$padded ${fp(loginScenario1)}']),
        );
        expect(report.findings, isEmpty, reason: step);
      }

      final changed = await check(
        journey([stepOne], confirmed: ['$padded ${fp(loginScenario2)}']),
      );
      expect(
        changed.findings.single.toJson(),
        allOf(
          containsPair('kind', 'suspect'),
          containsPair('recorded', fp(loginScenario2)),
        ),
      );
    });

    test(
      'an entry for a scenario no step names is confirmed_entry_stale',
      () async {
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
      },
    );

    test('a step whose scenario was deleted keeps its link', () async {
      final report = await check(
        journey(
          ['### 1. Open\n\nstep: login/email_login S9'],
          confirmed: ['login/email_login#S9 ${fp(loginScenario1)}'],
        ),
      );
      expect(spots(report, FindingKind.confirmedEntryStale), isEmpty);
      expect(spots(report, FindingKind.suspect), isEmpty);
      expect(report.findings.single.kind, FindingKind.journeyStepUnresolved);
    });

    test('login/email_login#S1: 047e817f9707 (map form) is confirmed_entry_malformed', () async {
      final report = await check(
        journey([stepOne], confirmed: ['"login/email_login#S1: 047e817f9707"']),
      );
      expect(spots(report, FindingKind.confirmedEntryMalformed), hasLength(1));
    });
  });

  group('sibling-story links', () {
    const sibling = 'shop/cart/drop_item#S1';
    const foreign = 'shop/pay/card#S1';

    String frWith(String entry, {String? recorded}) =>
        nestedFiles()['docs/$cartAddFr']!
            .replaceFirst('  - S1\n', '  - S1\n  - $entry\n')
            .replaceFirst(
              'confirmed:\n',
              'confirmed:\n${recorded == null ? '' : '  - $entry $recorded\n'}',
            );

    Future<({List<TrackedLink> links, String block})> linksOf(
      String entry,
    ) async {
      final session = openSession(
        await writeNestedProject(extra: {'docs/$cartAddFr': frWith(entry)}),
      );
      addTearDown(session.close);
      final context = CheckContext(session);
      return (
        links: trackedLinksOf(context, session.index.at(cartAddFr)!),
        block: context.scenarioBlocksOf(session.index.at(cartDrop)!)['S1']!,
      );
    }

    Future<CheckReport> checkWith(
      String entry, {
      required String recorded,
      Map<String, String> extra = const {},
    }) async => await checkOf(
      await writeNestedProject(
        extra: {
          'docs/$cartAddFr': frWith(entry, recorded: recorded),
          ...extra,
        },
      ),
      docPath: cartAddFr,
    );

    test(
      'a scenario of a sibling story is tracked against that story',
      () async {
        final (:links, :block) = await linksOf(sibling);
        final link = links.singleWhere((l) => l.label == sibling);

        expect(link.upstream, cartDrop);
        expect(link.block, 'Scenario 1');
        expect(link.fingerprint, fp(block));
      },
    );

    test('a story of another feature tracks no link', () async {
      final (:links, block: _) = await linksOf(foreign);

      expect(links.map((l) => l.label), ['S1']);
    });

    test('an edit to the sibling story makes the sibling link suspect, an edit to the own story leaves it clean', () async {
      final (links: _, :block) = await linksOf(sibling);
      final edited = nestedFiles()['docs/$cartDrop']!.replaceFirst(
        'the shopper acts',
        'the shopper acts twice',
      );
      final suspect = await checkWith(
        sibling,
        recorded: fp(block),
        extra: {'docs/$cartDrop': edited},
      );
      expect(
        suspect.findings
            .singleWhere((f) => f.kind == FindingKind.suspect)
            .toJson(),
        allOf(
          containsPair('link', sibling),
          containsPair('upstream', cartDrop),
          containsPair('block', 'Scenario 1'),
        ),
      );

      final ownEdited = nestedFiles()['docs/$cartAdd']!.replaceFirst(
        'the shopper acts',
        'the shopper acts twice',
      );
      final own = await checkWith(
        sibling,
        recorded: fp(block),
        extra: {'docs/$cartAdd': ownEdited},
      );
      expect(
        own.findings
            .where((f) => f.kind == FindingKind.suspect)
            .map((f) => f.toJson()['link']),
        ['S1'],
      );
    });

    test(
      'a sibling entry the FR traces is neither malformed nor stale',
      () async {
        final (links: _, :block) = await linksOf(sibling);
        final report = await checkWith(sibling, recorded: fp(block));

        expect(spots(report, FindingKind.confirmedEntryMalformed), isEmpty);
        expect(spots(report, FindingKind.confirmedEntryStale), isEmpty);
        expect(spots(report, FindingKind.suspect), isEmpty);
      },
    );

    test('a confirmed entry with a lettered scenario number is confirmed_entry_malformed', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr('  - S2 ${fp(loginScenario2)}', '  - S6a 0123456789ab'),
        ),
      );

      expect(spots(report, FindingKind.confirmedEntryMalformed), [
        '$loginFr:7: confirmed_entry_malformed',
      ]);
    });
  });

  group('override links', () {
    const shopDomain = 'specs/f02_shop/DOMAIN.md';
    const cartDomain = 'specs/f02_shop/f01_cart/DOMAIN.md';
    const shopAddress = 'domain:shop#INV-3';
    const shopRule = '- **INV-3** A cart holds stock.';
    final shopFingerprint = fp(shopRule);
    final editedRule = rootRule.replaceFirst('7 days', '14 days');
    final rootEntry = '$rootAddress $rootFingerprint';

    Future<List<Finding>> findings(
      Map<String, String> files,
      String docPath,
    ) async {
      final report = await checkOf(
        await writeCheckProject(extra: files, unstamped: files.keys.toSet()),
        docPath: docPath,
      );
      return [
        for (final finding in report.findings)
          if (linkKinds.contains(finding.kind)) finding,
      ];
    }

    Map<String, String> loginFiles(
      List<String> items, {
      List<String> entries = const [],
      bool draft = false,
      String root = rootRule,
    }) => overrideFiles(
      root: root,
      extra: {
        'docs/$loginDomain': domainDoc(items, entries: entries, draft: draft),
      },
    );

    Map<String, String> cartFiles(List<String> items, List<String> entries) =>
        overrideFiles(
          extra: {
            'docs/prds/features/f02_shop/FEATURE.md': '# Shop\n',
            'docs/prds/features/f02_shop/f01_cart/FEATURE.md': '# Cart\n',
            'docs/$shopDomain': domainDoc([shopRule]),
            'docs/$cartDomain': domainDoc(items, entries: entries),
          },
        );

    test('an edited root rule makes the override link suspect with the '
        'address as link', () async {
      final files = loginFiles(
        [overrideOfRoot],
        entries: [rootEntry],
        root: editedRule,
      );
      final finding = (await findings(files, loginDomain)).single;
      expect(finding.kind, FindingKind.suspect);
      expect(finding.line, lineOf(files['docs/$loginDomain']!, rootAddress));
      expect(finding.waitsFor, WaitsFor.agent);
      expect(finding.keys, {
        'link': rootAddress,
        'recorded': rootFingerprint,
        'upstream': rootDomain,
        'block': 'INV-3',
        'text': printedBlockOf(editedRule),
        'fingerprint': fp(editedRule),
      });
      expect(finding.message, isNot(contains(fp(editedRule))));
    });

    test('a suspect override link prints the rule text before the current fingerprint', () async {
      final files = loginFiles(
        [overrideOfRoot],
        entries: [rootEntry],
        root: editedRule,
      );
      final finding = (await findings(files, loginDomain)).single;
      expect(finding.kind, FindingKind.suspect);
      expect(finding.textLines, [
        finding.textLine,
        for (final line in printedBlockOf(editedRule).split('\n')) '    $line',
        '    fingerprint ${fp(editedRule)}',
      ]);
      expect(finding.textLines.first, isNot(contains(fp(editedRule))));
    });

    test('an unedited root rule keeps the override link clean', () async {
      expect(
        await findings(
          loginFiles([overrideOfRoot], entries: [rootEntry]),
          loginDomain,
        ),
        isEmpty,
      );
    });

    test('an edit to a nested bullet of the rule keeps it clean', () async {
      final files = loginFiles(
        [overrideOfRoot],
        entries: [rootEntry],
        root: '$rootRule\n  - Enforcer: the cart service.',
      );
      expect(await findings(files, loginDomain), isEmpty);
      final edited = loginFiles(
        [overrideOfRoot],
        entries: [rootEntry],
        root: '$rootRule\n  - Enforcer: the order service.',
      );
      expect(await findings(edited, loginDomain), isEmpty);
    });

    test("an approved topic's override goes suspect", () async {
      final files = overrideFiles(
        root: editedRule,
        extra: {
          'docs/$rulesTopic': topicDoc(
            ['- **RULE-1** A rule holds.', overrideOfRoot],
            entries: [rootEntry],
          ),
        },
      );
      final finding = (await findings(files, rulesTopic)).single;
      expect(finding.kind, FindingKind.suspect);
      expect(finding.keys['link'], rootAddress);
      expect(finding.keys['upstream'], rootDomain);
    });

    test('an override line with no entry is unconfirmed at the line', () async {
      final files = loginFiles([overrideOfRoot]);
      final finding = (await findings(files, loginDomain)).single;
      expect(finding.kind, FindingKind.unconfirmed);
      expect(finding.line, lineOf(files['docs/$loginDomain']!, 'Overrides:'));
      expect(finding.waitsFor, WaitsFor.agent);
      expect(finding.keys, {
        'link': rootAddress,
        'upstream': rootDomain,
        'block': 'INV-3',
        'text': printedBlockOf(rootRule),
        'fingerprint': rootFingerprint,
      });
    });

    test('a draft with a current override entry gets waitsFor owner', () async {
      final files = loginFiles(
        [overrideOfRoot],
        entries: [rootEntry],
        draft: true,
      );
      final finding = (await findings(files, loginDomain)).single;
      expect(finding.kind, FindingKind.unconfirmed);
      expect(finding.waitsFor, WaitsFor.owner);
      expect(finding.line, lineOf(files['docs/$loginDomain']!, rootAddress));
      expect(finding.message, contains("waits for the Owner's approve"));
    });

    test(
      'a draft with an older override entry still waits for the agent',
      () async {
        final files = loginFiles(
          [overrideOfRoot],
          entries: ['$rootAddress ${fp(editedRule)}'],
          draft: true,
        );
        final finding = (await findings(files, loginDomain)).single;
        expect(finding.kind, FindingKind.unconfirmed);
        expect(finding.waitsFor, WaitsFor.agent);
      },
    );

    test('an override entry no line links is stale', () async {
      final files = loginFiles(
        ['- **INV-1** An account holds one email.'],
        entries: [rootEntry],
      );
      final finding = (await findings(files, loginDomain)).single;
      expect(finding.kind, FindingKind.confirmedEntryStale);
      expect(finding.line, lineOf(files['docs/$loginDomain']!, rootAddress));
      expect(finding.keys, {'entry': rootEntry, 'link': rootAddress});
    });

    test(
      'an override entry with no address or no fingerprint is malformed',
      () async {
        final files = loginFiles(
          [overrideOfRoot],
          entries: ['INV-3 $rootFingerprint', rootAddress, rootEntry],
        );
        final found = await findings(files, loginDomain);
        expect(found.map((f) => f.kind), [
          FindingKind.confirmedEntryMalformed,
          FindingKind.confirmedEntryMalformed,
        ]);
        expect(
          found.first.message,
          contains(
            'is not an overrides entry; write '
            '"<doc type>:<name>#<ID> <12 lowercase hex characters>"',
          ),
        );
        expect(found.map((f) => f.keys['entry']), [
          'INV-3 $rootFingerprint',
          rootAddress,
        ]);
      },
    );

    test('a scenario entry in overrides is malformed and an override '
        'entry in confirmed is malformed', () async {
      final scenarioEntry = 'S1 $rootFingerprint';
      final inOverrides = loginFiles(
        [overrideOfRoot],
        entries: [scenarioEntry, rootEntry],
      );
      expect(
        (await findings(inOverrides, loginDomain)).map((f) => f.keys['entry']),
        [scenarioEntry],
      );
      final inConfirmed = await checkOf(
        await writeCheckProject(
          extra: fr('  - S2 ${fp(loginScenario2)}', '  - $rootEntry'),
        ),
        docPath: loginFr,
      );
      expect(
        spots(inConfirmed, FindingKind.confirmedEntryMalformed),
        hasLength(1),
      );
    });

    test(
      'the fix text of an override link names the overrides field',
      () async {
        final unconfirmed = (await findings(
          loginFiles([overrideOfRoot]),
          loginDomain,
        )).single;
        expect(
          unconfirmed.message,
          contains(
            'then record $rootAddress in `overrides` with the '
            'fingerprint after it',
          ),
        );
        final suspect = (await findings(
          loginFiles([overrideOfRoot], entries: [rootEntry], root: editedRule),
          loginDomain,
        )).single;
        expect(
          suspect.message,
          contains(
            'then record $rootAddress in `overrides` with the '
            'fingerprint after it',
          ),
        );
      },
    );

    test('an override address written into confirmed is told to move to '
        'overrides', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr('  - S2 ${fp(loginScenario2)}', '  - $rootEntry'),
        ),
        docPath: loginFr,
      );
      final malformed = report.findings.singleWhere(
        (f) => f.kind == FindingKind.confirmedEntryMalformed,
      );
      expect(malformed.message, contains('belongs in `overrides`'));
      expect(malformed.keys['entry'], rootEntry);
    });

    test('a malformed confirmed entry that is no override address keeps '
        'its form hint', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr('  - S2 ${fp(loginScenario2)}', '  - S2'),
        ),
        docPath: loginFr,
      );
      final malformed = report.findings.singleWhere(
        (f) => f.kind == FindingKind.confirmedEntryMalformed,
      );
      expect(
        malformed.message,
        'S2 is not a confirmed entry; write '
        '"<link> <12 lowercase hex characters>"',
      );
    });

    test('two lines of one id in two docs pair by address', () async {
      final items = [
        '- Overrides: [INV-3](../DOMAIN.md#invariants) — a cart holds stock, because stock',
        '- Overrides: [INV-3](../../DOMAIN.md#invariants) — carts expire, because stock',
      ];
      final entries = ['$shopAddress $shopFingerprint', rootEntry];
      expect(await findings(cartFiles(items, entries), cartDomain), isEmpty);

      final partial = cartFiles(items, [rootEntry]);
      final finding = (await findings(partial, cartDomain)).single;
      expect(finding.kind, FindingKind.unconfirmed);
      expect(finding.keys['link'], shopAddress);
      expect(
        finding.line,
        lineOf(partial['docs/$cartDomain']!, 'a cart holds stock, because'),
      );
    });

    test(
      'an api doc tracks its FR trace row, then its override line',
      () async {
        final original = checkProjectFiles()['docs/$loginApi']!;
        final files = overrideFiles(
          extra: {
            'docs/$loginApi': original
                .replaceFirst(
                  'confirmed:\n',
                  'overrides:\n  - $rootEntry\nconfirmed:\n',
                )
                .replaceFirst(
                  'Signs the Agent in.\n',
                  'Signs the Agent in.\n\n$overrideOfRoot\n',
                ),
          },
        );
        expect(await findings(files, loginApi), isEmpty);
        final session = openSession(
          await writeCheckProject(extra: files, unstamped: files.keys.toSet()),
        );
        addTearDown(session.close);
        final links = trackedLinksOf(
          CheckContext(session),
          session.index.at(loginApi)!,
        );
        expect(links.map((l) => (l.label, l.entryKey)), [
          ('email_login/check_password', 'confirmed'),
          (rootAddress, 'overrides'),
        ]);
      },
    );

    test('reordered lines or entries change no pairing', () async {
      final items = [
        '- Overrides: [INV-3](../DOMAIN.md#invariants) — a cart holds stock, because stock',
        '- Overrides: [INV-3](../../DOMAIN.md#invariants) — carts expire, because stock',
      ];
      final entries = ['$shopAddress $shopFingerprint', rootEntry];
      expect(
        await findings(cartFiles(items.reversed.toList(), entries), cartDomain),
        isEmpty,
      );
      expect(
        await findings(cartFiles(items, entries.reversed.toList()), cartDomain),
        isEmpty,
      );
    });

    test('two lines of one address share one link', () async {
      final session = openSession(
        await writeCheckProject(
          extra: loginFiles([overrideOfRoot, '$overrideOfRoot, twice']),
          unstamped: loginFiles([]).keys.toSet(),
        ),
      );
      addTearDown(session.close);
      final context = CheckContext(session);
      final links = trackedLinksOf(context, session.index.at(loginDomain)!);
      expect(links.map((l) => l.label), [rootAddress]);
      expect(links.single.entryKey, 'overrides');
    });

    test(
      'an nf keeps its own overrides field out of override checks',
      () async {
        final report = await checkOf(
          await writeCheckProject(extra: overrideFiles()),
          docPath: loginNf,
        );
        expect(
          report.findings.where((f) => linkKinds.contains(f.kind)),
          isEmpty,
        );
        final session = openSession(
          await writeCheckProject(extra: overrideFiles()),
        );
        addTearDown(session.close);
        final links = trackedLinksOf(
          CheckContext(session),
          session.index.at(loginNf)!,
        );
        expect(links.map((l) => (l.label, l.entryKey)), [
          ('NFR-P01', 'confirmed'),
        ]);
      },
    );
  });

  group('matrix row links', () {
    const item = 'email_login/check_password';
    const label = '$item#E01';
    const edgeCase = '1. E01 — An empty password → refused.';
    final current = fp(edgeCase);
    const older = '3f9a1c0b7e2d';
    const draftFr = (
      'verify_method: test\n',
      'verify_method: test\ndraft: true\n',
    );

    String testRow([
      String? fingerprint,
      String name = 'refuses an empty one',
    ]) => '- $item E01: `$name`${fingerprint == null ? '' : ' $fingerprint'}';

    String record(
      List<String> rows, {
      String front = '',
      List<String> statuses = const ['$item:implemented'],
    }) =>
        '${recordText(front: front, statuses: statuses)}'
        '\n## Verification matrix\n\n${rows.join('\n')}\n';

    int rowLine(String record, int i) =>
        record.split('\n').indexOf('## Verification matrix') + 3 + i;

    Future<List<Finding>> findingsOf(
      String record, {
      Map<String, String> extra = const {},
    }) async {
      final project = await writeCheckProject(
        extra: {
          '.specstone/config.yaml': _coverageConfig('edge_case'),
          loginRecord: record,
          ...extra,
        },
        // A stamp would add an `approved:` line and move every line below it.
        unstamped: {loginRecord},
      );
      return [
        for (final f in (await checkOf(project)).findings)
          if (f.path == loginRecord &&
              (f.kind == FindingKind.suspect ||
                  f.kind == FindingKind.unconfirmed))
            f,
      ];
    }

    test("a row stamped with the edge case's fingerprint is clean", () async {
      expect(await findingsOf(record([testRow(current)])), isEmpty);
    });

    test('a test row gives its literals joined by a comma and a space', () {
      final row = parseMatrixLine(
        '- $item: `reads a row`, `drops a row`',
        1,
      ) as MatrixRow;

      expect(matrixRowLiteralOf(row), 'reads a row, drops a row');
    });

    test('a changed edge case makes its row suspect', () async {
      const changed = '1. E01 — An empty password → refused at once.';
      final text = record([testRow(current)]);

      final finding = (await findingsOf(
        text,
        extra: fr(edgeCase, changed),
      )).single;

      expect(finding.kind, FindingKind.suspect);
      expect(finding.line, rowLine(text, 0));
      expect(finding.waitsFor, WaitsFor.agent);
      expect(
        finding.message,
        '$label changed after it was confirmed, recorded $current; read E01 '
        'of $loginFr below, then record $label with the fingerprint after it',
      );
      expect(finding.keys, {
        'link': label,
        'recorded': current,
        'upstream': loginFr,
        'block': 'E01',
        'text': changed,
        'fingerprint': fp(changed),
      });
      expect(finding.keys.keys, [
        'link',
        'recorded',
        'upstream',
        'block',
        'text',
        'fingerprint',
      ]);
      expect(finding.textLines, [
        finding.textLine,
        '    $changed',
        '    fingerprint ${fp(changed)}',
      ]);
    });

    test('a draft record changes no row state', () async {
      const changed = '1. E01 — An empty password → refused at once.';
      final rows = [
        testRow(current, 'refuses a clean one'),
        testRow(older, 'refuses a stale one'),
        testRow(null, 'refuses an unstamped one'),
      ];
      final approved = record(rows);
      final draft = record(rows, front: 'draft: true\n');

      for (final text in [approved, draft]) {
        final findings = await findingsOf(text, extra: fr(edgeCase, changed));
        expect(
          [
            for (final f in findings)
              (f.kind, f.line - rowLine(text, 0), f.waitsFor),
          ],
          [
            (FindingKind.suspect, 0, WaitsFor.agent),
            (FindingKind.suspect, 1, WaitsFor.agent),
            (FindingKind.unconfirmed, 2, WaitsFor.agent),
          ],
        );
      }
      final clean = await findingsOf(
        record(rows.take(1).toList(), front: 'draft: true\n'),
      );
      expect(clean, isEmpty);
    });

    test('a suspect row of a draft record holds the same keys and prints its edge case before the fingerprint', () async {
      const changed = '1. E01 — An empty password → refused at once.';
      final text = record([testRow(current)], front: 'draft: true\n');

      final finding = (await findingsOf(
        text,
        extra: fr(edgeCase, changed),
      )).single;

      expect(finding.kind, FindingKind.suspect);
      expect(finding.waitsFor, WaitsFor.agent);
      expect(finding.keys, {
        'link': label,
        'recorded': current,
        'upstream': loginFr,
        'block': 'E01',
        'text': changed,
        'fingerprint': fp(changed),
      });
      expect(finding.textLines, [
        finding.textLine,
        '    $changed',
        '    fingerprint ${fp(changed)}',
      ]);
    });

    test('an unstamped row of a draft record prints its edge case before the fingerprint', () async {
      final text = record([testRow()], front: 'draft: true\n');

      final finding = (await findingsOf(text)).single;

      expect(finding.kind, FindingKind.unconfirmed);
      expect(finding.waitsFor, WaitsFor.agent);
      expect(finding.textLines, [
        finding.textLine,
        '    $edgeCase',
        '    fingerprint $current',
      ]);
    });

    test(
      "a change below the edge case's first line makes the row suspect",
      () async {
        const changed = '$edgeCase\n   - A form of spaces';

        final finding = (await findingsOf(
          record([testRow(current)]),
          extra: fr(edgeCase, changed),
        )).single;

        expect(finding.kind, FindingKind.suspect);
        expect(finding.keys['text'], changed);
        expect(finding.keys['fingerprint'], fp(changed));
      },
    );

    test('a split edge case makes the old rows suspect', () async {
      const split =
          '1. E01 — An empty password, with no spaces → refused.\n'
          '2. E02 — A password of spaces → refused.\n'
          '3. E03 — A blank password → refused.';
      final text = record([testRow(current)]);

      final findings = await findingsOf(text, extra: fr(edgeCase, split));

      expect(
        [for (final f in findings) (f.kind, f.line)],
        [(FindingKind.suspect, rowLine(text, 0))],
      );
    });

    test('two rows of one edge case are judged one by one', () async {
      final text = record([
        testRow(current, 'refuses a current one'),
        testRow(older, 'refuses an older one'),
      ]);

      final finding = (await findingsOf(text)).single;

      expect(finding.kind, FindingKind.suspect);
      expect(finding.line, rowLine(text, 1));
      expect(finding.keys['recorded'], older);
    });

    test('a row of a missing edge case takes no state', () async {
      final text = record(['- $item E99: `refuses a long one` $older']);

      expect(await findingsOf(text), isEmpty);
    });

    test('a row of a story takes no state', () async {
      final text = record([
        '- email_login E01: `refuses a long one` $older',
        '- email_login E01: `refuses a short one`',
      ]);

      expect(await findingsOf(text), isEmpty);
    });

    test('a row of an item that names no doc takes no state', () async {
      final text = record([
        '- email_login/no_such_fr E01: `refuses a long one` $older',
        '- email_login/no_such_fr E01: `refuses a short one`',
      ]);

      expect(await findingsOf(text), isEmpty);
    });

    test('the row of a draft requirement goes to the Owner', () async {
      final text = record([
        testRow(older, 'refuses a stale one'),
        testRow(null, 'refuses an unstamped one'),
        testRow(current, 'refuses a clean one'),
      ]);

      final findings = await findingsOf(text, extra: edit(loginFr, [draftFr]));

      expect(
        [for (final f in findings) (f.kind, f.line, f.waitsFor)],
        [
          (FindingKind.suspect, rowLine(text, 0), WaitsFor.owner),
          (FindingKind.unconfirmed, rowLine(text, 1), WaitsFor.owner),
        ],
      );
      final [suspect, unconfirmed] = findings;
      expect(
        suspect.message,
        '$label changed after it was confirmed, recorded $older; it waits '
        "for the Owner's approve of $loginFr",
      );
      expect(suspect.keys, {
        'link': label,
        'recorded': older,
        'upstream': loginFr,
        'block': 'E01',
        'text': edgeCase,
        'fingerprint': current,
      });
      expect(suspect.textLines, [
        '${suspect.textLine} (waits for the Owner)',
        '    $edgeCase',
        '    fingerprint $current',
      ]);
      expect(
        unconfirmed.message,
        "$label waits for the Owner's approve of $loginFr",
      );
      expect(unconfirmed.keys.keys, [
        'link',
        'upstream',
        'block',
        'fingerprint',
      ]);
      expect(unconfirmed.textLines, [
        '${unconfirmed.textLine} (waits for the Owner)',
      ]);
      for (final f in findings) {
        expect(f.message, isNot(contains(current)));
      }
    });

    test('a row with no fingerprint goes to the agent', () async {
      for (final row in [testRow(), '- $item E01 skipped: no clock on CI']) {
        final text = record([row]);

        final finding = (await findingsOf(text)).single;

        expect(finding.kind, FindingKind.unconfirmed);
        expect(finding.line, rowLine(text, 0));
        expect(finding.waitsFor, WaitsFor.agent);
        expect(
          finding.message,
          '$label records no fingerprint; read E01 of $loginFr below, then '
          'record $label with the fingerprint after it',
        );
        expect(finding.keys.keys, [
          'link',
          'upstream',
          'block',
          'text',
          'fingerprint',
        ]);
        expect(finding.keys['text'], edgeCase);
        expect(finding.textLines, [
          finding.textLine,
          '    $edgeCase',
          '    fingerprint $current',
        ]);
      }
    });

    test('a set that writes a row fingerprint keeps the record draft and clears the row', () async {
      const target = 'implementation:login#verification_matrix';
      final project = await writeMatrixRecordProject(
        isDraft: true,
        config: _coverageConfig('edge_case'),
      );
      final sectionBase = getDoc(project, target)['base']! as String;

      final answer = writeIn(
        project,
        (s) => answerSet(
          s,
          SetRequest.parse(target, base: sectionBase),
          '${matrixRow.trimRight()} $current\n',
        ),
      );

      expect(answer.json['draft'], isTrue);
      expect(readDoc(project, loginRecord), contains('draft: true\n'));
      expect(
        readDoc(project, loginRecord),
        contains('E01: `a wrong password` $current'),
      );
      final rowFindings = (await checkOf(project)).findings.where(
        (f) =>
            f.path == loginRecord &&
            (f.kind == FindingKind.suspect ||
                f.kind == FindingKind.unconfirmed),
      );
      expect(rowFindings, isEmpty);
    });

    test('the rows of a planned requirement are still tracked', () async {
      final text = record(
        [
          testRow(older, 'refuses a stale one'),
          testRow(null, 'refuses an unstamped one'),
          testRow(current, 'refuses a clean one'),
        ],
        statuses: const ['$item:planned'],
      );

      final findings = await findingsOf(text);

      expect(
        [for (final f in findings) (f.kind, f.line, f.waitsFor)],
        [
          (FindingKind.suspect, rowLine(text, 0), WaitsFor.agent),
          (FindingKind.unconfirmed, rowLine(text, 1), WaitsFor.agent),
        ],
      );
    });

    test('the rows of a skipped requirement take no state', () async {
      final rows = [
        testRow(null, 'refuses an unstamped one'),
        testRow(older, 'refuses a stale one'),
      ];
      for (final statuses in [
        const ['$item:skipped:no clock on CI'],
        const [':skipped:no web view'],
        const ['email_login:skipped:no web view'],
      ]) {
        final text = record(rows, statuses: statuses);

        expect(await findingsOf(text), isEmpty, reason: '$statuses');
      }
    });

    test('a stale row of a skipped requirement is no suspect link', () async {
      Future<bool> isSuspectRecord(List<String> statuses) async {
        final project = await writeCheckProject(
          extra: {
            '.specstone/config.yaml': _coverageConfig('edge_case'),
            loginRecord: record([testRow(older)], statuses: statuses),
          },
          unstamped: {loginRecord},
        );
        final session = openSession(project);
        addTearDown(session.close);
        return hasSuspectLink(
          CheckContext(session),
          session.index.at(loginRecord)!,
        );
      }

      expect(await isSuspectRecord(const ['$item:implemented']), isTrue);
      expect(await isSuspectRecord(const ['$item:skipped:no clock']), isFalse);
      expect(await isSuspectRecord(const [':skipped:no web view']), isFalse);
    });
  });

  group('per-FR matrix row links', () {
    const item = 'email_login/check_password';
    const edgeCase = '1. E01 — An empty password → refused.';
    const contract =
        '## Statement\n\n$checkPasswordStatement\n\n## Edge cases\n\n$edgeCase';
    const headings = 'Statement, Edge cases';
    const inputOutput = '## Input / Output\n\nA password text.\n\n';
    final current = fp(contract);
    const older = '3f9a1c0b7e2d';
    const draftFr = (
      'verify_method: test\n',
      'verify_method: test\ndraft: true\n',
    );
    const read =
        'read the contract block of $loginFr below, then record $item with '
        'the fingerprint after it';

    String row([String? fingerprint, String name = 'refuses a wrong one']) =>
        '- $item: `$name`${fingerprint == null ? '' : ' $fingerprint'}';

    String record(List<String> rows, {String front = ''}) =>
        '${recordText(front: front, statuses: const ['$item:implemented'])}'
        '\n## Verification matrix\n\n${rows.join('\n')}\n';

    int rowLine(String record, int i) =>
        record.split('\n').indexOf('## Verification matrix') + 3 + i;

    Future<Directory> projectOf(
      String record,
      String mode,
      Map<String, String> extra,
    ) => writeCheckProject(
      extra: {
        '.specstone/config.yaml': _coverageConfig(mode),
        loginRecord: record,
        ...extra,
      },
      // A stamp would add an `approved:` line and move every line below it.
      unstamped: {loginRecord},
    );

    Future<List<Finding>> findingsOf(
      String record, {
      String mode = 'fr',
      Map<String, String> extra = const {},
    }) async {
      final project = await projectOf(record, mode, extra);
      return [
        for (final f in (await checkOf(project)).findings)
          if (f.path == loginRecord &&
              (f.kind == FindingKind.suspect ||
                  f.kind == FindingKind.unconfirmed))
            f,
      ];
    }

    Future<bool> isSuspectRecord(String record, String mode) async {
      final project = await projectOf(record, mode, const {});
      final session = openSession(project);
      addTearDown(session.close);
      return hasSuspectLink(
        CheckContext(session),
        session.index.at(loginRecord)!,
      );
    }

    test(
      'flags a per-FR row suspect when its contract block changes',
      () async {
        const changed = '1. E01 — An empty password → refused at once.';
        final block = contract.replaceFirst(edgeCase, changed);
        final text = record([row(current)]);

        final finding = (await findingsOf(
          text,
          extra: fr(edgeCase, changed),
        )).single;

        expect(finding.kind, FindingKind.suspect);
        expect(finding.line, rowLine(text, 0));
        expect(finding.waitsFor, WaitsFor.agent);
        expect(
          finding.message,
          '$item changed after it was confirmed, recorded $current; $read',
        );
        expect(finding.keys, {
          'link': item,
          'recorded': current,
          'upstream': loginFr,
          'block': headings,
          'text': block,
          'fingerprint': fp(block),
        });
        expect(finding.keys.keys, [
          'link',
          'recorded',
          'upstream',
          'block',
          'text',
          'fingerprint',
        ]);
        expect(finding.textLines, [
          finding.textLine,
          for (final line in block.split('\n')) '    $line',
          '    fingerprint ${fp(block)}',
        ]);
      },
    );

    test("tracks a per-FR row whatever its record's flag", () async {
      const changed = '1. E01 — An empty password → refused at once.';
      final rows = [row(older)];

      for (final front in ['', 'draft: true\n']) {
        final text = record(rows, front: front);

        final finding = (await findingsOf(
          text,
          extra: fr(edgeCase, changed),
        )).single;

        expect(finding.kind, FindingKind.suspect, reason: front);
        expect(finding.waitsFor, WaitsFor.agent, reason: front);
      }
      final clean = await findingsOf(
        record([row(current)], front: 'draft: true\n'),
      );
      expect(clean, isEmpty);
    });

    test('flags a per-FR row on a nested edge case edit', () async {
      const changed = '$edgeCase\n   - A form of spaces';
      final text = record([row(current)]);

      final finding = (await findingsOf(
        text,
        extra: fr(edgeCase, changed),
      )).single;

      expect(finding.kind, FindingKind.suspect);
      expect(finding.keys['text'], contract.replaceFirst(edgeCase, changed));
    });

    test('keeps a per-FR row clean on a title, frontmatter, behavior, rationale, or verification edit', () async {
      final text = record([row(current)]);
      final extra = edit(loginFr, [
        ('# Check the password', '# Check a password'),
        ('verify_method: test\n', 'verify_method: review\n'),
        ('## Rationale\n\n', '## Behavior\n\nA flow.\n\n## Rationale\n\n'),
        (
          'A wrong password must not sign in.',
          'A wrong password never signs in.',
        ),
        (
          'Test: a wrong password is refused.',
          'Test: an empty one is refused.',
        ),
      ]);

      expect(await findingsOf(text, extra: extra), isEmpty);
    });

    test(
      'names the headings present when the FR has no input and output',
      () async {
        final text = record([row()]);

        final without = (await findingsOf(text)).single;
        final withBoth = (await findingsOf(
          text,
          extra: fr('## Edge cases\n', '$inputOutput## Edge cases\n'),
        )).single;

        expect(without.keys['block'], headings);
        expect(withBoth.keys['block'], 'Statement, Input / Output, Edge cases');
        expect(
          withBoth.keys['text'],
          '## Statement\n\n$checkPasswordStatement\n\n$inputOutput'
          '## Edge cases\n\n$edgeCase',
        );
      },
    );

    test('waits for the Owner while the FR is a draft', () async {
      for (final fingerprint in [older, null]) {
        final text = record([row(fingerprint)]);

        final finding = (await findingsOf(
          text,
          extra: edit(loginFr, [draftFr]),
        )).single;

        expect(finding.waitsFor, WaitsFor.owner, reason: '$fingerprint');
        expect(
          finding.message,
          fingerprint == null
              ? "$item waits for the Owner's approve of $loginFr"
              : '$item changed after it was confirmed, recorded $older; it '
                    "waits for the Owner's approve of $loginFr",
        );
        expect(finding.keys['block'], headings);
        expect(finding.keys.containsKey('text'), fingerprint != null);
        expect(finding.keys['fingerprint'], current);
      }
    });

    test('reports an unstamped per-FR row unconfirmed for the agent', () async {
      final text = record([row()]);

      final finding = (await findingsOf(text)).single;

      expect(finding.kind, FindingKind.unconfirmed);
      expect(finding.line, rowLine(text, 0));
      expect(finding.waitsFor, WaitsFor.agent);
      expect(finding.message, '$item records no fingerprint; $read');
      expect(finding.keys.keys, [
        'link',
        'upstream',
        'block',
        'text',
        'fingerprint',
      ]);
      expect(finding.keys['text'], contract);
      expect(finding.textLines, [
        finding.textLine,
        for (final line in contract.split('\n')) '    $line',
        '    fingerprint $current',
      ]);
    });

    test('tracks no row under off and ignores its fingerprint', () async {
      for (final rows in [
        [row()],
        [row(older)],
      ]) {
        final text = record(rows);

        expect(await findingsOf(text, mode: 'false'), isEmpty);
        expect(await isSuspectRecord(text, 'false'), isFalse);
      }
    });

    test('tracks no refused-form row in any mode', () async {
      const perEdgeCase = '- $item E01: `refuses an empty one` $older';
      final perFr = row(older);
      for (final (mode, rows) in [
        ('false', [perEdgeCase]),
        ('fr', [perEdgeCase]),
        ('edge_case', [perFr]),
      ]) {
        final text = record(rows);

        expect(await findingsOf(text, mode: mode), isEmpty, reason: mode);
        expect(await isSuspectRecord(text, mode), isFalse, reason: mode);
      }
    });

    test(
      'tracks the per-FR row and not the per-edge-case rows of one FR under fr',
      () async {
        final text = record([
          '- $item E01: `refuses an empty one` $older',
          row(older),
        ]);

        final finding = (await findingsOf(text)).single;

        expect(finding.kind, FindingKind.suspect);
        expect(finding.line, rowLine(text, 1));
        expect(finding.keys['link'], item);
      },
    );

    test('keeps edge_case rows tracked against their edge case', () async {
      final text = record(['- $item E01: `refuses an empty one` $older']);

      final finding = (await findingsOf(text, mode: 'edge_case')).single;

      expect(finding.kind, FindingKind.suspect);
      expect(finding.keys['link'], '$item#E01');
      expect(finding.keys['block'], 'E01');
      expect(finding.keys['text'], edgeCase);
    });

    test('counts a suspect per-FR row for the suspect doc list', () async {
      expect(await isSuspectRecord(record([row(older)]), 'fr'), isTrue);
      expect(await isSuspectRecord(record([row(current)]), 'fr'), isFalse);
      expect(await isSuspectRecord(record([row()]), 'fr'), isFalse);
    });
  });
}
