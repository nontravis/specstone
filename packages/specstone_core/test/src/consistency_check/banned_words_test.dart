// The expected texts are plan literals kept as written.

import 'package:specstone_core/src/consistency_check/banned_words.dart';
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

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
    expect(finding.line, 14);
    expect(
      finding.toJson(),
      allOf(containsPair('word', 'fast'), containsPair('section', 'statement')),
    );
  });

  test(
    'a doc-level word and a section word in one section are both reported',
    () async {
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
    },
  );

  test('a gnfr section bans the word on its Statement lines only', () async {
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
    expect(spots(report, FindingKind.bannedWord), ['$gnfrDoc:11: banned_word']);
  });

  test(
    'allowed_words free a word everywhere, or in their section only',
    () async {
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
        '$loginFr:22: banned_word',
      ]);
    },
  );

  test('f04/us01/fr05/e05, f04/us01/fr05/e07: letter case is ignored, other words are not matched, a phrase spans '
      'spaces', () async {
    expect(bannedWordPattern('fast').hasMatch('Fast'), isTrue);
    expect(bannedWordPattern('fast').hasMatch('fastest'), isFalse);
    expect(bannedWordPattern('safe').hasMatch('safe-area'), isFalse);
    expect(bannedWordPattern('etc.').hasMatch('and so on, etc.'), isTrue);
    expect(bannedWordPattern('ad hoc').hasMatch('an ad  hoc rule'), isTrue);
    expect(bannedWordPattern('ad hoc').hasMatch('adhoc'), isFalse);
  });

  test('a software-tech spec doc type bans no word at either level', () async {
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

  test(
    'a banned-word finding names the template section id, not the header slug',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/templates/user_story.yaml':
                'lint:\n  banned_words: [sketch]\n',
            ...edit(loginStory, [
              ('## Acceptance Criteria\n', '## Acceptance criteria\n'),
              (
                'an account\n- **When** the Agent signs in',
                'a sketch\n- **When** the Agent signs in',
              ),
            ]),
          },
        ),
      );
      final finding = report.findings.singleWhere(
        (f) => f.kind == FindingKind.bannedWord,
      );
      expect(finding.toJson(), containsPair('section', 'acceptance_criteria'));
      expect(finding.message, 'sketch is a banned word in acceptance_criteria');
    },
  );

  test('a phrase and its last word are both reported on one line', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/fr.yaml':
              'lint:\n  banned_words: [as appropriate, appropriate]\n',
          ...fr(
            checkPasswordStatement,
            'The system shall refuse a wrong password as appropriate.',
          ),
        },
      ),
    );
    expect(
      report.findings
          .where((f) => f.kind == FindingKind.bannedWord)
          .map((f) => f.toJson()['word']),
      unorderedEquals(['as appropriate', 'appropriate']),
    );
  });

  Future<List<Finding>> bannedIn(String statement) async {
    final report = checkOf(
      await writeCheckProject(extra: fr(checkPasswordStatement, statement)),
    );
    return report.findings
        .where((f) => f.kind == FindingKind.bannedWord)
        .toList();
  }

  test('a word inside a single-backtick code span is not reported', () async {
    expect(await bannedIn('The system shall refuse a `fast` login.'), isEmpty);
  });

  test('a word inside a double-backtick code span is not reported', () async {
    expect(
      await bannedIn('The system shall refuse a ``fast`x`` login.'),
      isEmpty,
    );
  });

  test('a bare word on the line of a code span is still reported', () async {
    final found = await bannedIn(
      'The system shall refuse `fast` and fast logins.',
    );
    expect(found.map((f) => f.toJson()['word']), ['fast']);
  });

  test('an unclosed backtick run leaves the rest of the line prose', () async {
    final found = await bannedIn('The system shall refuse ``fast` logins.');
    expect(found.map((f) => f.toJson()['word']), ['fast']);
  });

  test('a word inside a fenced code block is not reported', () async {
    expect(
      await bannedIn(
        'The system shall refuse a wrong password.\n```\nfast\n```',
      ),
      isEmpty,
    );
  });

  test('cc-s03/inv9: a word builds its pattern once per run', () async {
    final session = openSession(await writeCheckProject());
    addTearDown(session.close);
    final context = CheckContext(session);
    expect(
      context.bannedPatternOf('fast'),
      same(context.bannedPatternOf('fast')),
    );
    expect(
      context.bannedPatternOf('fast'),
      isNot(same(context.bannedPatternOf('safe'))),
    );
    expect(
      context.bannedPatternOf('ad hoc').hasMatch('an ad  hoc rule'),
      isTrue,
    );
  });
}
