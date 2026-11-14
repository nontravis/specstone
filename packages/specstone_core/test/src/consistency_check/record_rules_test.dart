// The expected texts are plan literals kept as written.

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';

const Set<FindingKind> _recordKinds = {
  FindingKind.recordEntryUnresolved,
  FindingKind.recordEntryDuplicate,
  FindingKind.skipReasonMissing,
  FindingKind.skipWithCode,
  FindingKind.entryUnderSkip,
  FindingKind.featureStatusWritten,
};

const _recordLayer =
    'id: implementation\n'
    'description: One feature record per target.\n'
    'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
    'parent: feature\n'
    'per_target: true\n'
    'fields:\n'
    '  - id: statuses\n'
    '    type: record_status\n'
    '    list: true\n'
    '  - id: implements\n'
    '    type: output_ref\n'
    '    list: true\n'
    '    pointer: item_exact\n'
    '  - id: tests\n'
    '    type: output_ref\n'
    '    list: true\n'
    '    pointer: item_test\n';

const _recordPath = 'specs/f01_login/IMPLEMENTATION.md';
const _shopRecord = 'specs/f02_shop/IMPLEMENTATION.md';
const _cartRecord = 'specs/f02_shop/f01_cart/IMPLEMENTATION.md';

// The story and the FR of the login fixture, named relative to `login`.
const _story = 'email_login';
const _fr = 'email_login/check_password';

/// Returns a record: `statuses` first, then `implements`, one quoted line each.
///
/// With [statuses], the first line is file line 3, and `implements` follows
/// its last; with none, `implements` opens at line 2. A `front` text comes
/// first.
String _record({
  List<String> statuses = const [],
  List<String> code = const [],
  List<String> tests = const [],
  String front = '',
}) {
  String list(String key, List<String> lines) => lines.isEmpty
      ? ''
      : "$key:\n${[for (final l in lines) "  - '$l'\n"].join()}";
  return '---\n$front${list('statuses', statuses)}${list('implements', code)}'
      '${list('tests', tests)}---\n\n# Record\n';
}

/// The file line of the [i]th `statuses` item, from 0, under no `front`.
int _statusLine(int i) => 3 + i;

/// The file line of the [j]th `implements` item after [statusCount] statuses.
int _codeLine(int statusCount, int j) =>
    (statusCount == 0 ? 3 : 4 + statusCount) + j;

/// The file line of the [j]th `tests` item after [statusCount] statuses and
/// [codeCount] `implements` lines.
int _testLine(int statusCount, int codeCount, int j) =>
    2 +
    (statusCount == 0 ? 0 : 1 + statusCount) +
    (codeCount == 0 ? 0 : 1 + codeCount) +
    1 +
    j;

Map<String, String> _oneTarget(String path, String record) => {
  '.specstone/templates/implementation.yaml': _recordLayer,
  '.specstone/config.yaml': '${shippedPinsConfig()}code_root: app\n',
  'docs/$path': record,
};

