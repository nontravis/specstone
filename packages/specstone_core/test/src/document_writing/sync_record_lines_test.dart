// A matrix row matches a test name as one literal, so long names stay whole.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/document_writing/set_sync.dart';
import 'package:specstone_core/src/document_writing/sync_lines.dart';
import 'package:specstone_core/src/document_writing/sync_record_lines.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/matrix_mode.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/shipped_pins.dart' show shippedPinsConfig;
import '../../helpers/write_fixture.dart' hide loginFeature;

const _record = 'implementation:login';
const _fr = 'email_login/check_password';
const _edgeCase = '1. E01 — An empty password → refused.';
const _fingerprint = '0123456789ab';
const _old = 'ba9876543210';

final MergedDocType _recordType = fixtureDocTypeOf(loginRecord);

final String _contractFingerprint = fingerprintFor(
  '## Statement\n\n$checkPasswordStatement\n\n## Edge cases\n\n$_edgeCase',
);
final String _edgeCaseFingerprint = fingerprintFor(_edgeCase);

/// Returns the record with [status] as the FR's status, its `tests` field
/// holding [tests], and a Verification matrix section of [rows] when given.
String _recordText({
  String status = 'implemented',
  List<String> tests = const [],
  List<String>? rows,
}) => [
  "---\nstatuses:\n  - 'email_login:implemented'\n  - '$_fr:$status'\n",
  if (tests.isNotEmpty)
    'tests:\n${[for (final line in tests) "  - '$line'\n"].join()}',
  '---\n\n# Login implementation\n',
  if (rows != null) '\n## Verification matrix\n\n${rows.join('\n')}\n',
].join();

/// Returns the one line [line] reads as, as a sync file holds it.
T _lineOf<T extends SyncLine>(String line) =>
    parseSyncFile('sync.txt', '$line\n').lines.single as T;

/// Applies [line] under [mode], every row of the form [mode] does not read
/// taken as refused, as it is for an FR.
String _row(String text, String line, {MatrixMode mode = MatrixMode.fr}) =>
    applyRowLine(
      text,
      _recordType,
      _lineOf(line),
      mode: mode,
      isRefusedForm: (row) => row.form != mode.readsForm,
    );

String _tests(String text, String line) =>
    applyTestsLine(text, _recordType, _lineOf(line));

/// Writes the check fixture under [mode] with its record from [_recordText].
Future<Directory> _project({
  String mode = 'fr',
  String status = 'implemented',
  List<String> tests = const [],
  List<String>? rows,
}) => writeCheckProject(
  extra: {
    '.specstone/config.yaml':
        '${shippedPinsConfig()}verification_coverage: $mode\n',
    loginRecord: _recordText(status: status, tests: tests, rows: rows),
  },
  unstamped: {loginRecord},
  unfingerprinted: {loginRecord},
);

ReadAnswer _sync(Directory root, List<String> lines) => writeIn(
  root,
  (session) => answerSetSync(
    session,
    parseSyncFile('sync.txt', '${lines.join('\n')}\n'),
  ),
);

SyncFault _refused(Directory root, List<String> lines) {
  try {
    _sync(root, lines);
  } on SyncFault catch (fault) {
    return fault;
  }
  fail('the sync was not refused');
}

List<String> _refusalsOf(SyncFault fault) => [
  for (final refusal in fault.refusals)
    '${refusal.line} ${refusal.code}: ${refusal.message}',
];

