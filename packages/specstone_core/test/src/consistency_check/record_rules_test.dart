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

const Set<FindingKind> _matrixKinds = {
  FindingKind.matrixRowMalformed,
  FindingKind.matrixRowUnresolved,
  FindingKind.matrixTestUnresolved,
  FindingKind.matrixRowRepeated,
  FindingKind.matrixSkipConflict,
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
}) async => await checkOf(
  await writeCheckProject(
    extra: {..._oneTarget(path, record), ...extra},
    without: without,
    // A stamp would add an `approved:` line and move every line below it.
    unstamped: {'docs/$path'},
  ),
);

/// Checks the nested project, the `shop` record holding [shop] and the
/// `shop/cart` record [cart].
Future<CheckReport> _checkNested(String shop, String cart) async =>
    await checkOf(
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
    final report = await checkOf(
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

  group('matrix rows', () {
    const header = '## Verification matrix';

    String withRows(String record, List<String> rows) =>
        '$record\n$header\n\n${rows.join('\n')}\n';

    /// The file line of row [i] of [record].
    int rowLine(String record, int i) =>
        record.split('\n').indexOf(header) + 3 + i;

    /// Returns `<line> <kind>` per finding of either rule on the record.
    List<String> bothRules(CheckReport report) => [
      for (final f in report.findings)
        if (f.path == _recordPath &&
            (_recordKinds.contains(f.kind) || _matrixKinds.contains(f.kind)))
          '${f.line} ${f.kind.wire}',
    ];

    test('a row naming no item of the feature is unresolved', () async {
      final record = withRows(_record(), [
        '- $_story/pin_toast E01: `shows a toast`',
        '- signup/create E01 skipped: no signup here',
      ]);

      final report = await _check(record);

      expect(_found(report), [
        '${rowLine(record, 0)} record_entry_unresolved',
        '${rowLine(record, 1)} record_entry_unresolved',
      ]);
      expect(
        [
          for (final f in report.findings)
            if (f.kind == FindingKind.recordEntryUnresolved) f.keys['entry'],
        ],
        ['$_story/pin_toast', 'signup/create'],
      );
    });

    /// Checks [record] under the matrix mode `verification_coverage:` names.
    Future<CheckReport> checkUnder(String mode, String record) => _check(
      record,
      extra: {
        '.specstone/config.yaml':
            '${shippedPinsConfig()}code_root: app\n'
            'verification_coverage: $mode\n',
      },
    );

    /// The record findings at the rows of [record].
    List<String> rowFindings(CheckReport report, String record) => [
      for (final f in report.findings)
        if (f.path == _recordPath && f.line >= rowLine(record, 0))
          '${f.line} ${f.kind.wire}',
    ];

    test('a row of a skipped item is skip_with_code, once per row', () async {
      final record = withRows(
        _record(statuses: ['$_fr:skipped:no toast host']),
        ['- $_fr E01: `shows a toast`', '- $_fr E02 skipped: no host'],
      );

      final report = await checkUnder('edge_case', record);

      expect(_found(report), [
        '${rowLine(record, 0)} skip_with_code',
        '${rowLine(record, 1)} skip_with_code',
      ]);
      expect(
        [
          for (final f in report.findings)
            if (f.kind == FindingKind.skipWithCode) f.keys['entry'],
        ],
        [_fr, _fr],
      );
    });

    test('a row under a skip is entry_under_skip', () async {
      final record = withRows(_record(statuses: [':skipped:no web view']), [
        '- $_fr E01: `shows a toast`',
      ]);

      final report = await checkUnder('edge_case', record);

      expect(_found(report), ['${rowLine(record, 0)} entry_under_skip']);
      expect(
        _only(report, FindingKind.entryUnderSkip).toJson(),
        allOf(containsPair('entry', _fr), containsPair('skip', 'login')),
      );
    });

    test('the rows of an item outside the feature get only the unresolved '
        'finding', () async {
      final record = withRows(_record(), [
        '- signup/create E01: `signs up`',
        '- signup/create E01: `signs up`',
        '- signup/create E01 skipped: no signup here',
      ]);

      final report = await _check(record);

      expect(bothRules(report), [
        '${rowLine(record, 0)} record_entry_unresolved',
        '${rowLine(record, 1)} record_entry_unresolved',
        '${rowLine(record, 2)} record_entry_unresolved',
      ]);
    });

    test('a row of a skipped item gets no finding of any kind but the skip '
        "rule's", () async {
      for (final statuses in [
        ['$_fr:skipped:no toast host'],
        ['$_story:skipped:no toast host'],
        [':skipped:no web view'],
      ]) {
        final record = withRows(_record(statuses: statuses), [
          '- $_fr E01: `shows a toast`',
          '- $_fr E01: `shows a toast` 3f9a1c0b7e2d',
          '- $_fr E99: `shows a toast`',
          '- $_fr E01 skipped: no host',
        ]);

        final report = await checkUnder('edge_case', record);

        final kinds = [
          for (final f in report.findings)
            if (f.path == _recordPath && f.line >= rowLine(record, 0)) f.kind,
        ];

        expect(kinds, hasLength(4), reason: '$statuses');
        expect(
          kinds,
          everyElement(
            anyOf(FindingKind.skipWithCode, FindingKind.entryUnderSkip),
          ),
          reason: '$statuses',
        );
      }
    });

    test('a row of an item that holds no fault gives no finding, a row '
        'naming a story included', () async {
      final record = withRows(
        _record(statuses: ['$_story:implemented', '$_fr:implemented']),
        ['- $_fr E01: `shows a toast`', '- $_story E01: `shows a toast`'],
      );

      final report = await checkUnder('edge_case', record);

      expect(_found(report), isEmpty);
    });

    for (final mode in ['true', 'fr']) {
      test(
        'reads a per-FR row item as a tests line item under $mode',
        () async {
          final skipped = withRows(
            _record(statuses: ['$_fr:skipped:no toast host']),
            [
              '- $_fr: `shows a toast`, `hides a toast`',
              '- $_fr skipped: no host',
              '- signup/create: `signs up`',
            ],
          );
          final underSkip = withRows(
            _record(statuses: [':skipped:no web view']),
            ['- $_fr: `shows a toast`'],
          );

          expect(rowFindings(await checkUnder(mode, skipped), skipped), [
            '${rowLine(skipped, 0)} skip_with_code',
            '${rowLine(skipped, 1)} skip_with_code',
            '${rowLine(skipped, 2)} record_entry_unresolved',
          ]);
          expect(rowFindings(await checkUnder(mode, underSkip), underSkip), [
            '${rowLine(underSkip, 0)} entry_under_skip',
          ]);
        },
      );
    }

    test('gives a refused-form row no record entry finding', () async {
      final skipped = withRows(
        _record(statuses: ['$_fr:skipped:no toast host']),
        ['- $_fr E01: `shows a toast`', '- $_fr E02 skipped: no host'],
      );
      final underSkip = withRows(_record(statuses: [':skipped:no web view']), [
        '- $_fr E01: `shows a toast`',
      ]);
      final perFr = withRows(
        _record(statuses: ['$_fr:skipped:no toast host']),
        ['- $_fr: `shows a toast`', '- $_fr skipped: no host'],
      );

      for (final (mode, record) in [
        ('true', skipped),
        ('fr', underSkip),
        ('edge_case', perFr),
      ]) {
        final report = await checkUnder(mode, record);

        expect(
          [
            for (final f in report.findings)
              if (f.path == _recordPath && f.line >= rowLine(record, 0)) f.kind,
          ],
          everyElement(FindingKind.matrixRowMalformed),
          reason: mode,
        );
        expect(_found(report), isEmpty, reason: mode);
      }
    });

    test('gives a per-FR row naming no FR under edge_case the record entry '
        'finding alone', () async {
      final record = withRows(_record(), ['- no_such_fr: `shows a toast`']);

      final report = await checkUnder('edge_case', record);

      expect(rowFindings(report, record), [
        '${rowLine(record, 0)} record_entry_unresolved',
      ]);
    });

    test('a row naming an item outside the feature gives one finding in '
        'the whole check', () async {
      final record = withRows(_record(), ['- signup/create E01: `signs up`']);

      final report = await _check(record);

      expect(bothRules(report), [
        '${rowLine(record, 0)} record_entry_unresolved',
      ]);
    });

    test('a row naming a skipped story gives one finding in the whole '
        'check', () async {
      final record = withRows(
        _record(statuses: ['$_story:skipped:no toast host']),
        ['- $_story E01: `shows a toast`'],
      );

      final report = await _check(record);

      expect(bothRules(report), [
        '${rowLine(record, 0)} matrix_row_unresolved',
      ]);
    });
  });

  test('the last of two differing statuses lines decides the status, and '
      'only the second is a duplicate', () async {
    final skippedLast = await _check(
      _record(
        statuses: ['$_story:planned', '$_story:skipped:no toast host'],
        code: ['$_story:lib/a.dart'],
      ),
    );
    final plannedLast = await _check(
      _record(
        statuses: ['$_story:skipped:no toast host', '$_story:planned'],
        code: ['$_story:lib/a.dart'],
      ),
    );

    expect(_found(skippedLast), [
      '${_statusLine(1)} record_entry_duplicate',
      '${_codeLine(2, 0)} skip_with_code',
    ]);
    expect(_found(plannedLast), ['${_statusLine(1)} record_entry_duplicate']);
  });

  test('under an ancestor skip an implements line naming the nested feature '
      'with no statuses line is feature_status_written', () async {
    final report = await _checkNested(
      _record(statuses: [':skipped:no shop']),
      _record(code: [':lib/a.dart']),
    );

    expect(_found(report, _cartRecord), [
      '${_codeLine(0, 0)} feature_status_written',
    ]);
  });

  test('a statuses or implements line with no colon names its whole line as '
      'the unresolved entry', () async {
    final report = await _check(
      _record(statuses: ['show_toast'], code: ['show_toast']),
    );

    expect(_found(report), [
      '${_statusLine(0)} record_entry_unresolved',
      '${_codeLine(1, 0)} record_entry_unresolved',
    ]);
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.recordEntryUnresolved) f.keys['entry'],
      ],
      ['show_toast', 'show_toast'],
    );
  });

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

  test('a fingerprint on an implements line changes no finding', () async {
    List<String> code(String suffix) => [
      '$_story:lib/a.dart$suffix',
      '$_story:lib/a.dart:SignInPage$suffix',
      'ghost:lib/c.dart$suffix',
    ];
    String record(String suffix) => _record(
      statuses: ['$_story:skipped:no web view', '$_story:planned'],
      code: code(suffix),
    );

    final bare = await _check(record(''));
    final stamped = await _check(record(' 5d1e0c4b7a92'));

    expect(_found(bare), isNotEmpty);
    expect(_found(stamped), _found(bare));
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

  test('a CRLF record reports a faulty line '
      'once, at its line', () async {
    final crlf = _record(statuses: ['$_story:planned', 'ghost:planned'])
        .replaceAll('\n', '\r\n');
    final report = await _check(crlf);

    expect(_found(report), ['${_statusLine(1)} record_entry_unresolved']);
  });

  test('a record with malformed frontmatter '
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
      return await runCheck(session, codeTarget: codeTarget);
    }

    const jaspr = 'specs/jaspr/f01_login/IMPLEMENTATION.md';

    test('each record is checked in its own target, '
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

    test('--target keeps the records of that target '
        'alone', () async {
      final flutter = await check(codeTarget: 'flutter');
      final jasprOnly = await check(codeTarget: 'jaspr');

      expect(_found(flutter, jaspr), isEmpty);
      expect(_found(jasprOnly, jaspr), hasLength(2));
    });
  });
}
