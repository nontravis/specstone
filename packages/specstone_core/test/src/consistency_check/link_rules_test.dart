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
        'Users forget passwords; see [reset](us02_reset_password/story.md).',
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
      '$loginFeature:11: link_unresolved: link target us02_reset_password/story.md is no doc',
    );
  });

  test('f04/us02/s5, f04/us02/fr04/e01: a link to a deleted story names the link and its line', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginFeature,
          'Users forget passwords.',
          'Users forget passwords; see [reset](us02_reset_password/story.md).',
        ),
      ),
    );
    expect(
      report.findings.single.textLine,
      '$loginFeature:11: link_unresolved: link target us02_reset_password/story.md is no doc',
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

  test('f04/us02/fr04/e03, f04/us02/fr04/e04, f04/us02/fr04/e06, f04/us02/fr04/e07, f04/us01/fr06/e04: an anchor, a '
      'URL, a picture, a link outside the checked folders, and prose resolve or are no link', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(
            loginFeature,
            'Users forget passwords.',
            'Users forget passwords: [roles](../../PROJECT.md#role), [site](https://example.com), '
                '![diagram](diagram.png), [idea](../../../notes/idea.md), and story.md in prose.',
          ),
          'docs/notes/idea.md': '# Idea\n\n[gone](gone.md)\n',
        },
      ),
    );
    expect(report.findings, isEmpty);
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
