// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/fingerprint.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/rewrite_labels.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/override_link_fixture.dart';
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
Future<int> _unresolvedSteps(Directory root) async => (await checkOf(
  root,
  docPath: _journeyPath,
)).findings.where((f) => f.kind == FindingKind.journeyStepUnresolved).length;

Future<Set<FindingKind>> _kindsOf(Directory root, String docPath) async => {
  for (final f in (await checkOf(root, docPath: docPath)).findings) f.kind,
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
  test('rename of a story rewrites its journey step and entry', () async {
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
    expect(
      (await _kindsOf(root, _journeyPath)).intersection(_storyKinds),
      isEmpty,
    );
    expect(await _unresolvedSteps(root), 1);
  });

  test('rename of shop/set_up_cart rewrites its step and its confirmed entry, and the check reports no suspect, unconfirmed, or stale finding', () async {
    String shop(String text) => text
        .replaceAll('email_login', 'set_up_cart')
        .replaceAll('login', 'shop');
    final root = await writeCheckProject(
      without: {
        for (final key in checkProjectFiles().keys)
          if (shop(key) != key) key,
      },
      extra: {
        for (final MapEntry(:key, :value) in checkProjectFiles().entries)
          shop(key): shop(value),
        'docs/$_journeyPath': shop(_journey()),
      },
    );
    _rename(root, 'user_story:shop/set_up_cart', 'start_cart');
    final text = readDoc(root, _journeyPath);
    expect(text, contains('### 1. Sign in\n\nstep: shop/start_cart S1\n'));
    expect(text, contains('  - shop/start_cart#S1 $_fp1\n'));
    expect(
      (await _kindsOf(root, _journeyPath)).intersection(_storyKinds),
      isEmpty,
    );
  });

  test('rename of a feature rewrites every step naming its stories', () async {
    final root = await _project();
    _rename(root, 'feature:login', 'signin');
    final text = readDoc(root, _journeyPath);
    expect(text, contains('step: signin/email_login S1\n'));
    expect(text, contains('  - signin/email_login#S1 $_fp1\n'));
    expect(
      (await _kindsOf(root, _journeyPath)).intersection(_storyKinds),
      isEmpty,
    );
    expect(await _unresolvedSteps(root), 1);
  });

  test('rename of a story rewrites the api row and its entry', () async {
    final root = await _project();
    _rename(root, 'user_story:login/email_login', 'password_login');
    final api = readDoc(root, loginApi);
    expect(api, contains('| password_login/check_password | `signIn` |'));
    expect(api, contains('  - password_login/check_password $_fpStatement\n'));
    final kinds = await _kindsOf(root, loginApi);
    expect(kinds, isNot(contains(FindingKind.frTraceUnresolved)));
    expect(kinds, isNot(contains(FindingKind.suspect)));
    expect(kinds, isNot(contains(FindingKind.confirmedEntryStale)));
  });

  test('the renamed api row raises no unresolved, suspect, unconfirmed, or stale finding', () async {
    final root = await _project();
    _rename(root, 'user_story:login/email_login', 'password_login');
    final kinds = await _kindsOf(root, loginApi);
    for (final kind in [
      FindingKind.frTraceUnresolved,
      FindingKind.suspect,
      FindingKind.unconfirmed,
      FindingKind.confirmedEntryStale,
    ]) {
      expect(kinds, isNot(contains(kind)), reason: '$kind');
    }
  });

  test('an approved journey and api doc rewritten keep their approval and confirmations', () async {
    final root = await _project();
    _rename(root, 'user_story:login/email_login', 'password_login');
    for (final docPath in [_journeyPath, loginApi]) {
      expect(readDoc(root, docPath), contains('approved: "'), reason: docPath);
      final kinds = await _kindsOf(root, docPath);
      for (final kind in [
        FindingKind.suspect,
        FindingKind.unconfirmed,
        FindingKind.confirmedEntryStale,
        FindingKind.approvalStale,
      ]) {
        expect(kinds, isNot(contains(kind)), reason: '$docPath $kind');
      }
    }
  });

  test(
    'an api row and entry naming a story not renamed stay as written',
    () async {
      final root = await writeCheckProject(
        extra: edit(loginApi, [
          (
            'confirmed:\n  - email_login/check_password',
            'confirmed:\n  - other_story/do_it 0123456789ab\n  - email_login/check_password',
          ),
          (
            '| email_login/check_password | `signIn` |\n',
            '| email_login/check_password | `signIn` |\n| other_story/do_it | `doIt` |\n',
          ),
        ]),
      );
      _rename(root, 'user_story:login/email_login', 'password_login');
      final api = readDoc(root, loginApi);
      expect(api, contains('| other_story/do_it | `doIt` |\n'));
      expect(api, contains('  - other_story/do_it 0123456789ab\n'));
      expect(api, contains('| password_login/check_password | `signIn` |\n'));
    },
  );

  test('a rewritten api doc is laid out', () async {
    final root = await writeCheckProject(
      extra: edit(loginApi, [
        ('## Operations\n\n### signIn', '## Operations\n\n\n\n### signIn'),
      ]),
    );
    expect(readDoc(root, loginApi), contains('\n\n\n\n### signIn'));
    _rename(root, 'user_story:login/email_login', 'password_login');
    final api = readDoc(root, loginApi);
    expect(api, contains('| password_login/check_password | `signIn` |\n'));
    expect(api, isNot(contains('\n\n\n')));
  });

  test(
    'an api doc the format command refuses keeps every byte the rewrite leaves',
    () async {
      final root = await writeCheckProject(
        extra: edit(loginApi, [
          ('## Operations\n\n### signIn', '## Bogus\n\n\n\n### signIn'),
        ]),
        unstamped: {'docs/$loginApi'},
      );
      final before = readDoc(root, loginApi);
      _rename(root, 'user_story:login/email_login', 'password_login');
      expect(
        readDoc(root, loginApi),
        before.replaceAll(
          'email_login/check_password',
          'password_login/check_password',
        ),
      );
    },
  );

  test(
    'a journey the format command refuses keeps every byte the rewrite leaves',
    () async {
      final root = await writeCheckProject(
        extra: {'docs/$_journeyPath': '${_journey()}\n\n\n## Bogus\nx\n'},
        unstamped: {'docs/$_journeyPath'},
      );
      final before = readDoc(root, _journeyPath);
      final answer = _rename(
        root,
        'user_story:login/email_login',
        'password_login',
      );
      expect(answer.json['rewritten'], contains(_journeyPath));
      expect(
        readDoc(root, _journeyPath),
        before
            .replaceFirst(
              '### 1. Sign in\nstep: login/email_login S1',
              '### 1. Sign in\nstep: login/password_login S1',
            )
            .replaceFirst(
              '  - login/email_login#S1 ',
              '  - login/password_login#S1 ',
            ),
      );
    },
  );

  test('rename of an fr rewrites the row and the entry', () async {
    final root = await _project();
    _rename(root, 'fr:login/email_login/check_password', 'verify_password');
    final api = readDoc(root, loginApi);
    expect(api, contains('| email_login/verify_password | `signIn` |'));
    expect(api, contains('  - email_login/verify_password $_fpStatement\n'));
  });

  test(
    'rename of a feature leaves the api rows and entries as written',
    () async {
      final root = await _project();
      _rename(root, 'feature:login', 'signin');
      final api = readDoc(root, 'specs/f01_signin/API.md');
      expect(api, contains('| email_login/check_password | `signIn` |'));
      expect(api, contains('  - email_login/check_password $_fpStatement\n'));
    },
  );

  test(
    'an approved journey or api doc rewritten gets no draft: true',
    () async {
      final root = await _project();
      _rename(root, 'user_story:login/email_login', 'password_login');
      expect(readDoc(root, _journeyPath), isNot(contains('draft:')));
      expect(readDoc(root, loginApi), isNot(contains('draft:')));
    },
  );

  test('a step or FR cell naming a doc not renamed is unchanged', () async {
    final root = await _project();
    _rename(root, 'user_story:login/email_login', 'password_login');
    final text = readDoc(root, _journeyPath);
    expect(text, contains('step: other/story S2\nafter: 1\n'));
    expect(text, contains('  - other/story#S2 $_fp2\n'));
  });

  test('an fr entry S2 and an nf entry NFR-P01 are unchanged', () async {
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

  test('the pasted copy is unchanged', () async {
    final root = await _project();
    _rename(root, 'user_story:login/email_login', 'password_login');
    expect(readDoc(root, _journeyPath), contains(_copy));
  });

  test('each rewritten doc prints among rewritten', () async {
    final root = await _project();
    final answer = _rename(
      root,
      'user_story:login/email_login',
      'password_login',
    );
    expect(answer.json['rewritten'], containsAll([_journeyPath, loginApi]));
  });

  test('rename journey:sign_in --to sign_up moves its folder', () async {
    final root = await _project();
    expect(_rename(root, 'journey:sign_in', 'sign_up').json['moved'], [
      {'from': 'prds/journeys/sign_in/', 'to': 'prds/journeys/sign_up/'},
    ]);
    expect(
      docFile(root, 'prds/journeys/sign_up/JOURNEY.md').existsSync(),
      isTrue,
    );
  });

  test('reorder rewrites no step line and no label', () async {
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

  test('an unrelated non-UTF-8 api doc does not block a rename', () async {
    final root = await _project();
    final api = docFile(root, loginApi);
    api.writeAsBytesSync([...utf8.encode(api.readAsStringSync()), 0xff]);
    // A feature rename leaves every FR cell as written, so the api names no
    // renamed label.
    expect(_rename(root, 'feature:login', 'signin').json['moved'], isNotEmpty);
  });

  test('an unrelated non-UTF-8 journey does not block a rename', () async {
    final root = await _project();
    docFile(root, _journeyPath).writeAsBytesSync([
      ...utf8.encode(_journey().replaceAll('login/email_login', 'other/story')),
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
  });

  test(
    'a non-UTF-8 journey that names a renamed story refuses the rename',
    () async {
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
    },
  );

  test('a journey with no frontmatter or a leading blank line gets its step lines rewritten', () async {
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

  test(
    'rename of a sub-feature rewrites its parent api cell and entry',
    () async {
      final root = await _nestedWithCartApi();
      _rename(root, 'feature:shop/cart', 'basket');
      final api = readDoc(root, shopApi);
      expect(api, contains('| basket/add_item/check_stock | `addItem` |'));
      expect(api, contains('  - basket/add_item/check_stock $_fpCheckStock\n'));
      final kinds = await _kindsOf(root, shopApi);
      expect(kinds, isNot(contains(FindingKind.frTraceUnresolved)));
      expect(kinds, isNot(contains(FindingKind.confirmedEntryStale)));
      expect(kinds, isNot(contains(FindingKind.confirmedEntryMalformed)));
    },
  );

  test('rename of a top feature keeps every cell of its api', () async {
    final root = await _nestedWithCartApi();
    _rename(root, 'feature:shop', 'market');
    final api = readDoc(root, 'specs/f02_market/API.md');
    expect(api, contains('| cart/add_item/check_stock | `addItem` |'));
    expect(api, contains('  - cart/add_item/check_stock $_fpCheckStock\n'));
    final cartApi = readDoc(root, 'specs/f02_market/f01_cart/API.md');
    expect(cartApi, contains('| add_item/check_stock | `addItem` |'));
  });

  test('rename of a sub-feature keeps the cells of its own api', () async {
    final root = await _nestedWithCartApi();
    final answer = _rename(root, 'feature:shop/cart', 'basket');
    expect(
      answer.json['rewritten'],
      isNot(contains('specs/f02_shop/f01_basket/API.md')),
    );
    final cartApi = readDoc(root, 'specs/f02_shop/f01_basket/API.md');
    expect(cartApi, contains('| add_item/check_stock | `addItem` |'));
    expect(cartApi, contains('  - add_item/check_stock $_fpCheckStock\n'));
  });

  test(
    'rename of a story under a group feature cuts the cell at the feature name',
    () async {
      final root = await _groupedProject();
      _rename(
        root,
        'user_story:foundation/layout/email_login',
        'password_login',
      );
      final api = readDoc(root, 'specs/foundation/f01_layout/API.md');
      expect(api, contains('| password_login/check_password | `signIn` |'));
      expect(
        api,
        contains('  - password_login/check_password $_fpStatement\n'),
      );
    },
  );

  test('rename of a story rewrites the traced_from entry and confirmed label of an fr', () async {
    final root = await _frTraceProject();
    _rename(root, 'user_story:login/reset_password', 'recover_password');
    final fr = readDoc(root, loginFr);
    expect(fr, contains('traced_from: [S1, login/recover_password#S3]\n'));
    expect(fr, contains('  - login/recover_password#S3 $_fp3\n'));
    expect(fr, isNot(contains('reset_password')));
    expect(fr, isNot(contains('draft')));
    expect(await _frKinds(root), isEmpty);
  });

  for (final entry in [
    'login/reset_password#S3 $_fp3',
    '"login/reset_password#S3 $_fp3"',
  ]) {
    test('a flow-list confirmed label $entry rewrites as a '
        'block-list one does', () async {
      final root = await _frTraceProject();
      final file = File('${root.path}/docs/$loginFr');
      file.writeAsStringSync(
        file.readAsStringSync().replaceFirst(
          'confirmed:\n  - S1 $_fp1\n  - login/reset_password#S3 $_fp3\n',
          'confirmed: [S1 $_fp1, $entry]\n',
        ),
      );
      _rename(root, 'user_story:login/reset_password', 'recover_password');
      final renamed = entry.replaceFirst('reset_password', 'recover_password');
      expect(
        readDoc(root, loginFr),
        contains('confirmed: [S1 $_fp1, $renamed]\n'),
      );
      expect(await _frKinds(root), isEmpty);
    });
  }

  test(
    'a block-list traced_from rewrites and the other entries keep their text',
    () async {
      final root = await _frTraceProject(
        tracedFrom:
            'traced_from:\n  - S1\n  - "login/reset_password#S3" # why\n',
      );
      _rename(root, 'user_story:login/reset_password', 'recover_password');
      final fr = readDoc(root, loginFr);
      expect(
        fr,
        contains(
          'traced_from:\n  - S1\n  - "login/recover_password#S3" # why\n',
        ),
      );
      expect(await _frKinds(root), isEmpty);
    },
  );

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
    test('traced_from with $shape rewrites with confirmed', () async {
      final root = await _frTraceProject(tracedFrom: tracedFrom);
      _rename(root, 'user_story:login/reset_password', 'recover_password');
      final fr = readDoc(root, loginFr);
      expect(fr, contains('login/recover_password#S3'));
      expect(fr, isNot(contains('reset_password')));
      expect(fr, contains('  - login/recover_password#S3 $_fp3\n'));
      expect(await _frKinds(root), isEmpty);
    });
  }

  test(
    'an own-story label S<N> and an unrenamed story label keep their text',
    () async {
      final root = await _frTraceProject();
      final before = readDoc(root, loginFr);
      _rename(root, 'user_story:login/email_login', 'password_login');
      final renamedFr = loginFr.replaceFirst('email_login', 'password_login');
      expect(readDoc(root, renamedFr), before);
    },
  );

  test('move of a story rewrites the traced_from entry and confirmed label of an fr', () async {
    final root = await _frTraceProject();
    writeIn(
      root,
      (s) =>
          answerMove(s, ['user_story:login/reset_password'], under: 'account'),
    );
    final fr = readDoc(root, loginFr);
    expect(fr, contains('traced_from: [S1, account/reset_password#S3]\n'));
    expect(fr, contains('  - account/reset_password#S3 $_fp3\n'));
    expect(fr, isNot(contains('draft')));
    expect(await _frKinds(root), contains(FindingKind.scenarioTraceUnresolved));
  });

  group('override entries', () {
    final shopFingerprint = fingerprintFor(_shopRule);
    final entries = [
      '$_shopAddress $shopFingerprint',
      '$rootAddress $rootFingerprint',
    ];

    Future<Directory> project() => writeCheckProject(
      extra: overrideFiles(
        extra: {
          'docs/prds/features/f02_shop/FEATURE.md': '# Shop\n',
          'docs/prds/features/f02_shop/f01_cart/FEATURE.md': '# Cart\n',
          'docs/$_shopDomain': domainDoc([_shopRule]),
          'docs/$_cartDomain': domainDoc([
            '- **INV-9** A cart is small.',
            '- Overrides: [INV-3](../DOMAIN.md#invariants) — stock, because stock',
            '- Overrides: [INV-3](../../DOMAIN.md#invariants) — expire, because stock',
          ], entries: entries),
        },
      ),
    );

    Future<Set<FindingKind>> linkKindsOf(
      Directory root,
      String docPath,
    ) async => {
      for (final f in (await checkOf(root, docPath: docPath)).findings)
        if (linkKinds.contains(f.kind)) f.kind,
    };

    test('a feature rename rewrites the name of an override entry and keeps '
        'type, id, and fingerprint', () async {
      final root = await project();
      expect(await linkKindsOf(root, _cartDomain), isEmpty);
      final answer = _rename(root, 'feature:shop', 'store');
      expect(answer.json['rewritten'], contains(_cartDomainOf('store')));
      final text = readDoc(root, _cartDomainOf('store'));
      expect(text, contains('  - domain:store#INV-3 $shopFingerprint\n'));
      expect(text, isNot(contains('domain:shop#')));
      expect(await linkKindsOf(root, _cartDomainOf('store')), isEmpty);
    });

    test(
      'an override entry naming a root spec doc is never rewritten',
      () async {
        final root = await project();
        _rename(root, 'feature:shop', 'project_domain');
        expect(
          readDoc(root, _cartDomainOf('project_domain')),
          contains('  - $rootAddress $rootFingerprint\n'),
        );
      },
    );

    test('an override entry naming a nested spec doc keeps the whole name '
        'path in step with the rename', () async {
      const cartRule = '- **INV-9** A cart is small.';
      const lineDomain = 'specs/f02_shop/f01_cart/f01_line/DOMAIN.md';
      final cartFingerprint = fingerprintFor(cartRule);
      final root = await writeCheckProject(
        extra: overrideFiles(
          extra: {
            'docs/prds/features/f02_shop/FEATURE.md': '# Shop\n',
            'docs/prds/features/f02_shop/f01_cart/FEATURE.md': '# Cart\n',
            'docs/prds/features/f02_shop/f01_cart/f01_line/FEATURE.md':
                '# Line\n',
            'docs/$_shopDomain': domainDoc([_shopRule]),
            'docs/$_cartDomain': domainDoc([cartRule]),
            'docs/$lineDomain': domainDoc(
              [
                '- Overrides: [INV-9](../DOMAIN.md#invariants) — tiny, because stock',
              ],
              entries: ['domain:shop/cart#INV-9 $cartFingerprint'],
            ),
          },
        ),
      );
      expect(await linkKindsOf(root, lineDomain), isEmpty);
      _rename(root, 'feature:shop', 'store');
      final moved = lineDomain.replaceFirst('f02_shop', 'f02_store');
      expect(
        readDoc(root, moved),
        contains('  - domain:store/cart#INV-9 $cartFingerprint\n'),
      );
      expect(await linkKindsOf(root, moved), isEmpty);
    });

    test('a rename leaves override entries of other docs untouched', () async {
      final root = await project();
      final before = readDoc(root, _cartDomain);
      _rename(root, 'feature:login', 'signin');
      expect(readDoc(root, _cartDomain), before);
    });
  });

  test(
    'an fr under the moved story keeps the entry naming a story that stays',
    () async {
      final root = await _frTraceProject();
      final before = readDoc(root, _resetFr);
      writeIn(
        root,
        (s) => answerMove(s, [
          'user_story:login/reset_password',
        ], under: 'account'),
      );
      final moved = _resetFr
          .replaceFirst('f01_login', 'f02_account')
          .replaceFirst('us02', 'us01');
      expect(readDoc(root, moved), before);
      expect(
        await _frKinds(root, docPath: moved),
        contains(FindingKind.scenarioTraceUnresolved),
      );
    },
  );
  _movedFrTraceTests();
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

const _shopDomain = 'specs/f02_shop/DOMAIN.md';
const _cartDomain = 'specs/f02_shop/f01_cart/DOMAIN.md';
String _cartDomainOf(String shop) => 'specs/f02_$shop/f01_cart/DOMAIN.md';

const _shopAddress = 'domain:shop#INV-3';
const _shopRule = '- **INV-3** A cart holds stock.';

const Set<FindingKind> _frKindSet = {
  ..._storyKinds,
  FindingKind.scenarioTraceUnresolved,
};

Future<Set<FindingKind>> _frKinds(
  Directory root, {
  String docPath = loginFr,
}) async => {
  for (final f in (await checkOf(root, docPath: docPath)).findings)
    if (_frKindSet.contains(f.kind)) f.kind,
};

void _movedFrTraceTests() {
  group('rewriteMovedFrTraces', () {
    const source = 'shop/cart/add_item';
    const landing = 'shop/cart/drop_item';
    const fpOne = '00c22a7251ca';
    const fpTwo = '11d33b8362db';

    bool isLanding(String story) =>
        story == landing || story == 'cart/drop_item' || story == 'drop_item';

    String? rewrite(String frontmatter) => rewriteMovedFrTraces(
      '---\n${frontmatter}verify_method: test\n---\n\n# Check\n',
      sourceStory: source,
      isTargetStory: isLanding,
    );

    test("a moved fr's bare scenario entries gain the name of the story the fr came from, each fingerprint unchanged", () {
      expect(
        rewrite(
          'traced_from:\n  - S1\n  - S3\n'
          'confirmed:\n  - S1 $fpOne\n  - S3 $fpTwo\n',
        ),
        '---\ntraced_from:\n  - $source#S1\n  - $source#S3\n'
        'confirmed:\n  - $source#S1 $fpOne\n  - $source#S3 $fpTwo\n'
        'verify_method: test\n---\n\n# Check\n',
      );
    });

    test(
      'an entry naming the landing story by a short or typed name becomes bare',
      () {
        expect(
          rewrite(
            'traced_from:\n  - $landing#S2\n  - cart/drop_item#S2\n'
            '  - drop_item#S4\n'
            'confirmed:\n  - cart/drop_item#S2 $fpOne\n',
          ),
          '---\ntraced_from:\n  - S2\n  - S2\n  - S4\n'
          'confirmed:\n  - S2 $fpOne\n'
          'verify_method: test\n---\n\n# Check\n',
        );
      },
    );

    test('an entry naming a third story is untouched', () {
      expect(
        rewrite(
          'traced_from:\n  - shop/cart/keep_item#S1\n'
          'confirmed:\n  - shop/cart/keep_item#S1 $fpOne\n',
        ),
        isNull,
      );
    });

    test('flow-list and quoted entries keep their list shape, and an fr with no traced_from changes only confirmed', () {
      expect(
        rewrite(
          "traced_from: [S1, 'S2', $landing#S3]\n"
          "confirmed: [S1 $fpOne, 'S2 $fpTwo']\n",
        ),
        "---\ntraced_from: [$source#S1, '$source#S2', S3]\n"
        "confirmed: [$source#S1 $fpOne, '$source#S2 $fpTwo']\n"
        'verify_method: test\n---\n\n# Check\n',
      );
      expect(
        rewrite('confirmed:\n  - S1 $fpOne\n'),
        '---\nconfirmed:\n  - $source#S1 $fpOne\n'
        'verify_method: test\n---\n\n# Check\n',
      );
    });
  });
}
