// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/record_fixture.dart';
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

Future<Directory> _project(
  String record, {
  Map<String, String> extra = const {},
}) => writeCheckProject(
  extra: {loginRecord: record, _testFile: _testBody, ...extra},
  // A stamp would add an `approved:` line and move every line below it.
  unstamped: {loginRecord},
);

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

  for (final (name, statuses) in [
    ('its own skip', const ['$_fr:skipped:not in this client']),
    ('the skip of its story', const ['$_story:skipped:not in this client']),
  ]) {
    test('a row of an item under $name gets no literal finding', () async {
      final record = _record(
        statuses: statuses,
        rows: ['- $_fr E01: `no test holds this`'],
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
}
