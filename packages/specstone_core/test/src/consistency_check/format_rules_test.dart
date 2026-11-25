// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/cold_node.dart';
import '../../helpers/record_fixture.dart' show recordsRootTemplates;

const _driftMessage =
    'the file differs from what `specstone format` writes; run '
    '`specstone format $loginFr`';

void main() {
  useColdHostNode();

  test('a laid-out project raises no format_drift', () async {
    final report = await checkOf(await writeCheckProject());
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('a table padded to a different width gives one format_drift on line 1 naming the file and its fix', () async {
    final report = await checkOf(
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

  test('a doc differing in line endings only gives no format_drift', () async {
    final text = checkProjectFiles()['docs/$loginFr']!;
    final report = await checkOf(
      await writeCheckProject(
        extra: {'docs/$loginFr': text.replaceAll('\n', '\r\n')},
      ),
    );
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('a doc the format command refuses, for an unknown header, gives no format_drift', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: fr('## Rationale', '## Mystery\nx\n\n## Rationale'),
      ),
    );
    expect(spots(report, FindingKind.formatDrift), isEmpty);
    expect(spots(report, FindingKind.sectionUndeclared), hasLength(1));
  });

  test(
    'an unknown header, refused by format, is named by section_undeclared',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr('## Rationale', '## Mystery\nx\n\n## Rationale'),
        ),
      );
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.sectionUndeclared,
      );
      expect(finding.path, loginFr);
      expect(finding.keys, {'header': 'Mystery'});
    },
  );

  test(
    'a non-UTF-8 doc gives no format_drift and file_not_utf8 names it',
    () async {
      final project = await writeCheckProject();
      File('${project.path}/docs/$loginFr').writeAsBytesSync(
        latin1.encode(
          '# Check the password\n\n## Statement\n\nA café password.\n',
        ),
      );
      final report = await checkOf(project);
      expect(spots(report, FindingKind.fileNotUtf8), [
        '$loginFr:1: file_not_utf8',
      ]);
      expect(spots(report, FindingKind.formatDrift), isEmpty);
    },
  );

  test(
    'a generated block with out-of-date text gives no format_drift',
    () async {
      const journey = 'prds/journeys/sign_in/JOURNEY.md';
      final report = await checkOf(
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
    },
  );

  test(
    'check <target> reports format_drift for the docs of the target unit only',
    () async {
      const signupFr = 'prds/features/f02_signup/us01_create/fr01_store.md';
      final project = await writeCheckProject(
        extra: {
          ...fr('## Edge cases', '## Edge Cases'),
          'docs/prds/features/f02_signup/FEATURE.md': '# Sign up\n',
          'docs/prds/features/f02_signup/us01_create/USER_STORY.md':
              '# Create\n',
          'docs/$signupFr': checkProjectFiles()['docs/$loginFr']!.replaceFirst(
            '## Edge cases',
            '## Edge Cases',
          ),
        },
      );
      expect(
        spots(await checkOf(project, target: 'login'), FindingKind.formatDrift),
        ['$loginFr:1: format_drift'],
      );
    },
  );

  test("format_drift names the finding's own path in its fix", () async {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          ...fr(
            'A wrong password must not sign in.\n',
            'A wrong password must not sign in.\n\n| Case       | Result  |\n|------------|---------|\n| wrong      | refused |\n',
          ),
          ...recordsRootTemplates,
          record: '---\nstatuses:\n  - "email_login:planned"\n---\n\n# Record\n\n| Case       | Result  |\n|------------|---------|\n| wrong      | refused |\n',
        },
      ),
    );
    final findings = report.findings
        .where((f) => f.kind == FindingKind.formatDrift)
        .toList();
    expect(findings.map((f) => f.path), unorderedEquals([loginFr, record]));
    for (final finding in findings) {
      expect(finding.message, endsWith('`specstone format ${finding.path}`'));
    }
  });
}
