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

  test('sections out of the template order give one format_drift however many places differ', () async {
    final report = await checkOf(
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

  test('a header differing from the template in letter case gives one format_drift', () async {
    final report = await checkOf(
      await writeCheckProject(extra: fr('## Edge cases', '## Edge Cases')),
    );
    expect(spots(report, FindingKind.formatDrift), [
      '$loginFr:1: format_drift',
    ]);
  });

  test(
    'frontmatter keys out of the template order give one format_drift',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr(
            'traced_from:\n  - S2\nverify_method: test\n',
            'verify_method: test\ntraced_from:\n  - S2\n',
          ),
        ),
      );
      expect(spots(report, FindingKind.formatDrift), [
        '$loginFr:1: format_drift',
      ]);
    },
  );

  test('a header with extra spacing gives one format_drift', () async {
    final report = await checkOf(
      await writeCheckProject(extra: fr('## Edge cases', '##  Edge cases')),
    );
    expect(spots(report, FindingKind.formatDrift), [
      '$loginFr:1: format_drift',
    ]);
  });

  test('text right under a heading gives one format_drift', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: fr('## Rationale\n\nA wrong', '## Rationale\nA wrong'),
      ),
    );
    expect(spots(report, FindingKind.formatDrift), [
      '$loginFr:1: format_drift',
    ]);
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

  test('a doc with a repeated section, which format refuses, gives no format_drift', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: fr(
          'Test: a wrong password is refused.\n',
          'Test: a wrong password is refused.\n\n## Statement\n\nAgain.\n',
        ),
      ),
    );
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('a doc with unclosed frontmatter, which format refuses, gives no format_drift', () async {
    final report = await checkOf(
      await writeCheckProject(extra: fr('\n---\n\n# Check', '\n\n# Check')),
    );
    expect(spots(report, FindingKind.formatDrift), isEmpty);
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

  test('a story whose bytes are not UTF-8 raises no format_drift', () async {
    final project = await writeCheckProject();
    File('${project.path}/docs/$loginStory').writeAsBytesSync(
      latin1.encode('# Agent signs in at the café\n\n## Use Case\n\nx\n'),
    );
    final report = await checkOf(project);
    expect(spots(report, FindingKind.formatDrift), isEmpty);
    expect(
      spots(report, FindingKind.fileNotUtf8),
      contains('$loginStory:1: file_not_utf8'),
    );
  });

  test('a doc with an unclosed code fence gives no format_drift', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: fr(
          'A wrong password must not sign in.\n',
          'A wrong password must not sign in.\n\n```\nopen\n',
        ),
      ),
    );
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('a doc with an open generated block, which format refuses, gives no format_drift', () async {
    const journey = 'prds/journeys/sign_in/JOURNEY.md';
    final report = await checkOf(
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

  test('an untyped doc gives no format_drift', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {'docs/prds/notes/loose.md': '#   Loose\n\n\n\ntext   \n'},
      ),
    );
    expect(spots(report, FindingKind.untypedDoc), isNotEmpty);
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

  test('a doc lacking a required section but laid out gives required_section_missing only', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: fr('## Statement\n\n$checkPasswordStatement\n\n', ''),
      ),
    );
    expect(spots(report, FindingKind.requiredSectionMissing), [
      '$loginFr:1: required_section_missing',
    ]);
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });

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

  test(
    'a drifted record names the project path of its file in the fix',
    () async {
      const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            ...recordsRootTemplates,
            record: '---\nstatuses:\n  - "email_login:planned"\n---\n\n# Record\n\n| Case       | Result  |\n|------------|---------|\n| wrong      | refused |\n',
          },
        ),
      );
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.formatDrift,
      );
      expect(finding.path, record);
      expect(
        finding.message,
        'the file differs from what `specstone format` writes; run '
        '`specstone format $record`',
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
