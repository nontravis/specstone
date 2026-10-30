// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/write_fixture.dart' show docFile, readDoc, writeIn;

const _journeyPath = 'prds/journeys/sign_in/JOURNEY.md';
const _copy =
    '<!-- specstone:generated scenario_copy (do not edit) -->\n'
    'step: login/email_login S1\n'
    '<!-- specstone:generated end -->\n';

final String _fp1 = fingerprintOf(loginScenario1);
final String _fp2 = fingerprintOf(loginScenario2);
final String _fpStatement = fingerprintFor(checkPasswordStatement);

const Set<FindingKind> _storyKinds = {
  FindingKind.suspect,
  FindingKind.unconfirmed,
  FindingKind.confirmedEntryStale,
};

String _journey() =>
    '---\nconfirmed:\n  - login/email_login#S1 $_fp1\n'
    '  - other/story#S2 $_fp2\n---\n\n'
    '# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n'
    '### 1. Sign in\nstep: login/email_login S1\n$_copy\n'
    '### 2. Elsewhere\nstep: other/story S2\nafter: 1\n';

Future<Directory> _project() =>
    writeCheckProject(extra: {'docs/$_journeyPath': _journey()});

ReadAnswer _rename(Directory root, String address, String slug) =>
    writeIn(root, (s) => answerRename(s, address, slug: slug));

// The step naming other/story is unresolved by design; a renamed step that
// kept its old name would make a second one.
int _unresolvedSteps(Directory root) => checkOf(
  root,
  docPath: _journeyPath,
).findings.where((f) => f.kind == FindingKind.journeyStepUnresolved).length;

Set<FindingKind> _kindsOf(Directory root, String docPath) => {
  for (final f in checkOf(root, docPath: docPath).findings) f.kind,
};

void main() {
  test('f02/us06/s7, f02/us06/fr03/e01, f04/us02/fr06/e07: rename of a story rewrites its journey step and entry', () async {
    final root = await _project();
    final answer = _rename(
      root,
      'user_story:login/email_login',
      'password_login',
    );
    expect(answer.json['rewritten'], contains(_journeyPath));
    final text = readDoc(root, _journeyPath);
    expect(text, contains('### 1. Sign in\nstep: login/password_login S1\n'));
    expect(text, contains('  - login/password_login#S1 $_fp1\n'));
    expect(_kindsOf(root, _journeyPath).intersection(_storyKinds), isEmpty);
    expect(_unresolvedSteps(root), 1);
  });

  test('f02/us06/fr03/e02: rename of a feature rewrites every step naming its stories', () async {
    final root = await _project();
    _rename(root, 'feature:login', 'signin');
    final text = readDoc(root, _journeyPath);
    expect(text, contains('step: signin/email_login S1\n'));
    expect(text, contains('  - signin/email_login#S1 $_fp1\n'));
    expect(_kindsOf(root, _journeyPath).intersection(_storyKinds), isEmpty);
    expect(_unresolvedSteps(root), 1);
  });

  test('f02/us06/s8, f02/us06/fr03/e03, f04/us04/fr03/e08: rename of a story rewrites the api row and its entry', () async {
    final root = await _project();
    _rename(root, 'user_story:login/email_login', 'password_login');
    final api = readDoc(root, loginApi);
    expect(api, contains('| password_login/check_password | `signIn` |'));
    expect(api, contains('  - password_login/check_password $_fpStatement\n'));
    final kinds = _kindsOf(root, loginApi);
    expect(kinds, isNot(contains(FindingKind.frTraceUnresolved)));
    expect(kinds, isNot(contains(FindingKind.suspect)));
    expect(kinds, isNot(contains(FindingKind.confirmedEntryStale)));
  });

  test(
    'f02/us06/fr03/e04: rename of an fr rewrites the row and the entry',
    () async {
      final root = await _project();
      _rename(root, 'fr:login/email_login/check_password', 'verify_password');
      final api = readDoc(root, loginApi);
      expect(api, contains('| email_login/verify_password | `signIn` |'));
      expect(api, contains('  - email_login/verify_password $_fpStatement\n'));
    },
  );

  test('f02/us06/fr03/e05: rename of a feature leaves the api rows and entries as written', () async {
    final root = await _project();
    _rename(root, 'feature:login', 'signin');
    final api = readDoc(root, 'specs/f01_signin/API.md');
    expect(api, contains('| email_login/check_password | `signIn` |'));
    expect(api, contains('  - email_login/check_password $_fpStatement\n'));
  });

  test('f02/us06/fr03/e06: an approved journey or api doc rewritten gets no draft: true', () async {
    final root = await _project();
    _rename(root, 'user_story:login/email_login', 'password_login');
    expect(readDoc(root, _journeyPath), isNot(contains('draft:')));
    expect(readDoc(root, loginApi), isNot(contains('draft:')));
  });

  test('f02/us06/fr03/e07: a step or FR cell naming a doc not renamed is unchanged', () async {
    final root = await _project();
    _rename(root, 'user_story:login/email_login', 'password_login');
    final text = readDoc(root, _journeyPath);
    expect(text, contains('step: other/story S2\nafter: 1\n'));
    expect(text, contains('  - other/story#S2 $_fp2\n'));
  });

  test('f02/us06/fr03/e08: an fr entry S2 and an nf entry NFR-P01 are unchanged', () async {
    final root = await writeCheckProject(
      extra: {
        'docs/$loginFr':
            '---\nstatus: planned\ntraced_from:\n  - S2\n'
            '---\n\n# Check password\n\n## Statement\n$checkPasswordStatement\n',
      },
    );
    final before = readDoc(root, loginFr);
    final nfBefore = readDoc(root, loginNf);
    _rename(root, 'user_story:login/email_login', 'password_login');
    String moved(String path) =>
        path.replaceFirst('us01_email_login', 'us01_password_login');
    expect(readDoc(root, moved(loginFr)), before);
    expect(readDoc(root, moved(loginNf)), nfBefore);
  });

  test('f02/us06/fr03/e09: the pasted copy is unchanged', () async {
    final root = await _project();
    _rename(root, 'user_story:login/email_login', 'password_login');
    expect(readDoc(root, _journeyPath), contains(_copy));
  });

  test('f02/us06/fr03: each rewritten doc prints among rewritten', () async {
    final root = await _project();
    final answer = _rename(
      root,
      'user_story:login/email_login',
      'password_login',
    );
    expect(answer.json['rewritten'], containsAll([_journeyPath, loginApi]));
  });

  test(
    'f02/us06/fr01: rename journey:sign_in --to sign_up moves its folder',
    () async {
      final root = await _project();
      expect(_rename(root, 'journey:sign_in', 'sign_up').json['moved'], [
        {'from': 'prds/journeys/sign_in/', 'to': 'prds/journeys/sign_up/'},
      ]);
      expect(
        docFile(root, 'prds/journeys/sign_up/JOURNEY.md').existsSync(),
        isTrue,
      );
    },
  );

  test('f02/us05/fr02: reorder rewrites no step line and no label', () async {
    final root = await _project();
    final journey = readDoc(root, _journeyPath);
    final api = readDoc(root, loginApi);
    writeIn(
      root,
      (s) => answerReorder(s, 'user_story:login/email_login', place: '1'),
    );
    expect(readDoc(root, _journeyPath), journey);
    expect(readDoc(root, loginApi), api);
  });
}
