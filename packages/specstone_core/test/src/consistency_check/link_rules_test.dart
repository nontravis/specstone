// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

void main() {
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
}
