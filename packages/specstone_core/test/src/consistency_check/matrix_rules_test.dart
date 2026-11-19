// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/templates/models/matrix_mode.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/record_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';

const _fr = 'email_login/check_password';
const _story = 'email_login';
const _testFile = 'app/test/login_test.dart';
const _testBody =
    "void main() {\n  test('refuses an empty password', () {});\n"
    "  test('refuses a wrong password', () {});\n}\n";
const _matrixHeader = '## Verification matrix';
const _flutterRecord = '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
const _jasprRecord = '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md';

const Set<FindingKind> _matrixKinds = {
  FindingKind.matrixRowMalformed,
  FindingKind.matrixRowUnresolved,
  FindingKind.matrixTestUnresolved,
  FindingKind.matrixRowRepeated,
  FindingKind.matrixSkipConflict,
};

/// The requirement with a second edge case, for the rows that need two.
Map<String, String> _frWithTwoEdgeCases() => fr(
  '1. E01 — An empty password → refused.',
  '1. E01 — An empty password → refused.\n2. E02 — A long password → accepted.',
);

/// Returns a record with the [rows] under its matrix section.
///
/// A record built with `section: false` holds the rows' text and no header.
String _record({
  List<String> statuses = const ['$_fr:implemented'],
  List<String> tests = const ['$_fr:$_testFile'],
  List<String> rows = const [],
  bool section = true,
}) {
  final front = recordText(statuses: statuses, tests: tests);
  return '$front\n${section ? '$_matrixHeader\n\n' : ''}${rows.join('\n')}\n';
}

/// Returns the file line of row [i] of [record].
int _rowLine(String record, int i) =>
    record.split('\n').indexOf(_matrixHeader) + 3 + i;

/// The config that sets the matrix mode to [mode].
String _modeConfig(MatrixMode mode) => switch (mode) {
  MatrixMode.off => shippedPinsConfig(),
  MatrixMode.fr => '${shippedPinsConfig()}verification_coverage: fr\n',
  MatrixMode.edgeCase =>
    '${shippedPinsConfig()}verification_coverage: edge_case\n',
};

/// Returns the rows that name each of [literals] for [_fr] in the form [mode]
/// reads: one row holding them all, or one row per literal.
List<String> _rowsOf(MatrixMode mode, List<String> literals) =>
    switch (mode.readsForm) {
      RowForm.perFr => [
        '- $_fr: ${[for (final literal in literals) '`$literal`'].join(', ')}',
      ],
      RowForm.perEdgeCase => [
        for (final literal in literals) '- $_fr E01: `$literal`',
      ],
    };

/// The project of [record] under [mode]; the per-edge-case form by default,
/// the form the older tests of this file write.
Future<Directory> _project(
  String record, {
  Map<String, String> extra = const {},
  MatrixMode mode = MatrixMode.edgeCase,
}) => writeCheckProject(
  extra: {
    loginRecord: record,
    _testFile: _testBody,
    '.specstone/config.yaml': _modeConfig(mode),
    ...extra,
  },
  // A stamp would add an `approved:` line and move every line below it.
  unstamped: {loginRecord},
);

/// The config that turns coverage on in the per-edge-case form, or sets the
/// key to false.
String _coverageConfig([bool value = true]) =>
    '${shippedPinsConfig()}verification_coverage: '
    '${value ? 'edge_case' : 'false'}\n';

/// The requirement with edge cases E01 to E03.
Map<String, String> _frWithThreeEdgeCases() => fr(
  '1. E01 — An empty password → refused.',
  '1. E01 — An empty password → refused.\n'
      '2. E02 — A long password → accepted.\n'
      '3. E03 — A padded password → accepted.',
);

List<Finding> _missing(CheckReport report) => [
  for (final finding in report.findings)
    if (finding.kind == FindingKind.matrixRowMissing) finding,
];

List<List<Object?>> _missingEdgeCases(CheckReport report) => [
  for (final finding in _missing(report))
    [finding.keys['edge_case'], finding.line],
];

Future<CheckReport> _run(
  Directory project, {
  String? codeTarget,
  String? docPath,
}) async {
  final session = openSession(project);
  try {
    return await runCheck(session, codeTarget: codeTarget, docPath: docPath);
  } finally {
    session.close();
  }
}