Future<CheckReport> _check(
  String record, {
  String path = _recordPath,
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) async => checkOf(
  await writeCheckProject(
    extra: {..._oneTarget(path, record), ...extra},
    without: without,
    // A stamp would add an `approved:` line and move every line below it.
    unstamped: {'docs/$path'},
  ),
);

/// Checks the nested project, the `shop` record holding [shop] and the
/// `shop/cart` record [cart].
Future<CheckReport> _checkNested(String shop, String cart) async => checkOf(
  await writeCheckProject(
    extra: {
      ...nestedFiles(),
      ..._oneTarget(_shopRecord, shop),
      'docs/$_cartRecord': cart,
    },
    unstamped: {'docs/$_shopRecord', 'docs/$_cartRecord'},
  ),
);

/// Returns `<line> <kind>` per record finding on the record at [path].
List<String> _found(CheckReport report, [String path = _recordPath]) => [
  for (final f in report.findings)
    if (f.path == path && _recordKinds.contains(f.kind))
      '${f.line} ${f.kind.wire}',
];

Finding _only(CheckReport report, FindingKind kind) =>
    report.findings.singleWhere((f) => f.kind == kind);

void main() {
  test('a named, resolved, consistent record gives no '
      'finding', () async {
    final report = await _check(
      _record(
        statuses: ['$_story:implemented', '$_fr:planned'],
        code: ['$_story:lib/a.dart:SignInPage'],
      ),
    );

    expect(_found(report), isEmpty);
  });

  test('an entry no FR or story carries is unresolved, '
      'and names itself', () async {
    final report = await _check(
      _record(statuses: ['$_story/pin_toast:planned']),
    );

    expect(_found(report), ['${_statusLine(0)} record_entry_unresolved']);
    expect(
      _only(report, FindingKind.recordEntryUnresolved).toJson(),
      containsPair('entry', '$_story/pin_toast'),
    );
  });

  test('a story of another feature is unresolved: an '
      'entry names its item relative to its feature', () async {
    final report = await _check(_record(statuses: ['signup/create:planned']));

    expect(_found(report), ['${_statusLine(0)} record_entry_unresolved']);
  });

  test('a second statuses line is a duplicate; two '
      'implements lines are no finding', () async {
    final report = await _check(
      _record(
        statuses: ['$_story:planned', '$_story:implemented'],
        code: ['$_story:lib/a.dart', '$_story:lib/b.dart'],
      ),
    );

    expect(_found(report), ['${_statusLine(1)} record_entry_duplicate']);
    expect(
      _only(report, FindingKind.recordEntryDuplicate).toJson(),
      containsPair('entry', _story),
    );
  });

  test('a skip with no reason is reported at its '
      'statuses line; with a reason and no code it is no finding', () async {
    final bare = await _check(_record(statuses: ['$_story:skipped']));
    final blank = await _check(_record(statuses: ['$_story:skipped:']));
    final given = await _check(
      _record(statuses: ['$_story:skipped:no toast host on the web']),
    );

    expect(_found(bare), ['${_statusLine(0)} skip_reason_missing']);
    expect(
      _only(bare, FindingKind.skipReasonMissing).toJson(),
      containsPair('entry', _story),
    );
    expect(_found(blank), ['${_statusLine(0)} skip_reason_missing']);
    expect(_found(given), isEmpty);
  });

  test('a skip naming two code paths is reported at each '
      'implements line', () async {
    final report = await _check(
      _record(
        statuses: ['$_story:skipped:no toast host'],
        code: ['$_story:lib/a.dart', '$_story:lib/b.dart'],
      ),
    );

    expect(_found(report), [
      '${_codeLine(1, 0)} skip_with_code',
      '${_codeLine(1, 1)} skip_with_code',
    ]);
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.skipWithCode) f.keys['entry'],
      ],
      [_story, _story],
    );
  });

  test('under the feature skip a story with another '
      'status is reported, naming the skip; a story skip or no entry is '
      'none', () async {
    final report = await _check(
      _record(statuses: [':skipped:no web view', '$_story:implemented']),
    );
    final skipped = await _check(
      _record(statuses: [':skipped:no web view', '$_story:skipped:why']),
    );
    final absent = await _check(_record(statuses: [':skipped:no web view']));

    expect(_found(report), ['${_statusLine(1)} entry_under_skip']);
    expect(
      _only(report, FindingKind.entryUnderSkip).toJson(),
      allOf(containsPair('entry', _story), containsPair('skip', 'login')),
    );
    expect(_found(skipped), isEmpty);
    expect(_found(absent), isEmpty);
  });

  test('the feature skip in its record covers a nested '
      "feature's record", () async {
    final report = await _checkNested(
      _record(statuses: [':skipped:no shop']),
      _record(statuses: ['add_item:implemented']),
    );

    expect(_found(report, _cartRecord), ['${_statusLine(0)} entry_under_skip']);
    expect(
      _only(report, FindingKind.entryUnderSkip).toJson(),
      containsPair('skip', 'shop'),
    );
    expect(_found(report, _shopRecord), isEmpty);
  });

  test('under a story skip an FR with a planned status '
      'and a code path is reported at both lines', () async {
    final report = await _check(
      _record(
        statuses: ['$_story:skipped:why', '$_fr:planned'],
        code: ['$_fr:lib/a.dart'],
      ),
    );

    expect(_found(report), [
      '${_statusLine(1)} entry_under_skip',
      '${_codeLine(2, 0)} entry_under_skip',
    ]);
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.entryUnderSkip) f.keys['skip'],
      ],
      [_story, _story],
    );
  });

  test('the feature entry implemented is '
      'feature_status_written', () async {
    final report = await _check(_record(statuses: [':implemented']));

    expect(_found(report), ['${_statusLine(0)} feature_status_written']);
  });

  test('an entry whose story left the PRD by hand is '
      'unresolved', () async {
    final report = await _check(
      _record(statuses: ['$_story:planned']),
      without: {'docs/$loginStory', 'docs/$loginFr', 'docs/$loginNf'},
    );

    expect(_found(report), ['${_statusLine(0)} record_entry_unresolved']);
  });

  test('a project whose merged set holds no record doc '
      'type runs no rule of this FR', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
          'docs/$_recordPath': _record(
            statuses: ['ghost:skipped', ':implemented'],
            code: ['ghost:lib/a.dart'],
          ),
        },
      ),
    );

    expect(_found(report), isEmpty);
  });

  test('a draft record is checked as any record', () async {
    final report = await _check(
      _record(front: 'draft: true\n', statuses: ['ghost:planned']),
    );

    // `draft:` takes line 2, so the first statuses item sits one line lower.
    expect(_found(report), ['${_statusLine(0) + 1} record_entry_unresolved']);
  });

  test('an implements line with no statuses line reads '
      'planned and is no finding', () async {
    final report = await _check(_record(code: ['$_story:lib/a.dart']));

    expect(_found(report), isEmpty);
  });

  test('an implements line for no such FR is '
      'unresolved', () async {
    final report = await _check(
      _record(code: ['$_story/pin_toast:lib/pin.dart']),
    );

    expect(_found(report), ['${_codeLine(0, 0)} record_entry_unresolved']);
    expect(
      _only(report, FindingKind.recordEntryUnresolved).toJson(),
      containsPair('entry', '$_story/pin_toast'),
    );
  });

  test('under the feature skip an implements line with no '
      'statuses line is entry_under_skip', () async {
    final report = await _check(
      _record(statuses: [':skipped:no web view'], code: ['$_story:lib/a.dart']),
    );

    expect(_found(report), ['${_codeLine(1, 0)} entry_under_skip']);
  });

  test('a skip with no reason and two paths gives one '
      'finding per faulty line', () async {
    final report = await _check(
      _record(
        statuses: ['$_story:skipped'],
        code: ['$_story:lib/a.dart', '$_story:lib/b.dart'],
      ),
    );

    expect(_found(report), [
      '${_statusLine(0)} skip_reason_missing',
      '${_codeLine(1, 0)} skip_with_code',
      '${_codeLine(1, 1)} skip_with_code',
    ]);
  });

  test('an FR skip under a story skip, with a path, is '
      'skip_with_code and not entry_under_skip', () async {
    final report = await _check(
      _record(
        statuses: ['$_story:skipped:why', '$_fr:skipped:why'],
        code: ['$_fr:lib/a.dart'],
      ),
    );

    expect(_found(report), ['${_codeLine(2, 0)} skip_with_code']);
  });

  test('an implements line naming the feature is '
      'feature_status_written; under its own skip, skip_with_code', () async {
    final written = await _check(_record(code: [':lib/a.dart', ':lib/b.dart']));
    final planned = await _check(
      _record(statuses: [':planned'], code: [':lib/a.dart']),
    );
    final skipped = await _check(
      _record(
        statuses: [':skipped:no web view'],
        code: [':lib/a.dart', ':lib/b.dart'],
      ),
    );

    expect(_found(written), [
      '${_codeLine(0, 0)} feature_status_written',
      '${_codeLine(0, 1)} feature_status_written',
    ]);
    expect(_found(planned), [
      '${_statusLine(0)} feature_status_written',
      '${_codeLine(1, 0)} feature_status_written',
    ]);
    expect(_found(skipped), [
      '${_codeLine(1, 0)} skip_with_code',
      '${_codeLine(1, 1)} skip_with_code',
    ]);
  });

  test('under an ancestor skip the nested feature line is '
      'feature_status_written, never entry_under_skip', () async {
    final report = await _checkNested(
      _record(statuses: [':skipped:no shop']),
      _record(statuses: [':planned'], code: [':lib/a.dart']),
    );

    expect(_found(report, _cartRecord), [
      '${_statusLine(0)} feature_status_written',
      '${_codeLine(1, 0)} feature_status_written',
    ]);
  });

  test('a tests line takes the implements branch: on a skipped item '
      'skip_with_code, under a skip entry_under_skip', () async {
    final skipped = await _check(
      _record(
        statuses: ['$_story:skipped:no toast host'],
        tests: ['$_story:test/a_test.dart', '$_story:test/b_test.dart'],
      ),
    );
    final under = await _check(
      _record(
        statuses: [':skipped:no web view'],
        tests: ['$_story:test/a_test.dart'],
      ),
    );

    expect(_found(skipped), [
      '${_testLine(1, 0, 0)} skip_with_code',
      '${_testLine(1, 0, 1)} skip_with_code',
    ]);
    expect(
      _only(
        await _check(
          _record(
            statuses: ['$_story:skipped:no toast host'],
            tests: ['$_story:test/a_test.dart'],
          ),
        ),
        FindingKind.skipWithCode,
      ).toJson(),
      containsPair('entry', _story),
    );
    expect(_found(under), ['${_testLine(1, 0, 0)} entry_under_skip']);
    expect(
      _only(under, FindingKind.entryUnderSkip).toJson(),
      allOf(containsPair('entry', _story), containsPair('skip', 'login')),
    );
  });

  test('a tests line naming the feature itself is feature_status_written; '
      'under its own skip, skip_with_code', () async {
    final written = await _check(_record(tests: [':test/a_test.dart']));
    final skipped = await _check(
      _record(statuses: [':skipped:no web view'], tests: [':test/a_test.dart']),
    );

    expect(_found(written), ['${_testLine(0, 0, 0)} feature_status_written']);
    expect(_found(skipped), ['${_testLine(1, 0, 0)} skip_with_code']);
  });

  test('a tests line naming no story or FR, or no item, is '
      'record_entry_unresolved', () async {
    final report = await _check(
      _record(
        tests: ['$_story/pin_toast:test/a_test.dart', 'test/b_test.dart'],
      ),
    );

    expect(_found(report), [
      '${_testLine(0, 0, 0)} record_entry_unresolved',
      '${_testLine(0, 0, 1)} record_entry_unresolved',
    ]);
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.recordEntryUnresolved) f.keys['entry'],
      ],
      ['$_story/pin_toast', 'test/b_test.dart'],
    );
  });

  test(
    'a tests line of an item that holds no fault gives no finding',
    () async {
      final report = await _check(
        _record(
          statuses: ['$_fr:implemented'],
          code: ['$_fr:lib/a.dart'],
          tests: ['$_fr:test/a_test.dart:shows a toast'],
        ),
      );

      expect(_found(report), isEmpty);
    },
  );

  test('a line that names no item is unresolved, once, even '
      'when it holds the only fault', () async {
    final report = await _check(
      _record(statuses: ['planned'], code: ['lib/a.dart']),
    );

    expect(_found(report), [
      '${_statusLine(0)} record_entry_unresolved',
      '${_codeLine(1, 0)} record_entry_unresolved',
    ]);
  });

  test('an unresolved line is no duplicate and no skip '
      'finding, even when it repeats', () async {
    final report = await _check(
      _record(
        statuses: ['ghost:planned', 'ghost:skipped'],
        code: ['ghost:lib/a.dart'],
      ),
    );

    expect(_found(report), [
      '${_statusLine(0)} record_entry_unresolved',
      '${_statusLine(1)} record_entry_unresolved',
      '${_codeLine(2, 0)} record_entry_unresolved',
    ]);
  });

  test('f04/us03/fr05, Review Focus 5: a CRLF record reports a faulty line '
      'once, at its line', () async {
    final crlf = _record(statuses: ['$_story:planned', 'ghost:planned'])
        .replaceAll('\n', '\r\n');
    final report = await _check(crlf);

    expect(_found(report), ['${_statusLine(1)} record_entry_unresolved']);
  });

  test('f04/us03/fr05, Review Focus 5: a record with malformed frontmatter '
      'is reported once, as invalid YAML', () async {
    final report = await _check(
      '---\nstatuses:\n  - ghost:planned\n  : [\n---\n\n# Record\n',
    );
    final onRecord = [
      for (final f in report.findings)
        if (f.path == _recordPath) f.kind,
    ];

    expect(onRecord, [FindingKind.frontmatterInvalid]);
  });

  group('two targets', () {
    Future<CheckReport> check({String? codeTarget}) async {
      final session = openSession(
        await writeTwinProject(
          extra: {
            '.specstone/templates/implementation.yaml': _recordLayer,
            'docs/specs/flutter/f01_login/IMPLEMENTATION.md': _record(
              statuses: ['$_story:implemented'],
              code: ['$_story:lib/login.dart'],
            ),
            'docs/specs/jaspr/f01_login/IMPLEMENTATION.md': _record(
              statuses: ['ghost:planned', '$_story:skipped'],
            ),
          },
        ),
      );
      addTearDown(session.close);
      return runCheck(session, codeTarget: codeTarget);
    }

    const jaspr = 'specs/jaspr/f01_login/IMPLEMENTATION.md';

    test('f04/us03/fr05, INV-32: each record is checked in its own target, '
        'once', () async {
      final report = await check();

      expect(_found(report, jaspr), [
        '${_statusLine(0)} record_entry_unresolved',
        '${_statusLine(1)} skip_reason_missing',
      ]);
      expect(
        _found(report, 'specs/flutter/f01_login/IMPLEMENTATION.md'),
        isEmpty,
      );
    });

    test('f04/us03/fr05, INV-32: --target keeps the records of that target '
        'alone', () async {
      final flutter = await check(codeTarget: 'flutter');
      final jasprOnly = await check(codeTarget: 'jaspr');

      expect(_found(flutter, jaspr), isEmpty);
      expect(_found(jasprOnly, jaspr), hasLength(2));
    });
  });
}
