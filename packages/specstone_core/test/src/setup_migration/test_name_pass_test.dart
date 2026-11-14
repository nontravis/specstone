import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart' show Doc;
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart'
    show frontmatterValuesOf;
import 'package:specstone_core/src/plan_hash.dart';
import 'package:specstone_core/src/setup_migration/label_pass.dart'
    show LabelTree;
import 'package:specstone_core/src/setup_migration/legacy_plan.dart'
    show planLegacy, planLegacyRun;
import 'package:specstone_core/src/setup_migration/run_plan.dart'
    show PlannedCreate;
import 'package:specstone_core/src/setup_migration/test_name_pass.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/pack_version.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/git_repo.dart';
import '../../helpers/legacy_fixture.dart' show acmeLegacy;
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _featurePath = 'prds/features/f01_login/FEATURE.md';
const _storyPath = 'prds/features/f01_login/us01_email_login/USER_STORY.md';
const _frPath =
    'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
const _recordPath = 'specs/f01_login/IMPLEMENTATION.md';
const _otherFeaturePath = 'prds/features/f02_billing/FEATURE.md';
const _otherStoryPath = 'prds/features/f02_billing/us01_pay/USER_STORY.md';
const _testPath = 'app/test/auth_test.dart';
const _frLine = 'email_login/validate_credentials:test/auth_test.dart';

const Map<String, String> _loginDocs = {
  _featurePath: '# Login\n',
  _storyPath: '# Email login\n',
  _frPath: '# Validate credentials\n',
};

List<String> _packsOf(bool hasRecordPack) => [
  'prd-core',
  if (hasRecordPack) 'software-tech',
];

String _config({
  List<String> otherRepos = const [],
  bool hasRecordPack = true,
}) =>
    '${shippedPinsConfig(_packsOf(hasRecordPack))}'
    'code_root: app\n'
    '${otherRepos.isEmpty ? '' : 'agent_file_roots:\n'
              '${[for (final repo in otherRepos) '  - $repo\n'].join()}'}';

