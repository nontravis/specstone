import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/index_query/sync_group_file.dart';
import 'package:specstone_core/src/index_query/sync_prefill.dart'
    show syncVerdictMarker, syncVerdictsOf;
import 'package:specstone_core/src/index_query/sync_work.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/git_repo.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/per_fr_row_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';

const _login = 'app/lib/login.dart';
const _other = 'app/lib/other.dart';
const _signIn = 'app/lib/signin.dart';
const _stockTest = 'app/test/stock_test.dart';
const _stockName = 'refuses a sold-out item';
const _stockTestText =
    "void main() {\n  test('refuses an empty cart', () {});\n"
    "  test('$_stockName', () {});\n}\n";
const _staleStamp = '0123456789ab';
const _docLine = r'^==> doc · (\S+) \(\w+\) · (\S+) <==$';

void _append(String project, String file, int lines) {
  File('$project/$file').writeAsStringSync(
    [for (var i = 0; i < lines; i++) 'int v$i = $i;\n'].join(),
    mode: FileMode.append,
  );
}

/// Writes the check fixture, with a second code file, as a git repository
/// with its first commit made.
Future<Directory> _committedProject({
  Set<String> unfingerprinted = const {},
  Map<String, String> extra = const {},
}) async {
  final project = await writeCheckProject(
    extra: {_other: 'class Other {}\n', ...extra},
    unfingerprinted: unfingerprinted,
  );
  expect(git(project, ['init', '-q']).exitCode, 0);
  commitAll(project, 'first');
  return project;
}

/// Returns the code part of the group of [scope] in the check of [project].
Future<String> _partOf(Directory project, String scope) async {
  final session = openSession(project);
  addTearDown(session.close);
  final report = await runCheck(session);
  final group = syncGroupsOf(
    CheckContext(session),
    report,
  ).firstWhere((group) => group.scope == scope);
  return syncCodePart(
    session,
    group,
    syncVerdictsOf(session, group).judgedDocs,
  );
}

