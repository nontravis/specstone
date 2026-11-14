import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/code_stamp_step.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';

const _login = 'app/lib/login.dart';
const _stale = '0123456789ab';
const _from = '1.6.0';
const _step = 'stamp_code_fingerprints';
const _flutterRecord = 'specs/flutter/f01_login/IMPLEMENTATION.md';
const _jasprRecord = 'specs/jaspr/f01_login/IMPLEMENTATION.md';

/// Every doc whose code links the fixture writes, left with none recorded.
const _linkedDocs = {'docs/$loginRecord', 'docs/$loginArchitecture'};

String _fingerprintOf(String text) => fileCodeFingerprint(utf8.encode(text));

final String _loginText = checkProjectFiles()[_login]!;
final String _loginFingerprint = _fingerprintOf(_loginText);
final String _appLibFingerprint = folderCodeFingerprint([
  (path: _login, fingerprint: _loginFingerprint),
]);

/// Returns a record of [statuses] and [code], one quoted line each, approved
/// by no hash, so only its code links change.
String _record({
  List<String> statuses = const ['email_login:implemented'],
  List<String> code = const [],
  List<String> tests = const [],
}) {
  String list(String key, List<String> lines) => lines.isEmpty
      ? ''
      : "$key:\n${[for (final l in lines) "  - '$l'\n"].join()}";
  return '---\n${list('statuses', statuses)}${list('implements', code)}'
      '${list('tests', tests)}---\n\n# Login implementation\n';
}

