import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/sync_lines.dart';
import 'package:specstone_core/src/index_query/sync_prefill.dart';
import 'package:specstone_core/src/index_query/sync_work.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/git_repo.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/per_fr_row_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_doc_fixture.dart';

const _login = 'app/lib/login.dart';
const _signIn = 'app/lib/signin.dart';
const _implementsEntry = 'email_login:$_login:SignInPage';
const _testsLinkEntry = 'email_login/check_password:$_login:checkPassword';
const _testsEntry = 'email_login/check_password:$_login';
const _stockTest = 'app/test/stock_test.dart';
const _stockName = 'refuses a sold-out item';
const _stockTestText =
    "void main() {\n  test('refuses an empty cart', () {});\n"
    "  test('$_stockName', () {});\n}\n";
const _staleStamp = '0123456789ab';
const _entryOf = 'add_item/check_stock';

/// A charter, the stand-in type that holds both `covers` and `tasks`, over the
/// login code.
const _tasksCharter = <String, String>{
  'docs/specs/topics/login_tasks.md':
      '---\ncovers:\n  - app/lib/\ntasks:\n  - ENG-42\n  - ENG-50\n---\n\n'
      '# Login tasks\n\n## Purpose\n\nTracks the login tasks.\n',
};

/// Returns the verdict part of the group of [scope] in the check of
/// [project].
Future<String> _verdictOf(Directory project, String scope) async {
  final session = openSession(project);
  addTearDown(session.close);
  final report = await runCheck(session);
  final groups = syncGroupsOf(CheckContext(session), report);
  return syncVerdictsOf(
    session,
    groups.firstWhere((group) => group.scope == scope),
  ).text;
}

Future<Directory> _committedLogin({
  Map<String, String> extra = const {},
}) async {
  final project = await writeCheckProject(extra: extra);
  expect(git(project, ['init', '-q']).exitCode, 0);
  commitAll(project, 'first');
  return project;
}

/// Moves the login file to [to] with [text] as its content in one commit.
void _move(Directory project, String to, String text) {
  expect(git(project, ['mv', _login, to]).exitCode, 0);
  File('${project.path}/$to').writeAsStringSync(text);
  commitAll(project, 'move');
}

String _fingerprintOfFile(Directory project, String path) =>
    fileCodeFingerprint(
      File('${project.path}/$path').readAsBytesSync(),
      path: path,
    );