void main() {
  test('a changed file an FR points at prints its diff then the FR', () async {
    final project = await _committedProject();
    _append(project.path, _login, 1);

    final part = await _partOf(project, 'feature:login');

    final diffAt = part.indexOf('diff --git');
    final frAt = part.indexOf('fr01_check_password.md');
    final statementAt = part.indexOf(checkPasswordStatement);
    expect(diffAt, greaterThanOrEqualTo(0));
    expect(frAt, greaterThan(diffAt));
    expect(statementAt, greaterThan(frAt));
    expect(part, contains('## Edge cases'));
    expect(part, isNot(contains('A wrong password must not sign in.')));
  });

  test('a covering spec doc prints whole less its Rationale', () async {
    final project = await _committedProject(
      extra: doc(
        loginRecord,
        '# Login implementation\n',
        '# Login implementation\n\n## Notes\n\n- Rollout: see the tests\n\n'
            '## Rationale\n\nBecause shared.\n',
      ),
    );
    _append(project.path, _login, 1);

    final part = await _partOf(project, 'feature:login');

    expect(part, contains('- Rollout: see the tests'));
    expect(part, isNot(contains('Because shared.')));
  });

  test('a doc two files of the group point at prints once', () async {
    final project = await _committedProject(
      extra: doc(loginRecord, '  - app/lib/\n', '  - $_login\n  - $_other\n'),
    );
    _append(project.path, _login, 1);
    _append(project.path, _other, 1);

    final part = await _partOf(project, 'feature:login');

    expect(loginRecord.allMatches(part), hasLength(1));
    expect('diff --git a/$_other'.allMatches(part), hasLength(1));
  });

  test('a file with no base prints whole', () async {
    final project = await _committedProject(unfingerprinted: {loginRecord});

    final part = await _partOf(project, 'feature:login');

    expect(part, contains('class Other {}'));
    expect(part, contains('class SignInPage {}'));
    expect(part, isNot(contains('diff --git')));
  });

  test(
    'a file that cannot be read prints a naming line marked unreadable',
    () async {
      final project = await _committedProject(unfingerprinted: {loginRecord});
      final locked = '${project.path}/$_other';
      Process.runSync('chmod', ['000', locked]);
      addTearDown(() => Process.runSync('chmod', ['644', locked]));
      final session = openSession(project);
      addTearDown(session.close);
      final report = await runCheck(session);
      final group = syncGroupsOf(
        CheckContext(session),
        report,
        feature: 'login',
      ).single;

      final part = syncCodePart(
        session,
        group,
        syncVerdictsOf(session, group).judgedDocs,
      );

      expect(part, contains('==> code · $_other · unreadable <==\n'));
      expect(part, contains('class SignInPage {}'));
    },
    skip: unreadablePathSkipReason() ?? false,
  );

  test('an untracked file under a folder entry prints whole', () async {
    final project = await _committedProject();
    _append(project.path, _other, 1);
    File('${project.path}/app/lib/new.dart').writeAsStringSync('class N {}\n');

    final part = await _partOf(project, 'feature:login');

    expect(part, contains('diff --git a/$_other'));
    expect(part, contains('app/lib/new.dart'));
    expect(part, contains('class N {}'));
  });

  test(
    'a suspect matrix row prints the FR text and its test literal',
    () async {
      final project = await _stockProject(_stockTestText);

      final part = await _partOf(project, 'feature:shop');

      expect(part, contains(checkStockStatement));
      expect(part, contains('fingerprint '));
      expect(part, contains('refuses a sold-out item'));
      expect(part, contains('$_stockTest:3'));
    },
  );

  test('a row literal points at the test that names it whole', () async {
    final project = await _stockProject(
      "void main() {\n  test('refuses a sold-out item in bulk', () {});\n"
      "  test('refuses a sold-out item', () {});\n}\n",
    );

    final part = await _partOf(project, 'feature:shop');

    expect(part, contains('$_stockTest:3'));
    expect(part, isNot(contains('$_stockTest:2')));
  });

  test('a file under a folder link prints its diff once', () async {
    final project = await _committedProject();
    _append(project.path, _login, 1);

    final part = await _partOf(project, 'feature:login');

    expect('diff --git a/$_login'.allMatches(part), hasLength(1));
    expect(part, contains('fr01_check_password.md'));
  });

  test(
    "a folder entry's part leaves out the doc of an unchanged file under it",
    () async {
      final project = await _committedProject(extra: _storyOnOther());
      _append(project.path, _login, 1);

      final part = await _partOf(project, 'feature:login');

      expect(part, contains('fr01_check_password.md'));
      expect(part, contains(loginRecord));
      expect(part, isNot(contains(loginStory)));
    },
  );

  test(
    'a doc that names a changed file but owns no judged link prints nowhere',
    () async {
      final project = await _committedProject(
        extra: edit(loginRecord, [
          ..._storyOnOtherChanges,
          (
            "  - 'email_login/check_password:$_login'\n",
            "  - 'email_login/check_password:$_login'\n"
                "  - 'email_login:$_login'\n",
          ),
        ]),
      );
      _append(project.path, _login, 1);

      final part = await _partOf(project, 'feature:login');

      expect(part, isNot(contains(loginStory)));
    },
  );

  test(
    'two links on one file print both their owners under its one code part',
    () async {
      final project = await _committedProject();
      _append(project.path, _login, 1);

      final part = await _partOf(project, 'feature:login');

      final diffAt = part.indexOf('diff --git a/$_login');
      expect('diff --git a/$_login'.allMatches(part), hasLength(1));
      expect(loginStory.allMatches(part), hasLength(1));
      expect('fr01_check_password.md'.allMatches(part), hasLength(1));
      expect(part.indexOf(loginStory), greaterThan(diffAt));
      expect(part.indexOf('fr01_check_password.md'), greaterThan(diffAt));
    },
  );

  test(
    'each doc the group file prints owns a line of its verdict part',
    () async {
      final project = await _committedProject();
      _append(project.path, _login, 1);
      final session = openSession(project);
      addTearDown(session.close);
      final report = await runCheck(session);
      final group = syncGroupsOf(
        CheckContext(session),
        report,
      ).firstWhere((group) => group.scope == 'feature:login');

      final text = syncGroupText(session, group);

      final parts = text.split('\n$syncVerdictMarker\n');
      final verdicts = const LineSplitter().convert(parts.last);
      final docLines = RegExp(
        _docLine,
        multiLine: true,
      ).allMatches(parts.first).toList();
      expect(docLines, isNotEmpty);
      for (final line in docLines) {
        final name = line.group(1)!;
        final path = line.group(2)!;
        final item = name.substring(name.indexOf('/') + 1);
        expect(
          verdicts.any(
            (verdict) =>
                verdict.contains(' $path ') ||
                (verdict.contains(' $loginRecord ') &&
                    verdict.contains(' $item:')),
          ),
          isTrue,
          reason: 'no verdict line for $name',
        );
      }
    },
  );

  test(
    "a moved and changed entry's owner prints under its old folder",
    () async {
      final project = await _committedProject();
      _moveChanged(project);

      final part = await _partOf(project, 'feature:login');

      final folderAt = part.indexOf('==> code · app/lib/ · ');
      expect(folderAt, greaterThanOrEqualTo(0));
      expect(loginStory.allMatches(part), hasLength(1));
      expect(part.indexOf(loginStory), greaterThan(folderAt));
    },
  );

  test("a moved and changed entry's question line prints its doc", () async {
    final project = await _committedProject();
    _moveChanged(project);

    await _expectQuestionOwnersPrinted(project, 'feature:login', loginRecord);
  });

  test("a renamed row literal's question line prints its doc", () async {
    final project = await _renamedRowLiteral();

    await _expectQuestionOwnersPrinted(project, 'feature:shop', cartRecord);
  });

  test('the verdict part opens at column 0 after the code part', () async {
    final project = await _committedProject();
    _append(project.path, _login, 1);
    final session = openSession(project);
    addTearDown(session.close);
    final report = await runCheck(session);
    final group = syncGroupsOf(
      CheckContext(session),
      report,
    ).firstWhere((group) => group.scope == 'feature:login');

    final text = syncGroupText(session, group);

    expect(text, contains('\n==> verdicts <==\n'));
  });

  test('an FR prints its four contract sections', () async {
    final project = await _committedProject(
      extra: fr(
        '## Edge cases',
        '## Input / Output\n\nInput text.\n\n## Behavior\n\nBehavior text.\n\n'
            '## Edge cases',
      ),
    );
    _append(project.path, _login, 1);

    final part = await _partOf(project, 'feature:login');

    expect(part, contains(checkPasswordStatement));
    expect(part, contains('Input text.'));
    expect(part, contains('Behavior text.'));
    expect(part, contains('E01 — An empty password'));
  });
}