List<Finding> _matrix(CheckReport report) => [
  for (final finding in report.findings)
    if (_matrixKinds.contains(finding.kind)) finding,
];

List<String> _spots(CheckReport report) => [
  for (final f in _matrix(report)) '${f.path}:${f.line}: ${f.kind.wire}',
];

void main() {
  test('a row whose literal its test file holds gives no finding, a literal '
      'inside a longer name included', () async {
    final report = await _run(
      await _project(
        _record(
          rows: [
            '- $_fr E01: `refuses an empty password`',
            '- $_fr E01: `refuses an empty`',
            '- $_fr E01: `refuses a wrong password` 3f9a1c0b7e2d',
          ],
        ),
      ),
    );

    expect(_matrix(report), isEmpty);
    expect(report.warnings, isEmpty);
  });

  test('a literal holding a backtick, written in a double-backtick span, is '
      'matched against the test file as written', () async {
    const body =
        "void main() {\n  test('refuses a `quoted` password', () {});\n}\n";
    final held = await _run(
      await _project(
        _record(rows: ['- $_fr E01: `` refuses a `quoted` password ``']),
        extra: {_testFile: body},
      ),
    );
    expect(_matrix(held), isEmpty);

    final record = _record(
      rows: ['- $_fr E01: `` refuses a `quoted` secret ``'],
    );
    final missing = await _run(
      await _project(record, extra: {_testFile: body}),
    );
    final finding = _matrix(missing).single;
    expect(finding.kind, FindingKind.matrixTestUnresolved);
    expect(finding.keys, {'item': _fr, 'name': 'refuses a `quoted` secret'});
  });

  test('a renamed literal is unresolved', () async {
    final record = _record(rows: ['- $_fr E01: `refuses a blank password`']);

    final report = await _run(await _project(record));

    final finding = _matrix(report).single;
    expect(finding.kind, FindingKind.matrixTestUnresolved);
    expect(finding.path, loginRecord);
    expect(finding.line, _rowLine(record, 0));
    expect(finding.waitsFor, WaitsFor.agent);
    expect(finding.keys, {'item': _fr, 'name': 'refuses a blank password'});
  });

  test('a row of an item with no tests line is unresolved', () async {
    final record = _record(
      tests: const [],
      rows: ['- $_fr E01: `refuses an empty password`'],
    );

    final report = await _run(await _project(record));

    final finding = _matrix(report).single;
    expect(finding.kind, FindingKind.matrixTestUnresolved);
    expect(finding.line, _rowLine(record, 0));
    expect(finding.keys, {'item': _fr, 'name': 'refuses an empty password'});
  });

  test('a story or a missing edge case is unresolved', () async {
    final record = _record(
      rows: [
        '- $_story E01: `refuses an empty password`',
        '- $_fr E99: `refuses an empty password`',
      ],
    );

    final findings = _matrix(await _run(await _project(record)));

    expect(
      [for (final f in findings) f.kind],
      [FindingKind.matrixRowUnresolved, FindingKind.matrixRowUnresolved],
    );
    expect(
      [for (final f in findings) f.line],
      [_rowLine(record, 0), _rowLine(record, 1)],
    );
    expect(findings[0].keys, {'item': _story});
    expect(findings[1].keys, {'item': _fr, 'edge_case': 'E99'});
  });

  test('a malformed line is reported with the whole line', () async {
    final rows = [
      'A paragraph in the section.',
      '- $_fr E01',
      '- $_fr E01: `refuses an empty password` (flaky)',
      '- $_fr E01: `refuses an empty password` 3F9A1C0B7E2D',
    ];
    final record = _record(rows: rows);

    final findings = _matrix(await _run(await _project(record)));

    expect([
      for (final f in findings) f.kind,
    ], everyElement(FindingKind.matrixRowMalformed));
    expect(
      [for (final f in findings) f.line],
      [for (var i = 0; i < rows.length; i++) _rowLine(record, i)],
    );
    expect(
      [for (final f in findings) f.keys],
      [
        for (final row in rows) {'row': row},
      ],
    );
  });

  test('a repeated row and a skip beside another row are reported at the '
      'later row', () async {
    final record = _record(
      rows: [
        '- $_fr E01: `refuses an empty password`',
        '- $_fr E01: `refuses an empty password`',
        '- $_fr E01 skipped: no clock on CI',
        '- $_fr E02 skipped: needs root on CI',
        '- $_fr E02: `refuses a wrong password`',
      ],
    );

    final findings = _matrix(
      await _run(await _project(record, extra: _frWithTwoEdgeCases())),
    );

    expect(
      [for (final f in findings) f.kind],
      [
        FindingKind.matrixRowRepeated,
        FindingKind.matrixSkipConflict,
        FindingKind.matrixSkipConflict,
      ],
    );
    expect(
      [for (final f in findings) f.line],
      [_rowLine(record, 1), _rowLine(record, 2), _rowLine(record, 4)],
    );
    expect(
      [for (final f in findings) f.keys],
      [
        {'first': _rowLine(record, 0)},
        {'first': _rowLine(record, 0)},
        {'first': _rowLine(record, 3)},
      ],
    );
  });

  test("a planned entry's literal is not checked, every other check still "
      'runs', () async {
    final record = _record(
      statuses: const ['$_fr:planned'],
      tests: const [],
      rows: [
        '- $_fr E01: `no test holds this yet`',
        '- $_fr E99: `no test holds this yet`',
      ],
    );

    final findings = _matrix(await _run(await _project(record)));

    expect(
      [for (final f in findings) f.kind],
      [FindingKind.matrixRowUnresolved],
    );
    expect(findings.single.line, _rowLine(record, 1));
  });

  test('a deprecated entry checks the literal of its rows', () async {
    final record = _record(
      statuses: const ['$_fr:deprecated'],
      rows: ['- $_fr E01: `refuses a blank password`'],
    );

    final finding = _matrix(await _run(await _project(record))).single;

    expect(finding.kind, FindingKind.matrixTestUnresolved);
    expect(finding.line, _rowLine(record, 0));
  });

  for (final (name, statuses) in [
    ('its own skip', const ['$_fr:skipped:not in this client']),
    ('the skip of its story', const ['$_story:skipped:not in this client']),
    ('the skip of its feature', const [':skipped:not in this client']),
  ]) {
    test('a row of an item under $name gets no literal finding', () async {
      final record = _record(
        statuses: statuses,
        rows: ['- $_fr E01: `no test holds this`'],
      );

      final report = await _run(await _project(record));

      expect(_matrix(report), isEmpty);
    });

    test('rows of an item under $name get no row finding at all', () async {
      final record = _record(
        statuses: statuses,
        rows: [
          '- $_fr E99: `refuses an empty password`',
          '- $_fr E01: `refuses an empty password`',
          '- $_fr E01: `refuses an empty password`',
          '- $_fr E01 skipped: no clock on CI',
        ],
      );

      final report = await _run(await _project(record));

      expect(_matrix(report), isEmpty);
    });
  }

  test(
    'a row naming no story or FR, or the feature, gets no finding here',
    () async {
      final record = _record(
        rows: [
          '- email_login/pin E01: `refuses an empty password`',
          '- login E01: `refuses an empty password`',
        ],
      );

      final report = await _run(await _project(record));

      expect(_matrix(report), isEmpty);
    },
  );

  test('an unreadable test file warns once and gives no row finding', () async {
    final project = await _project(
      _record(
        rows: [
          '- $_fr E01: `refuses an empty password`',
          '- $_fr E01: `refuses a blank password`',
        ],
      ),
    );
    final path = '${project.path}/$_testFile';
    Process.runSync('chmod', ['000', path]);
    addTearDown(() => Process.runSync('chmod', ['644', path]));

    final report = await _run(project);

    expect(_matrix(report), isEmpty);
    expect(report.warnings, [
      '$_testFile: cannot read the file; tests names in it are not checked',
    ]);
  }, skip: unreadablePathSkipReason());

  test('findings sit on the record', () async {
    final project = await _project(
      _record(rows: ['- $_fr E01: `refuses a blank password`']),
    );

    expect(_spots(await _run(project)), hasLength(1));
    expect(_spots(await _run(project, docPath: loginRecord)), hasLength(1));
    expect(_matrix(await _run(project, docPath: loginFr)), isEmpty);
  });

  test('each target resolves its rows against its own code root', () async {
    final rows = ['- $_fr E01: `refuses an empty password`'];
    final project = await writeTwinProject(
      extra: {
        '.specstone/config.yaml':
            '${shippedPinsConfig()}verification_coverage: edge_case\n'
            'targets:\n  flutter:\n    code_root: flutter_ws\n'
            '  jaspr:\n    code_root: jaspr_ws\n',
        'flutter_ws/$_testFile': _testBody,
        _flutterRecord: _record(rows: rows),
        _jasprRecord: _record(rows: rows),
      },
    );

    final report = await _run(project);
    expect(_spots(report), [
      '$_jasprRecord:${_rowLine(_record(rows: rows), 0)}: matrix_test_unresolved',
    ]);
    expect(_spots(await _run(project, codeTarget: 'flutter')), isEmpty);
  });

  test('a record without the section gives no finding', () async {
    final report = await _run(
      await _project(
        _record(section: false, rows: ['- $_fr E99: `no test holds this`']),
      ),
    );

    expect(_matrix(report), isEmpty);
  });

  test('a CRLF record reports the same lines', () async {
    final record = _record(
      rows: [
        'A paragraph in the section.',
        '- $_fr E01: `refuses a blank password`',
      ],
    );

    final lf = _spots(await _run(await _project(record)));
    final crlf = _spots(
      await _run(await _project(record.replaceAll('\n', '\r\n'))),
    );

    expect(lf, hasLength(2));
    expect(crlf, lf);
  });

  group('rows in the form the mode reads', () {
    const formOff =
        'per-edge-case row; run specstone migrate to fold it into one row per FR';
    const formEdgeCase =
        'per-FR row under verification_coverage edge_case; write one row per edge case';

    for (final mode in MatrixMode.values) {
      group('under ${mode.name}', () {
        Future<CheckReport> run(
          String record, {
          Map<String, String> extra = const {},
        }) async =>
            await _run(await _project(record, mode: mode, extra: extra));

        test(
          'gives no finding for a per-FR row whose literals resolve',
          () async {
            final record = _record(
              rows: _rowsOf(mode, [
                'refuses an empty password',
                'refuses a wrong password',
              ]),
            );

            expect(_matrix(await run(record)), isEmpty);
          },
        );

        test('reports each unresolved literal of a per-FR row once', () async {
          final record = _record(
            rows: _rowsOf(mode, [
              'refuses a blank password',
              'refuses an empty password',
              'refuses a short password',
            ]),
          );

          final findings = _matrix(await run(record));

          expect([
            for (final f in findings) f.kind,
          ], everyElement(FindingKind.matrixTestUnresolved));
          expect(
            [for (final f in findings) f.keys],
            [
              {'item': _fr, 'name': 'refuses a blank password'},
              {'item': _fr, 'name': 'refuses a short password'},
            ],
          );
          expect(
            [for (final f in findings) f.line],
            mode.readsForm == RowForm.perFr
                ? [_rowLine(record, 0), _rowLine(record, 0)]
                : [_rowLine(record, 0), _rowLine(record, 2)],
          );
        });

        test('matches a literal inside a longer test name', () async {
          final record = _record(
            rows: _rowsOf(mode, ['refuses an empty', 'a wrong password']),
          );

          expect(_matrix(await run(record)), isEmpty);
        });

        test('reports a test row of an FR with no tests line once by its '
            'first literal', () async {
          final record = _record(
            tests: const [],
            rows: [
              _rowsOf(mode, [
                'refuses an empty password',
                'refuses a wrong password',
              ]).first,
            ],
          );

          final finding = _matrix(await run(record)).single;

          expect(finding.kind, FindingKind.matrixTestUnresolved);
          expect(finding.line, _rowLine(record, 0));
          expect(finding.keys, {
            'item': _fr,
            'name': 'refuses an empty password',
          });
        });

        test('reports a story row as unresolved in either form', () async {
          final record = _record(
            rows: [
              '- $_story: `refuses an empty password`',
              '- $_story E01: `refuses an empty password`',
            ],
          );

          final findings = _matrix(await run(record));

          expect([
            for (final f in findings) f.kind,
          ], everyElement(FindingKind.matrixRowUnresolved));
          expect(
            [for (final f in findings) f.keys],
            [
              {'item': _story},
              {'item': _story},
            ],
          );
          expect(
            [for (final f in findings) f.line],
            [_rowLine(record, 0), _rowLine(record, 1)],
          );
        });

        test(
          'reports an edge case the FR lacks only under edge_case',
          () async {
            final record = _record(
              rows: ['- $_fr E99: `refuses an empty password`'],
            );

            final finding = _matrix(await run(record)).single;

            if (mode == MatrixMode.edgeCase) {
              expect(finding.kind, FindingKind.matrixRowUnresolved);
              expect(finding.keys, {'item': _fr, 'edge_case': 'E99'});
            } else {
              expect(finding.kind, FindingKind.matrixRowMalformed);
              expect(finding.message, formOff);
            }
          },
        );

        test(
          'reports a refused-form row alone with the form message',
          () async {
            final readsFr = mode.readsForm == RowForm.perFr;
            final refused = readsFr
                ? '- $_fr E01: `no such name`'
                : '- $_fr: `no such name`';
            final record = _record(
              statuses: const ['$_fr:implemented'],
              rows: [refused, refused, '$refused 3f9a1c0b7e2d'],
            );

            final findings = _matrix(await run(record));

            expect([
              for (final f in findings) f.kind,
            ], everyElement(FindingKind.matrixRowMalformed));
            expect(
              [for (final f in findings) f.line],
              [for (var i = 0; i < 3; i++) _rowLine(record, i)],
            );
            expect([
              for (final f in findings) f.message,
            ], List.filled(3, readsFr ? formOff : formEdgeCase));
            expect([
              for (final f in findings) f.waitsFor,
            ], everyElement(readsFr ? WaitsFor.owner : WaitsFor.agent));
            expect(findings.first.keys, {'row': refused});
            expect(findings.last.keys, {'row': '$refused 3f9a1c0b7e2d'});
          },
        );

        test('reports a refused-form row of a skipped FR alone', () async {
          final readsFr = mode.readsForm == RowForm.perFr;
          final refused = readsFr ? '- $_fr E01: `x`' : '- $_fr: `x`';
          final record = _record(
            statuses: const ['$_fr:skipped:no clock on CI'],
            rows: [refused],
          );

          final finding = _matrix(await run(record)).single;

          expect(finding.kind, FindingKind.matrixRowMalformed);
          expect(finding.message, readsFr ? formOff : formEdgeCase);
        });

        test(
          'checks the row it reads beside a refused row of the same FR',
          () async {
            final readsFr = mode.readsForm == RowForm.perFr;
            final (refused, read, skip) = readsFr
                ? (
                    '- $_fr E01: `refuses an empty password`',
                    '- $_fr: `refuses a blank password`',
                    '- $_fr skipped: no clock on CI',
                  )
                : (
                    '- $_fr: `refuses an empty password`',
                    '- $_fr E01: `refuses a blank password`',
                    '- $_fr E01 skipped: no clock on CI',
                  );
            final record = _record(rows: [refused, read, skip]);

            final findings = _matrix(await run(record));

            expect(
              [
                for (final f in findings) [f.kind, f.line],
              ],
              [
                [FindingKind.matrixRowMalformed, _rowLine(record, 0)],
                [FindingKind.matrixTestUnresolved, _rowLine(record, 1)],
                [FindingKind.matrixSkipConflict, _rowLine(record, 2)],
              ],
            );
            expect(findings.last.keys, {'first': _rowLine(record, 1)});
          },
        );

        test('reports a skip row beside a test row as a conflict and not a '
            'repeat', () async {
          final test = _rowsOf(mode, ['refuses an empty password']).single;
          final skip = mode.readsForm == RowForm.perFr
              ? '- $_fr skipped: no clock on CI'
              : '- $_fr E01 skipped: no clock on CI';
          for (final rows in [
            [test, skip],
            [skip, test],
          ]) {
            final record = _record(rows: rows);

            final finding = _matrix(await run(record)).single;

            expect(
              finding.kind,
              FindingKind.matrixSkipConflict,
              reason: '$rows',
            );
            expect(finding.line, _rowLine(record, 1), reason: '$rows');
            expect(finding.keys, {
              'first': _rowLine(record, 0),
            }, reason: '$rows');
          }
        });

        test('skips the literal check of a planned FR', () async {
          final record = _record(
            statuses: const ['$_fr:planned'],
            tests: const [],
            rows: _rowsOf(mode, ['no test holds this yet']),
          );

          expect(_matrix(await run(record)), isEmpty);
        });
      });
    }

    for (final mode in [MatrixMode.off, MatrixMode.fr]) {
      group('under ${mode.name}, the per-FR form', () {
        test('reports a second per-FR test row as repeated', () async {
          final record = _record(
            rows: [
              '- $_fr: `refuses an empty password`',
              '- $_fr: `refuses a wrong password`',
            ],
          );

          final finding = _matrix(
            await _run(await _project(record, mode: mode)),
          ).single;

          expect(finding.kind, FindingKind.matrixRowRepeated);
          expect(finding.line, _rowLine(record, 1));
          expect(finding.keys, {'first': _rowLine(record, 0)});
        });

        test('reads a row of the form that edge_case refuses', () async {
          final record = _record(
            rows: [
              '- $_fr: `refuses an empty password`, `refuses a wrong password`',
            ],
          );

          final report = await _run(await _project(record, mode: mode));

          expect(_matrix(report), isEmpty);
        });
      });
    }

    test(
      'reports a repeated per-edge-case row only for the same literal',
      () async {
        final record = _record(
          rows: [
            '- $_fr E01: `refuses an empty password`',
            '- $_fr E01: `refuses a wrong password`',
            '- $_fr E01: `refuses an empty password`',
          ],
        );

        final finding = _matrix(await _run(await _project(record))).single;

        expect(finding.kind, FindingKind.matrixRowRepeated);
        expect(finding.line, _rowLine(record, 2));
        expect(finding.keys, {'first': _rowLine(record, 0)});
      },
    );

    test('runs every check with coverage off', () async {
      final record = _record(
        rows: [
          '- $_fr: `no such name`',
          '- $_fr: `refuses an empty password`',
          '- $_fr skipped: no clock on CI',
          '- $_story: `refuses an empty password`',
          'A paragraph in the section.',
        ],
      );

      final findings = _matrix(
        await _run(await _project(record, mode: MatrixMode.off)),
      );

      expect(
        [
          for (final f in findings) [f.kind, f.line],
        ],
        [
          [FindingKind.matrixTestUnresolved, _rowLine(record, 0)],
          [FindingKind.matrixRowRepeated, _rowLine(record, 1)],
          [FindingKind.matrixSkipConflict, _rowLine(record, 2)],
          [FindingKind.matrixRowUnresolved, _rowLine(record, 3)],
          [FindingKind.matrixRowMalformed, _rowLine(record, 4)],
        ],
      );
      expect(findings.last.message, contains('"- <item>: `<test name>`"'));
    });
  });

  group('coverage', () {
    // The statuses line of the fixture record: the first line under the key.
    const statusesLine = 3;

    test('an uncovered edge case is reported with coverage on', () async {
      final project = await _project(
        _record(rows: ['- $_fr E01: `refuses an empty password`']),
        extra: {
          ..._frWithTwoEdgeCases(),
          '.specstone/config.yaml': _coverageConfig(),
        },
      );

      final report = await _run(project);

      final finding = _missing(report).single;
      expect(finding.path, loginRecord);
      expect(finding.line, statusesLine);
      expect(finding.waitsFor, WaitsFor.agent);
      expect(finding.keys, {'item': _fr, 'edge_case': 'E02'});
      expect(
        finding.message,
        '$_fr#E02 is implemented and no matrix row names it',
      );
    });

    for (final (name, config) in [
      ('the key absent', shippedPinsConfig()),
      ('the key false', _coverageConfig(false)),
    ]) {
      test('coverage off stays silent with $name', () async {
        final project = await _project(
          _record(rows: ['- $_fr: `refuses a blank password`']),
          extra: {..._frWithTwoEdgeCases(), '.specstone/config.yaml': config},
        );

        final report = await _run(project);

        expect(_missing(report), isEmpty);
        expect(_matrix(report).single.kind, FindingKind.matrixTestUnresolved);
      });
    }

    test('with the coverage key absent or false, a stale row fingerprint '
        'still turns suspect', () async {
      final record = _record(
        rows: ['- $_fr E01: `refuses an empty password` 3f9a1c0b7e2d'],
      );
      for (final (name, config) in [
        ('the key absent', shippedPinsConfig()),
        ('the key false', _coverageConfig(false)),
      ]) {
        final project = await _project(
          record,
          extra: {..._frWithTwoEdgeCases(), '.specstone/config.yaml': config},
        );

        final report = await _run(project);

        expect(_missing(report), isEmpty, reason: name);
        expect(
          [
            for (final f in report.findings)
              if (f.path == loginRecord && f.kind == FindingKind.suspect)
                f.line,
          ],
          [_rowLine(record, 0)],
          reason: name,
        );
      }
    });

    test('a skip row or an unresolved row covers its edge case', () async {
      final record = _record(
        rows: [
          '- $_fr E01 skipped: no clock on CI',
          '- $_fr E02: `refuses a blank password`',
        ],
      );
      final project = await _project(
        record,
        extra: {
          ..._frWithTwoEdgeCases(),
          '.specstone/config.yaml': _coverageConfig(),
        },
      );

      final report = await _run(project);

      expect(_missing(report), isEmpty);
      expect(
        [for (final f in _matrix(report)) f.kind],
        [FindingKind.matrixTestUnresolved],
      );
    });

    for (final (name, statuses, verifyMethod) in [
      ('planned in its target', const ['$_fr:planned'], 'test'),
      ('deprecated in its target', const ['$_fr:deprecated'], 'test'),
      (
        'skipped in its target',
        const ['$_fr:skipped:not in this client'],
        'test',
      ),
      (
        'under the skip of its story',
        const ['$_story:skipped:not in this client', '$_fr:implemented'],
        'test',
      ),
      ('verified by inspection', const ['$_fr:implemented'], 'inspection'),
      ('verified by analysis', const ['$_fr:implemented'], 'analysis'),
      (
        'verified by demonstration',
        const ['$_fr:implemented'],
        'demonstration',
      ),
    ]) {
      test('a requirement $name needs no row', () async {
        final project = await _project(
          _record(statuses: statuses),
          extra: {
            ...edit(loginFr, [
              ('verify_method: test', 'verify_method: $verifyMethod'),
            ]),
            '.specstone/config.yaml': _coverageConfig(),
          },
        );

        expect(_missing(await _run(project)), isEmpty);
      });
    }

    test('a split reports each new edge case', () async {
      final project = await _project(
        _record(rows: ['- $_fr E01: `refuses an empty password`']),
        extra: {
          ..._frWithThreeEdgeCases(),
          '.specstone/config.yaml': _coverageConfig(),
        },
      );

      final report = await _run(project);

      expect(_missingEdgeCases(report), [
        ['E02', statusesLine],
        ['E03', statusesLine],
      ]);
    });

    test('each target reports its own record', () async {
      final rows = ['- $_fr E01: `refuses an empty password`'];
      final project = await writeTwinProject(
        extra: {
          ..._frWithTwoEdgeCases(),
          '.specstone/config.yaml':
              '${shippedPinsConfig()}verification_coverage: edge_case\n'
              'targets:\n  flutter:\n    code_root: flutter_ws\n'
              '  jaspr:\n    code_root: jaspr_ws\n',
          'flutter_ws/$_testFile': _testBody,
          _flutterRecord: _record(rows: rows),
          _jasprRecord: _record(statuses: const ['$_fr:planned'], rows: rows),
        },
      );

      final report = await _run(project);

      final finding = _missing(report).single;
      expect(finding.path, _flutterRecord);
      expect(finding.keys, {'item': _fr, 'edge_case': 'E02'});
      expect(
        finding.message,
        '$_fr#E02 is implemented in target flutter and no matrix row names it',
      );
      expect(_missing(await _run(project, codeTarget: 'jaspr')), isEmpty);
    });
  });

  group('matrix_row_missing per mode', () {
    const statusesLine = 3;

    test('reports an implemented test-verified FR no per-FR row names under '
        'fr', () async {
      final project = await _project(
        _record(),
        extra: _frWithTwoEdgeCases(),
        mode: MatrixMode.fr,
      );

      final finding = _missing(await _run(project)).single;

      expect(finding.path, loginRecord);
      expect(finding.line, statusesLine);
      expect(finding.waitsFor, WaitsFor.agent);
      expect(finding.keys, {'item': _fr});
      expect(finding.message, '$_fr is implemented and no matrix row names it');
    });

    test('reports nothing under off', () async {
      final project = await _project(
        _record(),
        extra: _frWithTwoEdgeCases(),
        mode: MatrixMode.off,
      );

      expect(_missing(await _run(project)), isEmpty);
    });

    test('counts a skip row and an unresolved test row as covering', () async {
      for (final row in [
        '- $_fr skipped: no clock on CI',
        '- $_fr: `refuses a blank password`',
      ]) {
        final project = await _project(
          _record(rows: [row]),
          extra: _frWithTwoEdgeCases(),
          mode: MatrixMode.fr,
        );

        expect(_missing(await _run(project)), isEmpty, reason: row);
      }
    });

    for (final (name, statuses, verifyMethod) in [
      ('planned', const ['$_fr:planned'], 'test'),
      ('deprecated', const ['$_fr:deprecated'], 'test'),
      ('skipped', const ['$_fr:skipped:not in this client'], 'test'),
      (
        'under a story skip',
        const ['$_story:skipped:not in this client', '$_fr:implemented'],
        'test',
      ),
      ('verified by inspection', const ['$_fr:implemented'], 'inspection'),
    ]) {
      test(
        'skips planned, deprecated, skipped, and non-test FRs: $name',
        () async {
          final project = await _project(
            _record(statuses: statuses),
            extra: {
              ...edit(loginFr, [
                ('verify_method: test', 'verify_method: $verifyMethod'),
              ]),
            },
            mode: MatrixMode.fr,
          );

          expect(_missing(await _run(project)), isEmpty);
        },
      );
    }

    test('reports only the target the FR is implemented in', () async {
      final project = await writeTwinProject(
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}verification_coverage: fr\n'
              'targets:\n  flutter:\n    code_root: flutter_ws\n'
              '  jaspr:\n    code_root: jaspr_ws\n',
          'flutter_ws/$_testFile': _testBody,
          _flutterRecord: _record(),
          _jasprRecord: _record(statuses: const ['$_fr:planned']),
        },
      );

      final finding = _missing(await _run(project)).single;

      expect(finding.path, _flutterRecord);
      expect(finding.keys, {'item': _fr});
      expect(
        finding.message,
        '$_fr is implemented in target flutter and no matrix row names it',
      );
      expect(_missing(await _run(project, codeTarget: 'jaspr')), isEmpty);
    });

    test('gives no missing row for a split edge case under fr', () async {
      final project = await _project(
        _record(rows: ['- $_fr: `refuses an empty password`']),
        extra: _frWithThreeEdgeCases(),
        mode: MatrixMode.fr,
      );

      expect(_missing(await _run(project)), isEmpty);
    });

    test('reports an unnamed edge case under edge_case', () async {
      final project = await _project(
        _record(rows: ['- $_fr E01: `refuses an empty password`']),
        extra: _frWithThreeEdgeCases(),
      );

      final report = await _run(project);

      expect(_missingEdgeCases(report), [
        ['E02', statusesLine],
        ['E03', statusesLine],
      ]);
      expect(_missing(report).first.keys, {'item': _fr, 'edge_case': 'E02'});
    });

    test('lets no refused-form row cover its FR', () async {
      final perEdgeCase = await _project(
        _record(rows: ['- $_fr E01: `refuses an empty password`']),
        extra: _frWithTwoEdgeCases(),
        mode: MatrixMode.fr,
      );
      final perFr = await _project(
        _record(rows: ['- $_fr: `refuses an empty password`']),
        extra: _frWithTwoEdgeCases(),
      );

      expect(_missing(await _run(perEdgeCase)).single.keys, {'item': _fr});
      expect(_missingEdgeCases(await _run(perFr)), [
        ['E01', statusesLine],
        ['E02', statusesLine],
      ]);
    });
  });
}