void main() {
  test('under fr a plus literal on an FR with no row makes its per-FR row with no fingerprint', () {
    expect(
      _row(_recordText(), 'row $_record $_fr: +`refuses an empty password`'),
      _recordText(rows: ['- $_fr: `refuses an empty password`']),
    );
  });

  test('under fr a plus literal on a test row appends to it and keeps its fingerprint', () {
    expect(
      _row(
        _recordText(rows: ['- $_fr: `refuses a wrong one` $_fingerprint']),
        'row $_record $_fr: +`refuses an empty password` +``has a `tick` in it``',
      ),
      _recordText(
        rows: [
          '- $_fr: `refuses a wrong one`, `refuses an empty password`, ``has a `tick` in it`` $_fingerprint',
        ],
      ),
    );
  });

  test('under fr a plus literal on a skip row puts a test row of no fingerprint in its place', () {
    expect(
      _row(
        _recordText(rows: ['- $_fr skipped: no test yet $_fingerprint']),
        'row $_record $_fr: +`refuses an empty password`',
      ),
      _recordText(rows: ['- $_fr: `refuses an empty password`']),
    );
  });

  test('a minus literal leaves the per-FR row, and a row left with no literal is removed, under fr and under edge_case', () {
    for (final mode in [MatrixMode.fr, MatrixMode.edgeCase]) {
      final held = _recordText(
        rows: [
          '- $_fr: `refuses a wrong one`, `refuses an empty password` $_fingerprint',
        ],
      );

      final once = _row(
        held,
        'row $_record $_fr: -`refuses a wrong one`',
        mode: mode,
      );
      final twice = _row(
        once,
        'row $_record $_fr: -`refuses an empty password`',
        mode: mode,
      );

      expect(
        once,
        _recordText(
          rows: ['- $_fr: `refuses an empty password` $_fingerprint'],
        ),
        reason: '$mode',
      );
      expect(
        twice,
        '${_recordText()}\n## Verification matrix\n\n',
        reason: '$mode',
      );
    }
  });

  test('under edge_case a per-edge-case line makes a row per plus literal and removes the row of each minus literal', () {
    expect(
      _row(
        _recordText(rows: ['- $_fr E01: `refuses a wrong one` $_fingerprint']),
        'row $_record $_fr E01: +`refuses an empty password` -`refuses a wrong one`',
        mode: MatrixMode.edgeCase,
      ),
      _recordText(rows: ['- $_fr E01: `refuses an empty password`']),
    );
  });

  test(
    'a row line whose write the record holds returns the text as it was',
    () {
      for (final (rows, line, mode) in [
        (
          ['- $_fr: `refuses a wrong one` $_fingerprint'],
          'row $_record $_fr: +`refuses a wrong one` -`gone`',
          MatrixMode.fr,
        ),
        (
          ['- $_fr skipped: no test yet'],
          'row $_record $_fr: -`gone`',
          MatrixMode.off,
        ),
        (const <String>[], 'row $_record $_fr: -`gone`', MatrixMode.fr),
        (
          ['- $_fr E01: `refuses a wrong one`'],
          'row $_record $_fr E01: +`refuses a wrong one` -`gone`',
          MatrixMode.edgeCase,
        ),
      ]) {
        final text = _recordText(rows: rows);

        expect(_row(text, line, mode: mode), text, reason: line);
      }
    },
  );

  test('each row line the mode refuses throws argument_invalid naming the mode', () {
    for (final (rows, line, mode, message) in [
      (
        const <String>[],
        'row $_record $_fr E01: +`refuses an empty password`',
        MatrixMode.fr,
        'a per-edge-case row line under verification_coverage fr; write one row per FR',
      ),
      (
        const <String>[],
        'row $_record $_fr E01: -`refuses an empty password`',
        MatrixMode.off,
        'a per-edge-case row line under verification_coverage off; write one row per FR',
      ),
      (
        const <String>[],
        'row $_record $_fr: +`refuses an empty password`',
        MatrixMode.edgeCase,
        'a per-FR row line that adds a literal under verification_coverage edge_case; write one row per edge case',
      ),
      (
        ['- $_fr E01: `refuses a wrong one`'],
        'row $_record $_fr: +`refuses an empty password`',
        MatrixMode.fr,
        '$_fr holds per-edge-case rows, which wait for specstone migrate under verification_coverage fr',
      ),
    ]) {
      expect(
        () => _row(_recordText(rows: rows), line, mode: mode),
        throwsA(
          isA<IndexFault>()
              .having(
                (fault) => fault.code,
                'code',
                IndexFaultCode.argumentInvalid,
              )
              .having((fault) => fault.message, 'message', message),
        ),
        reason: line,
      );
    }
  });

  test('a tests plus line adds its item line and a minus line removes it, each a second time changing nothing', () {
    const file = 'app/test/login_test.dart';
    final held = _recordText(
      tests: const ['email_login:app/test/sign_in_test.dart'],
    );

    final added = _tests(held, 'tests $_record $_fr: +$file');
    final removed = _tests(added, 'tests $_record $_fr: -$file');

    expect(
      added,
      _recordText(
        tests: const ['email_login:app/test/sign_in_test.dart', '$_fr:$file'],
      ),
    );
    expect(_tests(added, 'tests $_record $_fr: +$file'), added);
    expect(removed, held);
    expect(_tests(removed, 'tests $_record $_fr: -$file'), removed);
    expect(
      _tests(
        _tests(_recordText(), 'tests $_record $_fr: +$file'),
        'tests $_record $_fr: -$file',
      ),
      _recordText(),
    );
  });

  test(
    'a tests line on a doc type with no tests field throws argument_invalid',
    () {
      expect(
        () => applyTestsLine(
          _recordText(),
          fixtureDocTypeOf(loginArchitecture),
          _lineOf('tests $_record $_fr: +app/test/login_test.dart'),
        ),
        throwsA(
          isA<IndexFault>().having(
            (fault) => fault.code,
            'code',
            IndexFaultCode.argumentInvalid,
          ),
        ),
      );
    },
  );

  test('a minus literal written padded, as the record writes it, removes the literal', () {
    expect(
      _row(
        _recordText(rows: ['- $_fr: `refuses`, `` `x` works ``']),
        'row $_record $_fr: -`` `x` works ``',
      ),
      _recordText(rows: ['- $_fr: `refuses`']),
    );
  });

  test('a match after the row line that adds its row stamps it in the same write, and a match above it refuses stamp_entry_unknown', () async {
    const row = 'row $_record $_fr: +`refuses an empty password`';
    final match = 'match $_record $_fr $_contractFingerprint';
    final root = await _project();

    final fault = _refused(root, [match, row]);
    _sync(root, [row, match]);

    expect(_refusalsOf(fault), [
      '1 stamp_entry_unknown: no entry of $_record reads $_fr',
    ]);
    expect(
      readDoc(root, loginRecord),
      contains('\n- $_fr: `refuses an empty password` $_contractFingerprint\n'),
    );
  });

  test('a match on a matrix row the record holds stamps its upstream block fingerprint, and a fingerprint that differs refuses stamp_stale', () async {
    for (final (mode, row, entry, current) in [
      ('fr', '- $_fr: `refuses a wrong one` $_old', _fr, _contractFingerprint),
      (
        'edge_case',
        '- $_fr E01: `refuses a wrong one`',
        '$_fr E01',
        _edgeCaseFingerprint,
      ),
    ]) {
      final root = await _project(mode: mode, rows: [row]);

      final fault = _refused(root, ['match $_record $entry $_fingerprint']);
      _sync(root, ['match $_record $entry $current']);

      expect(_refusalsOf(fault), [
        '1 stamp_stale: $entry changed after $_fingerprint; judge it again',
      ], reason: mode);
      expect(fault.exitStatus, 75, reason: mode);
      expect(
        readDoc(root, loginRecord),
        contains('\n- $entry: `refuses a wrong one` $current\n'),
        reason: mode,
      );
      final report = await checkOf(root);
      expect(
        [
          ...spots(report, FindingKind.suspect),
          ...spots(report, FindingKind.unconfirmed),
        ].where((spot) => spot.startsWith(loginRecord)),
        isEmpty,
        reason: mode,
      );
    }
  });

  test(
    'a planned line on a matrix row stamps it and the FR stays planned',
    () async {
      final root = await _project(
        status: 'planned',
        rows: ['- $_fr: `refuses a wrong one`'],
      );

      _sync(root, ['planned $_record $_fr $_contractFingerprint']);

      final record = readDoc(root, loginRecord);
      expect(
        record,
        contains('\n- $_fr: `refuses a wrong one` $_contractFingerprint\n'),
      );
      expect(record, contains("'$_fr:planned'"));
    },
  );

  test('a row or tests line whose item names no story or FR of the record feature, and a row line the mode refuses, refuse the file naming each line', () async {
    final root = await _project();
    final before = readDoc(root, loginRecord);

    final fault = _refused(root, [
      'tests $_record email_login/none: +app/test/login_test.dart',
      'row $_record email_login/none: +`refuses`',
      'row $_record $_fr E01: +`refuses`',
    ]);

    expect(_refusalsOf(fault), [
      '1 stamp_entry_unknown: email_login/none names no story or FR of the feature of $_record',
      '2 stamp_entry_unknown: email_login/none names no story or FR of the feature of $_record',
      '3 argument_invalid: a per-edge-case row line under verification_coverage fr; write one row per FR',
    ]);
    expect(fault.exitStatus, 64);
    expect(readDoc(root, loginRecord), before);
  });

  test(
    'a repoint of a tests entry rewrites its path and keeps its item',
    () async {
      final root = await _project(tests: const ['$_fr:app/test/old_test.dart']);

      _sync(root, [
        'repoint $_record $_fr:app/test/old_test.dart app/test/login_test.dart',
      ]);

      final record = readDoc(root, loginRecord);
      expect(record, contains("'$_fr:app/test/login_test.dart'"));
      expect(record, isNot(contains('old_test.dart')));
    },
  );

  test('a tests line on a record whose tests block is not valid YAML refuses output_not_writable and writes no doc', () async {
    final root = await _project(tests: const ['$_fr:app/test/old_test.dart']);
    final broken = readDoc(root, loginRecord).replaceFirst(
      "'$_fr:app/test/old_test.dart'",
      "'$_fr:app/test/old_test.dart",
    );
    File('${root.path}/$loginRecord').writeAsStringSync(broken);

    final fault = _refused(root, [
      'tests $_record $_fr: +app/test/login_test.dart',
    ]);

    expect(_refusalsOf(fault), [
      '1 output_not_writable: cannot write $loginRecord: its tests block is not valid YAML',
    ]);
    expect(readDoc(root, loginRecord), broken);
  });

  test('a match on a matrix row of a planned FR stamps the row and the FR stays planned', () async {
    final root = await _project(
      status: 'planned',
      rows: ['- $_fr: `refuses a wrong one`'],
    );

    _sync(root, ['match $_record $_fr $_contractFingerprint']);

    final record = readDoc(root, loginRecord);
    expect(
      record,
      contains('\n- $_fr: `refuses a wrong one` $_contractFingerprint\n'),
    );
    expect(record, contains("'$_fr:planned'"));
  });

  test('a row line that adds and removes one literal throws argument_invalid naming the literal', () {
    expect(
      () => _row(
        _recordText(),
        'row $_record $_fr: +`refuses a wrong one` -`refuses a wrong one`',
      ),
      throwsA(
        isA<IndexFault>()
            .having(
              (fault) => fault.code,
              'code',
              IndexFaultCode.argumentInvalid,
            )
            .having(
              (fault) => fault.message,
              'message',
              '`refuses a wrong one` is both added and removed; write it once',
            ),
      ),
    );
  });

  test('under fr a per-FR line of a story that holds per-edge-case rows writes its row, since only an FR row waits for migrate', () async {
    final root = await _project(rows: ['- email_login E01: `signs in`']);

    _sync(root, ['row $_record email_login: +`signs in with an email`']);

    expect(
      readDoc(root, loginRecord),
      contains('\n- email_login: `signs in with an email`\n'),
    );
  });
}
