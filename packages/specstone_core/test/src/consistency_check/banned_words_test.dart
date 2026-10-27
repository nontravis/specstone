// The expected texts are plan literals kept as written.

import 'package:specstone_core/src/consistency_check/banned_words.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

void main() {
  test('f04/us01/s4, f04/us01/fr05/e01: fast counts in the Statement only, not in the Rationale', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: edit(loginFr, [
          (
            checkPasswordStatement,
            'The system shall refuse a wrong password fast.',
          ),
          (
            'A wrong password must not sign in.',
            'A fast wrong password must not sign in.',
          ),
        ]),
      ),
    );
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.bannedWord,
    );
    expect(finding.line, 15);
    expect(
      finding.toJson(),
      allOf(containsPair('word', 'fast'), containsPair('section', 'statement')),
    );
  });

  test('f04/us01/fr05/e02: a doc-level word and a section word in one section are both reported', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/fr.yaml': 'lint:\n  banned_words: [simply]\n',
          ...fr(
            checkPasswordStatement,
            'The system shall simply refuse a wrong password fast.',
          ),
        },
      ),
    );
    expect(
      report.findings
          .where((f) => f.kind == FindingKind.bannedWord)
          .map((f) => f.toJson()['word']),
      ['fast', 'simply'],
    );
  });

  test('f04/us01/fr05/e03: a gnfr section bans the word on its Statement lines only', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: edit(gnfrDoc, [
          (
            loginNfrStatement,
            '- **Statement:** The system shall answer a sign-in fast.',
          ),
          (
            '- **Rationale:** Users wait.',
            '- **Rationale:** Users want it fast.',
          ),
        ]),
      ),
    );
    expect(spots(report, FindingKind.bannedWord), ['$gnfrDoc:5: banned_word']);
  });

  test('f04/us01/fr05/e04: allowed_words free a word everywhere, or in their section only', () async {
    final everywhere = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/fr.yaml': 'lint:\n  allowed_words: [safe]\n',
          ...fr(
            checkPasswordStatement,
            'The system shall keep the password safe.',
          ),
        },
      ),
    );
    expect(spots(everywhere, FindingKind.bannedWord), isEmpty);
    final oneSection = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/fr.yaml': 'lint:\n  banned_words: [safe]\nsections:\n  - id: statement\n    lint:\n      allowed_words: [safe]\n',
          ...edit(loginFr, [
            (
              checkPasswordStatement,
              'The system shall keep the password safe.',
            ),
            ('A wrong password must not sign in.', 'Safe sign-in.'),
          ]),
        },
      ),
    );
    expect(spots(oneSection, FindingKind.bannedWord), [
      '$loginFr:21: banned_word',
    ]);
  });

  test('f04/us01/fr05/e05, f04/us01/fr05/e07: letter case is ignored, other words are not matched, a phrase spans '
      'spaces', () async {
    expect(bannedWordPattern('fast').hasMatch('Fast'), isTrue);
    expect(bannedWordPattern('fast').hasMatch('fastest'), isFalse);
    expect(bannedWordPattern('safe').hasMatch('safe-area'), isFalse);
    expect(bannedWordPattern('etc.').hasMatch('and so on, etc.'), isTrue);
    expect(bannedWordPattern('ad hoc').hasMatch('an ad  hoc rule'), isTrue);
    expect(bannedWordPattern('ad hoc').hasMatch('adhoc'), isFalse);
  });

  test('f04/us01/fr05/e06: a software-tech spec doc type bans no word at either level', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginApi,
          'Signs the Agent in.',
          'Signs the Agent in fast, and this is easy.',
        ),
      ),
    );
    expect(spots(report, FindingKind.bannedWord), isEmpty);
  });
}
