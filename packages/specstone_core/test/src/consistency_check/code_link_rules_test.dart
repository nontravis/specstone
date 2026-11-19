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
import 'package:specstone_core/src/consistency_check/models/file_fingerprint.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/marketing.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_doc_fixture.dart';
import '../../helpers/target_fixture.dart';
import '../../helpers/temp_tree.dart';

const _recordPath = '.specstone/records/f01_login/IMPLEMENTATION.md';
const _flutterRecord = '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
const _jasprRecord = '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md';
const _fr = 'email_login/check_password';
const _implemented = '$_fr:implemented';
const _login = 'app/lib/login.dart';
const _pointer = '$_login:checkPassword';
const _stale = '0123456789ab';
const _unreadable =
    'cannot read the file; implements Symbols in it are not checked';
const _unreadableLinks =
    'cannot read the file; the code links that reach it are not checked';

String _fingerprintOf(String text, String path) =>
    fileCodeFingerprint(utf8.encode(text), path: path);

/// Returns the fingerprint of a folder that lists [files], by path and text.
String _folderFingerprintOf(Map<String, String> files) =>
    folderCodeFingerprint([
      for (final MapEntry(:key, :value) in files.entries)
        FileFingerprint(path: key, fingerprint: _fingerprintOf(value, key)),
    ]);

final String _loginText = checkProjectFiles()[_login]!;
final String _loginFingerprint = _fingerprintOf(_loginText, _login);

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
  extra: {_recordPath: record, ...extra},
  without: without,
  unstamped: {_recordPath},
  unfingerprinted: {_recordPath, ...unfingerprinted},
);

/// The check fixture with its code under `code/` and no record, plus the
/// skill doc covering [covers] as written and its skill file.
Future<Directory> _skillProject(List<String> covers) => writeCheckProject(
  extra: {
    '.specstone/config.yaml': '${skillPinsConfig()}code_root: code\n',
    'code/$_login': _loginText,
    ...skillDocFile(covers),
    skillFile: skillText,
  },
  without: {_login, _recordPath},
  unfingerprinted: {'docs/$skillDoc'},
);

/// Returns the architecture doc of the fixture covering [covers].
Map<String, String> _covering(String covers) =>
    doc(loginArchitecture, '  - app/lib/\n', covers);

const _post = 'posts/launch.md';
const _postText = 'Launch day.\nSee the site.\n';

/// Returns the project of a `campaign` doc covering [covers], with no record
/// and the post file, pinning `prd-core` and `marketing`.
Future<Directory> _campaignProject(
  List<String> covers, {
  Set<String> unfingerprinted = const {},
}) => writeCheckProject(
  extra: {
    '.specstone/config.yaml': shippedPinsConfig(['prd-core', 'marketing']),
    'docs/$campaignDocPath': campaignDocText(covers),
    _post: _postText,
  },
  without: {_recordPath},
  unfingerprinted: unfingerprinted,
);

Future<CheckReport> _run(Directory project, {String? codeTarget}) async {
  final session = openSession(project);
  try {
    return await runCheck(session, codeTarget: codeTarget);
  } finally {
    session.close();
  }
}

List<Finding> _suspects(CheckReport report) =>
    _ofKind(report, FindingKind.codeSuspect);

List<Finding> _unconfirmed(CheckReport report) =>
    _ofKind(report, FindingKind.codeUnconfirmed);

