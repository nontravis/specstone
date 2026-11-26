// Test names are matrix literals, so long names stay whole.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/document_writing/sync_lines.dart';
import 'package:test/test.dart';

const _path = 'edits/sync.txt';
const _fingerprint = '0123456789ab';

SyncFault _refused(String text) {
  try {
    parseSyncFile(_path, text);
  } on SyncFault catch (fault) {
    return fault;
  }
  fail('expected a SyncFault');
}

List<SyncLine> _read(String text) => parseSyncFile(_path, text).lines;

void main() {
  test('a repoint line whose last part holds ":" reads as one RepointLine with that whole new path', () {
    final lines = _read(
      'repoint login app/lib/login.dart:signIn app/lib/auth/login.dart:signInPage',
    );

    expect(
      lines.single,
      isA<RepointLine>()
          .having((l) => l.entry, 'entry', 'app/lib/login.dart:signIn')
          .having(
            (l) => l.newPath,
            'new path',
            'app/lib/auth/login.dart:signInPage',
          ),
    );
  });

  test(
    'each of the eight line kinds reads as its own class with its fields',
    () {
      final lines = _read(
        [
          '? login app/lib/login.dart:signIn $_fingerprint',
          'match login app/lib/login.dart:run $_fingerprint',
          'planned login app/lib/login.dart:stop $_fingerprint',
          'mismatch login app/lib/login.dart:start: the timeout is 30 s, the code says 60 s',
          'repoint login app/lib/login.dart:signIn app/lib/auth/login.dart',
          'row implementation:login email_login/check_password: +`rejects a wrong password` -`old name`',
          'tests implementation:login email_login/check_password: +test/login_test.dart',
          'remove-task T-12 login app/lib/login.dart:signIn',
        ].join('\n'),
      );

      expect(lines, hasLength(8));
      expect(
        lines[0],
        isA<UnjudgedLine>()
            .having((l) => l.lineNumber, 'line', 1)
            .having((l) => l.doc, 'doc', 'login')
            .having((l) => l.entry, 'entry', 'app/lib/login.dart:signIn')
            .having((l) => l.fingerprint, 'fingerprint', _fingerprint),
      );
      expect(lines[1], isA<MatchLine>().having((l) => l.lineNumber, 'line', 2));
      expect(
        lines[2],
        isA<PlannedLine>().having((l) => l.lineNumber, 'line', 3),
      );
      expect(
        lines[3],
        isA<MismatchLine>()
            .having((l) => l.entry, 'entry', 'app/lib/login.dart:start')
            .having(
              (l) => l.point,
              'point',
              'the timeout is 30 s, the code says 60 s',
            ),
      );
      expect(
        lines[4],
        isA<RepointLine>()
            .having((l) => l.entry, 'entry', 'app/lib/login.dart:signIn')
            .having((l) => l.newPath, 'new path', 'app/lib/auth/login.dart'),
      );
      expect(
        lines[5],
        isA<RowLine>()
            .having((l) => l.record, 'record', 'implementation:login')
            .having((l) => l.item, 'item', 'email_login/check_password')
            .having((l) => l.edgeCase, 'edge case', isNull)
            .having((l) => l.added, 'added', ['rejects a wrong password'])
            .having((l) => l.removed, 'removed', ['old name']),
      );
      expect(
        lines[6],
        isA<TestsLine>()
            .having((l) => l.item, 'item', 'email_login/check_password')
            .having((l) => l.testFile, 'file', 'test/login_test.dart')
            .having((l) => l.adds, 'adds', isTrue),
      );
      expect(
        lines[7],
        isA<RemoveTaskLine>()
            .having((l) => l.task, 'task', 'T-12')
            .having((l) => l.doc, 'doc', 'login')
            .having((l) => l.entry, 'entry', 'app/lib/login.dart:signIn'),
      );
    },
  );

  test('a matrix row entry with an edge case keeps its space and a row line with an edge case reads it', () {
    final lines = _read(
      [
        'match implementation:login email_login/check_password E02 $_fingerprint',
        'row implementation:login email_login/check_password E02: +`locks the account`',
        'tests implementation:login email_login/check_password: -test/old_test.dart',
      ].join('\n'),
    );

    expect(
      lines[0],
      isA<MatchLine>().having(
        (l) => l.entry,
        'entry',
        'email_login/check_password E02',
      ),
    );
    expect(
      lines[1],
      isA<RowLine>().having((l) => l.edgeCase, 'edge case', 'E02').having(
        (l) => l.added,
        'added',
        ['locks the account'],
      ),
    );
    expect(lines[2], isA<TestsLine>().having((l) => l.adds, 'adds', isFalse));
  });

  test('a code span of a row literal may hold a colon, a space, and a longer backtick run, and loses its padding as CommonMark reads it', () {
    final lines = _read(
      'row implementation:login email_login/check_password: +`a: b c` +``has ` tick`` -`` `x` works `` -`  `',
    );

    expect(
      lines.single,
      isA<RowLine>()
          .having((l) => l.added, 'added', ['a: b c', 'has ` tick'])
          .having((l) => l.removed, 'removed', ['`x` works', '  ']),
    );
  });

  test('a file with a marking line reads only the lines after it and ignores a sync-shaped diff line above', () {
    final lines = _read(
      [
        '+match login app/lib/login.dart:signIn $_fingerprint',
        'match login app/lib/old.dart:gone $_fingerprint',
        '==> verdicts <==',
        'mismatch login app/lib/login.dart:signIn: the point',
      ].join('\n'),
    );

    expect(lines.single, isA<MismatchLine>());
    expect(lines.single.lineNumber, 4);
  });

  test(
    'a file with two marking lines reads only the lines after the last one',
    () {
      final lines = _read(
        [
          '==> verdicts <==',
          'match login app/lib/login.dart:signIn $_fingerprint',
          '==> verdicts <==',
          'mismatch login app/lib/login.dart:signIn: the point',
        ].join('\n'),
      );

      expect(lines.single, isA<MismatchLine>());
      expect(lines.single.lineNumber, 4);
    },
  );

  test('extra spaces between the parts of a line refuse that line', () {
    final fault = _refused(
      [
        '?  login app/lib/login.dart:signIn $_fingerprint',
        'match login  app/lib/login.dart:signIn $_fingerprint',
        'match login app/lib/login.dart:signIn  $_fingerprint',
        'mismatch login  app/lib/login.dart:signIn: the point',
        'repoint login app/lib/login.dart:signIn  app/lib/new.dart',
        'remove-task T-12  login app/lib/login.dart:signIn',
        'row  implementation:login email_login/check_password: +`a`',
        'tests implementation:login  email_login/check_password: +test/a_test.dart',
      ].join('\n'),
    );

    expect(fault.refusals.map((r) => r.line), [1, 2, 3, 4, 5, 6, 7, 8]);
  });

  test('a file with no marking line reads whole', () {
    final lines = _read(
      [
        'match login app/lib/login.dart:signIn $_fingerprint',
        'mismatch login app/lib/other.dart:run: the point',
      ].join('\n'),
    );

    expect(lines, hasLength(2));
  });

  test('blank lines are skipped and a file of none reads as no line', () {
    expect(
      _read('\n  \n? login app/lib/login.dart:signIn $_fingerprint\n\t\n'),
      hasLength(1),
    );
    expect(_read(''), isEmpty);
    expect(_read('==> verdicts <==\n'), isEmpty);
  });

  test('a CRLF file and a BOM read as LF text', () {
    final lines = _read(
      '﻿==> verdicts <==\r\n'
      'match login app/lib/login.dart:signIn $_fingerprint\r\n'
      'mismatch login app/lib/other.dart:run: the point\r\n',
    );

    expect(lines, hasLength(2));
    expect(
      lines[0],
      isA<MatchLine>()
          .having((l) => l.fingerprint, 'fingerprint', _fingerprint)
          .having((l) => l.lineNumber, 'line', 2),
    );
    expect(
      lines[1],
      isA<MismatchLine>().having((l) => l.point, 'point', 'the point'),
    );
  });

  test('a malformed line refuses argument_invalid naming its line number and every refused line comes in one fault', () {
    final fault = _refused(
      [
        '==> verdicts <==',
        'match login app/lib/login.dart:signIn $_fingerprint',
        'frobnicate login x',
        '',
        'match login app/lib/login.dart:run',
        'remove-task T-12',
      ].join('\n'),
    );

    expect(fault.refusals.map((r) => r.line), [3, 5, 6]);
    expect(fault.refusals.every((r) => r.code == 'argument_invalid'), isTrue);
    expect(fault.exitStatus, 64);
    expect(
      fault.toText().split('\n').map((l) => l.split(': ').take(2).join(': ')),
      [
        '$_path:3: argument_invalid',
        '$_path:5: argument_invalid',
        '$_path:6: argument_invalid',
      ],
    );
  });

  test('each form break refuses its line: a bad fingerprint, no point, no new path, a row with no literal, a tests line with no sign, a remove-task with no link or a task id holding a colon', () {
    const broken = [
      '? login app/lib/login.dart:signIn 0123456789AB',
      '? login app/lib/login.dart:signIn 0123456789a',
      'planned login 0123456789ab',
      'mismatch login app/lib/login.dart:signIn',
      'mismatch login app/lib/login.dart:signIn: ',
      'repoint login app/lib/login.dart:signIn',
      'row implementation:login email_login/check_password: ',
      'row implementation:login email_login/check_password: +test',
      'row implementation:login email_login/check_password: +`a`+`b`',
      'row implementation:login: +`a`',
      'tests implementation:login email_login/check_password: test/a_test.dart',
      'tests implementation:login email_login/check_password +test/a_test.dart',
      'remove-task T-12 login',
      'remove-task T:12 login app/lib/login.dart:signIn',
      ' match login app/lib/login.dart:signIn 0123456789ab',
    ];

    final fault = _refused(broken.join('\n'));

    expect(fault.refusals.map((r) => r.line), [
      for (var i = 1; i <= broken.length; i++) i,
    ]);
  });

  test('a match or planned line beside another verdict line of its entry refuses naming both lines', () {
    final fault = _refused(
      [
        'match login app/lib/login.dart:signIn $_fingerprint',
        'planned login app/lib/login.dart:signIn 111111111111',
        'mismatch login app/lib/login.dart:signIn: the point',
        '? login app/lib/login.dart:signIn $_fingerprint',
      ].join('\n'),
    );

    expect(fault.refusals.map((r) => r.line), [2, 3, 4]);
    for (final refusal in fault.refusals) {
      expect(refusal.message, contains('line 1'));
    }
  });

  test('mismatch lines of one entry and verdict lines of two entries stand together', () {
    final lines = _read(
      [
        'mismatch login app/lib/login.dart:signIn: first point',
        'mismatch login app/lib/login.dart:signIn: second point',
        'match login app/lib/login.dart:run $_fingerprint',
        'match other app/lib/login.dart:signIn $_fingerprint',
      ].join('\n'),
    );

    expect(lines, hasLength(4));
  });

  test('a sync fault prints one path line code message line per refusal and a lines array in its JSON', () {
    final fault = SyncFault(_path, [
      SyncRefusal.invalid(2, 'first'),
      const SyncRefusal(
        line: 5,
        code: 'stamp_stale',
        exitStatus: 75,
        message: 'second',
      ),
    ]);

    expect(
      fault.toText(),
      '$_path:2: argument_invalid: first\n$_path:5: stamp_stale: second',
    );
    expect(fault.exitStatus, 64);
    expect(fault.toJson(), {
      'error': {
        'code': 'argument_invalid',
        'message': 'first',
        'file': _path,
        'line': 2,
        'lines': [
          {
            'code': 'argument_invalid',
            'message': 'first',
            'file': _path,
            'line': 2,
          },
          {
            'code': 'stamp_stale',
            'message': 'second',
            'file': _path,
            'line': 5,
          },
        ],
      },
    });
  });

  test('a sync fault of stale refusals alone exits 75', () {
    final fault = SyncFault(_path, [
      const SyncRefusal(
        line: 1,
        code: 'stamp_stale',
        exitStatus: 75,
        message: 'stale',
      ),
    ]);

    expect(fault.exitStatus, 75);
  });
}
