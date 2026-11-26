// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';

const Set<FindingKind> _catalogKinds = {
  FindingKind.errorCodeDuplicate,
  FindingKind.errorCodeUnraised,
  FindingKind.errorCodeUncataloged,
};

const _apiDoc = 'specs/f01_login/API.md';
const _shopApiDoc = 'specs/f02_shop/API.md';
const _flutterApiDoc = 'specs/flutter/f01_login/API.md';
const _jasprApiDoc = 'specs/jaspr/f01_login/API.md';

/// The API doc of one feature, its `Errors` catalog one row per code.
///
/// The first code row sits on line 13, the second on line 14.
String _api(String title, List<String> codes) {
  const rowEnd = 'Enter the password again | no |';
  final rows = [
    for (final code in codes)
      '| `$code` | 400 | the password is wrong | $rowEnd',
  ];
  return '---\n---\n# $title\n\n## Operations\n\n- sign in\n\n'
      '## Errors\n\n'
      '| Code | Status or exit | Condition | Client action | Retryable |\n'
      '|---|---|---|---|---|\n'
      '${rows.join('\n')}\n';
}

/// A layer that takes the API doc back to one per target, over the twin
/// project's shared one.
const _perTargetApi = <String, String>{
  '.specstone/templates/api.yaml': 'id: api\nper_target: true\n',
};

/// The shop feature doc, so the shop API doc hangs under a feature.
const _shopFeature = 'prds/features/f02_shop/FEATURE.md';

/// The files of a shop with an API doc of [codes].
Map<String, String> _shop(List<String> codes) => {
  'docs/$_shopFeature':
      '---\nvision:\n  - PV-01\ngoals:\n  - PG-01\n---\n\n# Shop\n\n'
      '## Problem\nShoppers need it.\n\n## Benefit hypothesis\nMore orders.\n\n'
      '## Success measures\nOrders per week.\n\n## Current alternatives\n'
      'Phone orders.\n\n## Feature flow\nBrowse, then buy.\n\n'
      '## Out-of-scope\n- Gift cards — not planned\n',
  'docs/$_shopApiDoc': _api('Shop', codes),
};

/// The FR doc whose one edge case is [caseText].
///
/// The edge case sits on line 17.
String _frCase(String caseText) =>
    '---\ntraced_from:\n  - S2\nverify_method: test\n'
    'confirmed:\n  - S2 ${fingerprintFor(loginScenario2)}\n---\n\n'
    '# Check the password\n\n## Statement\n\n$checkPasswordStatement\n\n'
    '## Edge cases\n\n1. E01 — $caseText\n\n'
    '## Rationale\n\nA wrong password must not sign in.\n\n'
    '## Verification\n\nTest: a wrong password is refused.\n';

Future<CheckReport> _check(Map<String, String> extra) async => checkOf(
  await writeCheckProject(
    extra: extra,
    unstamped: {
      for (final path in extra.keys)
        if (path.startsWith('docs/')) path,
    },
  ),
);

/// Returns `<line> <kind> <message>` per catalog finding, findings order.
List<String> _found(CheckReport report) => [
  for (final f in report.findings.where((f) => _catalogKinds.contains(f.kind)))
    '${f.line} ${f.kind.wire} ${f.message}',
];

