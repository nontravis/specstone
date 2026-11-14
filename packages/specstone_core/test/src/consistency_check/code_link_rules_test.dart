import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/code_link_rules.dart';
import 'package:specstone_core/src/consistency_check/code_rules.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/implements_rule.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/target_fixture.dart';

const _recordPath = 'specs/f01_login/IMPLEMENTATION.md';
const _flutterRecord = 'specs/flutter/f01_login/IMPLEMENTATION.md';
const _jasprRecord = 'specs/jaspr/f01_login/IMPLEMENTATION.md';
const _fr = 'email_login/check_password';
const _implemented = '$_fr:implemented';
const _login = 'app/lib/login.dart';
const _pointer = '$_login:checkPassword';
const _stale = '0123456789ab';
const _unreadable =
    'cannot read the file; implements Symbols in it are not checked';

String _fingerprintOf(String text) => fileCodeFingerprint(utf8.encode(text));

/// Returns the fingerprint of a folder that lists [files], by path and text.
String _folderFingerprintOf(Map<String, String> files) =>
    folderCodeFingerprint([
      for (final MapEntry(:key, :value) in files.entries)
        (path: key, fingerprint: _fingerprintOf(value)),
    ]);

final String _loginText = checkProjectFiles()[_login]!;
final String _loginFingerprint = _fingerprintOf(_loginText);

/// Returns a record: `statuses`, `implements`, and `tests`, one quoted line
/// each, under a `draft: true` line when [isDraft].
String _record({
  List<String> statuses = const [_implemented],
  List<String> code = const [],
  List<String> tests = const [],
  bool isDraft = false,
}) {
  String list(String key, List<String> lines) => lines.isEmpty
      ? ''
      : "$key:\n${[for (final l in lines) "  - '$l'\n"].join()}";
  return '---\n${isDraft ? 'draft: true\n' : ''}${list('statuses', statuses)}'
      '${list('implements', code)}${list('tests', tests)}---\n\n# Record\n';
}

/// Returns the file line of the first line of [text] that holds [needle].
int _lineOf(String text, String needle) =>
    text.split('\n').indexWhere((line) => line.contains(needle)) + 1;

Future<Directory> _project(
  String record, {
  Map<String, String> extra = const {},
  Set<String> without = const {},
  Set<String> unfingerprinted = const {},
}) => writeCheckProject(
  extra: {'docs/$_recordPath': record, ...extra},
  without: without,
  unstamped: {'docs/$_recordPath'},
  unfingerprinted: {'docs/$_recordPath', ...unfingerprinted},
);

/// Returns the architecture doc of the fixture covering [covers].
Map<String, String> _covering(String covers) =>
    doc(loginArchitecture, '  - app/lib/\n', covers);

CheckReport _run(Directory project, {String? codeTarget}) {
  final session = openSession(project);
  try {
    return runCheck(session, codeTarget: codeTarget);
  } finally {
    session.close();
  }
}

List<Finding> _suspects(CheckReport report) =>
    _ofKind(report, FindingKind.codeSuspect);

List<Finding> _unconfirmed(CheckReport report) =>
    _ofKind(report, FindingKind.codeUnconfirmed);

List<Finding> _ofKind(CheckReport report, FindingKind kind) => [
  for (final f in report.findings)
    if (f.kind == kind) f,
];

/// Runs the rule alone on the doc at [docPath], keeping its context to read
/// what it read.
({CheckContext context, List<Finding> findings}) _checked(
  Directory project,
  String docPath,
) {
  final session = openSession(project);
  addTearDown(session.close);
  final context = CheckContext(session);
  final findings = checkCodeLinks(
    context,
    ImplementedWork(context, context.targets),
    session.index.at(docPath)!,
  ).toList();
  return (context: context, findings: findings);
}