/// The record edit that moves the story's `implements` entry to [_other].
const _storyOnOtherChanges = [
  ("'email_login:$_login:SignInPage'", "'email_login:$_other:Other'"),
];

/// Returns the fixture record whose story names [_other], not [_login].
Map<String, String> _storyOnOther() => edit(loginRecord, _storyOnOtherChanges);

/// Writes the nested project whose cart record lists [testText] as its test
/// file and holds [row], by default one stale per-FR row of `check_stock`.
Future<Directory> _stockProject(
  String testText, {
  String? row,
  String coverage = 'fr',
}) {
  final record = nestedRecords()[cartRecord]!.replaceFirst(
    'implements:',
    "tests:\n  - 'add_item/check_stock:$_stockTest'\nimplements:",
  );
  return writeNestedProject(
    extra: {
      ...nestedRecords(),
      '.specstone/config.yaml':
          '${shippedPinsConfig()}verification_coverage: $coverage\n',
      _stockTest: testText,
      cartRecord:
          '$record\n## Verification matrix\n\n'
          '${row ?? perFrRow(_staleStamp)}\n',
    },
  );
}

/// Moves [_login] to [_signIn] and adds a line to it, in one commit.
void _moveChanged(Directory project) {
  expect(git(project, ['mv', _login, _signIn]).exitCode, 0);
  _append(project.path, _signIn, 1);
  commitAll(project, 'move');
}

/// Writes the nested project as a git repository whose edge-case row of
/// `check_stock` is current, then renames its test literal in a second commit.
Future<Directory> _renamedRowLiteral() async {
  final project = await _stockProject(
    _stockTestText,
    coverage: 'edge_case',
    row:
        '- add_item/check_stock E01: `$_stockName` '
        '${fingerprintFor('1. E01 — A sold-out item → refused.')}',
  );
  expect(git(project, ['init', '-q']).exitCode, 0);
  commitAll(project, 'first');
  File('${project.path}/$_stockTest').writeAsStringSync(
    _stockTestText.replaceFirst(_stockName, 'rejects a sold-out item'),
  );
  commitAll(project, 'rename the test');
  return project;
}

/// Expects the code part of the group file of [scope] to print the doc each
/// `?` line of its verdict part is judged against: the item a line on
/// [record] names, else the line's doc.
Future<void> _expectQuestionOwnersPrinted(
  Directory project,
  String scope,
  String record,
) async {
  final session = openSession(project);
  addTearDown(session.close);
  final report = await runCheck(session);
  final group = syncGroupsOf(
    CheckContext(session),
    report,
  ).firstWhere((group) => group.scope == scope);

  final text = syncGroupText(session, group);

  final parts = text.split('\n$syncVerdictMarker\n');
  final printed = RegExp(_docLine, multiLine: true).allMatches(parts.first);
  final questions = [
    for (final line in const LineSplitter().convert(parts.last))
      if (line.startsWith('? ')) line,
  ];
  Set<String> coversOf(String docPath) {
    final file = File('${project.path}/$docPath');
    if (!file.existsSync()) return const {};
    final block = RegExp(
      r'^covers:\n((?:  - .*\n)*)',
      multiLine: true,
    ).firstMatch(file.readAsStringSync())?.group(1);
    return {
      for (final line in const LineSplitter().convert(block ?? ''))
        line.substring('  - '.length).split(' ').first,
    };
  }

  expect(questions, isNotEmpty);
  for (final question in questions) {
    final [_, doc, entry, ...] = question.split(' ');
    final item = entry.split(':').first;
    // A record's `covers` entry names no item, so the record owns it.
    final ownedByItem = doc == record && !coversOf(record).contains(entry);
    expect(
      printed.any(
        (line) => ownedByItem
            ? line.group(1)!.endsWith('/$item')
            : line.group(2) == doc,
      ),
      isTrue,
      reason: 'no doc printed for "$question"',
    );
  }
}
