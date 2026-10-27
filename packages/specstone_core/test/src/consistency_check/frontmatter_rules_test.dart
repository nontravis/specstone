// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

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
      'prds/personas/buyer/PERSONA.md:5: field_value_mismatch',
    ]);
  });

  test(
    'f04/us01/fr03/e04: a key no layer defines is field_undeclared at its line',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: fr(
            'verify_method: test\n',
            'verify_method: test\npriority: high\n',
          ),
        ),
      );
      expect(spots(report), ['$loginFr:6: field_undeclared']);
    },
  );

  test('f04/us01/fr03/e05, cc-s03/inv2, review focus 4: approved follows the merged set, with no F-04 change', () async {
    final project = await writeCheckProject(
      extra: fr(
        'verify_method: test\n',
        'verify_method: test\napproved: true\n',
      ),
    );
    final session = openSession(project);
    addTearDown(session.close);
    final builtIn = session.index.set
        .lookup('fr')!
        .fields
        .any((f) => f.id == 'approved');
    expect(
      spots(runCheck(session), FindingKind.fieldUndeclared),
      builtIn ? isEmpty : ['$loginFr:6: field_undeclared'],
    );
  });

  test('f04/us01/fr03/e06: a status written in a FEATURE is feature_status_written, whatever its stories hold', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/$loginFeature': checkProjectFiles()['docs/$loginFeature']!
              .replaceFirst('---\n\n', 'status: implemented\n---\n\n'),
        },
      ),
    );
    expect(spots(report), ['$loginFeature:6: feature_status_written']);
  });

  test('f04/us01/fr03/e07: invalid frontmatter is frontmatter_invalid only, and its warning is not printed', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr('status: implemented\n', 'status: "implemented\n'),
      ),
    );
    expect(spots(report), ['$loginFr:10: frontmatter_invalid']);
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
}
