// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/structure.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

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
            '## Notes\n${'- A long note line.\n' * 40}\n## Statement\n',
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

  group('consistency_check/find_template_breaks/check_sections_and_limits', () {
    const edgeFrom = '1. E01 — An empty password → refused.\n';
    const rationaleFrom = 'A wrong password must not sign in.\n';
    const itemLimitTemplate = '.specstone/templates/fr.yaml';

    String padded(String start, int length) => start.padRight(length, '.');

    List<Finding> itemFindings(Directory project) =>
        checkOf(project).findings
            .where((f) => f.kind == FindingKind.itemOverLimit)
            .toList();

    int lineOf(Directory project, String docPath, String prefix) =>
        File('${project.path}/docs/$docPath')
            .readAsLinesSync()
            .indexWhere((line) => line.startsWith(prefix)) +
        1;

    Future<Directory> withEdgeItem(int chars, {String? template}) =>
        writeCheckProject(
          extra: {
            itemLimitTemplate: ?template,
            ...fr(
              edgeFrom,
              '${edgeFrom}2. E02 — Another case → refused.\n'
              '${padded('3. E03 — A long case', chars)}\n',
            ),
          },
        );

    test(
      'E10: an item over the default limit is item_over_limit with its ID',
      () async {
        final project = await withEdgeItem(640);
        final finding = itemFindings(project).single;

        expect(finding.line, lineOf(project, loginFr, '3. E03'));
        expect(finding.waitsFor, WaitsFor.owner);
        expect(
          finding.toJson(),
          allOf(
            containsPair('section', 'edge_cases'),
            containsPair('id', 'E03'),
            containsPair('limit', 600),
            containsPair('actual', 640),
          ),
        );
        expect(
          finding.message,
          'item E03 of section edge_cases has 640 characters; the limit is 600',
        );
        expect(
          finding.toJson().keys.where(
            ['section', 'id', 'limit', 'actual'].contains,
          ),
          ['section', 'id', 'limit', 'actual'],
        );
      },
    );

    test(
      'E11: a paragraph with no ID is item_over_limit with no id key',
      () async {
        final project = await writeCheckProject(
          extra: fr(rationaleFrom, '${padded('A long rationale', 700)}\n'),
        );
        final finding = itemFindings(project).single;

        expect(finding.line, lineOf(project, loginFr, 'A long rationale'));
        expect(finding.toJson(), isNot(contains('id')));
        expect(
          finding.message,
          'the item at line ${finding.line} of section rationale has 700 '
          'characters; the limit is 600',
        );
      },
    );

    test('E12: a fenced code block is no item', () async {
      final project = await writeCheckProject(
        extra: {
          itemLimitTemplate: 'sections:\n  - id: verification\n    lint:\n      max_chars: 1000\n',
          ...fr(
            'Test: a wrong password is refused.\n',
            '```\n${'x' * 2000}\n```\n',
          ),
        },
      );

      expect(itemFindings(project), isEmpty);
      final over = checkOf(project).findings
          .singleWhere((f) => f.kind == FindingKind.charsOverLimit);
      expect(over.toJson(), containsPair('section', 'verification'));
    });

    test('E10: a repeated header the formatter refuses keeps each section its own items on disk', () async {
      final project = await writeCheckProject(
        extra: fr(
          '## Rationale\n',
          '## Edge cases\n\n1. E02 — A short case → refused.\n'
              '${padded('2. E03 — A long case', 640)}\n\n## Rationale\n',
        ),
      );
      final disk = File('${project.path}/docs/$loginFr').readAsStringSync();
      final finding = itemFindings(project).single;

      expect(layOutDoc(disk, fixtureDocTypeOf(loginFr)), disk);
      expect(finding.line, lineOf(project, loginFr, '2. E03'));
      expect(finding.toJson(), containsPair('section', 'edge_cases'));
      expect(finding.toJson(), containsPair('id', 'E03'));
      expect(finding.line, greaterThan(lineOf(project, loginFr, '1. E01')));
    });

    test(
      'E13: an item of 700 characters under max_item_chars 900 is no finding',
      () async {
        final project = await withEdgeItem(
          700,
          template: 'lint:\n  max_item_chars: 900\n',
        );

        expect(itemFindings(project), isEmpty);
      },
    );

    test('E14: an item of 901 characters under max_item_chars 900 is item_over_limit', () async {
      final project = await withEdgeItem(
        901,
        template: 'lint:\n  max_item_chars: 900\n',
      );

      expect(
        itemFindings(project).single.toJson(),
        allOf(containsPair('limit', 900), containsPair('actual', 901)),
      );
    });

    test('E13, E14: an item of exactly the limit is no finding, one character more is one', () async {
      expect(itemFindings(await withEdgeItem(600)), isEmpty);
      expect(
        itemFindings(await withEdgeItem(601)).single.toJson(),
        containsPair('actual', 601),
      );
      const raised = 'lint:\n  max_item_chars: 900\n';
      expect(itemFindings(await withEdgeItem(900, template: raised)), isEmpty);
    });

    test('a scenario over the limit is item_over_limit on its story and not '
        'on the copy a journey holds in a generated block', () async {
      final given = '- **Given** ${'x' * 710}';
      final project = await writeCheckProject(
        extra: {
          ...doc(
            loginStory,
            '- **Given** an account\n- **When** the Agent signs in',
            '$given\n- **When** the Agent signs in',
          ),
          'docs/prds/journeys/login/JOURNEY.md':
              '# Sign in\n\n## Goal\n\nAn Agent reaches the home page.\n\n'
              '## Steps\n\n### 1. Start\n\nstep: email_login S1\n'
              '${generatedOpenMarker('scenario_copy')}\n$given\n'
              '- **When** the Agent signs in\n$generatedEndMarker\n',
        },
      );

      expect(itemFindings(project).map((f) => f.path), [loginStory]);
    });

    test('E15: a lead paragraph over the limit is item_over_limit in section _lead', () async {
      final project = await writeCheckProject(
        extra: doc(
          loginArchitecture,
          '# Login architecture\n\n',
          '# Login architecture\n\n${padded('The lead says what the doc covers.', 687)}\n\n',
        ),
      );
      final finding = itemFindings(project).single;

      expect(finding.path, loginArchitecture);
      expect(finding.line, lineOf(project, loginArchitecture, 'The lead says'));
      expect(
        finding.toJson(),
        allOf(
          containsPair('section', '_lead'),
          containsPair('actual', 687),
          isNot(contains('id')),
        ),
      );
    });

    test(
      'E10: a lettered item form holds no ID and takes the line form',
      () async {
        final project = await writeCheckProject(
          extra: fr(edgeFrom, '${padded('3. E03a — A lettered case', 640)}\n'),
        );
        final finding = itemFindings(project).single;

        expect(finding.toJson(), isNot(contains('id')));
        expect(
          finding.message,
          'the item at line ${finding.line} of section edge_cases has 640 '
          'characters; the limit is 600',
        );
      },
    );

    test('E10: sections out of template order give the key and the line structure prints', () async {
      final project = await writeCheckProject(
        extra: fr(
          '## Statement\n\n$checkPasswordStatement\n\n## Edge cases\n\n$edgeFrom\n',
          '## Edge cases\n\n$edgeFrom\n## Statement\n\n\n\n'
              '${padded('A long statement', 700)}\n\n',
        ),
      );
      final session = openSession(project);
      addTearDown(session.close);
      final finding = runCheck(session).findings
          .singleWhere((f) => f.kind == FindingKind.itemOverLimit);
      final sections =
          (answerStructure(session.index, target: loginFr).json['docs']!
                      as List)
                  .cast<Map<String, Object?>>()
                  .single['sections']!
              as List;
      final statement = sections.cast<Map<String, Object?>>().singleWhere(
        (s) => s['key'] == 'statement',
      );
      final item = (statement['items']! as List).single as Map<String, Object?>;
      final diskLine = lineOf(project, loginFr, 'A long statement');

      expect(finding.toJson(), containsPair('section', 'statement'));
      expect(finding.line, item['line']);
      expect(finding.line, isNot(diskLine));
      expect(
        checkOf(project).findings.map((f) => f.kind),
        contains(FindingKind.formatDrift),
      );
    });
  });
}