/// Returns the `code_suspect` findings of the record in [project].
Future<List<Finding>> _recordSuspects(Directory project) async => [
  for (final f in _suspects(await _run(project)))
    if (f.path == _recordPath) f,
];

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
      final report = await _run(
        await _project(_record(code: ['$_fr:$_pointer $_loginFingerprint'])),
      );

      expect(_suspects(report), isEmpty);
    });

    test('that records no fingerprint gives code_unconfirmed with the current '
        'fingerprint on its own key', () async {
      final record = _record(code: ['$_fr:$_pointer']);

      final report = await _run(await _project(record));
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
        final report = await _run(
          await _project(_record(code: ['$_fr:$_pointer $_loginFingerprint'])),
        );

        expect(_unconfirmed(report), isEmpty);
        expect(_suspects(report), isEmpty);
      },
    );

    test('whose file gained a comment line and a blank line gives no '
        'code_suspect', () async {
      final project = await _project(
        _record(code: ['$_fr:$_pointer $_loginFingerprint']),
      );
      File(
        '${project.path}/$_login',
      ).writeAsStringSync('// added note\n\n$_loginText\n  // trailing note\n');

      final report = await _run(project);

      expect(_suspects(report), isEmpty);
      expect(_unconfirmed(report), isEmpty);
    });

    test(
      'whose file gained an end-of-line comment gives code_suspect',
      () async {
        final project = await _project(
          _record(code: ['$_fr:$_pointer $_loginFingerprint']),
        );
        final lines = _loginText.split('\n')
          ..[0] = '${_loginText.split('\n')[0]} // x';
        File('${project.path}/$_login').writeAsStringSync(lines.join('\n'));

        expect([
          for (final f in _suspects(await _run(project))) f.path,
        ], contains(_recordPath));
      },
    );

    test('that records no fingerprint waits for the agent in a draft record '
        'and an approved one', () async {
      for (final isDraft in [true, false]) {
        final [finding] = _unconfirmed(
          await _run(
            await _project(_record(code: ['$_fr:$_pointer'], isDraft: isDraft)),
          ),
        );

        expect(finding.waitsFor, WaitsFor.agent, reason: 'draft: $isDraft');
      }
    });

    test('that records no fingerprint and whose file is gone gives '
        'implements_path_unresolved alone', () async {
      final report = await _run(
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
      final current = _fingerprintOf(changed, _login);

      final [finding] = _suspects(await _run(project));

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

      expect(_suspects(await _run(project)), isEmpty);
    });

    test('reads its state the same in a draft record and an approved '
        'one', () async {
      for (final isDraft in [true, false]) {
        final report = await _run(
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
      final report = await _run(
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
        for (final f in (await _run(project)).findings)
          if (f.kind == FindingKind.implementsPathUnresolved) f,
      ], hasLength(3));
    });

    test('a Symbol entry or a covers entry ending in an 11- or 13-character'
        ' token is reported, never clean', () async {
      const elevenHex = '9a1c03be55d';
      const thirteenHex = '9a1c03be55d22';
      final record = _record(
        code: ['$_fr:$_pointer $elevenHex', '$_fr:$_pointer $thirteenHex'],
      );
      final project = await _project(
        record,
        extra: _covering(
          '  - app/lib/ $elevenHex\n  - app/lib/ $thirteenHex\n',
        ),
        unfingerprinted: {'docs/$loginArchitecture'},
      );

      final report = await _run(project);

      expect(
        _ofKind(
          report,
          FindingKind.implementsSymbolUnresolved,
        ).map((f) => f.line),
        [_lineOf(record, elevenHex), _lineOf(record, thirteenHex)],
      );
      expect(
        _ofKind(report, FindingKind.coversPathMissing).map((f) => f.path),
        [loginArchitecture, loginArchitecture],
      );
      expect(_suspects(report), isEmpty);
    });

    test('whose file changed a line inside a block comment gives'
        ' code_suspect', () async {
      const before = '/*\n  the old note\n*/\nint a;\n';
      final project = await _project(
        _record(code: ['$_fr:$_login ${_fingerprintOf(before, _login)}']),
        extra: {_login: before},
      );
      expect(await _recordSuspects(project), isEmpty);

      File(
        '${project.path}/$_login',
      ).writeAsStringSync(before.replaceFirst('the old note', 'the new note'));

      expect(await _recordSuspects(project), hasLength(1));
    });

    test('whose file changed a line of a string literal that opens with //'
        ' gives no code_suspect, and any other line of it one', () async {
      const before = "const s = '''\n// first\nkept\n''';\n";
      final project = await _project(
        _record(code: ['$_fr:$_login ${_fingerprintOf(before, _login)}']),
        extra: {_login: before},
      );
      final file = File('${project.path}/$_login')
        ..writeAsStringSync(before.replaceFirst('// first', '// second'));
      expect(await _recordSuspects(project), isEmpty);

      file.writeAsStringSync(before.replaceFirst('kept', 'changed'));

      expect(await _recordSuspects(project), hasLength(1));
    });

    test('written with a ./ prefix shares its one read with the Symbol '
        'rule', () async {
      final project = await _project(
        _record(
          code: [
            '$_fr:./$_pointer $_loginFingerprint',
            '$_fr:$_login:SignInPage $_loginFingerprint',
          ],
        ),
      );
      final session = openSession(project);
      addTearDown(session.close);
      final context = CheckContext(session);
      final record = session.index.at(_recordPath)!;

      checkImplements(context, record).toList();
      File('${project.path}/$_login').writeAsStringSync('class SignInPage {}');
      final findings = checkCodeLinks(
        context,
        ImplementedWork(context, context.targets),
        record,
      ).toList();

      expect(findings, isEmpty);
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
      final report = await _run(
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
      final report = await _run(
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
      final report = await _run(
        await writeCheckProject(
          extra: _covering('  - app/lib/ $folderFingerprint\n'),
        ),
      );

      expect(_suspects(report), isEmpty);
    });

    test('whose folder file gained a comment-only edit gives no '
        'code_suspect, an end-of-line comment edit one', () async {
      final project = await writeCheckProject(
        extra: _covering('  - app/lib/ $folderFingerprint\n'),
      );
      final file = File('${project.path}/$_login')
        ..writeAsStringSync('// note\n\n$_loginText// more\n');
      expect(_suspects(await _run(project)), isEmpty);

      file.writeAsStringSync('${_loginText.trimRight()} // x\n');
      expect(_suspects(await _run(project)), isNotEmpty);
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
        final report = await _run(
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
        FileFingerprint(path: _login, fingerprint: _loginFingerprint),
        FileFingerprint(
          path: 'app/lib/logo.png',
          fingerprint: fileCodeFingerprint(bytes, path: 'app/lib/logo.png'),
        ),
      ]);
      final project = await writeCheckProject(
        extra: _covering('  - app/lib/ $recorded\n'),
      );
      final logo = File('${project.path}/app/lib/logo.png')
        ..writeAsBytesSync(bytes);

      expect(_suspects(await _run(project)), isEmpty);

      logo.writeAsBytesSync([...bytes.take(5), 0xFE]);

      expect(_suspects(await _run(project)), hasLength(1));
    });

    test('that names a file reads it as a file', () async {
      final report = await _run(
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
        final report = await _run(await writeCheckProject(extra: extra));

        expect(_suspects(report), hasLength(1));
        expect(_suspects(report).single.keys['entry'], 'app/lib/');
        expect(_suspects(report).single.keys['path'], 'app/lib/');
        expect(_suspects(report).single.keys['recorded'], _stale);
        expect(_suspects(report).single.keys['fingerprint'], folderFingerprint);
      }
    });

    test('that records no fingerprint gives code_unconfirmed with the folder '
        'fingerprint', () async {
      final report = await _run(
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
      final report = await _run(
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
          _recordPath: _record(
            statuses: ['email_login:planned', '$_fr:planned'],
          ),
        },
        unstamped: {_recordPath},
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
          _recordPath: _record(
            statuses: ['email_login:planned', '$_fr:planned'],
          ),
        },
        unstamped: {_recordPath},
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

        final report = await _run(project);

        expect([for (final f in _suspects(report)) f.keys['path']], [_login]);
        expect(report.warnings.where((w) => w.contains('locked/x.dart')), [
          'app/lib/locked/x.dart: $_unreadableLinks',
          'app/lib/locked/x.dart: cannot read the file; doc names in it are not checked',
        ]);
      },
    );
  });

  group('a campaign covers entry', () {
    final postFingerprint = _fingerprintOf(_postText, _post);

    test('whose file changed after its fingerprint gives code_suspect with '
        'its path as written, in a project with no record', () async {
      final report = await _run(await _campaignProject(['$_post $_stale']));
      final [finding] = _suspects(report);

      expect(finding.path, campaignDocPath);
      expect(finding.keys, {
        'entry': _post,
        'path': _post,
        'recorded': _stale,
        'fingerprint': postFingerprint,
      });
    });

    test('a post that records no fingerprint gives code_unconfirmed with its '
        'own, in a project with no record', () async {
      final report = await _run(
        await _campaignProject(
          [_post],
          unfingerprinted: {'docs/$campaignDocPath'},
        ),
      );
      final [finding] = _unconfirmed(report);

      expect(finding.path, campaignDocPath);
      expect(finding.keys, {
        'entry': _post,
        'path': _post,
        'fingerprint': postFingerprint,
      });
    });

    test('whose file was checked out with CRLF line ends gives no '
        'finding', () async {
      final project = await _campaignProject(['$_post $postFingerprint']);
      File('${project.path}/$_post')
          .writeAsStringSync(_postText.replaceAll('\n', '\r\n'));

      final report = await _run(project);

      expect(_suspects(report), isEmpty);
      expect(_unconfirmed(report), isEmpty);
    });
  });

  group('a root: project covers entry', () {
    final skillFingerprint = _fingerprintOf(skillText, skillFile);

    test('whose skill file changed after its fingerprint gives code_suspect '
        'with its path from the project root, in a project with no '
        'record', () async {
      final report = await _run(await _skillProject(['$skillFile $_stale']));
      final [finding] = _suspects(report);

      expect(finding.path, skillDoc);
      expect(finding.keys, {
        'entry': skillFile,
        'path': skillFile,
        'recorded': _stale,
        'fingerprint': skillFingerprint,
      });
    });

    test('that records no fingerprint gives code_unconfirmed in a project '
        'with no record', () async {
      final report = await _run(await _skillProject([skillFile]));
      final [finding] = _unconfirmed(report);

      expect(finding.path, skillDoc);
      expect(finding.keys, {
        'entry': skillFile,
        'path': skillFile,
        'fingerprint': skillFingerprint,
      });
    });

    test('is read in a run one code target limits', () async {
      final project = await writeTwinProject(
        extra: {
          '.specstone/config.yaml':
              '${skillPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_ws\n'
              '  jaspr:\n    code_root: jaspr_ws\n',
          ...skillDocFile(['$skillFile $_stale']),
          skillFile: skillText,
        },
      );

      for (final target in ['flutter', 'jaspr']) {
        final report = await _run(project, codeTarget: target);
        expect(
          [for (final f in _suspects(report)) '${f.path}: ${f.keys['path']}'],
          ['$skillDoc: $skillFile'],
          reason: target,
        );
      }
    });

    test('of a project doc type naming a folder hashes each file by its path '
        'from the project root', () async {
      const tool = 'tools/run.sh';
      const toolText = 'echo run\n';
      final project = await writeCheckProject(
        extra: {
          '.specstone/config.yaml': '${shippedPinsConfig()}code_root: code\n',
          'code/$_login': _loginText,
          '.specstone/templates/toolset.yaml':
              'id: toolset\ndescription: Tools.\npath: ops/{slug}.md\n'
              'fields:\n  - id: covers\n    type: output_ref\n'
              '    list: true\n    pointer: prefix\n    root: project\n',
          'docs/ops/build.md':
              '---\ncovers:\n  - tools/ $_stale\n---\n\n# Build\n',
          tool: toolText,
        },
        without: {_login},
      );

      final [finding] = _suspects(await _run(project));

      expect(
        (finding.path, finding.keys['entry'], finding.keys['fingerprint']),
        ('ops/build.md', 'tools/', _folderFingerprintOf({tool: toolText})),
      );
    });

    test('of a project doc type with an output_ref field and no root hashes '
        'each file by its path from the code root', () async {
      const tool = 'tools/run.sh';
      const toolText = 'echo run\n';
      final project = await writeCheckProject(
        extra: {
          '.specstone/config.yaml': '${shippedPinsConfig()}code_root: code\n',
          'code/$tool': toolText,
          '.specstone/templates/toolset.yaml':
              'id: toolset\ndescription: Tools.\npath: ops/{slug}.md\n'
              'fields:\n  - id: covers\n    type: output_ref\n'
              '    list: true\n    pointer: prefix\n',
          'docs/ops/build.md':
              '---\ncovers:\n  - tools/ $_stale\n---\n\n# Build\n',
        },
        without: {_login},
      );

      final [finding] = _suspects(await _run(project));

      expect(
        (finding.path, finding.keys['entry'], finding.keys['fingerprint']),
        ('ops/build.md', 'tools/', _folderFingerprintOf({tool: toolText})),
      );
    });

    test(
      'whose file cannot be read takes no state and states the warning '
      'with its path from the project root',
      skip: unreadablePathSkipReason(),
      () async {
        final project = await _skillProject(['$skillFile $_stale']);
        final path = '${project.path}/$skillFile';
        Process.runSync('chmod', ['000', path]);
        addTearDown(() => Process.runSync('chmod', ['644', path]));

        final report = await _run(project);

        expect(_suspects(report), isEmpty);
        expect(report.warnings, contains('$skillFile: $_unreadableLinks'));
      },
    );
  });

  test(
    'a folder that cannot be listed takes no state and gives one warning, '
    'whether the covers scan, the fingerprint read, or both list it',
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

      final report = await _run(project);

      expect(_suspects(report), isEmpty);
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

      final report = await _run(project);

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

      final report = await _run(project);

      expect(_unconfirmed(report), isEmpty);
      expect(report.warnings, contains('$_login: $_unreadable'));
    },
  );

  test(
    'an unreadable file that a covers entry and a record entry with a Symbol '
    'both reach gives the Symbols warning once',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await _project(
        _record(code: ['$_fr:$_pointer $_stale']),
        extra: _covering('  - app/lib/ $_stale\n'),
      );
      final path = '${project.path}/$_login';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));

      final report = await _run(project);

      expect(report.warnings.where((w) => w.startsWith('$_login: cannot')), [
        '$_login: $_unreadable',
        '$_login: cannot read the file; doc names in it are not checked',
      ]);
    },
  );

  test(
    'an unreadable file a record entry with no Symbol names gives the '
    'Symbols warning',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await _project(
        _record(code: ['$_fr:$_login $_stale']),
        extra: _covering(''),
      );
      final path = '${project.path}/$_login';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));

      final report = await _run(project);

      expect(report.warnings.where((w) => w.startsWith('$_login: cannot')), [
        '$_login: $_unreadable',
        '$_login: cannot read the file; doc names in it are not checked',
      ]);
    },
  );

  test(
    'an unreadable file only a covers entry reaches gives the code-link '
    'warning',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await _project(
        _record(),
        extra: _covering('  - $_login $_stale\n'),
      );
      final path = '${project.path}/$_login';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));

      final report = await _run(project);

      expect(report.warnings.where((w) => w.startsWith('$_login: cannot')), [
        '$_login: $_unreadableLinks',
        '$_login: cannot read the file; doc names in it are not checked',
      ]);
    },
  );

  test(
    'an unreadable file a code-root and a root: project covers entry both '
    'reach, the code root at the project root, gives the warning once',
    skip: unreadablePathSkipReason(),
    () async {
      final project = await _project(
        _record(),
        extra: {
          '.specstone/config.yaml': skillPinsConfig(),
          ..._covering('  - $_login $_stale\n'),
          ...skillDocFile(['$_login $_stale']),
        },
      );
      final path = '${project.path}/$_login';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));

      final report = await _run(project);

      expect(report.warnings.where((w) => w.startsWith('$_login: cannot')), [
        '$_login: $_unreadableLinks',
        '$_login: cannot read the file; doc names in it are not checked',
      ]);
    },
  );

  group('CheckContext.codeBytesOf with a folder at the file path', () {
    Future<(CheckContext, CodeTarget)> contextWithFolders() async {
      final session = openSession(await writeTwinProject());
      addTearDown(session.close);
      for (final root in ['flutter_ws', 'jaspr_ws']) {
        Directory.fromUri(
          session.project.projectRoot.uri.resolve('$root/app/sealed.dart/'),
        ).createSync(recursive: true);
      }
      final context = CheckContext(session);
      return (context, context.targets.first);
    }

    test('states the code-link warning once per target and file, the target '
        'first', () async {
      final (context, flutter) = await contextWithFolders();
      final jaspr = context.targets.last;

      expect(
        context.codeBytesOf(
          flutter,
          'app/sealed.dart',
          reason: CodeRead.codeLink,
        ),
        isNull,
      );
      expect(
        context.codeBytesOf(
          flutter,
          './app/sealed.dart',
          reason: CodeRead.codeLink,
        ),
        isNull,
      );
      expect(
        context.codeBytesOf(
          jaspr,
          'app/sealed.dart',
          reason: CodeRead.codeLink,
        ),
        isNull,
      );

      expect(context.unstatedWarnings, [
        'flutter: app/sealed.dart: $_unreadableLinks',
        'jaspr: app/sealed.dart: $_unreadableLinks',
      ]);
    });

    test('lets the Symbols reason win in either read order', () async {
      final (context, flutter) = await contextWithFolders();
      final jaspr = context.targets.last;

      context
        ..codeBytesOf(flutter, 'app/sealed.dart', reason: CodeRead.codeLink)
        ..codeBytesOf(flutter, 'app/sealed.dart', reason: CodeRead.symbols)
        ..codeBytesOf(jaspr, 'app/sealed.dart', reason: CodeRead.symbols)
        ..codeBytesOf(jaspr, 'app/sealed.dart', reason: CodeRead.codeLink);

      expect(context.unstatedWarnings, [
        'flutter: app/sealed.dart: $_unreadable',
        'jaspr: app/sealed.dart: $_unreadable',
      ]);
    });
  });

  test('each code target compares its own file, and a target limits the '
      'run to its own records', () async {
    final project = await writeTwinProject();
    final flutterText = File('${project.path}/flutter_ws/$_login')
        .readAsStringSync();
    final record = _record(
      code: ['$_fr:$_pointer ${_fingerprintOf(flutterText, _login)}'],
    );
    for (final path in [_flutterRecord, _jasprRecord]) {
      File('${project.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(record);
    }

    final report = await _run(project);

    expect([for (final f in _suspects(report)) f.path], [_jasprRecord]);
    expect(_suspects(await _run(project, codeTarget: 'flutter')), isEmpty);
    expect(_suspects(await _run(project, codeTarget: 'jaspr')), hasLength(1));
  });

  group('currentCodeFingerprint', () {
    test('hashes each file by the given file hash, the current rule by '
        'default', () async {
      final root = await writeTree({
        'lib/a.dart': '// note\nint a;\n',
        'lib/b.dart': 'int b;\n',
      });
      List<int>? bytesOf(String file) =>
          File('${root.path}/$file').readAsBytesSync();
      String? fingerprint({String Function(List<int>, String)? fileHash}) =>
          fileHash == null
          ? currentCodeFingerprint(
              'lib/',
              codeRoot: root,
              nestedRoots: const [],
              bytesOf: bytesOf,
              onUnlistable: (_) {},
            )
          : currentCodeFingerprint(
              'lib/',
              codeRoot: root,
              nestedRoots: const [],
              bytesOf: bytesOf,
              onUnlistable: (_) {},
              fileHash: fileHash,
            );
      String of(String text, String path) =>
          fileCodeFingerprint(utf8.encode(text), path: path);
      String legacyOf(String text) =>
          legacyFileCodeFingerprint(utf8.encode(text));

      expect(
        fingerprint(),
        folderCodeFingerprint([
          FileFingerprint(
            path: 'lib/a.dart',
            fingerprint: of('int a;\n', 'lib/a.dart'),
          ),
          FileFingerprint(
            path: 'lib/b.dart',
            fingerprint: of('int b;\n', 'lib/b.dart'),
          ),
        ]),
      );
      expect(
        fingerprint(fileHash: (bytes, _) => legacyFileCodeFingerprint(bytes)),
        folderCodeFingerprint([
          FileFingerprint(
            path: 'lib/a.dart',
            fingerprint: legacyOf('// note\nint a;\n'),
          ),
          FileFingerprint(
            path: 'lib/b.dart',
            fingerprint: legacyOf('int b;\n'),
          ),
        ]),
      );
    });
  });
}