Future<Directory> _stockProject(
  String testText, {
  String? row,
  String coverage = 'fr',
}) {
  final record = nestedRecords()[cartRecord]!.replaceFirst(
    'implements:',
    "tests:\n  - '$_entryOf:$_stockTest'\nimplements:",
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

Future<Directory> _committedStock({String? row, String coverage = 'fr'}) async {
  final project = await _stockProject(
    _stockTestText,
    row: row,
    coverage: coverage,
  );
  expect(git(project, ['init', '-q']).exitCode, 0);
  commitAll(project, 'first');
  return project;
}

void main() {
  test(
    'a suspect code link gives a question line with its fingerprint',
    () async {
      final project = await _committedLogin();
      File('${project.path}/$_login')
          .writeAsStringSync('int v = 1;\n', mode: FileMode.append);

      final part = await _verdictOf(project, 'feature:login');

      expect(part, startsWith('==> verdicts <==\n'));
      expect(
        part,
        matches(
          RegExp(
            '^\\? $loginRecord $_implementsEntry [0-9a-f]{12}\$',
            multiLine: true,
          ),
        ),
      );
      expect(
        part,
        matches(
          RegExp('^\\? $loginRecord app/lib/ [0-9a-f]{12}\$', multiLine: true),
        ),
      );
    },
  );

  test("a feature group's clean link gets its recorded fingerprint", () async {
    final project = await _committedLogin();
    final session = openSession(project);
    addTearDown(session.close);
    final report = await runCheck(session);
    final group = syncGroupsOf(
      CheckContext(session),
      report,
      feature: 'login',
    ).single;

    final part = syncVerdictsOf(session, group).text;

    expect(group.links, isNotEmpty);
    for (final work in group.links) {
      final recorded = work.link.recorded;
      expect(recorded, isNotNull);
      final sameLinks = group.links.where(
        (other) =>
            other.doc.docPath == work.doc.docPath &&
            other.link.recorded == recorded,
      );
      expect(
        RegExp(
          '^\\? ${RegExp.escape(work.doc.docPath)} .* $recorded\$',
          multiLine: true,
        ).allMatches(part),
        hasLength(sameLinks.length),
      );
    }
  });

  test("a feature group's changed link keeps its one verdict line", () async {
    final project = await _committedLogin();
    File('${project.path}/$_login')
        .writeAsStringSync('int v = 1;\n', mode: FileMode.append);
    final session = openSession(project);
    addTearDown(session.close);
    final report = await runCheck(session);
    final group = syncGroupsOf(
      CheckContext(session),
      report,
      feature: 'login',
    ).single;

    final part = syncVerdictsOf(session, group).text;

    final changed = group.findings
        .where((finding) => finding.kind == FindingKind.codeSuspect)
        .toList();
    expect(changed, isNotEmpty);
    for (final finding in changed) {
      expect(
        part,
        matches(
          RegExp(
            '^\\? ${RegExp.escape(finding.path)} .* '
            '${finding.keys['fingerprint']}\$',
            multiLine: true,
          ),
        ),
      );
    }
    final questions = [
      for (final line in part.split('\n'))
        if (line.startsWith('? ')) line,
    ];
    expect(questions.toSet(), hasLength(questions.length));
    expect(questions, hasLength(group.links.length));
  });

  test(
    'a moved file with a changed fingerprint gives repoint and question lines',
    () async {
      final project = await _committedLogin();
      _move(
        project,
        _signIn,
        'class SignInPage {}\n\n'
        'bool checkPassword(String password) => password.isNotEmpty;\n'
        'int v = 1;\n',
      );

      final part = await _verdictOf(project, 'feature:login');

      expect(
        part,
        contains('repoint $loginRecord $_implementsEntry $_signIn\n'),
      );
      expect(
        part,
        contains(
          '? $loginRecord $_implementsEntry '
          '${_fingerprintOfFile(project, _signIn)}\n',
        ),
      );
    },
  );

  test(
    'a renamed file with the same fingerprint gives a repoint line alone',
    () async {
      final project = await _committedLogin();
      _move(
        project,
        _signIn,
        File('${project.path}/$_login').readAsStringSync(),
      );

      final part = await _verdictOf(project, 'feature:login');

      expect(
        part,
        contains('repoint $loginRecord $_implementsEntry $_signIn\n'),
      );
      expect(part, isNot(contains('? $loginRecord $_implementsEntry')));
    },
  );

  test('a move git shows as no rename gives no repoint line', () async {
    final project = await _committedLogin();
    _move(project, _signIn, 'final Object other = 1;\n// nothing shared\n');

    final part = await _verdictOf(project, 'feature:login');

    expect(part, startsWith('==> verdicts <==\n'));
    expect(part, isNot(contains('repoint')));
  });

  test(
    'a covers entry whose file git shows renamed gets a repoint line',
    () async {
      final project = await _committedLogin(
        extra: doc(loginRecord, '  - app/lib/\n', '  - $_login\n'),
      );
      _move(
        project,
        _signIn,
        File('${project.path}/$_login').readAsStringSync(),
      );

      final part = await _verdictOf(project, 'feature:login');

      expect(part, contains('repoint $loginRecord $_login $_signIn\n'));
    },
  );

  test(
    'a tests entry whose file git shows renamed gets a repoint line',
    () async {
      final project = await _committedLogin();
      _move(
        project,
        _signIn,
        File('${project.path}/$_login').readAsStringSync(),
      );

      final part = await _verdictOf(project, 'feature:login');

      expect(part, contains('repoint $loginRecord $_testsEntry $_signIn\n'));
    },
  );

  test('a renamed test name gives a row line with its new literal', () async {
    final project = await _committedStock();
    File('${project.path}/$_stockTest').writeAsStringSync(
      _stockTestText.replaceFirst(_stockName, 'rejects a sold-out item'),
    );
    commitAll(project, 'rename the test');

    final part = await _verdictOf(project, 'feature:shop');

    final rowAt = part.indexOf(
      'row $cartRecord $_entryOf: +`rejects a sold-out item` -`$_stockName`\n',
    );
    final questionAt = part.indexOf('? $cartRecord $_entryOf ');
    expect(rowAt, greaterThanOrEqualTo(0));
    expect(questionAt, greaterThan(rowAt));
  });

  test(
    'a new test name holding a backtick gives a row line that parses',
    () async {
      const renamed = 'rejects a `sold-out` item';
      final project = await _committedStock();
      File('${project.path}/$_stockTest')
          .writeAsStringSync(_stockTestText.replaceFirst(_stockName, renamed));
      commitAll(project, 'rename the test');

      final part = await _verdictOf(project, 'feature:shop');

      expect(
        part,
        contains('row $cartRecord $_entryOf: +``$renamed`` -`$_stockName`\n'),
      );
      final row = parseSyncFile('sync.txt', part).lines.whereType<RowLine>();
      expect(row.single.added, [renamed]);
    },
  );

  test(
    'a renamed edge case literal gives a row line then its fingerprint line',
    () async {
      final edgeFingerprint = fingerprintFor(
        '1. E01 — A sold-out item → refused.',
      );
      final project = await _committedStock(
        coverage: 'edge_case',
        row: '- $_entryOf E01: `$_stockName` $edgeFingerprint',
      );
      File('${project.path}/$_stockTest').writeAsStringSync(
        _stockTestText.replaceFirst(_stockName, 'rejects a sold-out item'),
      );
      commitAll(project, 'rename the test');

      final part = await _verdictOf(project, 'feature:shop');

      final rowAt = part.indexOf(
        'row $cartRecord $_entryOf E01: '
        '+`rejects a sold-out item` -`$_stockName`\n',
      );
      final question = '? $cartRecord $_entryOf E01 $edgeFingerprint\n';
      expect(rowAt, greaterThanOrEqualTo(0));
      expect(part.indexOf(question), greaterThan(rowAt));
      expect(question.allMatches(part), hasLength(1));
    },
  );

  test('an old path still at HEAD gets no repoint line', () async {
    final project = await _committedLogin();
    final text = File('${project.path}/$_login').readAsStringSync();
    _move(project, _signIn, text);
    File('${project.path}/$_login').writeAsStringSync(text);
    commitAll(project, 'bring it back');
    File('${project.path}/$_login').deleteSync();

    final part = await _verdictOf(project, 'feature:login');

    expect(part, isNot(contains('repoint')));
  });

  test('a path renamed twice repoints to the file that exists', () async {
    final project = await _committedLogin();
    final text = File('${project.path}/$_login').readAsStringSync();
    _move(project, _signIn, text);
    expect(git(project, ['mv', _signIn, 'app/lib/final.dart']).exitCode, 0);
    commitAll(project, 'move again');

    final part = await _verdictOf(project, 'feature:login');

    expect(
      part,
      contains('repoint $loginRecord $_implementsEntry app/lib/final.dart\n'),
    );
    expect(part, isNot(contains('$_implementsEntry $_signIn')));
  });

  test('a path renamed then deleted gets no repoint line', () async {
    final project = await _committedLogin();
    _move(project, _signIn, File('${project.path}/$_login').readAsStringSync());
    expect(git(project, ['rm', '-q', _signIn]).exitCode, 0);
    commitAll(project, 'delete it');

    final part = await _verdictOf(project, 'feature:login');

    expect(part, isNot(contains('repoint')));
  });

  test(
    'an unreadable moved file gives a repoint line and no question line',
    () async {
      final project = await _committedLogin();
      _move(
        project,
        _signIn,
        '${File('${project.path}/$_login').readAsStringSync()}int v = 1;\n',
      );
      final file = '${project.path}/$_signIn';
      expect(Process.runSync('chmod', ['000', file]).exitCode, 0);
      addTearDown(() => Process.runSync('chmod', ['644', file]));

      final part = await _verdictOf(project, 'feature:login');

      expect(
        part,
        contains('repoint $loginRecord $_implementsEntry $_signIn\n'),
      );
      expect(part, isNot(contains('? $loginRecord $_implementsEntry')));
    },
    skip: unreadablePathSkipReason(),
  );

  test(
    'an unconfirmed agent row whose FR is no draft gives a match line',
    () async {
      final project = await _committedStock(row: '- $_entryOf: `$_stockName`');
      final session = openSession(project);
      addTearDown(session.close);
      final report = await runCheck(session);
      final fingerprint = report.findings
          .firstWhere((finding) => finding.kind == FindingKind.unconfirmed)
          .keys['fingerprint'];

      final part = await _verdictOf(project, 'feature:shop');

      expect(part, contains('match $cartRecord $_entryOf $fingerprint\n'));
      expect(part, isNot(contains('? $cartRecord')));
    },
  );

  test(
    'an unconfirmed row whose FR is a draft gives a question line',
    () async {
      final project = await _stockProject(_stockTestText);
      File('${project.path}/docs/$cartAddFr').writeAsStringSync(
        File('${project.path}/docs/$cartAddFr').readAsStringSync().replaceFirst(
          'verify_method: test',
          'verify_method: test\ndraft: true',
        ),
      );
      final session = openSession(project);
      addTearDown(session.close);

      final part = syncVerdictsOf(
        session,
        SyncGroup(
          scope: 'feature:shop',
          route: SyncRoute.engineer,
          findings: [
            Finding(
              kind: FindingKind.unconfirmed,
              path: cartRecord,
              line: 1,
              message: 'm',
              waitsFor: WaitsFor.agent,
              keys: {
                'link': _entryOf,
                'targetPath': 'docs/$cartAddFr',
                'fingerprint': _staleStamp,
              },
            ),
          ],
          links: [],
        ),
      ).text;

      expect(part, contains('? $cartRecord $_entryOf $_staleStamp\n'));
      expect(part, isNot(contains('match')));
    },
  );

  test('a record matrix row finding resolves its FR from targetPath', () async {
    final project = await _stockProject(_stockTestText);
    final session = openSession(project);
    addTearDown(session.close);

    final part = syncVerdictsOf(
      session,
      SyncGroup(
        scope: 'feature:shop',
        route: SyncRoute.engineer,
        findings: [
          Finding(
            kind: FindingKind.unconfirmed,
            path: cartRecord,
            line: 1,
            message: 'm',
            waitsFor: WaitsFor.agent,
            keys: {
              'link': _entryOf,
              'targetPath': 'docs/$cartAddFr',
              'fingerprint': _staleStamp,
            },
          ),
        ],
        links: [],
      ),
    ).text;

    expect(part, contains('match $cartRecord $_entryOf $_staleStamp\n'));
  });

  test('a covers entry two docs share gives lines for its own doc', () async {
    final project = await _committedLogin(extra: _tasksCharter);
    File('${project.path}/$_login')
        .writeAsStringSync('int v = 1;\n', mode: FileMode.append);
    commitAll(project, 'feat: add v\n\nFixes ENG-42\nRefs ENG-50');

    final part = await _verdictOf(project, 'feature:login');

    expect(
      part.split('\n').where((line) => line.startsWith('remove-task')),
      unorderedEquals([
        'remove-task ENG-42 $loginRecord $_implementsEntry',
        'remove-task ENG-42 $loginRecord $_testsLinkEntry',
        'remove-task ENG-42 $loginRecord app/lib/',
      ]),
    );
  });

  test('a closing commit older than the diff base closes nothing', () async {
    final project = await _committedLogin(extra: _tasksCharter);
    final original = File('${project.path}/$_login').readAsStringSync();
    File('${project.path}/$_login')
        .writeAsStringSync('int v = 1;\n', mode: FileMode.append);
    commitAll(project, 'feat: add v\n\nFixes ENG-50');
    File('${project.path}/$_login').writeAsStringSync(original);
    commitAll(project, 'revert: drop v');
    File('${project.path}/$_login')
        .writeAsStringSync('int w = 2;\n', mode: FileMode.append);
    commitAll(project, 'feat: add w\n\nFixes ENG-42');

    final part = await _verdictOf(project, 'feature:login');

    expect(part, contains('remove-task ENG-42 '));
    expect(part, isNot(contains('remove-task ENG-50')));
  });

  test(
    'a root: project skill link with no task_ref gives no remove-task line',
    () async {
      final project = await writeCheckProject(
        extra: {
          '.specstone/config.yaml': '${skillPinsConfig()}code_root: code\n',
          'code/app/lib/login.dart': checkProjectFiles()['app/lib/login.dart']!,
          ...skillDocFile(['$skillFile 0123456789ab']),
          skillFile: skillText,
        },
        without: {'app/lib/login.dart'},
      );
      expect(git(project, ['init', '-q']).exitCode, 0);
      commitAll(project, 'first\n\nFixes ENG-42');

      final part = await _verdictOf(project, 'skill:review');

      expect(part, contains('? $skillDoc $skillFile '));
      expect(part, isNot(contains('remove-task')));
    },
  );
}