/// A committed git project: [docs] under `docs/`, [files] beside them, and
/// the nested repositories [otherRepos] ignored by it.
Future<Directory> _project({
  Map<String, String> docs = _loginDocs,
  Map<String, String> files = const {},
  List<String> otherRepos = const [],
  Map<String, String> untrackedFiles = const {},
  bool hasRecordPack = true,
}) async {
  final project = await writeTree({
    '.specstone/config.yaml': _config(
      otherRepos: otherRepos,
      hasRecordPack: hasRecordPack,
    ),
    for (final MapEntry(:key, :value) in docs.entries) 'docs/$key': value,
    for (final MapEntry(:key, :value) in files.entries) key: value,
    if (otherRepos.isNotEmpty)
      '.gitignore': '${[for (final repo in otherRepos) '$repo/'].join('\n')}\n',
  });
  final root = Directory(project.resolveSymbolicLinksSync());
  expect(git(root, ['init', '-q']).exitCode, 0);
  commitAll(root, 'base');
  for (final repo in otherRepos) {
    final folder = Directory('${root.path}/$repo');
    expect(git(folder, ['init', '-q']).exitCode, 0);
    commitAll(folder, 'base');
  }
  for (final MapEntry(:key, :value) in untrackedFiles.entries) {
    File('${root.path}/$key')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  return root;
}

Future<Directory?> _home() async => null;

/// The pass over [project], planned as the upgrade plans it.
({TestNamePass pass, PlanInputs inputs}) _run(
  Directory project, {
  Directory? home,
  Map<String, String> pending = const {},
  bool Function(String docPath)? isTaken,
}) {
  final config = ProjectConfig.read(project);
  final set = TemplateResolver().resolveCarried(
    packNames: config.pins.keys,
    homeDirectory: home,
  );
  final docsRoot = Directory('${project.path}/docs');
  final matcher = DocTypeMatcher(set, targetNames: config.targetNames);
  final docs = <TestNameDoc>[];
  final types = <String, MergedDocType>{};
  for (final entity in docsRoot.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;
    final docPath = entity.path.substring(docsRoot.path.length + 1);
    final match = matcher.match(docPath);
    final type = match is MatchedDocType ? match.docType : null;
    if (type != null) types[docPath] = type;
    docs.add((
      plannedPath: docPath,
      type: type,
      target: match is MatchedDocType ? match.target : null,
      lf: entity.readAsStringSync(),
    ));
  }
  final tree = LabelTree.of(
    [for (final doc in docs) (docPath: doc.plannedPath, lf: doc.lf)],
    set: set,
    docTypes: types,
  );
  final inputs = PlanInputs(project);
  final pass = inputs.collect(
    () => TestNamePass.plan(
      root: project,
      set: set,
      targets: config.targets,
      agentFileRoots: config.agentFileRoots,
      docs: docs,
      resolveLabel: (label) => tree.resolve(label, citingDocPath: ''),
      isTaken: isTaken ?? (_) => false,
      pendingCreates: [
        for (final MapEntry(:key, :value) in pending.entries)
          PlannedCreate(path: 'docs/$key', text: value),
      ],
    ),
  );
  return (pass: pass, inputs: inputs);
}

String _fileText(TestNamePass pass, String path) =>
    pass.fileRewrites.singleWhere((rewrite) => rewrite.path == path).text;

Object? _testsOf(String text) => frontmatterValuesOf(Doc.parse(text))['tests'];

String _test(String name) => "void main() {\n  test('$name', () {});\n}\n";

void main() {
  _legacyTests();
  group('test-name pass', () {
    test('a label opening a test name moves into the record as one '
        'line, and the name keeps its words', () async {
      final project = await _project(
        files: {_testPath: _test('f01/us01/fr01 rejects a wrong password')},
      );

      final pass = _run(project, home: await _home()).pass;

      expect(pass.recordCreates, hasLength(1));
      final record = pass.recordCreates.single;
      expect(record.docPath, _recordPath);
      expect(_testsOf(record.text), [
        'email_login/validate_credentials:test/auth_test.dart',
      ]);
      expect(_fileText(pass, _testPath), _test('rejects a wrong password'));
      expect(pass.rewrittenFiles, [_testPath]);
    });

    test('two tests naming one FR make one line', () async {
      final project = await _project(
        files: {
          _testPath:
              "void main() {\n  test('f01/us01/fr01 one', () {});\n"
              "  test('F-01 US-01 FR-01: two', () {});\n}\n",
        },
      );

      final pass = _run(project, home: await _home()).pass;

      expect(_testsOf(pass.recordCreates.single.text), [
        'email_login/validate_credentials:test/auth_test.dart',
      ]);
      expect(pass.recordLines, hasLength(1));
      expect(
        _fileText(pass, _testPath),
        "void main() {\n  test('one', () {});\n  test('two', () {});\n}\n",
      );
    });

    test('a Name whose longest prefix names the story goes to the '
        "story's entry", () async {
      final project = await _project(
        files: {_testPath: _test('login/email_login: signs in')},
      );

      final pass = _run(project, home: await _home()).pass;

      expect(_testsOf(pass.recordCreates.single.text), [
        'email_login:test/auth_test.dart',
      ]);
      expect(_fileText(pass, _testPath), _test('signs in'));
    });

    test('the longest prefix that names a story or FR wins', () async {
      final project = await _project(
        files: {
          _testPath: _test('login/email_login/validate_credentials - denies'),
        },
      );

      final pass = _run(project, home: await _home()).pass;

      expect(_testsOf(pass.recordCreates.single.text), [
        'email_login/validate_credentials:test/auth_test.dart',
      ]);
      expect(_fileText(pass, _testPath), _test('denies'));
    });

    test('a trailing e<nn> goes to its FR and a trailing s<nn> to its '
        'story, each named under --json', () async {
      final project = await _project(
        files: {
          _testPath:
              "void main() {\n  test('f01/us01/fr01/e03 empty password', "
              "() {});\n  test('f01/us01/s02 signs in', () {});\n}\n",
        },
      );

      final pass = _run(project, home: await _home()).pass;

      expect(_testsOf(pass.recordCreates.single.text), [
        'email_login/validate_credentials:test/auth_test.dart',
        'email_login:test/auth_test.dart',
      ]);
      final rewritten = (pass.json['rewritten']! as List)
          .cast<Map<String, Object?>>();
      expect(rewritten.map((entry) => entry['edgeCase']), ['E03', null]);
      expect(rewritten.map((entry) => entry['scenario']), [null, 'S02']);
      expect(
        _fileText(pass, _testPath),
        "void main() {\n  test('empty password', () {});\n"
        "  test('signs in', () {});\n}\n",
      );
    });

    test('a label followed by an item ID names the edge case', () async {
      final project = await _project(
        files: {_testPath: _test('F-01 US-01 FR-01 E05 blocks a lockout')},
      );

      final pass = _run(project, home: await _home()).pass;

      final rewritten = (pass.json['rewritten']! as List)
          .cast<Map<String, Object?>>();
      expect(rewritten.single['edgeCase'], 'E05');
      expect(_fileText(pass, _testPath), _test('blocks a lockout'));
    });

    test('an ID that resolves to no doc stays as written and counts '
        'left, unlisted', () async {
      final project = await _project(
        files: {_testPath: _test('f09/us09/fr09 old feature')},
      );

      final pass = _run(project, home: await _home()).pass;

      expect(pass.fileRewrites, isEmpty);
      expect(pass.recordCreates, isEmpty);
      expect(pass.left, 1);
      expect(pass.json['left'], isEmpty);
      expect(
        pass.planLine,
        'tests: 0 lines in 0 records; names: 0 rewritten in 0 files; left: 1',
      );
    });

    test('an ID that names two docs stays as written', () async {
      final project = await _project(
        docs: {
          ..._loginDocs,
          'prds/features/f01_other/FEATURE.md': '# Other\n',
          'prds/features/f01_other/us01_x/USER_STORY.md': '# X\n',
          'prds/features/f01_other/us01_x/fr01_y.md': '# Y\n',
        },
        files: {_testPath: _test('f01/us01/fr01 ambiguous')},
      );

      final pass = _run(project, home: await _home()).pass;

      expect(pass.fileRewrites, isEmpty);
      expect(pass.left, 1);
    });

    test('a partial label resolves to nothing and counts left', () async {
      final project = await _project(
        files: {_testPath: _test('us01/fr01 partial label')},
      );

      final pass = _run(project, home: await _home()).pass;

      expect(pass.fileRewrites, isEmpty);
      expect(pass.left, 1);
    });

    test('a test file in another repository gets its line, keeps its '
        'name, and is listed left', () async {
      final project = await _project(
        otherRepos: ['app/vendor'],
        files: {'app/vendor/test/dep_test.dart': _test('f01/us01/fr01 dep')},
      );

      final pass = _run(project, home: await _home()).pass;

      expect(_testsOf(pass.recordCreates.single.text), [
        'email_login/validate_credentials:vendor/test/dep_test.dart',
      ]);
      expect(pass.fileRewrites, isEmpty);
      expect(pass.left, 1);
      final left = (pass.json['left']! as List).cast<Map<String, Object?>>();
      expect(left.single['file'], 'app/vendor/test/dep_test.dart');
      expect(left.single['name'], 'f01/us01/fr01 dep');
      expect(left.single['item'], 'login/email_login/validate_credentials');
      expect(
        pass.planLine,
        'tests: 1 lines in 1 records; names: 0 rewritten in 0 files; left: 1',
      );
    });

    test('a name that is the ID alone takes its doc title', () async {
      final project = await _project(
        files: {_testPath: _test('f01/us01/fr01')},
      );

      final pass = _run(project, home: await _home()).pass;

      expect(_fileText(pass, _testPath), _test('Validate credentials'));
    });

    test('a string that opens with no doc ID is no test name, and a '
        'run that finds none prints no line', () async {
      final project = await _project(
        files: {
          _testPath:
              "void main() {\n  test('rejects a wrong password', () {});\n"
              "  print('lib/src/x.dart');\n  print('login/email_login.md');\n}\n",
        },
      );

      final pass = _run(project, home: await _home()).pass;

      expect(pass.planLine, isNull);
      expect(pass.fileRewrites, isEmpty);
      expect(pass.recordCreates, isEmpty);
      expect(pass.recordEdits, isEmpty);
      expect(pass.left, 0);
    });

    test('a project whose merged set holds no record doc type runs no '
        'pass', () async {
      final project = await _project(
        hasRecordPack: false,
        files: {_testPath: _test('f01/us01/fr01 rejects')},
      );

      final pass = _run(project).pass;

      expect(pass.planLine, isNull);
      expect(pass.fileRewrites, isEmpty);
    });

    test('the plan inputs bind each file the pass reads, tracked files '
        'only', () async {
      final project = await _project(
        files: {
          _testPath: _test('f01/us01/fr01 rejects'),
          'app/lib/a.dart': 'const x = 1;\n',
          'docs/notes/ignored.dart': "'f01/us01/fr01 not read'\n",
        },
        untrackedFiles: {
          'app/test/untracked_test.dart': _test('f01/us01/fr01'),
        },
      );

      final run = _run(project, home: await _home());

      expect(run.inputs.lines, contains('app/test/auth_test.dart '));
      expect(run.inputs.lines, contains('app/lib/a.dart '));
      expect(run.inputs.lines, isNot(contains('untracked_test')));
      expect(run.inputs.lines, isNot(contains('ignored.dart')));
      expect(run.pass.fileRewrites.map((rewrite) => rewrite.path), [_testPath]);
    });

    test('a feature with no record in the target gets a draft record '
        'holding the line', () async {
      final project = await _project(
        docs: {
          ..._loginDocs,
          _otherFeaturePath: '# Billing\n',
          _otherStoryPath: '# Pay\n',
        },
        files: {_testPath: _test('billing/pay checks out')},
      );

      final pass = _run(project, home: await _home()).pass;

      final record = pass.recordCreates.single;
      expect(record.docPath, 'specs/f02_billing/IMPLEMENTATION.md');
      expect(_valuesOf(record.text)['draft'], true);
      expect(_testsOf(record.text), ['pay:test/auth_test.dart']);
    });

    test('a record the run holds gains the line beside its own', () async {
      final project = await _project(
        docs: {
          ..._loginDocs,
          _recordPath:
              "---\ntests:\n  - 'email_login:test/other_test.dart:keeps'\n"
              '---\n\n# Record\n',
        },
        files: {_testPath: _test('f01/us01/fr01 rejects')},
      );

      final pass = _run(project, home: await _home()).pass;

      expect(pass.recordCreates, isEmpty);
      expect(_testsOf(pass.recordEdits[_recordPath]!), [
        'email_login:test/other_test.dart:keeps',
        'email_login/validate_credentials:test/auth_test.dart',
      ]);
    });

    test('a line the record already holds is not written again', () async {
      final project = await _project(
        docs: {
          ..._loginDocs,
          _recordPath: "---\ntests:\n  - '$_frLine'\n---\n\n# Record\n",
        },
        files: {_testPath: _test('f01/us01/fr01 rejects')},
      );

      final pass = _run(project, home: await _home()).pass;

      expect(pass.recordEdits, isEmpty);
      expect(pass.recordLines, isEmpty);
      expect(_fileText(pass, _testPath), _test('rejects'));
      expect(
        pass.planLine,
        'tests: 0 lines in 0 records; names: 1 rewritten in 1 files; left: 0',
      );
    });

    test(
      'a record a step of the run creates gains the line in place',
      () async {
        final project = await _project(
          files: {_testPath: _test('f01/us01/fr01 rejects')},
        );

        final pass = _run(
          project,
          home: await _home(),
          pending: {
            _recordPath:
                "---\ndraft: true\nstatuses:\n  - 'email_login:planned'\n---\n"
                '\n# Record\n',
          },
        ).pass;

        expect(pass.recordCreates, isEmpty);
        final text = pass.recordEdits[_recordPath]!;
        expect(_testsOf(text), [
          'email_login/validate_credentials:test/auth_test.dart',
        ]);
        expect(_valuesOf(text)['statuses'], ['email_login:planned']);
      },
    );

    test('a new record whose path holds a file the run cannot read as '
        'a record leaves the name as written', () async {
      final project = await _project(
        files: {_testPath: _test('f01/us01/fr01 rejects')},
      );

      final pass = _run(
        project,
        home: await _home(),
        isTaken: (docPath) => docPath == _recordPath,
      ).pass;

      expect(pass.recordCreates, isEmpty);
      expect(pass.fileRewrites, isEmpty);
      expect(pass.left, 1);
      expect(pass.json['left'], hasLength(1));
    });

    test('a record whose frontmatter is not valid YAML is left alone '
        'and its names stay', () async {
      final project = await _project(
        docs: {
          ..._loginDocs,
          _recordPath: '---\ntests: [unclosed\n---\n\n# Record\n',
        },
        files: {_testPath: _test('f01/us01/fr01 rejects')},
      );

      final pass = _run(project, home: await _home()).pass;

      expect(pass.recordEdits, isEmpty);
      expect(pass.fileRewrites, isEmpty);
      expect(pass.left, 1);
    });

    test('a file keeps its CRLF line ends and byte order mark', () async {
      final project = await _project(
        files: {
          _testPath: "﻿void main() {\r\n  test('f01/us01/fr01 rejects', () {});\r\n}\r\n",
        },
      );

      final pass = _run(project, home: await _home()).pass;

      expect(
        pass.fileRewrites.single.text,
        "﻿void main() {\r\n  test('rejects', () {});\r\n}\r\n",
      );
    });

    test('a file that is not UTF-8 is skipped', () async {
      final project = await _project(files: {'app/test/a.dart': 'x\n'});
      File('${project.path}/app/test/bin_test.dart')
          .writeAsBytesSync([0xFF, 0xFE, 0x27, 0x66, 0x30, 0x31]);
      commitAll(project, 'binary');

      final pass = _run(project, home: await _home()).pass;

      expect(pass.planLine, isNull);
    });

    test(
      'a double-quoted name and an escaped quote are read as one literal',
      () async {
        final project = await _project(
          files: {
            _testPath: 'void main() {\n  test("f01/us01/fr01 says \\"no\\"", () {});\n}\n',
          },
        );

        final pass = _run(project, home: await _home()).pass;

        expect(
          _fileText(pass, _testPath),
          'void main() {\n  test("says \\"no\\"", () {});\n}\n',
        );
      },
    );

    test('the text counts equal the lists --json holds', () async {
      final project = await _project(
        otherRepos: ['app/vendor'],
        files: {
          _testPath:
              "void main() {\n  test('f01/us01/fr01 a', () {});\n"
              "  test('login/email_login b', () {});\n"
              "  print('f01/us01/fr01 logged, not a test');\n}\n",
          'app/vendor/test/dep_test.dart': _test('f01/us01/fr01 dep'),
        },
      );

      final pass = _run(project, home: await _home()).pass;

      final rewritten = pass.json['rewritten']! as List;
      final left = pass.json['left']! as List;
      expect(rewritten, hasLength(3));
      expect(left, hasLength(1));
      expect(
        pass.planLine,
        'tests: 3 lines in 1 records; names: 3 rewritten in 1 files; '
        'left: ${left.length}',
      );
      expect(pass.left, left.length);
      expect(pass.recordLines, hasLength(3));
      expect(pass.json['written'], pass.recordLines);
    });
  });
}

Map<String, Object?> _valuesOf(String text) =>
    frontmatterValuesOf(Doc.parse(text));

void _legacyTests() {
  group('test-name pass in a legacy run', () {
    final since = PackVersion.parse(
      '1.5.0',
      file: 'test_name_pass_test.dart',
      key: 'software-tech',
    );

    Future<Directory> legacyProject(Map<String, String> files) async {
      final tree = await writeTree({...acmeLegacy, ...files});
      final root = Directory(tree.resolveSymbolicLinksSync());
      expect(git(root, ['init', '-q']).exitCode, 0);
      commitAll(root, 'base');
      return root;
    }

    test('a legacy run chains through the pass: the line lands in a new '
        'draft record and the name loses its label', () async {
      final root = await legacyProject({
        'test/auth_test.dart': _test('f01/us01/fr01 rejects a wrong password'),
      });

      final (:plan, :tests) = planLegacy(
        root,
        templates: TemplateResolver(),
        homeDirectory: null,
        testNamesSince: since,
      );

      expect(tests!.json['rewritten'], hasLength(1));
      expect(
        plan.toText(),
        contains(
          '  tests: 1 lines in 1 records; names: 1 rewritten in 1 files; '
          'left: 0\n',
        ),
      );
      final record = plan.creates.singleWhere(
        (create) => create.path == 'docs/$_recordPath',
      );
      expect(record.note, ' (draft)');
      expect(_testsOf(record.text), [
        'email_login/validate_credentials:test/auth_test.dart',
      ]);
      expect(
        plan.rewrites
            .singleWhere((rewrite) => rewrite.path == 'test/auth_test.dart')
            .text,
        _test('rejects a wrong password'),
      );
    });

    test('a legacy run holding no test name prints no tests line', () async {
      final root = await legacyProject({
        'test/auth_test.dart': _test('rejects a wrong password'),
      });

      final plan = planLegacyRun(
        root,
        templates: TemplateResolver(),
        homeDirectory: null,
        testNamesSince: since,
      );

      expect(plan.toText(), isNot(contains('tests:')));
    });

    test(
      'a legacy run before the release that names tests runs no pass',
      () async {
        final root = await legacyProject({
          'test/auth_test.dart': _test('f01/us01/fr01 rejects'),
        });

        final plan = planLegacyRun(
          root,
          templates: TemplateResolver(),
          homeDirectory: null,
        );

        expect(plan.toText(), isNot(contains('tests:')));
        expect(
          plan.rewrites.map((rewrite) => rewrite.path),
          isNot(contains('test/auth_test.dart')),
        );
      },
    );
  });
}
