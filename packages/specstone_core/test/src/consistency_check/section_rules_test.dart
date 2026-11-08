// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

void main() {
  test('f04/us01/s2, f04/us01/fr04/e01: a requirement with no Statement section names the file and the section', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: fr('## Statement\n\n$checkPasswordStatement\n\n', ''),
      ),
    );
    expect(
      report.findings
          .where((f) => f.kind == FindingKind.requiredSectionMissing)
          .single
          .textLine,
      '$loginFr:1: required_section_missing: required section statement is missing',
    );
  });

  test("f04/us01/s6: check on one feature reports only that feature's requirement", () async {
    const signupFr = 'prds/features/f02_signup/us01_create/fr01_store.md';
    final project = await writeCheckProject(
      extra: {
        ...fr('## Statement\n\n$checkPasswordStatement\n\n', ''),
        'docs/prds/features/f02_signup/FEATURE.md': '# Sign up\n',
        'docs/prds/features/f02_signup/us01_create/USER_STORY.md': '# Create\n',
        'docs/$signupFr':
            '---\ntraced_from:\n  - S1\nverify_method: test\n---\n\n# Store\n',
      },
    );
    expect(
      spots(checkOf(project), FindingKind.requiredSectionMissing),
      contains('$signupFr:1: required_section_missing'),
    );
    expect(
      spots(
        checkOf(project, target: 'login'),
        FindingKind.requiredSectionMissing,
      ),
      ['$loginFr:1: required_section_missing'],
    );
  });

  test('f04/us01/fr04/e02, f04/us01/fr04/e03: a header apart from letter case and whitespace is the section; an '
      'unknown one is section_undeclared', () async {
    final spaced = checkOf(
      await writeCheckProject(
        extra: doc(
          loginStory,
          '## Acceptance Criteria',
          '##  Acceptance   Criteria ',
        ),
      ),
    );
    expect(
      spaced.findings.where((f) => f.kind != FindingKind.formatDrift),
      isEmpty,
    );
    final report = checkOf(
      await writeCheckProject(
        extra: edit(loginStory, [
          ('## Acceptance Criteria', '## acceptance criteria'),
          ('## Use Case', '## Notes\nA note.\n\n## Use Case'),
        ]),
      ),
    );
    expect(spots(report, FindingKind.requiredSectionMissing), isEmpty);
    expect(spots(report, FindingKind.sectionUndeclared), [
      '$loginStory:12: section_undeclared',
    ]);
    expect(
      report.findings
          .firstWhere((f) => f.kind == FindingKind.sectionUndeclared)
          .toJson()['header'],
      'Notes',
    );
  });

  test('f04/us01/fr04/e04: a 412-line doc over its 400-line limit', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/$loginFr':
              '${checkProjectFiles()['docs/$loginFr']!}${'x\n' * 383}',
        },
      ),
    );
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.linesOverLimit,
    );
    expect(finding.textLine, startsWith('$loginFr:1: lines_over_limit'));
    expect(finding.toJson(), containsPair('limit', 400));
    expect(finding.toJson(), containsPair('actual', 412));
  });

  test('f04/us01/fr04/e05: a section over its own limit is reported at its header, the doc limit aside', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/fr.yaml':
              'sections:\n  - id: statement\n    lint:\n      max_lines: 5\n',
          ...fr(
            '$checkPasswordStatement\n',
            '$checkPasswordStatement\n${'More.\n' * 4}',
          ),
        },
      ),
    );
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.linesOverLimit,
    );
    expect(finding.line, 15);
    expect(
      finding.toJson(),
      allOf(
        containsPair('section', 'statement'),
        containsPair('limit', 5),
        containsPair('actual', 7),
      ),
    );
  });

  test('f04/us01/fr04: a doc over its character limit, at line 1', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {'.specstone/templates/fr.yaml': 'lint:\n  max_chars: 300\n'},
      ),
    );
    expect(spots(report, FindingKind.charsOverLimit), [
      '$loginFr:1: chars_over_limit',
    ]);
  });

  test(
    'f04/us01/fr04/e06: invalid frontmatter still gets its sections checked',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: edit(loginFr, [
            ('status: implemented\n', 'status: "implemented\n'),
            ('## Statement\n\n$checkPasswordStatement\n\n', ''),
          ]),
        ),
      );
      expect(spots(report, FindingKind.frontmatterInvalid), hasLength(1));
      expect(spots(report, FindingKind.requiredSectionMissing), [
        '$loginFr:1: required_section_missing',
      ]);
    },
  );

  test('f04/us01/fr04/e07: a vision entry with no quote line is vision_quote_missing at its heading', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          projectDoc,
          '> en: One sign-in for every app.\n',
          '> en: One sign-in for every app.\n\n### PV-02 — Low cost\n\nCheap to run.\n',
        ),
      ),
    );
    expect(spots(report, FindingKind.visionQuoteMissing), [
      '$projectDoc:18: vision_quote_missing',
    ]);
  });

  test(
    'f04/us01/fr04: a doc with no # title is title_missing at line 1',
    () async {
      final report = checkOf(
        await writeCheckProject(extra: fr('# Check the password\n\n', '')),
      );
      expect(spots(report, FindingKind.titleMissing), [
        '$loginFr:1: title_missing',
      ]);
    },
  );

  test('f04/us01/fr04: an undeclared section over the doc-level limits is reported at its header', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/fr.yaml':
              'lint:\n  max_lines: 30\n  max_chars: 600\n',
          ...fr(
            '## Statement\n',
            '## Notes\n${'A long note line.\n' * 40}\n## Statement\n',
          ),
        },
      ),
    );
    final notes = report.findings
        .where((f) => f.toJson()['section'] == 'notes')
        .toList();
    expect(
      notes.map((f) => f.kind),
      unorderedEquals([FindingKind.linesOverLimit, FindingKind.charsOverLimit]),
    );
    expect(notes.every((f) => f.line == notes.first.line), isTrue);
    expect(notes.first.toJson(), containsPair('limit', anyOf(30, 600)));
  });

  test(
    'f04/us01/fr04: a head line "# " with no text is title_missing at line 1',
    () async {
      for (final head in ['# \n\n', '#   \n\n']) {
        final report = checkOf(
          await writeCheckProject(extra: fr('# Check the password\n\n', head)),
        );
        expect(spots(report, FindingKind.titleMissing), [
          '$loginFr:1: title_missing',
        ]);
      }
    },
  );

  test('f04/us01/fr04: a section lint finding names the template section id, not the header slug', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/user_story.yaml': 'sections:\n  - id: acceptance_criteria\n    lint:\n      max_lines: 3\n      max_chars: 40\n',
          ...doc(
            loginStory,
            '## Acceptance Criteria\n',
            '## Acceptance criteria\n',
          ),
        },
      ),
    );
    final limits = report.findings.where(
      (f) =>
          f.kind == FindingKind.linesOverLimit ||
          f.kind == FindingKind.charsOverLimit,
    );
    expect(limits, hasLength(2));
    for (final finding in limits) {
      expect(finding.toJson(), containsPair('section', 'acceptance_criteria'));
      expect(finding.message, contains('section acceptance_criteria '));
    }
  });

  test('f04/us01/fr04: a fenced example heading in the vision section is no vision entry', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          projectDoc,
          '> en: One sign-in for every app.\n',
          '> en: One sign-in for every app.\n```\n### PV-02 — Example\n```\n',
        ),
      ),
    );
    expect(spots(report, FindingKind.visionQuoteMissing), isEmpty);
  });

  test('consistency_check/find_template_breaks/check_sections_and_limits E09: size counts the laid-out text, not the padding on disk', () async {
    final padded =
        '| Case${' ' * 600} | Result |\n|${'-' * 602}|--------|\n'
        '| wrong${' ' * 599} | refused |\n';
    final project = await writeCheckProject(
      extra: {
        '.specstone/templates/fr.yaml': 'lint:\n  max_chars: 1000\n',
        ...fr(
          'A wrong password must not sign in.\n',
          'A wrong password must not sign in.\n\n$padded',
        ),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.charsOverLimit), isEmpty);
    expect(spots(report, FindingKind.formatDrift), [
      '$loginFr:1: format_drift',
    ]);
  });

  test('consistency_check/find_template_breaks/check_sections_and_limits E09: a section counts the blank lines format adds under its ### headings', () async {
    final body = '${'### Head\ntext\n' * 3}${'filler\n' * 32}';
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/fr.yaml':
              'sections:\n  - id: statement\n    lint:\n      max_lines: 42\n',
          ...fr('$checkPasswordStatement\n', body),
        },
      ),
    );
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.linesOverLimit,
    );
    expect(finding.toJson(), containsPair('limit', 42));
    expect(finding.toJson(), containsPair('actual', 43));
  });

  test('consistency_check/find_template_breaks/check_sections_and_limits E09: a doc format refuses counts its text on disk', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/fr.yaml': 'lint:\n  max_chars: 300\n',
          ...fr(
            'A wrong password must not sign in.\n',
            'A wrong password must not sign in.\n\n```\nopen\n${'x' * 300}\n',
          ),
        },
      ),
    );
    expect(
      spots(report, FindingKind.charsOverLimit),
      contains('$loginFr:1: chars_over_limit'),
    );
    expect(spots(report, FindingKind.formatDrift), isEmpty);
  });
}
