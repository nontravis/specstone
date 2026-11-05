// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

void main() {
  test("f04/us02/fr04/e01, cc-s03/inv14, FM5: a broken link's line comes from the index, so check parses no doc text", () async {
    final project = await writeCheckProject(
      extra: doc(
        loginFeature,
        'Users forget passwords.',
        'Users forget passwords; see [reset](us02_reset_password/USER_STORY.md).',
      ),
    );
    final anHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    for (final file in Directory(
      '${project.path}/docs',
    ).listSync(recursive: true).whereType<File>()) {
      file.setLastModifiedSync(anHourAgo);
    }
    checkOf(project);
    // The stat is unchanged, so the next refresh keeps the row with its text
    // edited to hold no link.
    sqlite3.open('${project.path}/$indexFilePath')
      ..execute(
        "UPDATE docs SET text = replace(text, '](', '] (') WHERE doc_path = ?",
        [loginFeature],
      )
      ..close();
    final report = checkOf(project);
    expect(
      report.findings.single.textLine,
      '$loginFeature:11: link_unresolved: link target us02_reset_password/USER_STORY.md is no doc',
    );
  });

  test('f04/us02/s5, f04/us02/fr04/e01: a link to a deleted story names the link and its line', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'Users forget passwords; see [reset](us02_reset_password/USER_STORY.md).',
        ),
      ),
    );
    expect(
      report.findings.single.textLine,
      '$loginFeature:11: link_unresolved: link target us02_reset_password/USER_STORY.md is no doc',
    );
  });

  test('f04/us02/fr04/e02: a persona value no persona carries is doc_ref_unresolved', () async {
    final story = doc(
      loginStory,
      '  - app/lib/login.dart:SignInPage\n',
      '  - app/lib/login.dart:SignInPage\npersona:\n  - buyer\n',
    );
    final report = checkOf(await writeCheckProject(extra: story));
    expect(spots(report), ['$loginStory:8: doc_ref_unresolved']);
    expect(
      report.findings.single.toJson(),
      allOf(containsPair('field', 'persona'), containsPair('value', 'buyer')),
    );
    expect(report.findings.single.message, 'persona value buyer names no doc');
    final withBuyer = checkOf(
      await writeCheckProject(
        extra: {
          ...story,
          'docs/prds/personas/buyer/PERSONA.md': '---\nrole: Agent\npriority: primary\nbasis: proto\n---\n\n# Buyer\n',
        },
      ),
    );
    expect(spots(withBuyer, FindingKind.docRefUnresolved), isEmpty);
  });

  test('consistency_check/find_broken_pointers/resolve_doc_links E02: an empty '
      'depends_on list reports nothing', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          '  - PG-01\n---',
          '  - PG-01\ndepends_on: []\n---',
        ),
      ),
    );
    expect(report.findings, isEmpty);
  });

  test('consistency_check/find_broken_pointers/resolve_doc_links E02: a scalar '
      'depends_on is field_value_mismatch at the key line', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          '  - PG-01\n---',
          '  - PG-01\ndepends_on: login\n---',
        ),
      ),
    );
    expect(spots(report), ['$loginFeature:6: field_value_mismatch']);
  });

  test('consistency_check/find_broken_pointers/resolve_doc_links E02: an empty '
      'depends_on item is doc_ref_unresolved at the item line', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          '  - PG-01\n---',
          '  - PG-01\ndepends_on:\n  - ""\n---',
        ),
      ),
    );
    expect(spots(report), ['$loginFeature:7: doc_ref_unresolved']);
  });

  test(
    'consistency_check/find_broken_pointers/resolve_doc_links E02: a depends_on value '
    'no feature carries is doc_ref_unresolved; a feature resolves only',
    () async {
      final dependsOn = doc(
        loginFeature,
        '  - PG-01\n---',
        '  - PG-01\ndepends_on:\n  - checkout\n  - login/email_login\n  - login\n---',
      );
      final report = checkOf(await writeCheckProject(extra: dependsOn));
      expect(spots(report), [
        '$loginFeature:7: doc_ref_unresolved',
        '$loginFeature:8: doc_ref_unresolved',
      ]);
      expect(
        report.findings.first.message,
        'depends_on value checkout names no doc',
      );
      final withCheckout = checkOf(
        await writeCheckProject(
          extra: {
            ...dependsOn,
            'docs/prds/features/f02_checkout/FEATURE.md':
                checkProjectFiles()['docs/$loginFeature']!.replaceFirst(
                  '# Login',
                  '# Checkout',
                ),
          },
        ),
      );
      expect(spots(withCheckout, FindingKind.docRefUnresolved), [
        '$loginFeature:8: doc_ref_unresolved',
      ]);
    },
  );

  test('f04/us02/fr04/e03, f04/us02/fr04/e04, f04/us02/fr04/e06, f04/us02/fr04/e07, f04/us01/fr06/e04: an anchor, a '
      'URL, a picture, a link outside the checked folders, and prose resolve or are no link', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(
            loginFeature,
            'Users forget passwords.',
            'Users forget passwords: [roles](../../PROJECT.md#role), [site](https://example.com), '
                '![diagram](diagram.png), [idea](../../../notes/idea.md), and USER_STORY.md in prose.',
          ),
          'docs/notes/idea.md': '# Idea\n\n[gone](gone.md)\n',
          'docs/prds/features/f01_login/diagram.png': 'png',
        },
      ),
    );
    expect(report.findings, isEmpty);
  });

  group('link_target_missing', () {
    const picture = 'docs/prds/features/f01_login/flow chart.png';

    List<String> missingOf(Directory project) => [
      for (final f in checkOf(project).findings)
        if (f.kind == FindingKind.linkTargetMissing) f.textLine,
    ];

    Map<String, String> linking(String text) => doc(
      loginFeature,
      'Users forget passwords.',
      'Users forget passwords; $text',
    );

    test('f04/us02/fr04/e10, PS-R2, M6: a link out of the docs root to a file that is not there names the project path', () async {
      final project = await writeCheckProject(
        extra: doc(
          gnfrDoc,
          'N/A — none applies.',
          'See [x](../../../docs/prds/d03_non_functional.md).',
        ),
      );
      expect(spots(checkOf(project), FindingKind.linkTargetMissing), [
        'prds/GNFR.md:9: link_target_missing',
      ]);
      expect(missingOf(project), [
        'prds/GNFR.md:9: link_target_missing: link target ../../../docs/prds/d03_non_functional.md is missing at ../docs/prds/d03_non_functional.md',
      ]);
      final finding = checkOf(project).findings
          .firstWhere((f) => f.kind == FindingKind.linkTargetMissing);
      expect(
        finding.toJson(),
        allOf(
          containsPair('target', '../../../docs/prds/d03_non_functional.md'),
          containsPair('path', '../docs/prds/d03_non_functional.md'),
        ),
      );
      expect(finding.kind.isProjectLevel, isFalse);
    });

    test('f04/us02/fr04/e11, PS-R3: a picture with no file is a finding inside docs too', () async {
      final project = await writeCheckProject(
        extra: linking('![flow](flow.png)'),
      );
      expect(missingOf(project), [
        '$loginFeature:11: link_target_missing: link target flow.png is missing at docs/prds/features/f01_login/flow.png',
      ]);
    });

    test(
      'f04/us02/fr04/e11: a picture whose file is there is no finding',
      () async {
        final project = await writeCheckProject(
          extra: {
            ...linking('![flow](flow.png)'),
            'docs/prds/features/f01_login/flow.png': 'png',
          },
        );
        expect(missingOf(project), isEmpty);
      },
    );

    test('f04/us02/fr04/e11, PS-R2: the target is reported as written while the escape is checked decoded', () async {
      final missing = await writeCheckProject(
        extra: linking('![flow](flow%20chart.png#top)'),
      );
      expect(missingOf(missing), [
        '$loginFeature:11: link_target_missing: link target flow%20chart.png#top is missing at docs/prds/features/f01_login/flow chart.png',
      ]);
      final present = await writeCheckProject(
        extra: {...linking('![flow](flow%20chart.png#top)'), picture: 'png'},
      );
      expect(missingOf(present), isEmpty);
    });

    test('f04/us02/fr04/e11: a query is left out of the checked path', () async {
      final missing = await writeCheckProject(
        extra: linking('![a](a.png?raw=1)'),
      );
      expect(missingOf(missing), [
        '$loginFeature:11: link_target_missing: link target a.png?raw=1 is missing at docs/prds/features/f01_login/a.png',
      ]);
      final present = await writeCheckProject(
        extra: {
          ...linking('![a](a.png?raw=1)'),
          'docs/prds/features/f01_login/a.png': 'png',
        },
      );
      expect(missingOf(present), isEmpty);
    });

    test('f04/us02/fr04, M6: an existing folder counts as present', () async {
      final project = await writeCheckProject(
        extra: {
          ...linking('[assets](assets/)'),
          'docs/prds/features/f01_login/assets/a.txt': 'a',
        },
      );
      expect(missingOf(project), isEmpty);
    });

    test('f04/us02/fr04/e12: a link to an existing file outside the project is no finding', () async {
      final outside = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}specstone_e12_${DateTime.now().microsecondsSinceEpoch}.txt',
      )..writeAsStringSync('x');
      addTearDown(outside.deleteSync);
      final project = await writeCheckProject(
        extra: linking('[o](../../../../../${outside.uri.pathSegments.last})'),
      );
      expect(project.parent.path, Directory.systemTemp.path);
      expect(missingOf(project), isEmpty);
    });

    test('f04/us02/fr04/e13: a web address, mailto, and a rooted path are no finding', () async {
      final project = await writeCheckProject(
        extra: linking(
          '[w](https://example.com/a.png) [m](mailto:a@b.c) [r](/abs/x.md) [s](#top)',
        ),
      );
      expect(missingOf(project), isEmpty);
    });

    test('f04/us02/fr04/e14, PS-R3: a missing in-tree .md link stays link_unresolved only', () async {
      final project = await writeCheckProject(extra: linking('[g](gone.md)'));
      expect(missingOf(project), isEmpty);
      expect(spots(checkOf(project), FindingKind.linkUnresolved), [
        '$loginFeature:11: link_unresolved',
      ]);
    });
  });

  test('f04/us02/fr04/e05, f04/us01/fr01/e04, f04/us01/fr06/e03: an old-format, untyped doc gets its links checked, '
      'and a DocPath target checks it alone', () async {
    final project = await writeCheckProject(
      extra: {'docs/prds/d01_context.md': '# Context\n\n[gone](gone.md)\n'},
    );
    const expected = [
      'prds/d01_context.md:1: untyped_doc',
      'prds/d01_context.md:3: link_unresolved',
    ];
    expect(spots(checkOf(project)), expected);
    expect(spots(checkOf(project, target: 'prds/d01_context.md')), expected);
  });

  test(
    'f04/us02/fr04: two links to one deleted doc are two findings',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: doc(
            loginFeature,
            'Users forget passwords.',
            'See [a](gone.md).\nSee [b](gone.md) again.',
          ),
        ),
      );
      expect(spots(report), [
        '$loginFeature:11: link_unresolved',
        '$loginFeature:12: link_unresolved',
      ]);
    },
  );

  test('f04/us01/fr06/e03: a broken link to a file outside the checked folders is reported', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'See [idea](../../../notes/gone.md).',
        ),
      ),
    );
    expect(
      report.findings.single.textLine,
      '$loginFeature:11: link_unresolved: link target ../../../notes/gone.md is no doc',
    );
  });

  test('f04/us02/fr04: an angle-bracket destination with a space is shown as written', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'See [a](<gone one.md>).',
        ),
      ),
    );
    expect(
      report.findings.single.textLine,
      '$loginFeature:11: link_unresolved: link target gone one.md is no doc',
    );
  });

  test('f04/us02/fr04: a non-ASCII destination is shown as written', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'x\nSee [a](ไทย.md).',
        ),
      ),
    );
    expect(
      report.findings.single.textLine,
      '$loginFeature:12: link_unresolved: link target ไทย.md is no doc',
    );
  });

  test('f04/us02/fr04: reference links sit on the line of their use, definitions in any order', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'See [a][r2].\nAnd [b][r1].\n\n[r1]: x.md\n[r2]: y.md\n\n```\n[c](fenced.md)\n```',
        ),
      ),
    );
    expect(
      [for (final f in report.findings) f.textLine],
      [
        '$loginFeature:11: link_unresolved: link target y.md is no doc',
        '$loginFeature:12: link_unresolved: link target x.md is no doc',
      ],
    );
  });

  test(
    'f04/us02/fr04: wrapped link text does not displace the next broken link',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: doc(
            loginFeature,
            'Users forget passwords.',
            'See [long\ntext](gone-a.md).\n\nAnd [b](gone-b.md).',
          ),
        ),
      );
      expect(
        [for (final f in report.findings) f.textLine],
        [
          '$loginFeature:11: link_unresolved: link target gone-a.md is no doc',
          '$loginFeature:14: link_unresolved: link target gone-b.md is no doc',
        ],
      );
    },
  );

  test('f04/us02/fr04: a balanced () in a destination and [] in link text are placed', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'See [a](x(1).md).\nAnd [see [x]](gone.md).',
        ),
      ),
    );
    expect(
      [for (final f in report.findings) f.textLine],
      [
        '$loginFeature:11: link_unresolved: link target x(1).md is no doc',
        '$loginFeature:12: link_unresolved: link target gone.md is no doc',
      ],
    );
  });

  test('f04/us02/fr04/e09, cc-s03/inv15, LP4: a doc the parser fails on gets markdown_unparsed at line 1', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'Users forget passwords.\n\n[a]:<b\\',
        ),
      ),
    );
    expect(
      [for (final f in report.findings) f.textLine],
      [
        '$loginFeature:1: markdown_unparsed: the markdown parser failed on this doc; its links are not checked',
      ],
    );
    expect(report.warnings, isEmpty);
  });
}
