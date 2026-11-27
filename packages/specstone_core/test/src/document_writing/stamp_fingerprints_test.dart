// A matrix row matches a test name as one literal, so long names stay whole.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/models/file_fingerprint.dart';
import 'package:specstone_core/src/document_writing/stamp_fault.dart';
import 'package:specstone_core/src/document_writing/stamp_fingerprints.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/rulebook_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';
import '../../helpers/write_fixture.dart' hide loginFeature;

const _archAddress = 'charter:login';

/// The doc whose `covers` the tests stamp: a charter, which holds `covers`
/// and `tasks` both.
const _coversDoc = 'specs/topics/login.md';
const _recordAddress = 'implementation:login';
const _login = 'app/lib/login.dart';
const _old = '0123456789ab';
const _checkPassword = 'email_login/check_password';

final String _loginText = checkProjectFiles()[_login]!;

String _fileFingerprint(String text, String path) =>
    fileCodeFingerprint(utf8.encode(text), path: path);

String _folderFingerprint(Map<String, String> files) => folderCodeFingerprint([
  for (final MapEntry(:key, :value) in files.entries)
    FileFingerprint(path: key, fingerprint: _fileFingerprint(value, key)),
]);

/// Returns the record: one `implemented` story, one `planned` FR, and the
/// `implements` [code] lines.
String _record(List<String> code) =>
    "---\nstatuses:\n  - 'email_login:implemented'\n"
    "  - '$_checkPassword:planned'\nimplements:\n"
    '${[for (final line in code) "  - '$line'\n"].join()}'
    '---\n\n# Login implementation\n';

const _defaultCode = [
  'email_login:$_login:SignInPage',
  '$_checkPassword:$_login:checkPassword',
];

/// Returns the check fixture, its charter doc covering [covers] and its
/// record holding [code], both with no fingerprint but as written.
Future<Directory> _project({
  List<String> covers = const [_login, 'app/lib/ $_old'],
  List<String> code = _defaultCode,
  Map<String, String> extra = const {},
}) => writeCheckProject(
  extra: {
    'docs/$_coversDoc':
        '---\ncovers:\n${[for (final entry in covers) '  - $entry\n'].join()}---\n\n# Login rules\n',
    loginRecord: _record(code),
    ...extra,
  },
  unstamped: {loginRecord},
  unfingerprinted: {'docs/$_coversDoc', loginRecord},
);

ReadAnswer _stamp(
  Directory root,
  String address,
  List<String> args, {
  String? codeTarget,
}) => writeIn(
  root,
  (session) => answerStamp(
    session,
    StampRequest.parse(address, args, codeTarget: codeTarget),
  ),
);

StampFault _refused(Directory root, String address, List<String> args) {
  try {
    _stamp(root, address, args);
  } on StampFault catch (fault) {
    return fault;
  }
  fail('the stamp was not refused');
}