void main() {
  test(
    'an edge case naming its own feature catalog code gives no finding',
    () async {
      final report = await _check({
        'docs/$_apiDoc': _api('Login', ['bad_password']),
        'docs/$loginFr': _frCase(
          'an empty password → `bad_password` is refused',
        ),
      });

      expect(_found(report), isEmpty);
    },
  );

  test(
    'a code with two rows in one catalog is a duplicate at the second row',
    () async {
      final report = await _check({
        'docs/$_apiDoc': _api('Login', ['bad_password', 'bad_password']),
      });

      expect(
        _found(report).singleWhere((f) => f.contains('duplicate')),
        '14 error_code_duplicate bad_password is written into the catalog more '
        'than once',
      );
    },
  );

  test('a run kept to one doc or target reports the catalog findings of its '
      'files only', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$_apiDoc': _api('Login', ['bad_password', 'bad_password']),
        'docs/$loginFr': _frCase(
          'an empty password → `bad_password` is refused',
        ),
        ..._shop(['doc_not_found', 'doc_not_found']),
      },
      unstamped: {'docs/$_apiDoc', 'docs/$loginFr', 'docs/$_shopApiDoc'},
    );

    List<String> duplicates(CheckReport report) => [
      for (final f in report.findings)
        if (f.kind == FindingKind.errorCodeDuplicate) f.path,
    ];

    expect(
      duplicates(await checkOf(project)),
      unorderedEquals([_apiDoc, _shopApiDoc]),
    );
    expect(duplicates(await checkOf(project, docPath: _apiDoc)), [_apiDoc]);
    expect(duplicates(await checkOf(project, target: 'login')), [_apiDoc]);
  });

  test('a row no unskipped edge case or scenario of its feature names is '
      'unraised', () async {
    final report = await _check({
      'docs/$_apiDoc': _api('Login', ['bad_password', 'account_locked']),
      'docs/$loginFr': _frCase('an empty password → `bad_password` is refused'),
    });

    expect(
      _found(report).singleWhere((f) => f.contains('unraised')),
      '14 error_code_unraised no requirement of login names account_locked',
    );
  });

  test('a code span naming another feature catalog code while its own catalog '
      'lacks it is uncataloged', () async {
    final report = await _check({
      'docs/$_apiDoc': _api('Login', ['bad_password']),
      'docs/$loginFr': _frCase('a missing doc → `doc_not_found` is refused'),
      ..._shop(['doc_not_found']),
    });

    expect(
      _found(report).singleWhere((f) => f.contains('uncataloged')),
      '17 error_code_uncataloged doc_not_found names no row of the catalog '
      'of login',
    );
  });

  test('a code span no catalog of the project holds names no code', () async {
    final report = await _check({
      'docs/$_apiDoc': _api('Login', ['bad_password']),
      'docs/$loginFr': _frCase('a new code → `brand_new_code` is refused'),
    });

    expect(_found(report).where((f) => f.contains('uncataloged')), isEmpty);
  });

  test('a code an FR the record skips names is no uncataloged finding, and a '
      'row only skipped FRs name stays unraised', () async {
    final report = await _check({
      'docs/$_apiDoc': _api('Login', ['bad_password', 'account_locked']),
      'docs/$loginFr': _frCase(
        'a locked account → `account_locked` is refused',
      ),
      loginRecord:
          "---\nstatuses:\n  - 'email_login:implemented'\n"
          "  - 'email_login/check_password:skipped:no web view'\n---\n\n"
          '# Login implementation\n',
    });

    expect(_found(report).where((f) => f.contains('uncataloged')), isEmpty);
    expect(_found(report).where((f) => f.contains('unraised')), [
      '13 error_code_unraised no requirement of login names bad_password',
      '14 error_code_unraised no requirement of login names account_locked',
    ]);
  });

  test('a skipped FR naming a code its own catalog lacks is no uncataloged'
      ' finding', () async {
    final report = await _check({
      'docs/$_apiDoc': _api('Login', ['bad_password']),
      'docs/$loginFr': _frCase('a missing doc → `doc_not_found` is refused'),
      ..._shop(['doc_not_found']),
      loginRecord:
          "---\nstatuses:\n  - 'email_login:implemented'\n"
          "  - 'email_login/check_password:skipped:no web view'\n---\n\n"
          '# Login implementation\n',
    });

    expect(_found(report).where((f) => f.contains('uncataloged')), isEmpty);
  });

  test(
    'an FR whose feature chain holds no error doc gives no catalog finding',
    () async {
      final report = await _check({
        'docs/$loginFr': _frCase('a missing doc → `doc_not_found` is refused'),
        ..._shop(['doc_not_found']),
      });

      expect(_found(report).where((f) => f.contains('uncataloged')), isEmpty);
    },
  );

  test('a components code span naming a code another catalog holds is no'
      ' uncataloged finding', () async {
    final report = await _check({
      'docs/$_apiDoc': _api('Login', ['bad_password']),
      'docs/$loginFr': _frCase('an empty password → `bad_password` is refused'),
      'docs/$loginArchitecture':
          '---\ncovers:\n  - app/lib/\n---\n\n# Login architecture\n\n'
          '## Components\n\n'
          '| Component | Responsibility |\n|---|---|\n'
          '| Sign-in | Raises `doc_not_found` for a wrong password |\n',
      ..._shop(['doc_not_found']),
    });

    expect(_found(report).where((f) => f.contains('uncataloged')), isEmpty);
  });

  test('a code span in a section whose doc type sets no names_codes names no '
      'code', () async {
    final report = await _check({
      'docs/$_apiDoc': _api('Login', ['bad_password']),
      'docs/$loginFr': _frCase('an empty password → `bad_password` is refused'),
      'docs/$loginArchitecture':
          '---\ncovers:\n  - app/lib/\n---\n\n# Login architecture\n\n'
          '## Components\n\n'
          '| Component | Responsibility |\n|---|---|\n'
          '| Sign-in | Raises `account_locked` for a wrong password |\n',
    });

    expect(_found(report), isEmpty);
  });

  test(
    'a merged set that sets neither catalog nor names_codes runs no rule',
    () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
            'docs/$_apiDoc': _api('Login', ['bad_password']),
          },
        ),
      );

      expect(_found(report), isEmpty);
    },
  );

  test('a catalog of a doc type under another id is checked as the shipped'
      ' one is', () async {
    final report = await _check({
      '.specstone/templates/fault_list.yaml':
          'id: fault_list\n'
          'description: Faults.\npath: specs/f{nn}_{slug}/FAULTS.md\n'
          'parent: feature\n'
          'sections:\n  - id: faults\n    header: Faults\n'
          '    lint:\n      catalog:\n        column: Code\n',
      'docs/specs/f01_login/FAULTS.md':
          '---\n---\n# Login faults\n\n## Faults\n\n'
          '| Code | Note |\n|---|---|\n'
          '| `bad_password` | first |\n| `bad_password` | second |\n',
    });

    expect(
      _found(report).singleWhere((f) => f.contains('duplicate')),
      '10 error_code_duplicate bad_password is written into the catalog more '
      'than once',
    );
  });

  test('a code named only in a statement or an input_output section reads as raised', () async {
    final report = await _check({
      '.specstone/templates/fr.yaml':
          'sections:\n'
          '  - id: statement\n    lint:\n      names_codes: true\n'
          '  - id: input_output\n    lint:\n      names_codes: true\n',
      'docs/$_apiDoc': _api('Login', ['bad_password', 'account_locked']),
      'docs/$loginFr':
          '---\ntraced_from:\n  - S2\nverify_method: test\n'
          'confirmed:\n  - S2 ${fingerprintFor(loginScenario2)}\n---\n\n'
          '# Check the password\n\n## Statement\n\n'
          'The system shall refuse `bad_password` within 1 s.\n\n'
          'It never answers `doc_not_found`.\n\n'
          '## Input / Output\n\nRaises `account_locked` for a locked account.\n\n'
          '## Rationale\n\nA wrong password must not sign in.\n\n'
          '## Verification\n\nTest: a wrong password is refused.\n',
      ..._shop(['doc_not_found']),
    });

    final login = [
      for (final f in report.findings)
        if (_catalogKinds.contains(f.kind) &&
            !(f.kind == FindingKind.errorCodeUnraised && f.path == _shopApiDoc))
          '${f.line} ${f.kind.wire} ${f.message}',
    ];
    expect(login, [
      '15 error_code_uncataloged doc_not_found names no row of the catalog of login',
    ]);
  });

  test('a story scenario naming a code is read like an FR edge case', () async {
    final report = await _check({
      'docs/$_apiDoc': _api('Login', ['bad_password']),
      'docs/$loginStory': checkProjectFiles()['docs/$loginStory']!.replaceFirst(
        '- **Then** the Agent sees the sign-in refused',
        '- **Then** the Agent sees `account_locked`',
      ),
      ..._shop(['account_locked']),
    });

    expect(
      _found(report).singleWhere((f) => f.contains('uncataloged')),
      startsWith('26 error_code_uncataloged account_locked names no row'),
    );
  });

  test('two targets: each catalog is checked in its own target alone, and an '
      'uncataloged message names its target', () async {
    final report = await checkOf(
      await writeTwinProject(
        extra: {
          ..._perTargetApi,
          'docs/$_flutterApiDoc': _api('Login', ['bad_password']),
          'docs/$_jasprApiDoc': _api('Login', ['account_locked']),
          ...edit(loginFr, [
            (
              'An empty password → refused.',
              'An empty password → `bad_password` is refused.',
            ),
          ]),
        },
      ),
    );

    final uncataloged = _found(report)
        .where((f) => f.contains('uncataloged'))
        .toList();
    expect(uncataloged, hasLength(1));
    expect(uncataloged.single, contains('jaspr'));
  });

  test('a requirement under a sub-feature counts toward the catalog of the '
      'nearest feature above it that holds one', () async {
    final report = await checkOf(
      await writeNestedProject(
        extra: {
          'docs/$_shopApiDoc': _api('Shop', ['out_of_stock']),
          'docs/$cartAddFr': nestedFiles()['docs/$cartAddFr']!.replaceFirst(
            'A sold-out item → refused.',
            'A sold-out item → `out_of_stock`.',
          ),
        },
      ),
    );

    expect(_found(report), isEmpty);
  });

  test('a skipped FR counts toward nothing, in a project with named targets '
      'too', () async {
    final report = await checkOf(
      await writeTwinProject(
        extra: {
          ..._perTargetApi,
          'docs/$_flutterApiDoc': _api('Login', ['bad_password']),
          'docs/$_jasprApiDoc': _api('Login', ['bad_password']),
          ...edit(loginFr, [
            (
              'An empty password → refused.',
              'An empty password → `bad_password` is refused.',
            ),
          ]),
          '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md':
              "---\nstatuses:\n  - 'email_login:skipped:no web'\n---\n\n"
              '# Jaspr implementation\n',
        },
      ),
    );

    expect(
      [
        for (final f in report.findings)
          if (_catalogKinds.contains(f.kind)) '${f.path} ${f.kind.wire}',
      ],
      ['$_jasprApiDoc error_code_unraised'],
    );
  });

  group('a project catalog', () {
    const faultsDoc = 'specs/FAULTS.md';

    /// A project doc type with no parent whose one table is a catalog.
    ///
    /// Its first code row sits on line 9, the second on line 10.
    Map<String, String> faults(
      List<String> codes, {
      String path = faultsDoc,
    }) => {
      '.specstone/templates/fault_registry.yaml':
          'id: fault_registry\n'
          'description: Faults.\npath: specs/FAULTS.md\n'
          'per_target: ${path != faultsDoc}\n'
          'sections:\n  - id: faults\n    header: Faults\n'
          '    lint:\n      catalog:\n        column: Code\n',
      'docs/$path':
          '---\n---\n# Faults\n\n## Faults\n\n'
          '| Code | Note |\n|---|---|\n'
          '${[for (final code in codes) '| `$code` | note |'].join('\n')}\n',
    };

    test('of a target with no feature catalog holds the target to its codes '
        'both ways', () async {
      final report = await _check({
        ...faults(['bad_password', 'account_locked']),
        'docs/$loginFr': _frCase(
          'an empty password → `bad_password` is refused',
        ),
      });

      expect(_found(report), [
        '10 error_code_unraised no requirement names account_locked',
      ]);
    });

    test('row no requirement of its target names is unraised, each target '
        'reading its own requirements', () async {
      final report = await checkOf(
        await writeTwinProject(
          extra: {
            ...faults(['bad_password'], path: 'specs/flutter/FAULTS.md'),
            ...faults(['bad_password'], path: 'specs/jaspr/FAULTS.md'),
            ...edit(loginFr, [
              (
                'An empty password → refused.',
                'An empty password → `bad_password` is refused.',
              ),
            ]),
            '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md':
                "---\nstatuses:\n  - 'email_login:skipped:no web'\n---\n\n"
                '# Jaspr implementation\n',
          },
        ),
      );

      expect(_found(report), [
        '9 error_code_unraised no requirement in jaspr names bad_password',
      ]);
    });

    test('code a feature requirement names is held by the project catalog '
        'when its feature catalog lacks it', () async {
      final report = await _check({
        ...faults(['shared_code']),
        'docs/$_apiDoc': _api('Login', ['bad_password']),
        'docs/$loginFr': _frCase('a shared fault → `shared_code` is refused'),
      });

      expect(_found(report), [
        '13 error_code_unraised no requirement of login names bad_password',
      ]);
    });

    test('code neither the feature nor the project catalog holds is '
        'uncataloged, naming its target', () async {
      final report = await checkOf(
        await writeTwinProject(
          extra: {
            ..._perTargetApi,
            ...faults(['shared_code'], path: 'specs/jaspr/FAULTS.md'),
            'docs/$_jasprApiDoc': _api('Login', ['bad_password']),
            'docs/$_shopFeature': _shop([])['docs/$_shopFeature']!,
            'docs/specs/jaspr/f02_shop/API.md': _api('Shop', ['doc_not_found']),
            ...edit(loginFr, [
              (
                'An empty password → refused.',
                'An empty password → `bad_password` and `doc_not_found`.',
              ),
            ]),
          },
        ),
      );

      final uncataloged = report.findings
          .where((f) => f.kind == FindingKind.errorCodeUncataloged)
          .toList();
      expect(uncataloged.map((f) => f.keys['code']), ['doc_not_found']);
      expect(uncataloged.single.message, contains('jaspr'));
    });

    test(
      'rows twice in one catalog give a duplicate at the second row',
      () async {
        final report = await _check({
          ...faults(['bad_password', 'bad_password']),
        });

        expect(_found(report).where((f) => f.contains('duplicate')), [
          '10 error_code_duplicate bad_password is written into the catalog more than once',
        ]);
      },
    );

    test('with a requirement whose feature chain holds no catalog gives no '
        'uncataloged finding', () async {
      final report = await _check({
        ...faults(['shared_code']),
        'docs/$loginFr': _frCase('a missing doc → `doc_not_found` is refused'),
        ..._shop(['doc_not_found']),
      });

      expect(_found(report).where((f) => f.contains('uncataloged')), isEmpty);
    });

    test('is no catalog of a feature-level doc whose feature doc is missing, '
        'so its rows raise nothing', () async {
      final report = await _check({
        'docs/$_apiDoc': _api('Login', ['bad_password']),
        'docs/$loginFr': _frCase(
          'an empty password → `bad_password` is refused',
        ),
        'docs/$_shopApiDoc': _api('Shop', ['doc_not_found']),
      });

      expect(_found(report), isEmpty);
    });

    test('rows beside a feature catalog leave the feature findings as they '
        'are', () async {
      final report = await _check({
        ...faults(['shared_code']),
        'docs/$_apiDoc': _api('Login', ['bad_password', 'account_locked']),
        'docs/$loginFr': _frCase(
          'an empty password → `bad_password` is refused',
        ),
      });

      expect(_found(report), [
        '9 error_code_unraised no requirement names shared_code',
        '14 error_code_unraised no requirement of login names account_locked',
      ]);
    });
  });

  test('a run kept to one target reads the codes of every target, so it '
      'agrees with the full run', () async {
    final project = await writeTwinProject(
      extra: {
        ..._perTargetApi,
        'docs/$_flutterApiDoc': _api('Login', ['bad_password']),
        'docs/$_jasprApiDoc': _api('Login', ['account_locked']),
        ...edit(loginFr, [
          (
            'An empty password → refused.',
            'An empty password → `bad_password` is refused.',
          ),
        ]),
      },
    );
    Future<List<String>> run(String? codeTarget) async {
      final session = openSession(project);
      try {
        return [
          for (final f in (await runCheck(
            session,
            codeTarget: codeTarget,
          )).findings)
            if (_catalogKinds.contains(f.kind)) '${f.path} ${f.kind.wire}',
        ];
      } finally {
        session.close();
      }
    }

    final jaspr = await run('jaspr');
    expect(jaspr, contains('$loginFr error_code_uncataloged'));
    expect(jaspr, contains('$_jasprApiDoc error_code_unraised'));
    expect(jaspr.where((f) => f.contains('flutter')), isEmpty);
  });

  test('a table without the code column gives no catalog row', () async {
    final report = await _check({
      'docs/$_apiDoc':
          '${_api('Login', ['bad_password'])}\n'
          '| Role | Allowed |\n|---|---|\n'
          '| `ADMIN` | yes |\n| `MEMBER` | no |\n',
      'docs/$loginFr': _frCase('an empty password → `bad_password` is refused'),
    });

    expect(_found(report), isEmpty);
  });

  test(
    'each catalog table reads the code column its own header names',
    () async {
      final report = await _check({
        'docs/$_apiDoc':
            '---\n---\n# Login\n\n## Operations\n\n- sign in\n\n'
            '## Errors\n\n'
            '| Role | Allowed |\n|---|---|\n| `ADMIN` | yes |\n\n'
            '| Group | Code | Status or exit | Condition | Client action | Retryable |\n'
            '|---|---|---|---|---|---|\n'
            '| auth | `bad_password` | 400 | wrong | again | no |\n'
            '| auth | `account_locked` | 423 | locked | wait | no |\n',
        'docs/$loginFr': _frCase(
          'an empty password → `bad_password` is refused',
        ),
      });

      expect(_found(report), [
        '18 error_code_unraised no requirement of login names account_locked',
      ]);
    },
  );
}
