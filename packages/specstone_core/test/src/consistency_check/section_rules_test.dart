// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/structure.dart';
import 'package:specstone_core/src/rendering/formatter.dart'
    show Refused, formatDoc, layOutDoc;
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart'
    show defaultMaxItemChars;
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';

void main() {
  test('a requirement with no Statement section names the file and the section', () async {
    final report = await checkOf(
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

  test("check on one feature reports only that feature's requirement", () async {
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
      spots(await checkOf(project), FindingKind.requiredSectionMissing),
      contains('$signupFr:1: required_section_missing'),
    );
    expect(
      spots(
        await checkOf(project, target: 'login'),
        FindingKind.requiredSectionMissing,
      ),
      ['$loginFr:1: required_section_missing'],
    );
  });

  test('a header apart from letter case and whitespace is the section; an '
      'unknown one is section_undeclared', () async {
    final spaced = await checkOf(
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
    final report = await checkOf(
      await writeCheckProject(
        extra: edit(loginStory, [
          ('## Acceptance Criteria', '## acceptance criteria'),
          ('## Use Case', '## Notes\nA note.\n\n## Use Case'),
        ]),
      ),
    );
    expect(spots(report, FindingKind.requiredSectionMissing), isEmpty);
    expect(spots(report, FindingKind.sectionUndeclared), [
      '$loginStory:9: section_undeclared',
    ]);
    expect(
      report.findings
          .firstWhere((f) => f.kind == FindingKind.sectionUndeclared)
          .toJson()['header'],
      'Notes',
    );
  });

  test(
    'a doc of 405 non-blank body lines is over its 400-line limit',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'docs/$loginFr':
                '${checkProjectFiles()['docs/$loginFr']!}${'x\n' * 396}',
          },
        ),
      );
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.linesOverLimit,
      );
      expect(finding.textLine, startsWith('$loginFr:1: lines_over_limit'));
      expect(finding.toJson(), containsPair('limit', 400));
      expect(finding.toJson(), containsPair('actual', 405));
    },
  );

  test('60 blank lines or 30 frontmatter lines more leave the '
      'doc line count alone', () async {
    const base =
        '---\ntraced_from:\n  - S2\nverify_method: test\n'
        'confirmed:\n  - S2 h\n---\n\n# Check the password\n\n'
        '## Statement\n\nA wrong password must not sign in.\n\n';
    final fill = 'x\n' * 402;
    Future<CheckReport> reportOf(String text) async =>
        await checkOf(await writeCheckProject(extra: {'docs/$loginFr': text}));
    Object? actualOf(CheckReport report) => report.findings
        .firstWhere((f) => f.kind == FindingKind.linesOverLimit)
        .toJson()['actual'];
    final withFrontmatter = base.replaceFirst('---\n', '---\n${'x: y\n' * 30}');
    // The approval stamp keeps the frontmatter lines at 30 + the rest.
    final stamped = withApprovalHashes({
      'docs/$loginFr': '$withFrontmatter$fill',
    })['docs/$loginFr']!;
    expect(actualOf(await reportOf('$base$fill')), 405);
    expect(actualOf(await reportOf('$base${'\n' * 60}$fill')), 405);
    expect(actualOf(await reportOf(stamped)), 405);
  });

  test('invalid frontmatter counts its body from the closing '
      'delimiter; an unclosed one counts its whole text', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: edit(loginFr, [
          ('verify_method: test\n', 'verify_method: "test\n'),
          ('## Verification\n\nTest: a wrong password is refused.\n', ''),
        ]),
      ),
    );
    expect(spots(report, FindingKind.linesOverLimit), isEmpty);
    final unclosed = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/$loginFr':
              '${checkProjectFiles()['docs/$loginFr']!.replaceFirst('---\ntraced_from:', '----\ntraced_from:')}${'x\n' * 386}',
        },
      ),
    );
    expect(spots(unclosed, FindingKind.linesOverLimit), [
      '$loginFr:1: lines_over_limit',
    ]);
  });

  Future<CheckReport> statementOf(int fillerLines) async => await checkOf(
    await writeCheckProject(
      extra: {
        '.specstone/templates/fr.yaml':
            'sections:\n  - id: statement\n    lint:\n      max_lines: 40\n',
        ...fr(
          '$checkPasswordStatement\n',
          '$checkPasswordStatement\n\n${'### Head\ntext\n' * 3}${'filler\n' * fillerLines}',
        ),
      },
    ),
  );

  test('40 body lines at max_lines 40, the blank lines format adds under '
      '### headings and the header line left out, have no finding', () async {
    final report = await statementOf(33);
    expect(spots(report, FindingKind.linesOverLimit), isEmpty);
  });

  test('41 body lines at max_lines 40 report limit 40 and actual 41', () async {
    final report = await statementOf(34);
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.linesOverLimit,
    );
    expect(finding.toJson(), containsPair('limit', 40));
    expect(finding.toJson(), containsPair('actual', 41));
  });

  test('a record whose 300 frontmatter lines and 40 body lines '
      'stay under both limits', () async {
    final record =
        "---\nstatuses:\n  - 'email_login:implemented'\n"
        '${'  # comment filler\n' * 299}---\n\n# Login implementation\n'
        '${'x\n' * 40}';
    final report = await checkOf(
      await writeCheckProject(extra: {loginRecord: record}),
    );
    expect(spots(report, FindingKind.linesOverLimit), isEmpty);
  });

  group('a record with a matrix section', () {
    const head =
        "---\nstatuses:\n  - 'email_login:implemented'\n---\n\n"
        '# Login implementation\n\n';
    String row(int number, {int nameLength = 76}) {
      final name = '${'n' * (nameLength - 6)}${'$number'.padLeft(6, '0')}';
      return '- email_login/check_password E01: `$name`';
    }

    String recordOf(Iterable<String> rows) =>
        '$head${'x\n' * 40}\n## Verification matrix\n\n${rows.join('\n')}\n';

    test(
      'over the doc caps only by its matrix gives no size finding',
      () async {
        final record = recordOf([for (var i = 0; i < 700; i++) row(i)]);
        expect(
          record.length,
          greaterThan(60000),
          reason: 'the rows alone pass the character cap',
        );
        final report = await checkOf(
          await writeCheckProject(
            extra: {loginRecord: record},
            unstamped: {loginRecord},
          ),
        );
        expect(spots(report, FindingKind.linesOverLimit), isEmpty);
        expect(spots(report, FindingKind.charsOverLimit), isEmpty);
      },
    );

    test('over its own limit still gives its finding', () async {
      final record = recordOf([for (var i = 0; i < 6; i++) row(i)]);
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            loginRecord: record,
            '.specstone/templates/implementation.yaml':
                'sections:\n  - id: verification_matrix\n    lint:\n'
                '      max_lines: 5\n',
          },
          unstamped: {loginRecord},
        ),
      );
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.linesOverLimit,
      );
      expect(
        finding.toJson(),
        allOf(
          containsPair('section', 'verification_matrix'),
          containsPair('limit', 5),
          containsPair('actual', 6),
        ),
      );
    });

    test('over its own character limit still gives its finding', () async {
      final record = recordOf([for (var i = 0; i < 6; i++) row(i)]);
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            loginRecord: record,
            '.specstone/templates/implementation.yaml':
                'sections:\n  - id: verification_matrix\n    lint:\n'
                '      max_chars: 300\n',
          },
          unstamped: {loginRecord},
        ),
      );
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.charsOverLimit,
      );
      expect(
        finding.toJson(),
        allOf(
          containsPair('section', 'verification_matrix'),
          containsPair('limit', 300),
          containsPair('actual', greaterThan(300)),
        ),
      );
    });

    test('with a row over the item cap still gives its finding', () async {
      final long = row(1, nameLength: 640);
      final record = recordOf([row(0), long]);
      final report = await checkOf(
        await writeCheckProject(
          extra: {loginRecord: record},
          unstamped: {loginRecord},
        ),
      );
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.itemOverLimit,
      );
      expect(finding.path, loginRecord);
      expect(finding.line, record.split('\n').indexOf(long) + 1);
      expect(
        finding.toJson(),
        allOf(
          containsPair('section', 'verification_matrix'),
          containsPair('limit', defaultMaxItemChars),
          containsPair('actual', greaterThan(defaultMaxItemChars)),
        ),
      );
    });
  });

  Future<CheckReport> fiveLineLimitOf(int moreLines) async => await checkOf(
    await writeCheckProject(
      extra: {
        '.specstone/templates/fr.yaml':
            'sections:\n  - id: statement\n    lint:\n      max_lines: 5\n',
        ...fr(
          '$checkPasswordStatement\n',
          '$checkPasswordStatement\n${'More.\n' * moreLines}',
        ),
      },
    ),
  );

  test('a section over its own limit is reported at its header, the doc limit aside', () async {
    final report = await fiveLineLimitOf(5);
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.linesOverLimit,
    );
    expect(finding.line, 12);
    expect(
      finding.toJson(),
      allOf(
        containsPair('section', 'statement'),
        containsPair('limit', 5),
        containsPair('actual', 6),
      ),
    );
  });

  group('a persona snapshot at max_lines 4', () {
    Future<CheckReport> snapshotOf(int bodyLines) async => await checkOf(
      await writeCheckProject(
        extra: {
          'docs/prds/personas/buyer/PERSONA.md':
              '---\nrole: Agent\npriority: primary\nbasis: proto\n---\n\n'
              '# Buyer\n\n## Snapshot\n${'A buyer line.\n' * bodyLines}',
        },
      ),
    );

    test('of 4 non-blank body lines, its header line counting none, has no '
        'finding', () async {
      final report = await snapshotOf(4);
      expect(spots(report, FindingKind.linesOverLimit), isEmpty);
    });

    test(
      'of 5 body lines is lines_over_limit with limit 4 and actual 5',
      () async {
        final report = await snapshotOf(5);
        final finding = report.findings.singleWhere(
          (f) => f.kind == FindingKind.linesOverLimit,
        );
        expect(
          finding.toJson(),
          allOf(
            containsPair('section', 'snapshot'),
            containsPair('limit', 4),
            containsPair('actual', 5),
          ),
        );
      },
    );
  });

  test('a doc over its character limit, at line 1', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {'.specstone/templates/fr.yaml': 'lint:\n  max_chars: 300\n'},
      ),
    );
    expect(spots(report, FindingKind.charsOverLimit), [
      '$loginFr:1: chars_over_limit',
    ]);
  });

  test('invalid frontmatter still gets its sections checked', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: edit(loginFr, [
          ('verify_method: test\n', 'verify_method: "test\n'),
          ('## Statement\n\n$checkPasswordStatement\n\n', ''),
        ]),
      ),
    );
    expect(spots(report, FindingKind.frontmatterInvalid), hasLength(1));
    expect(spots(report, FindingKind.requiredSectionMissing), [
      '$loginFr:1: required_section_missing',
    ]);
  });

  test(
    'a vision entry with no quote line is vision_quote_missing at its heading',
    () async {
      final report = await checkOf(
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
    },
  );

  test('a doc with no # title is title_missing at line 1', () async {
    final report = await checkOf(
      await writeCheckProject(extra: fr('# Check the password\n\n', '')),
    );
    expect(spots(report, FindingKind.titleMissing), [
      '$loginFr:1: title_missing',
    ]);
  });

  test(
    'an undeclared section over the doc-level limits is reported at its header',
    () async {
      final report = await checkOf(
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
        unorderedEquals([
          FindingKind.linesOverLimit,
          FindingKind.charsOverLimit,
        ]),
      );
      expect(notes.every((f) => f.line == notes.first.line), isTrue);
      expect(notes.first.toJson(), containsPair('limit', anyOf(30, 600)));
    },
  );

  test('a head line "# " with no text is title_missing at line 1', () async {
    for (final head in ['# \n\n', '#   \n\n']) {
      final report = await checkOf(
        await writeCheckProject(extra: fr('# Check the password\n\n', head)),
      );
      expect(spots(report, FindingKind.titleMissing), [
        '$loginFr:1: title_missing',
      ]);
    }
  });

  test(
    'a section lint finding names the template section id, not the header slug',
    () async {
      final report = await checkOf(
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
        expect(
          finding.toJson(),
          containsPair('section', 'acceptance_criteria'),
        );
        expect(finding.message, contains('section acceptance_criteria '));
      }
    },
  );

  test(
    'a fenced example heading in the vision section is no vision entry',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: doc(
            projectDoc,
            '> en: One sign-in for every app.\n',
            '> en: One sign-in for every app.\n```\n### PV-02 — Example\n```\n',
          ),
        ),
      );
      expect(spots(report, FindingKind.visionQuoteMissing), isEmpty);
    },
  );

  test('size counts the laid-out text, not the padding on disk', () async {
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
    final report = await checkOf(project);
    expect(spots(report, FindingKind.charsOverLimit), isEmpty);
    expect(spots(report, FindingKind.formatDrift), [
      '$loginFr:1: format_drift',
    ]);
  });

  test('a section counts the blank lines format adds under its ### headings', () async {
    final body = '${'### Head\ntext\n' * 3}${'filler\n' * 32}';
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/fr.yaml':
              'sections:\n  - id: statement\n    lint:\n      max_lines: 37\n',
          ...fr('$checkPasswordStatement\n', body),
        },
      ),
    );
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.linesOverLimit,
    );
    expect(finding.toJson(), containsPair('limit', 37));
    expect(finding.toJson(), containsPair('actual', 38));
  });

  test('a doc format refuses counts its text on disk', () async {
    final report = await checkOf(
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

  group('Check the title, sections, and size limits', () {
    const edgeFrom = '1. E01 — An empty password → refused.\n';
    const rationaleFrom = 'A wrong password must not sign in.\n';
    const itemLimitTemplate = '.specstone/templates/fr.yaml';

    String padded(String start, int length) => start.padRight(length, '.');

    Future<List<Finding>> itemFindings(Directory project) async =>
        (await checkOf(project)).findings
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
      'an item over the default limit is item_over_limit with its ID',
      () async {
        final project = await withEdgeItem(640);
        final finding = (await itemFindings(project)).single;

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

    test('a paragraph with no ID is item_over_limit with no id key', () async {
      final project = await writeCheckProject(
        extra: fr(rationaleFrom, '${padded('A long rationale', 700)}\n'),
      );
      final finding = (await itemFindings(project)).single;

      expect(finding.line, lineOf(project, loginFr, 'A long rationale'));
      expect(finding.toJson(), isNot(contains('id')));
      expect(
        finding.message,
        'the item at line ${finding.line} of section rationale has 700 '
        'characters; the limit is 600',
      );
    });

    test('item over the cap only through its links gives no finding', () async {
      final links = [
        for (var i = 0; i < 8; i++) '[link](${'a' * 17}.md)',
        '[link](${'b' * 7}.md)',
      ];
      final head = '1. E01 — ${links.join(' ')} ';
      final item = '$head${'x' * (625 - head.length)}';
      final project = await writeCheckProject(extra: fr(edgeFrom, '$item\n'));
      final disk = File('${project.path}/docs/$loginFr').readAsStringSync();
      final docChars = layOutDoc(disk, fixtureDocTypeOf(loginFr)).runes.length;
      File('${project.path}/$itemLimitTemplate')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'lint:\n  max_chars: ${docChars - 1}\n'
          'sections:\n  - id: edge_cases\n    lint:\n      max_chars: 600\n',
        );
      final sizeFindings = (await checkOf(project)).findings
          .where((f) => f.kind == FindingKind.charsOverLimit)
          .map((f) => f.toJson())
          .toList();

      expect(item.length, 625);
      expect(await itemFindings(project), isEmpty);
      expect(
        sizeFindings,
        unorderedEquals([
          allOf(
            containsPair('section', 'edge_cases'),
            containsPair('actual', '\n$item'.length),
          ),
          allOf(isNot(contains('section')), containsPair('actual', docChars)),
        ]),
      );
    });

    test('a fenced code block is no item', () async {
      final project = await writeCheckProject(
        extra: {
          itemLimitTemplate: 'sections:\n  - id: verification\n    lint:\n      max_chars: 1000\n',
          ...fr(
            'Test: a wrong password is refused.\n',
            '```\n${'x' * 2000}\n```\n',
          ),
        },
      );

      expect(await itemFindings(project), isEmpty);
      final over = (await checkOf(project)).findings
          .singleWhere((f) => f.kind == FindingKind.charsOverLimit);
      expect(over.toJson(), containsPair('section', 'verification'));
    });

    test('a repeated header the formatter refuses keeps each section its own items on disk', () async {
      final project = await writeCheckProject(
        extra: fr(
          '## Rationale\n',
          '## Edge cases\n\n1. E02 — A short case → refused.\n'
              '${padded('2. E03 — A long case', 640)}\n\n## Rationale\n',
        ),
      );
      final disk = File('${project.path}/docs/$loginFr').readAsStringSync();
      final finding = (await itemFindings(project)).single;

      expect(layOutDoc(disk, fixtureDocTypeOf(loginFr)), disk);
      expect(finding.line, lineOf(project, loginFr, '2. E03'));
      expect(finding.toJson(), containsPair('section', 'edge_cases'));
      expect(finding.toJson(), containsPair('id', 'E03'));
      expect(finding.line, greaterThan(lineOf(project, loginFr, '1. E01')));
    });

    test(
      'an item of 700 characters under max_item_chars 900 is no finding',
      () async {
        final project = await withEdgeItem(
          700,
          template: 'lint:\n  max_item_chars: 900\n',
        );

        expect(await itemFindings(project), isEmpty);
      },
    );

    test(
      'an item of 901 characters under max_item_chars 900 is item_over_limit',
      () async {
        final project = await withEdgeItem(
          901,
          template: 'lint:\n  max_item_chars: 900\n',
        );

        expect(
          (await itemFindings(project)).single.toJson(),
          allOf(containsPair('limit', 900), containsPair('actual', 901)),
        );
      },
    );

    test(
      'an item of exactly the limit is no finding, one character more is one',
      () async {
        expect(await itemFindings(await withEdgeItem(600)), isEmpty);
        expect(
          (await itemFindings(await withEdgeItem(601))).single.toJson(),
          containsPair('actual', 601),
        );
        const raised = 'lint:\n  max_item_chars: 900\n';
        expect(
          await itemFindings(await withEdgeItem(900, template: raised)),
          isEmpty,
        );
      },
    );

    test('a glossary entry of 301 characters is item_over_limit and one of 300 '
        'is no finding', () async {
      Future<Directory> withTerm(int chars) => writeCheckProject(
        extra: {
          'docs/prds/GLOSSARY.md':
              '# Domain glossary\n\n## Terms\n\n'
              '${padded('- **Term** — A definition', chars)}\n',
        },
      );

      expect(await itemFindings(await withTerm(300)), isEmpty);
      final finding = (await itemFindings(await withTerm(301))).single;
      expect(finding.path, 'prds/GLOSSARY.md');
      expect(
        finding.toJson(),
        allOf(
          containsPair('section', 'terms'),
          containsPair('limit', 300),
          containsPair('actual', 301),
        ),
      );
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

      expect((await itemFindings(project)).map((f) => f.path), [loginStory]);
    });

    test('a lead paragraph over the limit is item_over_limit in section _lead', () async {
      final project = await writeCheckProject(
        extra: doc(
          loginArchitecture,
          '# Login architecture\n\n',
          '# Login architecture\n\n${padded('The lead says what the doc covers.', 687)}\n\n',
        ),
      );
      final finding = (await itemFindings(project)).single;

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

    test('a lettered item form holds no ID and takes the line form', () async {
      final project = await writeCheckProject(
        extra: fr(edgeFrom, '${padded('3. E03a — A lettered case', 640)}\n'),
      );
      final finding = (await itemFindings(project)).single;

      expect(finding.toJson(), isNot(contains('id')));
      expect(
        finding.message,
        'the item at line ${finding.line} of section edge_cases has 640 '
        'characters; the limit is 600',
      );
    });

    test('sections out of template order give the key and the line structure prints', () async {
      final project = await writeCheckProject(
        extra: fr(
          '## Statement\n\n$checkPasswordStatement\n\n## Edge cases\n\n$edgeFrom\n',
          '## Edge cases\n\n$edgeFrom\n## Statement\n\n\n\n'
              '${padded('A long statement', 700)}\n\n',
        ),
      );
      final session = openSession(project);
      addTearDown(session.close);
      final finding = (await runCheck(session)).findings
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
        (await checkOf(project)).findings.map((f) => f.kind),
        contains(FindingKind.formatDrift),
      );
    });
  });

  group('title_no_number', () {
    const layer = '.specstone/templates/fr.yaml';
    int lineOf(Directory project, String docPath, String text) =>
        File('${project.path}/docs/$docPath')
            .readAsLinesSync()
            .indexWhere((line) => line == text) +
        1;
    final numbered = fr('# Check the password', '# Check 2 passwords');

    test(
      'a title holding a digit is title_numbered at the title line',
      () async {
        final project = await writeCheckProject(
          extra: {layer: 'lint:\n  title_no_number: true\n', ...numbered},
        );
        final found = (await checkOf(project)).findings
            .where((f) => f.kind == FindingKind.titleNumbered)
            .toList();
        expect(found, hasLength(1));
        expect(
          found.single.line,
          lineOf(project, loginFr, '# Check 2 passwords'),
        );
        expect(found.single.waitsFor, WaitsFor.agent);
      },
    );

    test(
      'the same title in a doc type without the key has no finding',
      () async {
        final project = await writeCheckProject(extra: numbered);
        expect(
          (await checkOf(project)).findings.map((f) => f.kind),
          isNot(contains(FindingKind.titleNumbered)),
        );
      },
    );

    test('a title with no digit has no finding under the key', () async {
      final project = await writeCheckProject(
        extra: {layer: 'lint:\n  title_no_number: true\n'},
      );
      expect(
        (await checkOf(project)).findings.map((f) => f.kind),
        isNot(contains(FindingKind.titleNumbered)),
      );
    });
  });

  group('when_field', () {
    const layerPath = '.specstone/templates/fr.yaml';
    String layer(String values) =>
        'sections:\n  - id: input_output\n    required: true\n'
        '    when_field: {field: verify_method, values: [$values]}\n';
    final withSection = fr(
      '## Edge cases',
      '## Input / Output\n\nA password.\n\n## Edge cases',
    );

    Future<List<Finding>> found(Directory project, FindingKind kind) async => [
      for (final f in (await checkOf(project)).findings)
        if (f.kind == kind) f,
    ];

    test('a doc whose field holds a value lacking the section reports it '
        'missing', () async {
      final project = await writeCheckProject(
        extra: {layerPath: layer('test')},
      );
      final missing = await found(project, FindingKind.requiredSectionMissing);
      expect(missing, hasLength(1));
      expect(missing.single.toJson(), containsPair('section', 'input_output'));
      expect(missing.single.line, 1);
    });

    test('a doc whose field holds none of the values lacking the section has '
        'no finding', () async {
      final project = await writeCheckProject(
        extra: {layerPath: layer('demo')},
      );
      expect(await found(project, FindingKind.requiredSectionMissing), isEmpty);
    });

    test('a doc whose field holds none of the values and the section reports '
        'it at its header', () async {
      final project = await writeCheckProject(
        extra: {layerPath: layer('demo'), ...withSection},
      );
      final outside = await found(
        project,
        FindingKind.sectionOutsideFieldValue,
      );
      expect(outside, hasLength(1));
      expect(
        outside.single.line,
        File('${project.path}/docs/$loginFr')
                .readAsLinesSync()
                .indexWhere((line) => line == '## Input / Output') +
            1,
      );
      expect(outside.single.toJson(), containsPair('section', 'input_output'));
      expect(outside.single.waitsFor, WaitsFor.agent);
    });

    test('a doc whose field is unset counts as outside the values', () async {
      final project = await writeCheckProject(
        extra: {
          layerPath: layer('test'),
          ...edit(loginFr, [
            ('verify_method: test\n', ''),
            (
              '## Edge cases',
              '## Input / Output\n\nA password.\n\n## Edge cases',
            ),
          ]),
        },
      );
      expect(
        await found(project, FindingKind.sectionOutsideFieldValue),
        hasLength(1),
      );
      expect(
        (await found(
          project,
          FindingKind.requiredSectionMissing,
        )).where((f) => f.toJson()['section'] == 'input_output'),
        isEmpty,
      );
    });

    test(
      'a doc whose field holds a value and the section has no finding',
      () async {
        final project = await writeCheckProject(
          extra: {layerPath: layer('test'), ...withSection},
        );
        expect(
          await found(project, FindingKind.sectionOutsideFieldValue),
          isEmpty,
        );
        expect(
          (await found(
            project,
            FindingKind.requiredSectionMissing,
          )).where((f) => f.toJson()['section'] == 'input_output'),
          isEmpty,
        );
      },
    );
  });

  group('move hints on a doc-level size finding', () {
    const payDomain = 'specs/f02_shop/f02_pay/DOMAIN.md';
    const domainCap = '.specstone/templates/domain.yaml';
    const capLayer = 'lint:\n  max_chars: 60\n';

    String invariants(List<String> items) =>
        '# Domain\n\n## Invariants\n${items.join('\n')}\n';

    String cite(String id) => 'See [$id](../DOMAIN.md#invariants).';

    Future<Directory> shopWith(Map<String, String> docs) => writeNestedProject(
      extra: {
        domainCap: capLayer,
        for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
      },
    );

    Future<Finding> docLevel(Directory project, String docPath) async =>
        (await checkOf(project)).findings.singleWhere(
          (f) =>
              f.kind == FindingKind.charsOverLimit &&
              f.path == docPath &&
              f.line == 1,
        );

    const shopItems = [
      '- **INV-1** First rule.',
      '- **INV-2** Second rule.',
      '- **INV-3** Third rule.',
      '- **INV-4** Fourth rule.',
    ];

    test('lists each item cited only under one sub-feature, per sub-feature in the message', () async {
      final project = await shopWith({
        shopDomain: invariants(shopItems),
        cartDomain: invariants([
          '- **INV-1** Cart rule. ${cite('INV-1')}',
          '- **INV-2** Cart rule. ${cite('INV-2')}',
        ]),
        payDomain: invariants([
          '- **INV-2** Pay rule. ${cite('INV-2')}',
          '- **INV-3** Pay rule. ${cite('INV-3')}',
        ]),
      });
      final finding = await docLevel(project, shopDomain);
      expect(finding.toJson()['candidates'], [
        {'id': 'INV-1', 'under': 'shop/cart'},
        {'id': 'INV-3', 'under': 'shop/pay'},
      ]);
      expect(finding.toJson(), isNot(contains('split')));
      expect(
        finding.message,
        endsWith(
          '; INV-1 are cited only under shop/cart; '
          'INV-3 are cited only under shop/pay',
        ),
      );
    });

    test(
      'a feature with stories and no sub-feature takes the split key',
      () async {
        final project = await writeCheckProject(
          extra: {
            domainCap: capLayer,
            'docs/specs/f01_login/DOMAIN.md': invariants(shopItems),
          },
        );
        final finding = await docLevel(project, 'specs/f01_login/DOMAIN.md');
        expect(finding.toJson(), containsPair('split', 'sub_features'));
        expect(finding.toJson(), isNot(contains('candidates')));
        expect(
          finding.message,
          endsWith('; group stories into sub-features first'),
        );
      },
    );

    test(
      'a section-level finding and a PRD doc finding carry neither key',
      () async {
        final project = await writeNestedProject(
          extra: {
            domainCap: capLayer,
            '.specstone/templates/feature.yaml':
                'max_depth: 3\nlint:\n  max_chars: 60\n',
            'docs/$shopDomain': invariants(shopItems),
            'docs/$cartDomain': invariants([
              '- **INV-1** Cart rule. ${cite('INV-1')}',
            ]),
          },
        );
        final sized = (await checkOf(project)).findings.where(
          (f) =>
              f.kind == FindingKind.charsOverLimit ||
              f.kind == FindingKind.linesOverLimit,
        );
        final other = sized.where(
          (f) =>
              f.path.startsWith('prds/') || f.toJson().containsKey('section'),
        );
        expect(other, isNotEmpty);
        for (final finding in other) {
          expect(finding.toJson(), isNot(contains('candidates')));
          expect(finding.toJson(), isNot(contains('split')));
        }
      },
    );

    test(
      'items no doc cites leave a sub-feature feature with neither key',
      () async {
        final project = await shopWith({shopDomain: invariants(shopItems)});
        final finding = await docLevel(project, shopDomain);
        expect(finding.toJson(), isNot(contains('candidates')));
        expect(finding.toJson(), isNot(contains('split')));
        expect(finding.message, isNot(contains('cited only under')));
      },
    );

    test(
      'an item an override line links is left out of the candidates',
      () async {
        final project = await shopWith({
          shopDomain: invariants(shopItems),
          cartDomain: invariants([
            '- **INV-1** Cart rule. ${cite('INV-1')}',
            '- **INV-2** Cart rule. ${cite('INV-2')}',
            '- Overrides: [INV-1](../DOMAIN.md#invariants) — differs, because stock',
          ]),
        });
        final finding = await docLevel(project, shopDomain);
        expect(finding.toJson()['candidates'], [
          {'id': 'INV-2', 'under': 'shop/cart'},
        ]);
        expect(
          finding.message,
          endsWith('; INV-2 are cited only under shop/cart'),
        );
        expect(finding.message, isNot(contains('INV-1')));
      },
    );

    test('an item cited under a sub-feature and from outside every sub-feature is no candidate', () async {
      final project = await shopWith({
        shopDomain: invariants(shopItems),
        cartDomain: invariants(['- **INV-1** Cart rule. ${cite('INV-1')}']),
        'specs/f02_shop/API.md':
            '# Shop API\n\n## Operations\n### addItem\n'
            'See [INV-1](DOMAIN.md#invariants).\n',
      });
      final finding = await docLevel(project, shopDomain);
      expect(finding.toJson(), isNot(contains('candidates')));
    });

    test(
      'lists two items cited only under one sub-feature, comma separated',
      () async {
        final project = await shopWith({
          shopDomain: invariants(shopItems),
          cartDomain: invariants([
            '- **INV-1** Cart rule. ${cite('INV-1')}',
            '- **INV-3** Cart rule. ${cite('INV-3')}',
          ]),
        });
        final finding = await docLevel(project, shopDomain);
        expect(finding.toJson()['candidates'], [
          {'id': 'INV-1', 'under': 'shop/cart'},
          {'id': 'INV-3', 'under': 'shop/cart'},
        ]);
        expect(
          finding.message,
          endsWith('; INV-1, INV-3 are cited only under shop/cart'),
        );
      },
    );

    test('a spec doc of a feature with no sub-feature and no story takes neither key', () async {
      final project = await writeCheckProject(
        extra: {
          domainCap: capLayer,
          'docs/prds/features/f03_empty/FEATURE.md': '# Empty\n',
          'docs/specs/f03_empty/DOMAIN.md': invariants(shopItems),
        },
      );
      final finding = await docLevel(project, 'specs/f03_empty/DOMAIN.md');
      expect(finding.toJson(), isNot(contains('candidates')));
      expect(finding.toJson(), isNot(contains('split')));
      expect(
        finding.message,
        'the doc has ${finding.toJson()['actual']} characters; the limit is 60',
      );
    });
  });

  group('size and shape edge cases', () {
    test('a requirement with no Statement section carries section statement in its finding', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: fr('## Statement\n\n$checkPasswordStatement\n\n', ''),
        ),
      );
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.requiredSectionMissing,
      );
      expect(finding.toJson(), containsPair('section', 'statement'));
    });

    group('a doc whose frontmatter is not valid YAML', () {
      const badStart = '---\nverify_method: "test\n';
      String docOf(int bodyLines) =>
          '$badStart${'x: y\n' * 30}---\n\n# Check the password\n\n## Statement\n\n$checkPasswordStatement\n\n${'x\n' * (bodyLines - 3)}';

      Future<CheckReport> reportOf(int bodyLines) async => await checkOf(
        await writeCheckProject(extra: {'docs/$loginFr': docOf(bodyLines)}),
      );

      test(
        'counts its body lines alone, 400 of them under the limit',
        () async {
          final report = await reportOf(400);
          expect(spots(report, FindingKind.frontmatterInvalid), hasLength(1));
          expect(spots(report, FindingKind.linesOverLimit), isEmpty);
        },
      );

      test(
        'counts 401 body lines as over the limit, the frontmatter left out',
        () async {
          final finding = (await reportOf(401)).findings
              .singleWhere((f) => f.kind == FindingKind.linesOverLimit);
          expect(finding.toJson(), containsPair('limit', 400));
          expect(finding.toJson(), containsPair('actual', 401));
        },
      );
    });

    test('a journey scenario copy counts toward the journey section limit and gives no item finding', () async {
      final given = '- **Given** ${'x' * 710}';
      const journeyPath = 'prds/journeys/login/JOURNEY.md';
      final project = await writeCheckProject(
        extra: {
          '.specstone/templates/journey.yaml':
              'sections:\n  - id: steps\n    lint:\n      max_chars: 400\n',
          ...doc(
            loginStory,
            '- **Given** an account\n- **When** the Agent signs in',
            '$given\n- **When** the Agent signs in',
          ),
          'docs/$journeyPath':
              '# Sign in\n\n## Goal\n\nAn Agent reaches the home page.\n\n## Steps\n\n### 1. Start\n\nstep: email_login S1\n${generatedOpenMarker('scenario_copy')}\n$given\n- **When** the Agent signs in\n$generatedEndMarker\n',
        },
      );
      final onJourney = (await checkOf(project)).findings
          .where((f) => f.path == journeyPath)
          .toList();
      final limit = onJourney.singleWhere(
        (f) => f.kind == FindingKind.charsOverLimit,
      );
      expect(limit.toJson(), containsPair('section', 'steps'));
      expect(limit.toJson(), containsPair('limit', 400));
      expect(limit.toJson()['actual'], greaterThan(710));
      expect(
        onJourney.where((f) => f.kind == FindingKind.itemOverLimit),
        isEmpty,
      );
    });

    test('a record whose frontmatter lines push its file past 60000 characters is chars_over_limit, its lines under the limit', () async {
      final record =
          "---\nstatuses:\n  - 'email_login:implemented'\n"
          '${'  # ${'c' * 200}\n' * 300}---\n\n# Login implementation\n${'x\n' * 40}';
      expect(record.length, greaterThan(60000));
      final report = await checkOf(
        await writeCheckProject(extra: {loginRecord: record}),
      );
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.charsOverLimit,
      );
      expect(finding.path, loginRecord);
      expect(finding.toJson(), containsPair('limit', 60000));
      expect(finding.toJson()['actual'], greaterThan(60000));
      expect(spots(report, FindingKind.linesOverLimit), isEmpty);
    });

    test('a feature doc with no # line, or an empty one, is title_missing at line 1', () async {
      for (final head in ['', '# \n\n']) {
        final report = await checkOf(
          await writeCheckProject(
            extra: doc(loginFeature, '# Login\n\n', head),
          ),
        );
        expect(spots(report, FindingKind.titleMissing), [
          '$loginFeature:1: title_missing',
        ]);
      }
    });
  });

  group('a blank required section', () {
    const layerPath = '.specstone/templates/fr.yaml';
    const rationaleSection =
        '## Rationale\n\nA wrong password must not sign in.\n\n';
    String layer(String values) =>
        'sections:\n  - id: input_output\n    required: true\n'
        '    when_field: {field: verify_method, values: [$values]}\n';

    Future<List<Finding>> missingOf(Directory project, String section) async =>
        [
          for (final f in (await checkOf(project)).findings)
            if (f.kind == FindingKind.requiredSectionMissing &&
                f.toJson()['section'] == section)
              f,
        ];

    test('a blank required section is missing at its header', () async {
      final project = await writeCheckProject(
        extra: fr(rationaleSection, '## Rationale\n\n'),
      );
      final missing = await missingOf(project, 'rationale');
      expect(missing, hasLength(1));
      expect(
        missing.single.line,
        lineOfFirst(project, loginFr, '## Rationale'),
      );
      expect(missing.single.message, 'required section rationale is empty');
    });

    test(
      'a blank section required by its when_field is missing at its header',
      () async {
        final project = await writeCheckProject(
          extra: {
            layerPath: layer('test'),
            ...fr('## Edge cases', '## Input / Output\n\n## Edge cases'),
          },
        );
        final missing = await missingOf(project, 'input_output');
        expect(missing, hasLength(1));
        expect(
          missing.single.line,
          lineOfFirst(project, loginFr, '## Input / Output'),
        );
        expect(
          missing.single.message,
          'required section input_output is empty',
        );
      },
    );

    test(
      'spaces, tabs, and CRLF breaks alone leave a required section blank',
      () async {
        final project = await writeCheckProject(
          extra: {
            for (final MapEntry(:key, :value) in fr(
              rationaleSection,
              '## Rationale\n  \n\t\n\n',
            ).entries)
              key: value.replaceAll('\n', '\r\n'),
          },
        );
        expect(
          File('${project.path}/docs/$loginFr').readAsStringSync(),
          contains('\r\n'),
        );
        final missing = await missingOf(project, 'rationale');
        expect(missing, hasLength(1));
        expect(
          missing.single.line,
          lineOfFirst(project, loginFr, '## Rationale'),
        );
      },
    );

    test('a blank last section with no final break is missing', () async {
      final project = await writeCheckProject(
        extra: fr(
          '## Verification\n\nTest: a wrong password is refused.\n',
          '## Verification',
        ),
      );
      final missing = await missingOf(project, 'verification');
      expect(missing, hasLength(1));
      expect(
        missing.single.line,
        lineOfFirst(project, loginFr, '## Verification'),
      );
    });

    test(
      'an unformattable doc still reports a blank required section',
      () async {
        final project = await writeCheckProject(
          extra: fr(
            rationaleSection,
            '## Edge cases\n\n2. E02 — Another case → refused.\n\n## Rationale\n\n',
          ),
        );
        final disk = File('${project.path}/docs/$loginFr').readAsStringSync();
        expect(
          formatDoc(Doc.parse(disk), fixtureDocTypeOf(loginFr)),
          isA<Refused>(),
        );
        final missing = await missingOf(project, 'rationale');
        expect(missing, hasLength(1));
        expect(
          missing.single.line,
          lineOfFirst(project, loginFr, '## Rationale'),
        );
      },
    );

    test(
      'a blank required section under broken frontmatter is still missing',
      () async {
        final project = await writeCheckProject(
          extra: edit(loginFr, [
            ('verify_method: test\n', 'verify_method: "test\n'),
            ('## Statement\n\n$checkPasswordStatement\n\n', ''),
            (rationaleSection, '## Rationale\n\n'),
          ]),
        );
        final report = await checkOf(project);
        expect(spots(report, FindingKind.frontmatterInvalid), hasLength(1));
        final missing = await missingOf(project, 'rationale');
        expect(missing, hasLength(1));
        expect(
          missing.single.line,
          lineOfFirst(project, loginFr, '## Rationale'),
        );
      },
    );

    test('one non-blank line of any kind keeps a required section', () async {
      final bodies = [
        '### A subsection',
        'TBR — x',
        '<!-- a note -->',
        '${generatedOpenMarker('scenario_copy')}\n$generatedEndMarker',
        '<reason, assumptions, related requirements, design constraints>',
      ];
      for (final body in bodies) {
        final project = await writeCheckProject(
          extra: fr(rationaleSection, '## Rationale\n\n$body\n\n'),
        );
        expect(await missingOf(project, 'rationale'), isEmpty, reason: body);
      }
    });

    test('a blank optional section is not missing', () async {
      final project = await writeCheckProject(
        extra: fr('## Edge cases', '## Behavior\n\n## Edge cases'),
      );
      expect(await missingOf(project, 'behavior'), isEmpty);
    });

    test(
      'a blank when_field section outside its values is not missing',
      () async {
        final project = await writeCheckProject(
          extra: {
            layerPath: layer('demo'),
            ...fr('## Edge cases', '## Input / Output\n\n## Edge cases'),
          },
        );
        final report = await checkOf(project);
        expect(spots(report, FindingKind.requiredSectionMissing), isEmpty);
        expect(
          spots(report, FindingKind.sectionOutsideFieldValue),
          hasLength(1),
        );
      },
    );
  });
}