/// The check fixture with every code link unrecorded and [extra] on top.
Future<Directory> _project({
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) => writeCheckProject(
  extra: extra,
  without: without,
  unfingerprinted: _linkedDocs,
);

/// Plans the step over the docs of [project] with the project's targets.
CodeStampStep _planAt(Directory project) {
  final session = openSession(project);
  try {
    final config = session.project;
    final docs = [
      for (final file in Directory(
        '${config.projectRoot.path}/docs',
      ).listSync(recursive: true).whereType<File>())
        _docOf(config.matcher, config.projectRoot, file),
    ]..sort((a, b) => a.docPath.compareTo(b.docPath));
    return CodeStampStep.plan(
      docs,
      projectRoot: config.projectRoot,
      set: config.set,
      targets: config.targets,
    );
  } finally {
    session.close();
  }
}

CodeStampDoc _docOf(DocTypeMatcher matcher, Directory root, File file) {
  final docPath = file.path.substring('${root.path}/docs/'.length);
  final match = matcher.match(docPath);
  return (
    docPath: docPath,
    lf: toLf(file.readAsStringSync()),
    type: match is MatchedDocType ? match.docType : null,
    target: match is MatchedDocType ? match.target : null,
  );
}

/// Writes each rewrite of [step] under [project].
void _write(Directory project, CodeStampStep step) {
  for (final MapEntry(key: docPath, value: lf) in step.rewrites.entries) {
    File('${project.path}/docs/$docPath').writeAsStringSync(lf);
  }
}

CheckReport _check(Directory project) {
  final session = openSession(project);
  try {
    return runCheck(session);
  } finally {
    session.close();
  }
}

List<Finding> _codeFindings(CheckReport report) => [
  for (final finding in report.findings)
    if (finding.kind == FindingKind.codeSuspect ||
        finding.kind == FindingKind.codeUnconfirmed)
      finding,
];

String _read(Directory project, String docPath) =>
    File('${project.path}/docs/$docPath').readAsStringSync();

void main() {
  group('which code links take a fingerprint', () {
    test(
      'an implemented entry and a covers folder take the fingerprint the '
      'check computes, so the next check finds no code link to compare',
      () async {
        final project = await _project();
        expect(_codeFindings(_check(project)), isNotEmpty);

        final step = _planAt(project);
        _write(project, step);

        expect(
          _read(project, loginRecord),
          contains(
            "  - 'email_login:app/lib/login.dart:SignInPage "
            "$_loginFingerprint'\n",
          ),
        );
        expect(
          _read(project, loginArchitecture),
          contains('covers:\n  - app/lib/ $_appLibFingerprint\n'),
        );
        expect(_codeFindings(_check(project)), isEmpty);
      },
    );

    test('a stale fingerprint is replaced in place, with no compare', () async {
      final project = await _project(
        extra: {
          'docs/$loginRecord': _record(
            code: ['email_login:$_login:SignInPage $_stale'],
          ),
        },
      );

      final step = _planAt(project);

      expect(
        step.rewrites[loginRecord],
        contains("  - 'email_login:$_login:SignInPage $_loginFingerprint'\n"),
      );
      expect(step.rewrites[loginRecord], isNot(contains(_stale)));
    });

    test('a bare entry takes its fingerprint after one space, and a bare '
        'stale one is replaced', () async {
      final project = await _project(
        extra: {
          'docs/$loginArchitecture':
              checkProjectFiles()['docs/$loginArchitecture']!.replaceFirst(
                'covers:\n  - app/lib/\n',
                'covers:\n  - app/lib/\n  - app/lib/login.dart $_stale\n',
              ),
        },
      );

      final step = _planAt(project);

      expect(
        step.rewrites[loginArchitecture],
        contains(
          'covers:\n  - app/lib/ $_appLibFingerprint\n'
          '  - app/lib/login.dart $_loginFingerprint\n',
        ),
      );
    });

    test('a planned entry whose file exists, a skipped entry, an entry whose '
        'path names nothing, and a tests line stay as written', () async {
      final record = _record(
        statuses: [
          'email_login:planned',
          'email_login/check_password:skipped:not this release',
        ],
        code: [
          'email_login:$_login:SignInPage',
          'email_login/check_password:$_login:checkPassword',
          'email_login:app/lib/missing.dart',
        ],
        tests: ['email_login:$_login'],
      );
      final project = await _project(extra: {'docs/$loginRecord': record});

      final step = _planAt(project);

      expect(step.rewrites, isNot(contains(loginRecord)));
    });

    test('a covers entry of a target that holds no implemented item yet '
        'waits and stays as written', () async {
      final project = await _project(
        extra: {
          'docs/$loginRecord': _record(
            statuses: ['email_login:planned'],
            code: ['email_login:app/lib/missing.dart'],
          ),
        },
      );

      final step = _planAt(project);

      expect(step.rewrites, isEmpty);
      expect(
        step.stepLine(from: _from, step: _step).text,
        'from 1.6.0: stamp_code_fingerprints: 0 docs; 0 entries',
      );
    });

    test(
      'a deprecated entry is no planned entry and takes a fingerprint',
      () async {
        final project = await _project(
          extra: {
            'docs/$loginRecord': _record(
              statuses: ['email_login:deprecated'],
              code: ['email_login:$_login:SignInPage'],
            ),
          },
        );

        final step = _planAt(project);

        expect(
          step.rewrites[loginRecord],
          contains("'email_login:$_login:SignInPage $_loginFingerprint'"),
        );
      },
    );

    test('the step marks no draft and keeps each approval line', () async {
      final project = await writeCheckProject(
        unfingerprinted: {'docs/$loginArchitecture'},
      );
      final before = _read(project, loginArchitecture);

      final step = _planAt(project);

      final stamped = step.rewrites[loginArchitecture]!;
      expect(stamped, isNot(contains('draft')));
      expect(
        RegExp(r'^approved: .*$', multiLine: true).firstMatch(stamped)![0],
        RegExp(r'^approved: .*$', multiLine: true).firstMatch(before)![0],
      );
    });

    test('a tree already stamped rewrites nothing', () async {
      final project = await writeCheckProject();

      final step = _planAt(project);

      expect(step.rewrites, isEmpty);
      expect(step.paths, isEmpty);
    });
  });

  group('one named code target', () {
    test('every implemented link takes its fingerprint, so the next check '
        'finds no code link to compare', () async {
      final project = await _project(
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n  app:\n    code_root: .\n',
        },
      );
      expect(_codeFindings(_check(project)), hasLength(3));

      final step = _planAt(project);
      _write(project, step);

      expect(
        step.stepLine(from: _from, step: _step).text,
        'from 1.6.0: stamp_code_fingerprints: 2 docs; 3 entries',
      );
      expect(_codeFindings(_check(project)), isEmpty);
    });
  });

  group('an entry the step cannot rewrite', () {
    test('a folded scalar stays as written and is not counted', () async {
      final project = await _project(
        extra: {
          'docs/$loginRecord':
              "---\nstatuses:\n  - 'email_login:implemented'\n"
              'implements:\n  - >-\n    email_login:$_login:SignInPage\n'
              '---\n\n# Login implementation\n',
        },
      );

      final step = _planAt(project);

      expect(step.rewrites, isNot(contains(loginRecord)));
      expect(
        step.stepLine(from: _from, step: _step).text,
        'from 1.6.0: stamp_code_fingerprints: 1 docs; 1 entries',
      );
    });
  });

  group('the step line', () {
    test('one code target counts the docs and the entries it stamps', () async {
      final project = await _project();

      final step = _planAt(project);
      final line = step.stepLine(from: _from, step: _step);

      expect(
        line.text,
        'from 1.6.0: stamp_code_fingerprints: 2 docs; 3 entries',
      );
      expect(line.paths, [loginArchitecture, loginRecord]);
      expect(line.toJson(), {
        'from': '1.6.0',
        'step': _step,
        'paths': [loginArchitecture, loginRecord],
        'unreadable': <String>[],
      });
    });

    test('two code targets count the entries of each target', () async {
      final project = await writeTwinProject();
      final records = {
        _flutterRecord: _record(code: ['email_login:$_login:SignInPage']),
        _jasprRecord: _record(
          statuses: ['email_login:planned'],
          code: ['email_login:$_login'],
        ),
      };
      for (final MapEntry(key: path, value: text) in records.entries) {
        File('${project.path}/docs/$path')
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
      }

      final step = _planAt(project);

      expect(
        step.stepLine(from: _from, step: _step).text,
        'from 1.6.0: stamp_code_fingerprints: 2 docs; flutter: 2 entries; '
        'jaspr: 0 entries',
      );
      expect(step.paths, [flutterArchitecture, _flutterRecord]);
    });

    test(
      'a file that cannot be read stays as written and is counted as '
      'unreadable, never among the paths',
      skip: unreadablePathSkipReason(),
      () async {
        final project = await _project(
          extra: {
            'docs/$loginRecord': _record(
              code: ['email_login:$_login:SignInPage'],
            ),
            'docs/$loginArchitecture':
                checkProjectFiles()['docs/$loginArchitecture']!.replaceFirst(
                  '  - app/lib/\n',
                  '  - app/lib/other.dart\n',
                ),
            'app/lib/other.dart': 'class Other {}\n',
          },
        );
        final locked = '${project.path}/$_login';
        Process.runSync('chmod', ['000', locked]);
        addTearDown(() => Process.runSync('chmod', ['644', locked]));

        final step = _planAt(project);
        final line = step.stepLine(from: _from, step: _step);

        expect(
          line.text,
          'from 1.6.0: stamp_code_fingerprints: 1 docs; 1 entries; '
          'unreadable: 1',
        );
        expect(line.paths, [loginArchitecture]);
        expect(line.toJson()['unreadable'], [_login]);
        expect(step.rewrites, isNot(contains(loginRecord)));
      },
    );
  });
}