void main() {
  final loginFingerprint = _fileFingerprint(_loginText, _login);

  test('a stamp replies with one docs element naming the bare name, doc type, path, and stamped entries', () async {
    final root = await _project();

    final answer = _stamp(root, _archAddress, ['$_login=$loginFingerprint']);

    expect(answer.json.keys, {'docs'});
    expect(answer.json['docs']! as List, hasLength(1));
    expect(docOf(answer), {
      'name': 'login',
      'docType': 'charter',
      'path': _coversDoc,
      'stamped': [_login],
    });
  });

  test('a stamp of two entries ends each with its fingerprint in one write '
      'and leaves the draft mark alone', () async {
    final root = await _project();
    final before = readDoc(root, _coversDoc);
    final folder = _folderFingerprint({_login: _loginText});

    final answer = _stamp(root, _archAddress, [
      '$_login=$loginFingerprint',
      'app/lib/=$folder',
    ]);

    expect(
      readDoc(root, _coversDoc),
      before
          .replaceFirst('  - $_login\n', '  - $_login $loginFingerprint\n')
          .replaceFirst('  - app/lib/ $_old\n', '  - app/lib/ $folder\n'),
    );
    expect(answer.text, '$_archAddress: 2 stamped\n');
    expect(docOf(answer)['stamped'], [_login, 'app/lib/']);
    final session = openSession(root);
    final report = await runCheck(session);
    session.close();
    expect([
      for (final finding in report.findings)
        if (finding.path == _coversDoc &&
            (finding.kind == FindingKind.codeSuspect ||
                finding.kind == FindingKind.codeUnconfirmed))
          finding.textLine,
    ], isEmpty);
  });

  test(
    'a stamp naming no entry of the doc refuses stamp_entry_unknown',
    () async {
      final root = await _project();
      final before = readDoc(root, _coversDoc);

      final fault = _refused(root, _archAddress, ['app/lib/none.dart=$_old']);

      expect(fault.exitStatus, 64);
      expect(fault.refusals.single.code, WriteFaultCode.stampEntryUnknown);
      expect(
        fault.refusals.single.message,
        'no entry of $_archAddress reads app/lib/none.dart',
      );
      expect(readDoc(root, _coversDoc), before);
    },
  );

  test(
    'a fingerprint that differs from the code refuses stamp_stale',
    () async {
      final root = await _project();
      final before = readDoc(root, _coversDoc);

      final fault = _refused(root, _archAddress, ['$_login=$_old']);

      expect(fault.exitStatus, 75);
      expect(fault.refusals.single.code, WriteFaultCode.stampStale);
      expect(
        fault.refusals.single.message,
        '$_login changed after $_old; judge it again',
      );
      expect(fault.refusals.single.message, isNot(contains(loginFingerprint)));
      expect(readDoc(root, _coversDoc), before);
    },
  );

  test('a stamp on a planned record entry writes its fingerprint and keeps it planned', () async {
    final root = await _project();
    final before = readDoc(root, loginRecord);
    const entry = '$_checkPassword:$_login:checkPassword';

    _stamp(root, _recordAddress, ['$entry=$loginFingerprint']);

    expect(
      readDoc(root, loginRecord),
      before.replaceFirst("'$entry'", "'$entry $loginFingerprint'"),
    );
    expect(readDoc(root, loginRecord), contains("'$_checkPassword:planned'"));
  });

  group('an entry whose path, Symbol, or implements folder does not resolve refuses stamp_entry_unresolved', () {
    final cases = {
      'a covers path gone': (
        covers: ['app/lib/gone.dart'],
        code: _defaultCode,
        address: _archAddress,
        entry: 'app/lib/gone.dart',
        finding: 'covers_path_missing',
      ),
      'an implements path gone': (
        covers: [_login],
        code: ['email_login:app/lib/gone.dart:Thing'],
        address: _recordAddress,
        entry: 'email_login:app/lib/gone.dart:Thing',
        finding: 'implements_path_unresolved',
      ),
      'an implements folder': (
        covers: [_login],
        code: ['email_login:app/lib/'],
        address: _recordAddress,
        entry: 'email_login:app/lib/',
        finding: 'implements_path_unresolved',
      ),
      'an implements Symbol gone': (
        covers: [_login],
        code: ['email_login:$_login:Gone'],
        address: _recordAddress,
        entry: 'email_login:$_login:Gone',
        finding: 'implements_symbol_unresolved',
      ),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () async {
        final root = await _project(covers: value.covers, code: value.code);
        final docPath = value.address == _archAddress
            ? _coversDoc
            : loginRecord;
        final before = readDoc(root, docPath);

        final fault = _refused(root, value.address, ['${value.entry}=$_old']);

        expect(fault.exitStatus, 64);
        expect(fault.refusals.single.code, WriteFaultCode.stampEntryUnresolved);
        expect(
          fault.refusals.single.message,
          '${value.entry} does not resolve: ${value.finding}',
        );
        expect(readDoc(root, docPath), before);
      });
    }
  });

  // D9
  group('an entry the resolver refuses names the code check gives it', () {
    final cases = {
      'an implements entry holding a .. segment': (
        covers: [_login],
        code: ['email_login:app/lib/nope/../login.dart:SignInPage'],
        address: _recordAddress,
        entry: 'email_login:app/lib/nope/../login.dart:SignInPage',
        finding: 'implements_path_unresolved',
      ),
      'a covers entry outside the code root': (
        covers: ['../outside.dart'],
        code: _defaultCode,
        address: _archAddress,
        entry: '../outside.dart',
        finding: 'covers_path_outside',
      ),
      'a covers entry folding to the code root': (
        covers: ['app/lib/..'],
        code: _defaultCode,
        address: _archAddress,
        entry: 'app/lib/..',
        finding: 'covers_path_outside',
      ),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () async {
        final root = await _project(covers: value.covers, code: value.code);
        final docPath = value.address == _archAddress
            ? _coversDoc
            : loginRecord;
        final before = readDoc(root, docPath);

        final fault = _refused(root, value.address, ['${value.entry}=$_old']);

        expect(fault.exitStatus, 64);
        expect(fault.refusals.single.code, WriteFaultCode.stampEntryUnresolved);
        expect(
          fault.refusals.single.message,
          '${value.entry} does not resolve: ${value.finding}',
        );
        expect(readDoc(root, docPath), before);
      });
    }
  });

  // D10
  test(
    'an implements entry whose Symbol after : is empty refuses with the code '
    'check reports for it',
    () async {
      const entry = 'email_login:$_login:';
      final root = await _project(code: [entry]);
      final session = openSession(root);
      final report = await runCheck(session);
      session.close();
      final checkCodes = {
        for (final finding in report.findings)
          if (finding.path == loginRecord &&
              finding.keys['entry'] == '$_login:' &&
              finding.kind != FindingKind.codeUnconfirmed)
            finding.kind.wire,
      };
      final before = readDoc(root, loginRecord);

      final fault = _refused(root, _recordAddress, ['$entry=$_old']);

      expect(checkCodes, {'implements_symbol_unresolved'});
      expect(fault.refusals.single.code, WriteFaultCode.stampEntryUnresolved);
      expect(
        fault.refusals.single.message,
        '$entry does not resolve: implements_symbol_unresolved',
      );
      expect(readDoc(root, loginRecord), before);
    },
  );

  test(
    'a covers entry differing from the disk name by letter case alone refuses '
    'with the code check reports for it',
    () async {
      const wrongCase = 'app/lib/Login.dart';
      final root = await _project(covers: [wrongCase]);
      final session = openSession(root);
      final report = await runCheck(session);
      session.close();
      final checkCodes = {
        for (final finding in report.findings)
          if (finding.path == _coversDoc &&
              finding.kind == FindingKind.coversPathMissing)
            finding.kind.wire,
      };

      final fault = _refused(root, _archAddress, ['$wrongCase=$_old']);

      expect(checkCodes, {'covers_path_missing'});
      expect(fault.refusals.single.code, WriteFaultCode.stampEntryUnresolved);
      expect(
        fault.refusals.single.message,
        '$wrongCase does not resolve: ${checkCodes.single}',
      );
    },
  );

  test(
    'a covers entry in NFC over a file written under its NFD name stamps',
    () async {
      const nfd = 'app/lib/cafe\u{301}.dart';
      const nfc = 'app/lib/caf\u{e9}.dart';
      const text = 'class Cafe {}\n';
      final root = await _project(covers: [nfc], extra: {nfd: text});

      final answer = _stamp(root, _archAddress, [
        '$nfc=${_fileFingerprint(text, nfd)}',
      ]);

      expect(docOf(answer)['stamped'], [nfc]);
    },
  );

  test('an empty covers entry refuses stamp_entry_unresolved naming '
      'covers_entry_empty, in each empty form', () async {
    // Each pair is the entry as the doc writes it and as `--stamp` names it.
    const forms = [
      ("''", ''),
      ('.', '.'),
      ('./', './'),
      ('/', '/'),
      ('./.', './.'),
    ];
    for (final (written, named) in forms) {
      final root = await _project(covers: [written]);
      final before = readDoc(root, _coversDoc);

      final fault = _refused(root, _archAddress, ['$named=$_old']);

      expect(fault.exitStatus, 64, reason: written);
      expect(
        fault.refusals.single.code,
        WriteFaultCode.stampEntryUnresolved,
        reason: written,
      );
      expect(
        fault.refusals.single.message,
        '$named does not resolve: covers_entry_empty',
        reason: written,
      );
      expect(readDoc(root, _coversDoc), before, reason: written);
    }
  });

  test(
    'an entry whose code cannot be read refuses stamp_entry_unresolved as file_unreadable',
    skip: unreadablePathSkipReason(),
    () async {
      final root = await _project();
      final path = '${root.path}/$_login';
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['644', path]));
      final before = readDoc(root, _coversDoc);

      final fault = _refused(root, _archAddress, ['$_login=$_old']);

      expect(fault.exitStatus, 64);
      expect(fault.refusals.single.code, WriteFaultCode.stampEntryUnresolved);
      expect(
        fault.refusals.single.message,
        '$_login does not resolve: file_unreadable',
      );
      expect(readDoc(root, _coversDoc), before);
    },
  );

  test(
    'several refused stamps write nothing and list each entry with its code',
    () async {
      final root = await _project();
      final before = readDoc(root, _coversDoc);

      final fault = _refused(root, _archAddress, [
        'app/lib/none.dart=$_old',
        'app/lib/=$_old',
        '$_login=$loginFingerprint',
      ]);

      expect(fault.exitStatus, 64);
      expect(fault.toJson()['error'], {
        'code': 'stamp_entry_unknown',
        'message': 'no entry of $_archAddress reads app/lib/none.dart',
        'refusals': [
          {'entry': 'app/lib/none.dart', 'code': 'stamp_entry_unknown'},
          {'entry': 'app/lib/', 'code': 'stamp_stale'},
        ],
      });
      expect(readDoc(root, _coversDoc), before);
    },
  );

  test('an entry holding = and : splits on its last =', () async {
    const path = 'app/lib/a=b.dart';
    const text = 'class Thing {}\n';
    const entry = 'email_login:$path:Thing';
    final root = await _project(code: const [entry], extra: const {path: text});
    final fingerprint = _fileFingerprint(text, path);

    _stamp(root, _recordAddress, ['$entry=$fingerprint']);

    expect(readDoc(root, loginRecord), contains("'$entry $fingerprint'"));
  });

  test('a folder stamp takes the fingerprint check reads, nested roots left '
      'out', () async {
    final project = await writeTwinProject(
      extra: {
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n'
            '  flutter:\n    code_root: flutter_ws\n'
            '  jaspr:\n    code_root: flutter_ws/app/lib/jaspr\n',
        'flutter_ws/app/lib/extra.dart': 'int extra;\n',
        'flutter_ws/app/lib/jaspr/app/lib/login.dart': 'int nested;\n',
      },
      unfingerprinted: {flutterRecord},
    );
    final flutterLogin = File('${project.path}/flutter_ws/app/lib/login.dart')
        .readAsStringSync();
    final folder = _folderFingerprint({
      'app/lib/extra.dart': 'int extra;\n',
      'app/lib/login.dart': flutterLogin,
    });

    _stamp(project, _recordAddress, [
      'app/lib/=$folder',
    ], codeTarget: 'flutter');

    expect(readDoc(project, flutterRecord), contains('- app/lib/ $folder'));
  });

  test(
    'a shared doc of a two-target project refuses its code-root entry '
    'as shared_doc_code_path and still stamps a root: project entry',
    () async {
      const tool = 'tools/run.sh';
      const toolText = 'echo run\n';
      const entry = 'flutter_ws/app/lib/login.dart';
      final project = await writeCheckProject(
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_ws\n'
              '  jaspr:\n    code_root: jaspr_ws\n',
          charterLayerFile: charterLayer
              .replaceFirst('per_target: true', 'per_target: false')
              .replaceFirst(
                'fields:\n',
                'fields:\n  - id: tools\n    type: output_ref\n    list: true\n'
                    '    pointer: prefix\n    root: project\n',
              ),
          'docs/$_coversDoc':
              '---\ncovers:\n  - $entry\ntools:\n  - tools/\n---\n\n'
              '# Login rules\n',
          entry: _loginText,
          tool: toolText,
        },
        without: {_login, loginRecord},
        unfingerprinted: {'docs/$_coversDoc'},
      );
      final before = readDoc(project, _coversDoc);
      final fingerprint = _folderFingerprint({tool: toolText});

      final fault = _refused(project, _archAddress, ['$entry=$_old']);

      expect(fault.refusals.single.code, WriteFaultCode.stampEntryUnresolved);
      expect(
        fault.refusals.single.message,
        '$entry does not resolve: shared_doc_code_path',
      );
      expect(readDoc(project, _coversDoc), before);
      _stamp(project, _archAddress, ['tools/=$fingerprint']);
      expect(readDoc(project, _coversDoc), contains('  - tools/ $fingerprint'));
    },
  );

  test('a stamp of the same entry twice counts and lists it once', () async {
    final root = await _project();

    final answer = _stamp(root, _archAddress, [
      '$_login=$loginFingerprint',
      '$_login=$loginFingerprint',
    ]);

    expect(answer.text, '$_archAddress: 1 stamped\n');
    expect(docOf(answer)['stamped'], [_login]);
  });

  test('a stamp with no --stamp argument is argument_missing', () {
    expect(
      () => StampRequest.parse(_archAddress, const []),
      throwsA(
        isA<IndexFault>().having(
          (fault) => fault.code,
          'code',
          IndexFaultCode.argumentMissing,
        ),
      ),
    );
  });

  test('a root: project entry resolves from the project root', () async {
    const tool = 'tools/run.sh';
    const toolText = 'echo run\n';
    final root = await writeCheckProject(
      extra: {
        '.specstone/config.yaml': '${shippedPinsConfig()}code_root: code\n',
        'code/$_login': _loginText,
        '.specstone/templates/toolset.yaml':
            'id: toolset\ndescription: Tools.\npath: ops/{slug}.md\n'
            'fields:\n  - id: covers\n    type: output_ref\n'
            '    list: true\n    pointer: prefix\n    root: project\n',
        'docs/ops/build.md': '---\ncovers:\n  - tools/\n---\n\n# Build\n',
        tool: toolText,
      },
      without: {_login, loginRecord},
      unfingerprinted: {'docs/ops/build.md'},
    );
    final fingerprint = _folderFingerprint({tool: toolText});

    final answer = _stamp(root, 'toolset:build', ['tools/=$fingerprint']);

    expect(answer.text, 'toolset:build: 1 stamped\n');
    expect(readDoc(root, 'ops/build.md'), contains('- tools/ $fingerprint'));
  });

  test('a --stamp argument with no = or a fingerprint that is not 12 '
      'lowercase hex characters is argument_invalid', () {
    for (final arg in ['app/lib/login.dart', 'a=0123456789AB', 'a=abc', 'a=']) {
      expect(
        () => StampRequest.parse(_archAddress, [arg]),
        throwsA(
          isA<IndexFault>().having(
            (fault) => fault.code,
            'code',
            IndexFaultCode.argumentInvalid,
          ),
        ),
        reason: arg,
      );
    }
  });
}
