// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/write_fixture.dart' show docFile, readDoc, writeIn;

const _journeyPath = 'prds/journeys/sign_in/JOURNEY.md';
const _copy =
    '<!-- specstone:generated scenario_copy (do not edit) -->\n'
    'step: login/email_login S1\n'
    '<!-- specstone:generated end -->\n';

final String _fp1 = fingerprintOf(loginScenario1);
final String _fp2 = fingerprintOf(loginScenario2);
final String _fpStatement = fingerprintFor('\n$checkPasswordStatement');
final String _fpCheckStock = fingerprintFor(checkStockStatement);

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

const _cartApi = 'specs/f02_shop/f01_cart/API.md';

// The sub-feature `cart` holds its own API doc, whose cells sit below cart.
Future<Directory> _nestedWithCartApi() => writeNestedProject(
  extra: {
    'docs/$_cartApi':
        '---\nconfirmed:\n  - add_item/check_stock $_fpCheckStock\n---\n\n'
        '# Cart API\n\n## FR trace\n\n| FR | Operation |\n|---|---|\n'
        '| add_item/check_stock | `addItem` |\n\n## Operations\n\nNone.\n',
  },
);

// Stratum's layout: a group folder before the first `f{nn}_` segment.
Future<Directory> _groupedProject() {
  const feature = 'prds/features/foundation/f01_layout/FEATURE.md';
  const story =
      'prds/features/foundation/f01_layout/us01_email_login/USER_STORY.md';
  const fr =
      'prds/features/foundation/f01_layout/us01_email_login/fr01_check_password.md';
  const api = 'specs/foundation/f01_layout/API.md';
  final files = checkProjectFiles();
  return writeCheckProject(
    without: {
      'docs/$loginFeature',
      'docs/$loginStory',
      'docs/$loginFr',
      'docs/$loginNf',
      'docs/$loginArchitecture',
      'docs/$loginApi',
    },
    extra: {
      '.specstone/templates/feature.yaml':
          'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
      '.specstone/templates/user_story.yaml': 'path: prds/features/{slug}/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md\n',
      '.specstone/templates/fr.yaml': 'path: prds/features/{slug}/f{nn}_{slug}/us{nn}_{slug}/fr{nn}_{slug}.md\n',
      '.specstone/templates/api.yaml':
          'path: specs/{slug}/f{nn}_{slug}/API.md\n',
      'docs/$feature': files['docs/$loginFeature']!,
      'docs/$story': files['docs/$loginStory']!,
      'docs/$fr': files['docs/$loginFr']!,
      'docs/$api': files['docs/$loginApi']!,
    },
  );
}

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
    expect(text, contains('### 1. Sign in\n\nstep: login/password_login S1\n'));
    expect(text, contains('  - login/password_login#S1 $_fp1\n'));
    expect(_kindsOf(root, _journeyPath).intersection(_storyKinds), isEmpty);
    expect(_unresolvedSteps(root), 1);
  });

  test('document_writing/rename_doc/rewrite_link_labels E01: rename of a shop story rewrites its step and its confirmed entry, and the check reports no suspect, unconfirmed, or stale finding', () async {
    final fingerprint = fingerprintFor(
      '### Scenario 1 — [happy] Add an item\n- **Given** a shopper\n'
      '- **When** the shopper acts\n- **Then** the shopper sees the result',
    );
    final root = await writeNestedProject(
      extra: {
        'docs/$_journeyPath':
            '---\nconfirmed:\n  - shop/cart/add_item#S1 $fingerprint\n---\n\n'
            '# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n'
            '### 1. Add\nstep: shop/cart/add_item S1\n',
      },
    );
    _rename(root, 'user_story:shop/cart/add_item', 'start_cart');
    final text = readDoc(root, _journeyPath);
    expect(text, contains('step: shop/cart/start_cart S1\n'));
    expect(text, contains('  - shop/cart/start_cart#S1 $fingerprint\n'));
    expect(_kindsOf(root, _journeyPath).intersection(_storyKinds), isEmpty);
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

  test(
    'f02/us06/fr03: an unrelated non-UTF-8 api doc does not block a rename',
    () async {
      final root = await _project();
      final api = docFile(root, loginApi);
      api.writeAsBytesSync([...utf8.encode(api.readAsStringSync()), 0xff]);
      // A feature rename leaves every FR cell as written, so the api names no
      // renamed label.
      expect(
        _rename(root, 'feature:login', 'signin').json['moved'],
        isNotEmpty,
      );
    },
  );

  test(
    'f02/us06/fr03: an unrelated non-UTF-8 journey does not block a rename',
    () async {
      final root = await _project();
      docFile(root, _journeyPath).writeAsBytesSync([
        ...utf8.encode(
          _journey().replaceAll('login/email_login', 'other/story'),
        ),
        0xff,
      ]);
      expect(
        _rename(
          root,
          'user_story:login/email_login',
          'password_login',
        ).json['moved'],
        isNotEmpty,
      );
    },
  );

  test('f02/us06/fr03: a non-UTF-8 journey that names a renamed story refuses the rename', () async {
    final root = await _project();
    final journey = docFile(root, _journeyPath);
    journey.writeAsBytesSync([...journey.readAsBytesSync(), 0xff]);
    expect(
      () => _rename(root, 'user_story:login/email_login', 'password_login'),
      throwsA(
        isA<RenderFault>().having(
          (e) => e.code,
          'code',
          RenderFaultCode.outputNotWritable,
        ),
      ),
    );
  });

  test('f02/us06/fr03: a journey with no frontmatter or a leading blank line gets its step lines rewritten', () async {
    for (final lead in ['', '\n']) {
      final root = await writeCheckProject(
        extra: {
          'docs/$_journeyPath':
              '$lead# Sign in\n\n## Goal\nGet in.\n\n## Flow\n\n## Steps\n'
              '### 1. Sign in\nstep: login/email_login S1\n\n'
              '### 2. Next\nstep: login/email_login S2\nafter: 1\n',
        },
        // The stamp would give the journey the frontmatter the test lacks.
        unstamped: {'docs/$_journeyPath'},
      );
      _rename(root, 'user_story:login/email_login', 'password_login');
      expect(
        readDoc(root, _journeyPath),
        '$lead# Sign in\n\n## Goal\n\nGet in.\n\n## Flow\n\n## Steps\n\n'
        '### 1. Sign in\n\nstep: login/password_login S1\n\n'
        '### 2. Next\n\nstep: login/password_login S2\nafter: 1\n',
      );
    }
  });

  test('f02/us06/fr03/e10: rename of a sub-feature rewrites its parent api cell and entry', () async {
    final root = await _nestedWithCartApi();
    _rename(root, 'feature:shop/cart', 'basket');
    final api = readDoc(root, shopApi);
    expect(api, contains('| basket/add_item/check_stock | `addItem` |'));
    expect(api, contains('  - basket/add_item/check_stock $_fpCheckStock\n'));
    final kinds = _kindsOf(root, shopApi);
    expect(kinds, isNot(contains(FindingKind.frTraceUnresolved)));
    expect(kinds, isNot(contains(FindingKind.confirmedEntryStale)));
    expect(kinds, isNot(contains(FindingKind.confirmedEntryMalformed)));
  });

  test(
    'f02/us06/fr03/e11: rename of a top feature keeps every cell of its api',
    () async {
      final root = await _nestedWithCartApi();
      _rename(root, 'feature:shop', 'market');
      final api = readDoc(root, 'specs/f02_market/API.md');
      expect(api, contains('| cart/add_item/check_stock | `addItem` |'));
      expect(api, contains('  - cart/add_item/check_stock $_fpCheckStock\n'));
      final cartApi = readDoc(root, 'specs/f02_market/f01_cart/API.md');
      expect(cartApi, contains('| add_item/check_stock | `addItem` |'));
    },
  );

  test(
    'f02/us06/fr03/e12: rename of a sub-feature keeps the cells of its own api',
    () async {
      final root = await _nestedWithCartApi();
      final answer = _rename(root, 'feature:shop/cart', 'basket');
      expect(
        answer.json['rewritten'],
        isNot(contains('specs/f02_shop/f01_basket/API.md')),
      );
      final cartApi = readDoc(root, 'specs/f02_shop/f01_basket/API.md');
      expect(cartApi, contains('| add_item/check_stock | `addItem` |'));
      expect(cartApi, contains('  - add_item/check_stock $_fpCheckStock\n'));
    },
  );

  test('f02/us06/fr03/e13: rename of a story under a group feature cuts the cell at the feature name', () async {
    final root = await _groupedProject();
    _rename(root, 'user_story:foundation/layout/email_login', 'password_login');
    final api = readDoc(root, 'specs/foundation/f01_layout/API.md');
    expect(api, contains('| password_login/check_password | `signIn` |'));
    expect(api, contains('  - password_login/check_password $_fpStatement\n'));
  });

  test('document_writing/rename_doc/rewrite_link_labels E15: rename of a story rewrites the traced_from entry and confirmed label of an fr', () async {
    final root = await _frTraceProject();
    _rename(root, 'user_story:login/reset_password', 'recover_password');
    final fr = readDoc(root, loginFr);
    expect(fr, contains('traced_from: [S1, login/recover_password#S3]\n'));
    expect(fr, contains('  - login/recover_password#S3 $_fp3\n'));
    expect(fr, isNot(contains('reset_password')));
    expect(fr, isNot(contains('draft')));
    expect(_frKinds(root), isEmpty);
  });

  for (final entry in [
    'login/reset_password#S3 $_fp3',
    '"login/reset_password#S3 $_fp3"',
  ]) {
    test(
      'document_writing/rename_doc/rewrite_link_labels E15: a flow-list confirmed label $entry rewrites as a '
      'block-list one does',
      () async {
        final root = await _frTraceProject();
        final file = File('${root.path}/docs/$loginFr');
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(
            'confirmed:\n  - S1 $_fp1\n  - login/reset_password#S3 $_fp3\n',
            'confirmed: [S1 $_fp1, $entry]\n',
          ),
        );
        _rename(root, 'user_story:login/reset_password', 'recover_password');
        final renamed = entry.replaceFirst(
          'reset_password',
          'recover_password',
        );
        expect(
          readDoc(root, loginFr),
          contains('confirmed: [S1 $_fp1, $renamed]\n'),
        );
        expect(_frKinds(root), isEmpty);
      },
    );
  }

  test('document_writing/rename_doc/rewrite_link_labels E15: a block-list traced_from rewrites and the other entries keep their text', () async {
    final root = await _frTraceProject(
      tracedFrom: 'traced_from:\n  - S1\n  - "login/reset_password#S3" # why\n',
    );
    _rename(root, 'user_story:login/reset_password', 'recover_password');
    final fr = readDoc(root, loginFr);
    expect(
      fr,
      contains('traced_from:\n  - S1\n  - "login/recover_password#S3" # why\n'),
    );
    expect(_frKinds(root), isEmpty);
  });

  for (final (shape, tracedFrom) in [
    (
      'a comment line above the key',
      '# note\ntraced_from: [S1, login/reset_password#S3]\n',
    ),
    (
      'a blank line above the key',
      '\ntraced_from: [S1, login/reset_password#S3]\n',
    ),
    (
      'a flow list over two lines',
      'traced_from: [S1,\n  login/reset_password#S3]\n',
    ),
  ]) {
    test(
      'document_writing/rename_doc/rewrite_link_labels E15: traced_from with $shape rewrites with confirmed',
      () async {
        final root = await _frTraceProject(tracedFrom: tracedFrom);
        _rename(root, 'user_story:login/reset_password', 'recover_password');
        final fr = readDoc(root, loginFr);
        expect(fr, contains('login/recover_password#S3'));
        expect(fr, isNot(contains('reset_password')));
        expect(fr, contains('  - login/recover_password#S3 $_fp3\n'));
        expect(_frKinds(root), isEmpty);
      },
    );
  }

  test('document_writing/rename_doc/rewrite_link_labels E15: an own-story label S<N> and an unrenamed story label keep their text', () async {
    final root = await _frTraceProject();
    final before = readDoc(root, loginFr);
    _rename(root, 'user_story:login/email_login', 'password_login');
    final renamedFr = loginFr.replaceFirst('email_login', 'password_login');
    expect(readDoc(root, renamedFr), before);
  });

  test('document_writing/move_story/rewrite_moved_story_references E04: move of a story rewrites the traced_from entry and confirmed label of an fr', () async {
    final root = await _frTraceProject();
    writeIn(
      root,
      (s) => answerMove(s, 'user_story:login/reset_password', under: 'account'),
    );
    final fr = readDoc(root, loginFr);
    expect(fr, contains('traced_from: [S1, account/reset_password#S3]\n'));
    expect(fr, contains('  - account/reset_password#S3 $_fp3\n'));
    expect(fr, isNot(contains('draft')));
    expect(_frKinds(root), contains(FindingKind.scenarioTraceUnresolved));
  });

  test('document_writing/move_story/rewrite_moved_story_references E05: an fr under the moved story keeps the entry naming a story that stays', () async {
    final root = await _frTraceProject();
    final before = readDoc(root, _resetFr);
    writeIn(
      root,
      (s) => answerMove(s, 'user_story:login/reset_password', under: 'account'),
    );
    final moved = _resetFr
        .replaceFirst('f01_login', 'f02_account')
        .replaceFirst('us02', 'us01');
    expect(readDoc(root, moved), before);
    expect(
      _frKinds(root, docPath: moved),
      contains(FindingKind.scenarioTraceUnresolved),
    );
  });
}

