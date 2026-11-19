import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/models/file_fingerprint.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show baseHashOf, withKeyBlock;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/setup_migration/code_stamp_step.dart';
import 'package:specstone_core/src/setup_migration/tree_move.dart'
    show docPathsOf;
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/counting_io.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_doc_fixture.dart';
import '../../helpers/target_fixture.dart';
import '../../helpers/write_fixture.dart' show docFile, writeIn;

const _login = 'app/lib/login.dart';
const _stale = '0123456789ab';
const _from = '1.6.0';
const _step = 'stamp_code_fingerprints';
const _flutterRecord = '.specstone/records/flutter/f01_login/IMPLEMENTATION.md';
const _jasprRecord = '.specstone/records/jaspr/f01_login/IMPLEMENTATION.md';

/// Every doc whose code links the fixture writes, left with none recorded.
const Set<String> _linkedDocs = {loginRecord, 'docs/$loginArchitecture'};

String _fingerprintOf(String text, String path) =>
    fileCodeFingerprint(utf8.encode(text), path: path);

String _legacyOf(String text) => legacyFileCodeFingerprint(utf8.encode(text));

final String _loginText = checkProjectFiles()[_login]!;
final String _loginFingerprint = _fingerprintOf(_loginText, _login);
final String _appLibFingerprint = folderCodeFingerprint([
  FileFingerprint(path: _login, fingerprint: _loginFingerprint),
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
CodeStampStep _planAt(Directory project, {bool restamp = false}) {
  final session = openSession(project);
  try {
    final config = session.project;
    final docsRoot = Directory('${config.projectRoot.path}/docs');
    final docs = [
      for (final docPath in docPathsOf(docsRoot, config.projectRoot)..sort())
        _docOf(
          config.matcher,
          docPath,
          fileOfDocPath(
            docPath,
            docsRoot: docsRoot,
            projectRoot: config.projectRoot,
          ),
        ),
    ];
    return CodeStampStep.plan(
      docs,
      projectRoot: config.projectRoot,
      set: config.set,
      targets: config.targets,
      restamp: restamp,
    );
  } finally {
    session.close();
  }
}

CodeStampDoc _docOf(DocTypeMatcher matcher, String docPath, File file) {
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
    docFile(project, docPath).writeAsStringSync(lf);
  }
}

Future<CheckReport> _check(Directory project) async {
  final session = openSession(project);
  try {
    return await runCheck(session);
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
    docFile(project, docPath).readAsStringSync();

/// Returns the real-path resolves of planning the step over a record that
/// holds [links] implemented entries for one code file.
Future<int> _resolvesOfPlan(int links) async {
  final project = await _project(
    extra: {
      loginRecord: _record(
        code: [for (var i = 0; i < links; i++) 'email_login:$_login:Symbol$i'],
      ),
    },
  );
  return countRealPathResolves(() => _planAt(project));
}

void main() {
  test(
    'planning resolves real paths as often for twice the code links',
    () async {
      final base = await _resolvesOfPlan(10);
      final doubled = await _resolvesOfPlan(20);

      expect(doubled, base);
    },
  );

  group('which code links take a fingerprint', () {
    test(
      'an implemented entry and a covers folder take the fingerprint the '
      'check computes, so the next check finds no code link to compare',
      () async {
        final project = await _project();
        expect(_codeFindings(await _check(project)), isNotEmpty);

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
        expect(_codeFindings(await _check(project)), isEmpty);
      },
    );

    test('a stale fingerprint is replaced in place, with no compare', () async {
      final project = await _project(
        extra: {
          loginRecord: _record(
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
      final project = await _project(extra: {loginRecord: record});

      final step = _planAt(project);

      expect(step.rewrites, isNot(contains(loginRecord)));
    });

    test('a covers entry of a target that holds no implemented item yet '
        'waits and stays as written', () async {
      final project = await _project(
        extra: {
          loginRecord: _record(
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
            loginRecord: _record(
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
      expect(_codeFindings(await _check(project)), hasLength(3));

      final step = _planAt(project);
      _write(project, step);

      expect(
        step.stepLine(from: _from, step: _step).text,
        'from 1.6.0: stamp_code_fingerprints: 2 docs; 3 entries',
      );
      expect(_codeFindings(await _check(project)), isEmpty);
    });
  });

  group('an entry the step stamps', () {
    test(
      'a folded scalar is written as a block list entry and counted',
      () async {
        final project = await _project(
          extra: {
            loginRecord:
                "---\nstatuses:\n  - 'email_login:implemented'\n"
                'implements:\n  - >-\n    email_login:$_login:SignInPage\n'
                '---\n\n# Login implementation\n',
          },
        );

        final step = _planAt(project);

        expect(
          step.rewrites[loginRecord],
          contains('implements:\n  - email_login:$_login:SignInPage '),
        );
        expect(
          step.stepLine(from: _from, step: _step).text,
          'from 1.6.0: stamp_code_fingerprints: 2 docs; 2 entries',
        );
      },
    );

    test(
      'the text equals what set --field writes for the same entries',
      () async {
        const held = 'covers:\n  - "app/lib/login.dart"\n  - app/lib/\n';
        final doc = checkProjectFiles()['docs/$loginArchitecture']!;
        final project = await _project(
          extra: {'docs/$loginArchitecture': withKeyBlock(doc, 'covers', held)},
        );
        final step = _planAt(project);

        writeIn(
          project,
          (s) => answerSet(
            s,
            SetRequest.parse(
              loginArchitecture,
              field: 'covers',
              base: baseHashOf(held),
            ),
            '- app/lib/login.dart $_loginFingerprint\n'
            '- app/lib/ $_appLibFingerprint\n',
          ),
        );

        expect(
          step.rewrites[loginArchitecture],
          _read(project, loginArchitecture),
        );
      },
    );
  });

  group('a root: project covers entry', () {
    final skillFingerprint = _fingerprintOf(skillText, skillFile);

    test('of a doc in no code target takes the fingerprint of its file '
        'from the project root, so the next check finds no code link to '
        'compare, and counts in no entry count', () async {
      final project = await writeCheckProject(
        extra: {
          '.specstone/config.yaml': '${skillPinsConfig()}code_root: code\n',
          'code/$_login': _loginText,
          ...skillDocFile([skillFile]),
          skillFile: skillText,
        },
        without: {_login, loginRecord},
        unfingerprinted: {..._linkedDocs, 'docs/$skillDoc'},
      );
      expect(_codeFindings(await _check(project)), isNotEmpty);

      final step = _planAt(project);
      _write(project, step);

      expect(
        step.stepLine(from: _from, step: _step).text,
        'from 1.6.0: stamp_code_fingerprints: 1 docs; 0 entries',
      );
      expect(
        _read(project, skillDoc),
        contains('covers:\n  - $skillFile $skillFingerprint\n'),
      );
      expect(_codeFindings(await _check(project)), isEmpty);
    });

    test("with two code targets counts in no target's entry count", () async {
      final project = await writeTwinProject(
        extra: {
          '.specstone/config.yaml':
              '${skillPinsConfig()}targets:\n'
              '  flutter:\n    code_root: flutter_ws\n'
              '  jaspr:\n    code_root: jaspr_ws\n',
          ...skillDocFile([skillFile]),
          skillFile: skillText,
        },
        unfingerprinted: {'docs/$skillDoc'},
      );

      final step = _planAt(project);

      expect(
        step.stepLine(from: _from, step: _step).text,
        'from 1.6.0: stamp_code_fingerprints: 1 docs; flutter: 0 entries; '
        'jaspr: 0 entries',
      );
      expect(step.paths, [skillDoc]);
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
      expect(line.paths, [loginRecord, loginArchitecture]);
      expect(line.toJson(), {
        'from': '1.6.0',
        'step': _step,
        'paths': [loginRecord, loginArchitecture],
        'unreadable': <String>[],
      });
    });

    test('two code targets count the entries of each target', () async {
      final project = await writeTwinProject(
        unfingerprinted: {
          'docs/$flutterArchitecture',
          'docs/$jasprArchitecture',
        },
      );
      final records = {
        _flutterRecord: _record(code: ['email_login:$_login:SignInPage']),
        _jasprRecord: _record(
          statuses: ['email_login:planned'],
          code: ['email_login:$_login'],
        ),
      };
      for (final MapEntry(key: path, value: text) in records.entries) {
        docFile(project, path)
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
      }

      final step = _planAt(project);

      expect(
        step.stepLine(from: _from, step: _step).text,
        'from 1.6.0: stamp_code_fingerprints: 2 docs; flutter: 2 entries; '
        'jaspr: 0 entries',
      );
      expect(step.paths, [_flutterRecord, flutterArchitecture]);
    });

    test(
      'a file that cannot be read stays as written and is counted as '
      'unreadable, never among the paths',
      skip: unreadablePathSkipReason(),
      () async {
        final project = await _project(
          extra: {
            loginRecord: _record(code: ['email_login:$_login:SignInPage']),
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

  group('restamp mode', () {
    const restampStep = 'restamp_code_fingerprints';
    const other = 'app/lib/other.dart';
    const otherText = '// Other.\nclass Other {}\n\n';
    final legacyLogin = _legacyOf(_loginText);

    /// Plans the restamp over a project whose record holds [code] entries,
    /// all implemented, and whose architecture doc holds [covers].
    Future<Directory> restampProject({
      List<String> code = const [],
      List<String> covers = const [],
      List<String> statuses = const ['email_login:implemented'],
    }) => _project(
      extra: {
        loginRecord: _record(statuses: statuses, code: code),
        'docs/$loginArchitecture':
            checkProjectFiles()['docs/$loginArchitecture']!.replaceFirst(
              'covers:\n  - app/lib/\n',
              'covers:\n${[for (final c in covers) '  - $c\n'].join()}',
            ),
        other: otherText,
      },
    );

    test('a link stamped under the old rule takes the new fingerprint, so '
        'the next check finds no suspect link', () async {
      final project = await restampProject(
        code: ['email_login:$_login:SignInPage $legacyLogin'],
      );
      expect(_codeFindings(await _check(project)), isNotEmpty);

      final step = _planAt(project, restamp: true);
      _write(project, step);

      expect(
        _read(project, loginRecord),
        contains("  - 'email_login:$_login:SignInPage $_loginFingerprint'\n"),
      );
      expect(
        _codeFindings(await _check(project))
            .where((finding) => finding.kind == FindingKind.codeSuspect),
        isEmpty,
      );
      expect(
        step.stepLine(from: '1.7.0', step: restampStep).text,
        'from 1.7.0: restamp_code_fingerprints: 1 docs; 1 entries',
      );
    });

    test('a suspect link and a link with no fingerprint stay as written, '
        'and are not counted', () async {
      final project = await restampProject(
        code: [
          'email_login:$_login:SignInPage $_stale',
          'email_login/check_password:$_login:checkPassword',
        ],
      );

      final step = _planAt(project, restamp: true);

      expect(step.rewrites, isEmpty);
      expect(
        step.stepLine(from: '1.7.0', step: restampStep).text,
        'from 1.7.0: restamp_code_fingerprints: 0 docs; 0 entries',
      );
    });

    test('a planned entry stays as written', () async {
      final project = await restampProject(
        statuses: ['email_login:planned'],
        code: ['email_login:$_login:SignInPage $legacyLogin'],
      );

      final step = _planAt(project, restamp: true);

      expect(step.rewrites, isNot(contains(loginRecord)));
    });

    test('a link whose code has no line the new rule drops is not '
        'counted', () async {
      const plainCode = 'class SignInPage {}\n';
      final project = await _project(
        extra: {
          _login: plainCode,
          loginRecord: _record(
            code: ['email_login:$_login:SignInPage ${_legacyOf(plainCode)}'],
          ),
        },
      );

      final step = _planAt(project, restamp: true);

      expect(step.rewrites, isEmpty);
    });

    test('a link already clean under the new fingerprint stays while its '
        'code holds droppable lines', () async {
      final project = await restampProject(
        code: ['email_login:$_login:SignInPage $_loginFingerprint'],
      );

      final step = _planAt(project, restamp: true);

      expect(step.rewrites, isEmpty);
      expect(
        step.stepLine(from: '1.7.0', step: restampStep).text,
        'from 1.7.0: restamp_code_fingerprints: 0 docs; 0 entries',
      );
    });

    test('two code targets count the links restamped in each', () async {
      final project = await writeTwinProject(
        extra: {'flutter_ws/$_login': _loginText},
        unfingerprinted: {
          'docs/$flutterArchitecture',
          'docs/$jasprArchitecture',
        },
      );
      final records = {
        _flutterRecord: _record(
          code: ['email_login:$_login:SignInPage $legacyLogin'],
        ),
        _jasprRecord: _record(
          statuses: ['email_login:planned'],
          code: ['email_login:$_login:SignInPage $legacyLogin'],
        ),
      };
      for (final MapEntry(key: path, value: text) in records.entries) {
        docFile(project, path)
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
      }

      final step = _planAt(project, restamp: true);

      expect(
        step.stepLine(from: '1.7.0', step: restampStep).text,
        'from 1.7.0: restamp_code_fingerprints: 1 docs; flutter: 1 entries; '
        'jaspr: 0 entries',
      );
      expect(step.paths, [_flutterRecord]);
    });

    test('restamps a folder link and leaves a suspect sibling', () async {
      final legacyFolder = folderCodeFingerprint([
        FileFingerprint(path: _login, fingerprint: legacyLogin),
        FileFingerprint(path: other, fingerprint: _legacyOf(otherText)),
      ]);
      final newFolder = folderCodeFingerprint([
        FileFingerprint(path: _login, fingerprint: _loginFingerprint),
        FileFingerprint(
          path: other,
          fingerprint: _fingerprintOf(otherText, other),
        ),
      ]);
      final project = await restampProject(
        covers: ['app/lib/ $legacyFolder', '$other $_stale'],
      );

      final step = _planAt(project, restamp: true);

      expect(
        step.rewrites[loginArchitecture],
        contains('covers:\n  - app/lib/ $newFolder\n  - $other $_stale\n'),
      );
      expect(
        step.stepLine(from: '1.7.0', step: restampStep).text,
        'from 1.7.0: restamp_code_fingerprints: 1 docs; 1 entries',
      );
    });

    test(
      'the text equals what the stamp mode writes for the same code',
      () async {
        final project = await restampProject(
          code: ['email_login:$_login:SignInPage $legacyLogin'],
        );

        final restamped = _planAt(project, restamp: true);
        final stamped = _planAt(project);

        expect(restamped.rewrites[loginRecord], stamped.rewrites[loginRecord]);
      },
    );
  });
}
