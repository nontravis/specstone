// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/shipped_pins.dart';

/// The FR with [line] added as the last frontmatter line.
Map<String, String> _frWithKey(String line) => fr(
  '${fingerprintFor(loginScenario2)}\n---',
  '${fingerprintFor(loginScenario2)}\n$line\n---',
);

void main() {
  test('f04/us01/fr03/e01, f04/us01/fr03: a missing required field is reported at line 1', () async {
    final report = checkOf(
      await writeCheckProject(extra: fr('verify_method: test\n', '')),
    );
    final finding = report.findings.single;
    expect(
      finding.textLine,
      '$loginFr:1: required_field_missing: required field verify_method is missing',
    );
    expect(finding.toJson()['field'], 'verify_method');
  });

  test('f04/us01/s3, f04/us01/fr03/e02: a value off its enum names the field, the line, and the four values', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr('verify_method: test', 'verify_method: maybe'),
      ),
    );
    expect(
      report.findings.single.textLine,
      '$loginFr:5: field_value_mismatch: verify_method is maybe; it takes test, analysis, inspection, or demonstration',
    );
    expect(report.findings.single.toJson()['value'], 'maybe');
  });

  test('f04/us01/fr03/e03: a list field written as a scalar, and a date that is not a date, mismatch', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...fr('traced_from:\n  - S2\n', 'traced_from: S2\n'),
          'docs/prds/personas/buyer/PERSONA.md': '---\nrole: Agent\npriority: primary\nbasis: proto\nreviewed: next week\n---\n\n# Buyer\n',
        },
      ),
    );
    expect(spots(report, FindingKind.fieldValueMismatch), [
      '$loginFr:3: field_value_mismatch',
      'prds/personas/buyer/PERSONA.md:6: field_value_mismatch',
    ]);
  });

  test(
    'f04/us01/fr03/e04: a key no layer defines is field_undeclared at its line',
    () async {
      final report = checkOf(
        await writeCheckProject(extra: _frWithKey('priority: high')),
      );
      expect(spots(report), ['$loginFr:8: field_undeclared']);
    },
  );

  test('f04/us01/fr03/e05, cc-s03/inv2, review focus 4: approved follows the merged set, with no F-04 change', () async {
    final project = await writeCheckProject(
      extra: _frWithKey('approved: true'),
    );
    final session = openSession(project);
    addTearDown(session.close);
    final builtIn = session.index.set
        .lookup('fr')!
        .fields
        .any((f) => f.id == 'approved');
    expect(
      spots(runCheck(session), FindingKind.fieldUndeclared),
      builtIn ? isEmpty : ['$loginFr:8: field_undeclared'],
    );
  });

  for (final (label, written) in [
    ('E05, a quoted 12-hex hash', 'approved: "3f2a9c01b4de"'),
    ('E10, the 1.1.0 mark true', 'approved: true'),
    ('E10, a boolean false', 'approved: false'),
    ('E10, a list', 'approved: [a]'),
    ('E10, a number', 'approved: 7'),
  ]) {
    test(
      'consistency_check/find_template_breaks/check_frontmatter_fields $label: approved raises no field finding',
      () async {
        final report = checkOf(
          await writeCheckProject(extra: _frWithKey(written)),
        );
        expect(spots(report, FindingKind.fieldValueMismatch), isEmpty);
        expect(spots(report, FindingKind.fieldUndeclared), isEmpty);
      },
    );
  }

  test('f04/us01/fr03/e06: a status written in a FEATURE is feature_status_written, whatever its stories hold', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/$loginFeature': checkProjectFiles()['docs/$loginFeature']!
              .replaceFirst(
                '---\nvision:',
                '---\nstatus: implemented\nvision:',
              ),
        },
      ),
    );
    expect(spots(report), ['$loginFeature:2: feature_status_written']);
    expect(report.findings.single.toJson().containsKey('field'), isFalse);
  });

  group(
    'consistency_check/find_template_breaks/check_frontmatter_fields, records',
    () {
      const recordPath = 'specs/f01_login/IMPLEMENTATION.md';

      /// The record doc with [recordFrontmatter]; the shipped pack types it.
      Map<String, String> recordProject(String recordFrontmatter) => {
        'docs/$recordPath': '---\n$recordFrontmatter---\n\n# Login record\n',
      };

      /// The story and the FR, each writing the status the record now holds.
      final withStatus = {
        ...edit(loginStory, [
          ('---\ngoals:', '---\nstatus: implemented\ngoals:'),
        ]),
        ...fr('---\ntraced_from:', '---\nstatus: implemented\ntraced_from:'),
      };

      test('f04/us01/fr03/e11: a story or FR writing status is requirement_status_written while the merged set holds the record doc type', () async {
        final report = checkOf(
          await writeCheckProject(
            unstamped: {'docs/$recordPath'},
            extra: {...recordProject(''), ...withStatus},
          ),
        );
        expect(spots(report, FindingKind.requirementStatusWritten), [
          '$loginStory:2: requirement_status_written',
          '$loginFr:2: requirement_status_written',
        ]);
        expect(
          report.findings
              .firstWhere((f) => f.kind == FindingKind.requirementStatusWritten)
              .toJson()
              .containsKey('field'),
          isFalse,
        );
        expect(spots(report, FindingKind.fieldValueMismatch), isEmpty);
        expect(spots(report, FindingKind.fieldUndeclared), isEmpty);
      });

      test('f04/us01/fr03/e11: the same docs with no record doc type in the merged set take no finding', () async {
        final report = checkOf(
          await writeCheckProject(
            extra: {
              ...withStatus,
              '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
            },
          ),
        );
        expect(spots(report, FindingKind.requirementStatusWritten), isEmpty);
      });

      test('f04/us01/fr03/e11: a story or FR with no status written takes no finding', () async {
        final report = checkOf(
          await writeCheckProject(
            unstamped: {'docs/$recordPath'},
            extra: recordProject(''),
          ),
        );
        expect(spots(report, FindingKind.requirementStatusWritten), isEmpty);
      });

      test('f04/us01/fr03/e11: a feature still takes feature_status_written, not the requirement kind', () async {
        final report = checkOf(
          await writeCheckProject(
            unstamped: {'docs/$recordPath'},
            extra: {
              ...recordProject(''),
              'docs/$loginFeature': checkProjectFiles()['docs/$loginFeature']!
                  .replaceFirst(
                    '---\nvision:',
                    '---\nstatus: implemented\nvision:',
                  ),
            },
          ),
        );
        expect(spots(report, FindingKind.featureStatusWritten), [
          '$loginFeature:2: feature_status_written',
        ]);
      });

      test('f04/us01/fr03/e13: the record doc type is found by its record_status field, whatever its id', () async {
        final report = checkOf(
          await writeCheckProject(
            unstamped: {'docs/$recordPath'},
            extra: {
              ...withStatus,
              '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
              '.specstone/templates/target_record.yaml':
                  'id: target_record\n'
                  'description: One feature record per target.\n'
                  'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
                  'parent: feature\n'
                  'per_target: true\n'
                  'fields:\n'
                  '  - id: statuses\n'
                  '    type: record_status\n'
                  '    list: true\n',
              ...recordProject(''),
            },
          ),
        );
        expect(spots(report, FindingKind.requirementStatusWritten), [
          '$loginStory:2: requirement_status_written',
          '$loginFr:2: requirement_status_written',
        ]);
      });

      test('f04/us01/fr03/e14: an implements line with a space after the colon reads as a map and mismatches', () async {
        final report = checkOf(
          await writeCheckProject(
            unstamped: {'docs/$recordPath'},
            extra: recordProject(
              'implements:\n  - show_toast: lib/toast.dart\n',
            ),
          ),
        );
        final mismatches = [
          for (final f in report.findings)
            if (f.kind == FindingKind.fieldValueMismatch &&
                f.path == recordPath)
              f,
        ];
        expect(mismatches.map((f) => '${f.path}:${f.line}'), ['$recordPath:2']);
        expect(mismatches.single.toJson()['field'], 'implements');
      });

      test('f04/us01/fr03/e14: an implements line with no space stays one string and gives no finding', () async {
        final report = checkOf(
          await writeCheckProject(
            unstamped: {'docs/$recordPath'},
            extra: recordProject(
              'implements:\n  - show_toast:lib/toast.dart\n',
            ),
          ),
        );
        expect(spots(report, FindingKind.fieldValueMismatch), isEmpty);
      });

      test('f04/us01/fr03/e15: a statuses line giving an item the status wip mismatches, naming the field and the four statuses', () async {
        final report = checkOf(
          await writeCheckProject(
            unstamped: {'docs/$recordPath'},
            extra: recordProject('statuses:\n  - login:wip\n'),
          ),
        );
        final mismatch = report.findings.singleWhere(
          (f) => f.kind == FindingKind.fieldValueMismatch,
        );
        expect('${mismatch.path}:${mismatch.line}', '$recordPath:2');
        expect(mismatch.toJson()['field'], 'statuses');
        expect(
          mismatch.message,
          contains('planned, implemented, deprecated, or skipped'),
        );
      });

      for (final line in [
        'login:planned',
        'login/email_login:implemented',
        ':deprecated',
        'login/email_login/check_password:skipped:no UI here',
      ]) {
        test('f04/us01/fr03/e15: the statuses line $line fits', () async {
          final report = checkOf(
            await writeCheckProject(
              unstamped: {'docs/$recordPath'},
              extra: recordProject('statuses:\n  - "$line"\n'),
            ),
          );
          expect(spots(report, FindingKind.fieldValueMismatch), isEmpty);
        });
      }

      test('f04/us01/fr03/e15: a statuses line with no status, or no colon, mismatches', () async {
        final report = checkOf(
          await writeCheckProject(
            unstamped: {'docs/$recordPath'},
            extra: recordProject('statuses:\n  - login\n  - "login:"\n'),
          ),
        );
        expect(spots(report, FindingKind.fieldValueMismatch), [
          '$recordPath:2: field_value_mismatch',
        ]);
      });
    },
  );

  test('f04/us01/fr03/e12: an FR that still writes implements under the shipped pack, which declares no such field on fr, is field_undeclared naming the field', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: _frWithKey('implements:\n  - app/lib/login.dart:checkPassword'),
      ),
    );
    final found = report.findings
        .where((f) => f.kind == FindingKind.fieldUndeclared)
        .toList();
    expect(found.map((f) => '${f.path}:${f.line}'), ['$loginFr:8']);
    expect(found.single.toJson()['field'], 'implements');
  });

  test('f04/us01/fr03/e12: a story that still writes implements is field_undeclared the same way', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: edit(loginStory, [
          (
            '  - PG-01\n---',
            '  - PG-01\nimplements:\n  - app/lib/login.dart:SignInPage\n---',
          ),
        ]),
      ),
    );
    expect(spots(report, FindingKind.fieldUndeclared), [
      '$loginStory:5: field_undeclared',
    ]);
  });

  test('f04/us01/fr03/e07: invalid frontmatter is frontmatter_invalid only, and its warning is not printed', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr('verify_method: test\n', 'verify_method: "test\n'),
      ),
    );
    expect(spots(report), ['$loginFr:7: frontmatter_invalid']);
    expect(report.warnings, isEmpty);
  });

  test('f04/us01/fr03/e08: an untyped doc gets no field rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {'docs/notes/idea.md': '---\npriority: high\n---\n\n# Idea\n'},
      ),
    );
    expect(spots(report, FindingKind.fieldUndeclared), isEmpty);
  });

  test('review focus 3: a requirement with no frontmatter misses each required field at line 1', () async {
    final text = checkProjectFiles()['docs/$loginFr']!;
    final report = checkOf(
      await writeCheckProject(
        extra: {'docs/$loginFr': text.substring(text.indexOf('# Check'))},
      ),
    );
    expect(spots(report, FindingKind.requiredFieldMissing), [
      '$loginFr:1: required_field_missing',
      '$loginFr:1: required_field_missing',
    ]);
  });

  test('f04/us01/fr03/e04: an undeclared key with an empty value is still field_undeclared', () async {
    final report = checkOf(
      await writeCheckProject(extra: _frWithKey('priority:')),
    );
    expect(spots(report), ['$loginFr:8: field_undeclared']);
  });

  group('f04/us01/fr03/e09: a required field group', () {
    const layer = '.specstone/templates/feature.yaml';
    const groups = 'lint:\n  required_field_groups:\n    - [vision, goals]\n';
    final feature = checkProjectFiles()['docs/$loginFeature']!;
    final noKeys = feature.replaceFirst(
      '---\nvision:\n  - PV-01\ngoals:\n  - PG-01\n---\n',
      '---\n---\n',
    );

    test(
      'with no value in any member is one field_group_missing at line 1',
      () async {
        final report = checkOf(
          await writeCheckProject(
            extra: {layer: groups, 'docs/$loginFeature': noKeys},
          ),
        );
        final found = report.findings
            .where((f) => f.kind == FindingKind.fieldGroupMissing)
            .toList();
        expect(spots(report, FindingKind.fieldGroupMissing), [
          '$loginFeature:1: field_group_missing',
        ]);
        expect(found.single.message, 'none of vision, goals holds a value');
        expect(found.single.toJson()['fields'], ['vision', 'goals']);
      },
    );

    test('with one member holding a value is no finding', () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            layer: groups,
            'docs/$loginFeature': feature.replaceFirst(
              'vision:\n  - PV-01\n',
              '',
            ),
          },
        ),
      );
      expect(spots(report, FindingKind.fieldGroupMissing), isEmpty);
    });

    test(
      'on a doc with invalid frontmatter is frontmatter_invalid only',
      () async {
        final report = checkOf(
          await writeCheckProject(
            extra: {
              layer: groups,
              'docs/$loginFeature': feature.replaceFirst(
                'vision:',
                'vision: "x',
              ),
            },
          ),
        );
        expect(spots(report, FindingKind.fieldGroupMissing), isEmpty);
        expect(spots(report, FindingKind.frontmatterInvalid), hasLength(1));
      },
    );
  });

  test(
    'e17: a feature system naming no Systems row is no field finding',
    () async {
      final feature = checkProjectFiles()['docs/$loginFeature']!;
      final report = checkOf(
        await writeCheckProject(
          extra: {
            'docs/$loginFeature': feature.replaceFirst(
              '---\nvision:',
              '---\nsystem: Watch app\nvision:',
            ),
          },
        ),
      );
      expect(
        report.findings.where(
          (f) =>
              f.kind != FindingKind.formatDrift &&
              f.kind != FindingKind.approvalStale,
        ),
        everyElement(
          predicate<Finding>(
            (f) => f.kind == FindingKind.systemUnresolved,
            'a system_unresolved',
          ),
        ),
      );
    },
  );
}