const _resetStory = 'prds/features/f01_login/us02_reset_password/USER_STORY.md';
const _resetFr =
    'prds/features/f01_login/us02_reset_password/fr01_send_link.md';
const _accountFeature = 'prds/features/f02_account/FEATURE.md';
const _scenario3 =
    '### Scenario 3 — [happy] Reset the password\n\n- **Given** an account\n'
    '- **When** the Agent asks for a reset\n- **Then** the Agent gets a link';

final String _fp3 = fingerprintOf(_scenario3);

// Login's FR traces its own S1 and the sibling story's S3; the sibling story
// holds an FR that traces the login story's S1.
Future<Directory> _frTraceProject({
  String tracedFrom = 'traced_from: [S1, login/reset_password#S3]\n',
}) {
  final files = checkProjectFiles();
  final loginFeatureText = files['docs/$loginFeature']!;
  return writeCheckProject(
    extra: {
      'docs/$_accountFeature': loginFeatureText.replaceFirst(
        '# Login',
        '# Account',
      ),
      'docs/$_resetStory': files['docs/$loginStory']!
          .replaceFirst('# Agent signs in with email', '# Agent resets')
          .replaceFirst('implements:\n  - app/lib/login.dart:SignInPage\n', '')
          .replaceFirst(loginScenario2, _scenario3)
          .replaceFirst(loginScenario1, _scenario3.replaceFirst('3', '1')),
      'docs/$loginFr': files['docs/$loginFr']!
          .replaceFirst('traced_from:\n  - S2\n', tracedFrom)
          .replaceFirst(
            'confirmed:\n  - S2 ${fingerprintFor(loginScenario2)}\n',
            'confirmed:\n  - S1 $_fp1\n  - login/reset_password#S3 $_fp3\n',
          ),
      'docs/$_resetFr': files['docs/$loginFr']!
          .replaceFirst(
            'traced_from:\n  - S2\n',
            'traced_from: [login/email_login#S1]\n',
          )
          .replaceFirst(
            'confirmed:\n  - S2 ${fingerprintFor(loginScenario2)}\n',
            'confirmed:\n  - login/email_login#S1 $_fp1\n',
          ),
    },
  );
}

const Set<FindingKind> _frKindSet = {
  ..._storyKinds,
  FindingKind.scenarioTraceUnresolved,
};

Set<FindingKind> _frKinds(Directory root, {String docPath = loginFr}) => {
  for (final f in checkOf(root, docPath: docPath).findings)
    if (_frKindSet.contains(f.kind)) f.kind,
};
