// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _driftMessage =
    'the file differs from what `specstone format` writes; run '
    '`specstone format docs/$loginFr`';

void main() {
  test('consistency_check/find_template_breaks/report_format_drift: a laid-out project raises no format_drift', () async {
    final report = checkOf(await writeCheckProject());
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('consistency_check/find_template_breaks/report_format_drift E01: a table padded to a different width gives one format_drift on line 1 naming the file and its fix', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr(
          'A wrong password must not sign in.\n',
          'A wrong password must not sign in.\n\n| Case       | Result  |\n|------------|---------|\n| wrong      | refused |\n',
        ),
      ),
    );
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.formatDrift,
    );
    expect(finding.path, loginFr);
    expect(finding.line, 1);
    expect(finding.message, _driftMessage);
    expect(finding.keys, isEmpty);
  });

  test('consistency_check/find_template_breaks/report_format_drift E02: sections out of the template order give one format_drift however many places differ', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: edit(loginFr, [
          (
            '## Rationale\n\nA wrong password must not sign in.\n\n## Verification\n\nTest: a wrong password is refused.\n',
            '## Verification\n\nTest: a wrong password is refused.\n\n## Rationale\n\nA wrong password must not sign in.\n',
          ),
        ]),
      ),
    );
    expect(spots(report, FindingKind.formatDrift), [
      '$loginFr:1: format_drift',
    ]);
  });

  test('consistency_check/find_template_breaks/report_format_drift E02: a header differing from the template in letter case gives one format_drift', () async {
    final report = checkOf(
      await writeCheckProject(extra: fr('## Edge cases', '## Edge Cases')),
    );
    expect(spots(report, FindingKind.formatDrift), [
      '$loginFr:1: format_drift',
    ]);
  });

  test('consistency_check/find_template_breaks/report_format_drift E03: a doc differing in line endings only gives no format_drift', () async {
    final text = checkProjectFiles()['docs/$loginFr']!;
    final report = checkOf(
      await writeCheckProject(
        extra: {'docs/$loginFr': text.replaceAll('\n', '\r\n')},
      ),
    );
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('consistency_check/find_template_breaks/report_format_drift E04: a doc the format command refuses, for an unknown header, gives no format_drift', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr('## Rationale', '## Mystery\nx\n\n## Rationale'),
      ),
    );
    expect(spots(report, FindingKind.formatDrift), isEmpty);
    expect(spots(report, FindingKind.sectionUndeclared), hasLength(1));
  });

  test('consistency_check/find_template_breaks/report_format_drift E04: a doc with an unclosed code fence gives no format_drift', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr(
          'A wrong password must not sign in.\n',
          'A wrong password must not sign in.\n\n```\nopen\n',
        ),
      ),
    );
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('consistency_check/find_template_breaks/report_format_drift E04: a doc with an open generated block, which format refuses, gives no format_drift', () async {
    const journey = 'prds/journeys/sign_in/JOURNEY.md';
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/$journey':
              '# Sign in\n\n## Goal\n\nGet in.\n\n## Flow\n\n'
              '<!-- specstone:generated journey_flow (do not edit) -->\n'
              '| a     | b |\n|---|---|\n',
        },
      ),
      docPath: journey,
    );
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('consistency_check/find_template_breaks/report_format_drift E05: an untyped doc gives no format_drift', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {'docs/prds/notes/loose.md': '#   Loose\n\n\n\ntext   \n'},
      ),
    );
    expect(spots(report, FindingKind.untypedDoc), isNotEmpty);
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('consistency_check/find_template_breaks/report_format_drift E06: a doc lacking a required section but laid out gives required_section_missing only', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr('## Statement\n\n$checkPasswordStatement\n\n', ''),
      ),
    );
    expect(spots(report, FindingKind.requiredSectionMissing), [
      '$loginFr:1: required_section_missing',
    ]);
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('consistency_check/find_template_breaks/report_format_drift E07: a generated block with out-of-date text gives no format_drift', () async {
    const journey = 'prds/journeys/sign_in/JOURNEY.md';
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/$journey':
              '# Sign in\n\n## Goal\n\nGet in.\n\n## Flow\n\n'
              '<!-- specstone:generated journey_flow (do not edit) -->\n'
              '```mermaid\nflowchart TD\n  stale\n```\n'
              '<!-- specstone:generated end -->\n\n## Steps\n',
        },
      ),
      docPath: journey,
    );
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('consistency_check/find_template_breaks/report_format_drift E08: check <target> reports format_drift for the docs of the target unit only', () async {
    const signupFr = 'prds/features/f02_signup/us01_create/fr01_store.md';
    final project = await writeCheckProject(
      extra: {
        ...fr('## Edge cases', '## Edge Cases'),
        'docs/prds/features/f02_signup/FEATURE.md': '# Sign up\n',
        'docs/prds/features/f02_signup/us01_create/USER_STORY.md': '# Create\n',
        'docs/$signupFr': checkProjectFiles()['docs/$loginFr']!.replaceFirst(
          '## Edge cases',
          '## Edge Cases',
        ),
      },
    );
    expect(spots(checkOf(project, target: 'login'), FindingKind.formatDrift), [
      '$loginFr:1: format_drift',
    ]);
  });
}