void main() {
  group('a record entry', () {
    test("that records its file's fingerprint gives no finding", () async {
      final report = _run(
        await _project(_record(code: ['$_fr:$_pointer $_loginFingerprint'])),
      );

      expect(_suspects(report), isEmpty);
    });

    test('that records no fingerprint gives code_unconfirmed with the current '
        'fingerprint on its own key', () async {
      final record = _record(code: ['$_fr:$_pointer']);

      final report = _run(await _project(record));
      final [finding] = _unconfirmed(report);

      expect(_suspects(report), isEmpty);
      expect(finding.path, _recordPath);
      expect(finding.line, _lineOf(record, _pointer));
      expect(finding.waitsFor, WaitsFor.agent);
      expect(finding.message, '$_login records no fingerprint');
      expect(finding.message, isNot(contains(_loginFingerprint)));
      expect(finding.keys, {
        'entry': _pointer,
        'path': _login,
        'fingerprint': _loginFingerprint,
      });
      expect(finding.textLines, [
        '$_recordPath:${finding.line}: code_unconfirmed: ${finding.message}',
        '    fingerprint $_loginFingerprint',
      ]);
    });

    test(
      'that records its file fingerprint gives neither code finding',
      () async {
        final report = _run(
          await _project(_record(code: ['$_fr:$_pointer $_loginFingerprint'])),
        );

        expect(_unconfirmed(report), isEmpty);
        expect(_suspects(report), isEmpty);
      },
    );

    test('that records no fingerprint waits for the agent in a draft record '
        'and an approved one', () async {
      for (final isDraft in [true, false]) {
        final [finding] = _unconfirmed(
          _run(
            await _project(_record(code: ['$_fr:$_pointer'], isDraft: isDraft)),
          ),
        );

        expect(finding.waitsFor, WaitsFor.agent, reason: 'draft: $isDraft');
      }
    });

    test('that records no fingerprint and whose file is gone gives '
        'implements_path_unresolved alone', () async {
      final report = _run(
        await _project(
          _record(code: ['$_fr:app/lib/gone.dart:Gone']),
          without: const {_login},
        ),
      );

      expect(_unconfirmed(report), isEmpty);
      expect(
        _ofKind(report, FindingKind.implementsPathUnresolved),
        hasLength(1),
      );
    });

    test('whose file changed gives code_suspect with the current '
        'fingerprint on its own key', () async {
      final record = _record(code: ['$_fr:$_pointer $_stale']);
      final changed = '${_loginText}class Added {}\n';
      final project = await _project(
        record,
        extra: _covering(
          '  - app/lib/ ${_folderFingerprintOf({_login: changed})}\n',
        ),
      );
      File('${project.path}/$_login').writeAsStringSync(changed);
      final current = _fingerprintOf(changed);

      final [finding] = _suspects(_run(project));

      expect(finding.path, _recordPath);
      expect(finding.line, _lineOf(record, '$_pointer $_stale'));
      expect(finding.waitsFor, WaitsFor.agent);
      expect(
        finding.message,
        '$_login changed since its fingerprint $_stale was recorded',
      );
      expect(finding.message, isNot(contains(current)));
      expect(finding.keys, {
        'entry': _pointer,
        'path': _login,
        'recorded': _stale,
        'fingerprint': current,
      });
      expect(finding.textLines, [
        '$_recordPath:${finding.line}: code_suspect: ${finding.message}',
        '    fingerprint $current',
      ]);
    });

    test('whose file was checked out with CRLF line ends gives no '
        'finding', () async {
      final project = await _project(
        _record(code: ['$_fr:$_pointer $_loginFingerprint']),
      );
      File('${project.path}/$_login')
          .writeAsStringSync(_loginText.replaceAll('\n', '\r\n'));

      expect(_suspects(_run(project)), isEmpty);
    });

    test('reads its state the same in a draft record and an approved '
        'one', () async {
      for (final isDraft in [true, false]) {
        final report = _run(
          await _project(
            _record(code: ['$_fr:$_pointer $_stale'], isDraft: isDraft),
          ),
        );

        expect(_suspects(report), hasLength(1), reason: 'draft: $isDraft');
      }
    });

    test('naming a file another entry names reads it once, and each entry '
        'takes its own state', () async {
      final record = _record(
        code: [
          '$_fr:$_pointer $_loginFingerprint',
          '$_fr:$_login:SignInPage $_stale',
        ],
      );
      final (:context, :findings) = _checked(
        await _project(record),
        _recordPath,
      );

      expect(context.codeFilesRead, 1);
      expect(
        [for (final f in findings) f.line],
        [_lineOf(record, 'SignInPage')],
      );
    });

    test('whose file is gone gives implements_path_unresolved alone', () async {
      final report = _run(
        await _project(
          _record(code: ['$_fr:app/lib/gone.dart:Gone $_stale']),
          without: const {_login},
        ),
      );

      expect(_suspects(report), isEmpty);
      expect([
        for (final f in report.findings)
          if (f.kind == FindingKind.implementsPathUnresolved) f,
      ], hasLength(1));
    });

    test('ending in a token that is no fingerprint records none and '
        'reads nothing', () async {
      final record = _record(
        code: [
          '$_fr:$_login 9A1C03BE55D2',
          '$_fr:$_login 9a1c03be55d',
          '$_fr:$_login 9a1c03be55d22',
        ],
      );
      final project = await _project(record);
      final (:context, :findings) = _checked(project, _recordPath);

      expect(findings, isEmpty);
      expect(context.codeFilesRead, 0);
      expect([
        for (final f in _run(project).findings)
          if (f.kind == FindingKind.implementsPathUnresolved) f,
      ], hasLength(3));
    });

    test('written with a ./ prefix shares its one read with the Symbol '
        'rule', () async {
      final session = openSession(
        await _project(
          _record(
            code: ['$_fr:./$_pointer $_stale', '$_fr:$_login:SignInPage'],
          ),
        ),
      );
      addTearDown(session.close);
      final context = CheckContext(session);
      final record = session.index.at(_recordPath)!;

      checkImplements(context, record).toList();
      checkCodeLinks(
        context,
        ImplementedWork(context, context.targets),
        record,
      ).toList();

      expect(context.codeFilesRead, 1);
    });

    test('of a skipped item reads nothing', () async {
      final (:context, :findings) = _checked(
        await _project(
          _record(
            statuses: ['$_fr:skipped:not needed'],
            code: ['$_fr:$_login $_stale'],
          ),
        ),
        _recordPath,
      );

      expect(findings, isEmpty);
      expect(context.codeFilesRead, 0);
    });

    test('in a tests line is no code link', () async {
      final report = _run(
        await _project(
          _record(
            code: ['$_fr:$_pointer $_loginFingerprint'],
            tests: ['$_fr:$_login:a_test $_stale'],
          ),
        ),
      );

      expect(_suspects(report), isEmpty);
    });
  });

  group('a planned entry', () {
    test('naming a file not written yet reads nothing', () async {
      final (:context, :findings) = _checked(
        await _project(
          _record(
            statuses: ['$_fr:planned'],
            code: ['$_fr:app/lib/toast.dart:showToast $_stale'],
          ),
        ),
        _recordPath,
      );

      expect(findings, isEmpty);
      expect(context.codeFilesRead, 0);
    });

    test('naming a folder reads nothing', () async {
      final (:context, :findings) = _checked(
        await _project(
          _record(statuses: ['$_fr:planned'], code: ['$_fr:app/lib/ $_stale']),
        ),
        _recordPath,
      );

      expect(findings, isEmpty);
      expect(context.codeFilesRead, 0);
    });

    test(
      'naming a file not written yet and recording none reads nothing',
      () async {
        final (:context, :findings) = _checked(
          await _project(
            _record(
              statuses: ['$_fr:planned'],
              code: ['$_fr:app/lib/toast.dart:showToast'],
            ),
          ),
          _recordPath,
        );

        expect(findings, isEmpty);
        expect(context.codeFilesRead, 0);
      },
    );

    test('whose file exists reads it and records no fingerprint gives '
        'code_unconfirmed and no code_suspect', () async {
      final record = _record(
        statuses: ['$_fr:planned'],
        code: ['$_fr:$_login:resetPassword'],
      );
      final (:context, :findings) = _checked(
        await _project(record),
        _recordPath,
      );

      expect(context.codeFilesRead, 1);
      expect(
        [for (final f in findings) (f.kind, f.line, f.keys['fingerprint'])],
        [
          (
            FindingKind.codeUnconfirmed,
            _lineOf(record, 'resetPassword'),
            _loginFingerprint,
          ),
        ],
      );
    });

    test('whose file exists and whose Symbol is not added yet gives '
        'code_unconfirmed alone', () async {
      final report = _run(
        await _project(
          _record(
            statuses: ['$_fr:planned'],
            code: ['$_fr:$_login:resetPassword'],
          ),
        ),
      );

      expect(_unconfirmed(report), hasLength(1));
      expect(_ofKind(report, FindingKind.implementsPathUnresolved), isEmpty);
      expect(_ofKind(report, FindingKind.implementsSymbolUnresolved), isEmpty);
    });

    test('whose file exists and records a stale fingerprint gives '
        'code_suspect', () async {
      final record = _record(
        statuses: ['$_fr:planned'],
        code: ['$_fr:$_login:resetPassword $_stale'],
      );
      final (:context, :findings) = _checked(
        await _project(record),
        _recordPath,
      );

      expect(context.codeFilesRead, 1);
      expect(
        [for (final f in findings) (f.kind, f.line)],
        [(FindingKind.codeSuspect, _lineOf(record, 'resetPassword'))],
      );
    });
  });

  group('a covers entry', () {
    final folderFingerprint = _folderFingerprintOf({_login: _loginText});

    test("that records its folder's fingerprint gives no finding", () async {
      final report = _run(
        await writeCheckProject(
          extra: _covering('  - app/lib/ $folderFingerprint\n'),
        ),
      );

      expect(_suspects(report), isEmpty);
    });

    test('whose folder gained, lost, or renamed a file gives '
        'code_suspect', () async {
      final recorded = _folderFingerprintOf({
        _login: _loginText,
        'app/lib/b.dart': 'b\n',
      });
      final cases = {
        'added': (folderFingerprint, {'app/lib/b.dart': 'b\n'}),
        'lost': (recorded, const <String, String>{}),
        'renamed': (recorded, {'app/lib/c.dart': 'b\n'}),
      };
      for (final MapEntry(key: name, value: (fingerprint, files))
          in cases.entries) {
        final report = _run(
          await writeCheckProject(
            extra: {..._covering('  - app/lib/ $fingerprint\n'), ...files},
          ),
        );

        expect(_suspects(report), hasLength(1), reason: name);
      }
    });

    test('reads a file that is not UTF-8 over its raw bytes', () async {
      const bytes = [0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF];
      final recorded = folderCodeFingerprint([
        (path: _login, fingerprint: _loginFingerprint),
        (path: 'app/lib/logo.png', fingerprint: fileCodeFingerprint(bytes)),
      ]);
      final project = await writeCheckProject(
        extra: _covering('  - app/lib/ $recorded\n'),
      );
      final logo = File('${project.path}/app/lib/logo.png')
        ..writeAsBytesSync(bytes);

      expect(_suspects(_run(project)), isEmpty);

      logo.writeAsBytesSync([...bytes.take(5), 0xFE]);

      expect(_suspects(_run(project)), hasLength(1));
    });

    test('that names a file reads it as a file', () async {
      final report = _run(
        await writeCheckProject(
          extra: _covering('  - $_login $_loginFingerprint\n'),
        ),
      );

      expect(_suspects(report), isEmpty);
    });

    test('reads its state the same in a draft doc and an approved '
        'one', () async {
      final covers = _covering('  - app/lib/ $_stale\n');
      final draft = {
        'docs/$loginArchitecture': covers['docs/$loginArchitecture']!
            .replaceFirst('covers:', 'draft: true\ncovers:'),
      };
      for (final extra in [covers, draft]) {
        final report = _run(await writeCheckProject(extra: extra));

        expect(_suspects(report), hasLength(1));
        expect(_suspects(report).single.keys['entry'], 'app/lib/');
        expect(_suspects(report).single.keys['path'], 'app/lib/');
        expect(_suspects(report).single.keys['recorded'], _stale);
        expect(_suspects(report).single.keys['fingerprint'], folderFingerprint);
      }
    });

    test('that records no fingerprint gives code_unconfirmed with the folder '
        'fingerprint', () async {
      final report = _run(
        await _project(
          _record(code: ['$_fr:$_pointer $_loginFingerprint']),
          extra: _covering('  - app/lib/\n'),
          unfingerprinted: {'docs/$loginArchitecture'},
        ),
      );
      final [finding] = _unconfirmed(report);

      expect(_suspects(report), isEmpty);
      expect(finding.path, loginArchitecture);
      expect(finding.waitsFor, WaitsFor.agent);
      expect(finding.message, 'app/lib/ records no fingerprint');
      expect(finding.keys, {
        'entry': 'app/lib/',
        'path': 'app/lib/',
        'fingerprint': folderFingerprint,
      });
      expect(finding.textLines.last, '    fingerprint $folderFingerprint');
    });

    test('that records no fingerprint and names a missing path gives '
        'covers_path_missing alone', () async {
      final report = _run(
        await _project(
          _record(code: ['$_fr:$_pointer $_loginFingerprint']),
          extra: _covering('  - app/lib/gone/\n'),
          unfingerprinted: {'docs/$loginArchitecture'},
        ),
      );

      expect(_unconfirmed(report), isEmpty);
      expect(_ofKind(report, FindingKind.coversPathMissing), hasLength(1));
    });

    test('of a target with no implemented entry yet and no fingerprint reads '
        'nothing', () async {
      final project = await writeCheckProject(
        extra: {
          ..._covering('  - app/lib/\n'),
          'docs/$_recordPath': _record(
            statuses: ['email_login:planned', '$_fr:planned'],
          ),
        },
        unstamped: {'docs/$_recordPath'},
        unfingerprinted: {'docs/$loginArchitecture'},
      );
      final (:context, :findings) = _checked(project, loginArchitecture);

      expect(findings, isEmpty);
      expect(context.codeFilesRead, 0);
    });

    test('of a target with no implemented entry yet reads nothing', () async {
      final project = await writeCheckProject(
        extra: {
          ..._covering('  - app/lib/ $_stale\n'),
          'docs/$_recordPath': _record(
            statuses: ['email_login:planned', '$_fr:planned'],
          ),
        },
        unstamped: {'docs/$_recordPath'},
      );
      final (:context, :findings) = _checked(project, loginArchitecture);

      expect(findings, isEmpty);
      expect(context.codeFilesRead, 0);
    });

    test(
      'over a folder with an unreadable file takes no state and states '
      "its warning, and the doc's other entries take theirs",
      skip: unreadablePathSkipReason(),
      () async {
        final project = await writeCheckProject(
          extra: {
            ..._covering('  - app/lib/locked/ $_stale\n  - $_login $_stale\n'),
            'app/lib/locked/x.dart': 'x\n',
          },
        );
        final path = '${project.path}/app/lib/locked/x.dart';
        Process.runSync('chmod', ['000', path]);
        addTearDown(() => Process.runSync('chmod', ['644', path]));

        final report = _run(project);

        expect([for (final f in _suspects(report)) f.keys['path']], [_login]);
        expect(report.warnings.where((w) => w.contains('locked/x.dart')), [
          'app/lib/locked/x.dart: $_unreadable',
          'app/lib/locked/x.dart: cannot read the file; doc names in it are not checked',
        ]);
      },
    );

    test(
      'over a folder that cannot be listed takes no state',
      skip: unreadablePathSkipReason(),
      () async {
        final project = await writeCheckProject(
          extra: {
            ..._covering('  - app/lib/ $_stale\n'),
            'app/lib/sealed/a.dart': 'a\n',
          },
        );
        final path = '${project.path}/app/lib/sealed';
        Process.runSync('chmod', ['000', path]);
        addTearDown(() => Process.runSync('chmod', ['755', path]));

        final report = _run(project);

        expect(_suspects(report), isEmpty);
        expect(
          report.warnings,
          contains(
            'app/lib/sealed: cannot list the folder; files under it are not '
            'checked for covers or fingerprints',
          ),
        );
      },
    );
  });

  test(
    'a folder that cannot be listed gives one warning, whether the covers '
    'scan, the fingerprint read, or both list it',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await writeCheckProject(
        extra: {
          ..._covering('  - app/lib/ $_stale\n  - app/lib/sealed/ $_stale\n'),
          'app/lib/sealed/a.dart': 'a\n',
        },
      );
      final path = '${project.path}/app/lib/sealed';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['755', path]));

      const warning =
          'app/lib/sealed: cannot list the folder; files under it are not '
          'checked for covers or fingerprints';

      final report = _run(project);

      expect(
        report.warnings.where(
          (w) =>
              w.startsWith('app/lib/sealed: cannot') &&
              !w.contains('doc names'),
        ),
        [warning],
      );
    },
  );

  test(
    'an unreadable file of a record entry gives the warning and no '
    'finding',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await _project(_record(code: ['$_fr:$_pointer $_stale']));
      final path = '${project.path}/$_login';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));

      final report = _run(project);

      expect(_suspects(report), isEmpty);
      expect(report.warnings, contains('$_login: $_unreadable'));
    },
  );

  test(
    'an unreadable file of a record entry with no fingerprint gives the '
    'warning and no finding',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await _project(_record(code: ['$_fr:$_pointer']));
      final path = '${project.path}/$_login';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));

      final report = _run(project);

      expect(_unconfirmed(report), isEmpty);
      expect(report.warnings, contains('$_login: $_unreadable'));
    },
  );

  test('each code target compares its own file, and a target limits the '
      'run to its own records', () async {
    final project = await writeTwinProject();
    final flutterText = File('${project.path}/flutter_ws/$_login')
        .readAsStringSync();
    final record = _record(
      code: ['$_fr:$_pointer ${_fingerprintOf(flutterText)}'],
    );
    for (final path in [_flutterRecord, _jasprRecord]) {
      File('${project.path}/docs/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(record);
    }

    final report = _run(project);

    expect([for (final f in _suspects(report)) f.path], [_jasprRecord]);
    expect(_suspects(_run(project, codeTarget: 'flutter')), isEmpty);
    expect(_suspects(_run(project, codeTarget: 'jaspr')), hasLength(1));
  });
}
