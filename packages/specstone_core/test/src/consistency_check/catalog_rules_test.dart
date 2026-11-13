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

const _errorDoc = 'specs/f01_login/ERROR.md';
const _shopErrorDoc = 'specs/f02_shop/ERROR.md';
const _flutterErrorDoc = 'specs/flutter/f01_login/ERROR.md';
const _jasprErrorDoc = 'specs/jaspr/f01_login/ERROR.md';

/// The error doc of one feature, its catalog one row per code.
///
/// The first code row sits on line 13, the second on line 14.
String _error(String title, List<String> codes) {
  const rowEnd = 'Enter the password again |';
  final rows = [
    for (final code in codes)
      '| `$code` | 400 | invalid_argument | the password is wrong | SignIn | $rowEnd',
  ];
  return '---\n---\n# $title\n\n## Error envelope\n\nThe envelope.\n\n'
      '## Error catalog\n\n'
      '| Code | Exit/HTTP | Category | Triggered by | Implemented by | Client guidance |\n'
      '|---|---|---|---|---|---|\n'
      '${rows.join('\n')}\n\n'
      '## Retry policy\n\n| Category | Retry? |\n|---|---|\n| invalid_argument | no |\n';
}

/// The shop feature doc, so the shop error doc hangs under a feature.
const _shopFeature = 'prds/features/f02_shop/FEATURE.md';

/// The files of a shop with an error doc of [codes].
Map<String, String> _shop(List<String> codes) => {
  'docs/$_shopFeature':
      '---\nvision:\n  - PV-01\ngoals:\n  - PG-01\n---\n\n# Shop\n\n'
      '## Problem\nShoppers need it.\n\n## Benefit hypothesis\nMore orders.\n\n'
      '## Success measures\nOrders per week.\n\n## Current alternatives\n'
      'Phone orders.\n\n## Feature flow\nBrowse, then buy.\n\n'
      '## Out-of-scope\n- Gift cards — not planned\n',
  'docs/$_shopErrorDoc': _error('Shop errors', codes),
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
        'docs/$_errorDoc': _error('Login errors', ['bad_password']),
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
        'docs/$_errorDoc': _error('Login errors', [
          'bad_password',
          'bad_password',
        ]),
      });

      expect(
        _found(report).singleWhere((f) => f.contains('duplicate')),
        '14 error_code_duplicate bad_password is written into the catalog more '
        'than once',
      );
    },
  );

  test('a row no unskipped edge case or scenario of its feature names is '
      'unraised', () async {
    final report = await _check({
      'docs/$_errorDoc': _error('Login errors', [
        'bad_password',
        'account_locked',
      ]),
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
      'docs/$_errorDoc': _error('Login errors', ['bad_password']),
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
      'docs/$_errorDoc': _error('Login errors', ['bad_password']),
      'docs/$loginFr': _frCase('a new code → `brand_new_code` is refused'),
    });

    expect(_found(report).where((f) => f.contains('uncataloged')), isEmpty);
  });

  test('a code an FR the record skips names is no uncataloged finding, and a '
      'row only skipped FRs name stays unraised', () async {
    final report = await _check({
      'docs/$_errorDoc': _error('Login errors', [
        'bad_password',
        'account_locked',
      ]),
      'docs/$loginFr': _frCase(
        'a locked account → `account_locked` is refused',
      ),
      'docs/$loginRecord':
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

  test('a code span in a section whose doc type sets no names_codes names no '
      'code', () async {
    final report = await _check({
      'docs/$_errorDoc': _error('Login errors', ['bad_password']),
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
      final report = checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
            'docs/$_errorDoc': _error('Login errors', ['bad_password']),
          },
        ),
      );

      expect(_found(report), isEmpty);
    },
  );

  test('a story scenario naming a code is read like an FR edge case', () async {
    final report = await _check({
      'docs/$_errorDoc': _error('Login errors', ['bad_password']),
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
    final report = checkOf(
      await writeTwinProject(
        extra: {
          'docs/$_flutterErrorDoc': _error('Login errors', ['bad_password']),
          'docs/$_jasprErrorDoc': _error('Login errors', ['account_locked']),
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
    final report = checkOf(
      await writeNestedProject(
        extra: {
          'docs/$_shopErrorDoc': _error('Shop errors', ['out_of_stock']),
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
    final report = checkOf(
      await writeTwinProject(
        extra: {
          'docs/$_flutterErrorDoc': _error('Login errors', ['bad_password']),
          'docs/$_jasprErrorDoc': _error('Login errors', ['bad_password']),
          ...edit(loginFr, [
            (
              'An empty password → refused.',
              'An empty password → `bad_password` is refused.',
            ),
          ]),
          'docs/specs/jaspr/f01_login/IMPLEMENTATION.md':
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
      ['$_jasprErrorDoc error_code_unraised'],
    );
  });

  test('a run kept to one target reads the codes of every target, so it '
      'agrees with the full run', () async {
    final project = await writeTwinProject(
      extra: {
        'docs/$_flutterErrorDoc': _error('Login errors', ['bad_password']),
        'docs/$_jasprErrorDoc': _error('Login errors', ['account_locked']),
        ...edit(loginFr, [
          (
            'An empty password → refused.',
            'An empty password → `bad_password` is refused.',
          ),
        ]),
      },
    );
    List<String> run(String? codeTarget) {
      final session = openSession(project);
      try {
        return [
          for (final f in runCheck(session, codeTarget: codeTarget).findings)
            if (_catalogKinds.contains(f.kind)) '${f.path} ${f.kind.wire}',
        ];
      } finally {
        session.close();
      }
    }

    final jaspr = run('jaspr');
    expect(jaspr, contains('$loginFr error_code_uncataloged'));
    expect(jaspr, contains('$_jasprErrorDoc error_code_unraised'));
    expect(jaspr.where((f) => f.contains('flutter')), isEmpty);
  });
}
