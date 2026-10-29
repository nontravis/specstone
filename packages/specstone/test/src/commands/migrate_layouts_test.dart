import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/legacy_fixture.dart';
import '../../../../specstone_core/test/helpers/relative_link.dart';
import '../../helpers/write_runner.dart';

/// One `check --json` finding.
typedef _Finding = ({String kind, String path, String message});

/// Whether [path] has a segment that is exactly `.git`.
bool _inGitFolder(String path) =>
    path.replaceAll(r'\', '/').split('/').contains('.git');

/// Every file under [root] outside a `.git` folder, by path, with its bytes.
Map<String, List<int>> _bytesUnder(Directory root) => {
  for (final entity in root.listSync(recursive: true, followLinks: false))
    if (entity is File && !_inGitFolder(entity.path))
      entity.path: entity.readAsBytesSync(),
};

/// Asserts each of [present] exists and each of [gone] does not, under [root].
void _expectFiles(
  Directory root, {
  List<String> present = const [],
  List<String> gone = const [],
}) {
  for (final path in present) {
    expect(File('${root.path}/$path').existsSync(), isTrue, reason: path);
  }
  for (final path in gone) {
    expect(File('${root.path}/$path').existsSync(), isFalse, reason: path);
  }
}

FakeConsole _owner() =>
    FakeConsole(stdinIsTerminal: true, stdoutIsTerminal: true, answers: ['y']);

/// Runs [args] in [dir] and returns the exit status and the printed text.
Future<({int status, String out, String err})> _run(
  Directory dir,
  List<String> args, {
  FakeConsole? console,
}) async {
  final (:runner, :out, :err) = writeRunner(dir, console: console);
  final status = await runner.run(args);
  return (status: status, out: out.toString(), err: err.toString());
}

/// Runs `check --json` in [dir]; a status other than 0 or 1 is a fault.
Future<List<_Finding>> _check(Directory dir) async {
  final result = await _run(dir, ['check', '--json']);
  expect(result.status, anyOf(0, 1), reason: result.err);
  final json = jsonDecode(result.out) as Map<String, Object?>;
  return [
    for (final finding in json['findings']! as List)
      (
        kind: (finding as Map)['kind']! as String,
        path: finding['docPath']! as String,
        message: finding['message']! as String,
      ),
  ];
}

/// Runs `migrate --dry-run` then `migrate` answering `y` in [dir], and
/// checks the two-commit, clean-tree end state.
Future<void> _migrate(Directory dir, {Directory? repo}) async {
  final before = _bytesUnder(dir);
  final dry = await _run(dir, ['migrate', '--dry-run']);
  expect(dry.status, 0, reason: dry.err);
  expect(dry.out, endsWith('dry run: nothing written\n'));
  expect(_bytesUnder(dir), before);

  final head =
      (git(repo ?? dir, ['rev-list', '--count', 'HEAD']).stdout as String)
          .trim();
  final run = await _run(dir, ['migrate'], console: _owner());
  expect(run.status, 0, reason: run.err);
  final count =
      (git(repo ?? dir, ['rev-list', '--count', 'HEAD']).stdout as String)
          .trim();
  expect(int.parse(count) - int.parse(head), 2);
  expect(git(repo ?? dir, ['status', '--porcelain']).stdout, isEmpty);
}

/// Runs `migrate` again and expects `nothing to migrate`.
Future<void> _migrateAgain(Directory dir) async {
  final again = await _run(dir, ['migrate']);
  expect(again.status, 0, reason: again.err);
  expect(again.out, 'nothing to migrate\n');
}

/// Migrates [files] in a fresh git repository, checks it, migrates again,
/// and returns the project root and its findings.
Future<(Directory, List<_Finding>)> _layout(Map<String, String> files) async {
  final root = await gitFixture(files);
  await _migrate(root);
  final findings = await _check(root);
  await _migrateAgain(root);
  return (root, findings);
}

/// Writes [files] under [path] and commits them in a new git repository.
Future<Directory> _gitRepoAt(String path, Map<String, String> files) async {
  final root = Directory(path)..createSync(recursive: true);
  for (final MapEntry(:key, :value) in files.entries) {
    final file = File('$path/$key');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(value);
  }
  expect(git(root, ['init', '-q']).exitCode, 0);
  expect(git(root, ['config', 'user.name', 't']).exitCode, 0);
  expect(git(root, ['config', 'user.email', 't@t']).exitCode, 0);
  expect(git(root, ['config', 'core.autocrlf', 'false']).exitCode, 0);
  commitAll(root, 'legacy');
  return root;
}

Iterable<String> _untyped(List<_Finding> findings) => [
  for (final f in findings)
    if (f.kind == 'untyped_doc') f.path,
];

const _context = 'docs/prds/d01_context.md';

void main() {
  final skip = hasGit ? null : 'git is not available';

  test('f06/us01/s4: flat, as Specstone', () async {
    final (_, findings) = await _layout(acmeLegacy);

    expect(
      _untyped(findings),
      containsAll([
        'specs/f01_login/s02_api_login.md',
        'specs/f01_login/s02_api_session.md',
        'specs/topics/shared/s01_architecture.md',
        'specs/INDEX.md',
      ]),
    );
    expect(findings.where((f) => f.kind == 'suspect'), isEmpty);
  }, skip: skip);

  test('f06/us01/s5: grouped modules, as brick_dartfrog', () async {
    final (root, findings) = await _layout({
      ...groupedLegacy,
      _context: '# D-01 — Context\n',
    });

    expect(
      File('${root.path}/docs/prds/features/tool_module/f01_stripe/FEATURE.md')
          .existsSync(),
      isTrue,
    );
    expect(
      _untyped(findings),
      isNot(contains('prds/features/tool_module/f01_stripe/FEATURE.md')),
    );
    expect(
      _untyped(findings),
      contains('prds/features/brick_module/README.md'),
    );
    expect(
      File('${root.path}/.specstone/templates/feature.yaml').readAsStringSync(),
      'path: prds/features/{slug}/f{nn}_{slug}/FEATURE.md\n',
    );
    final onDisk = [
      for (final f in Directory('${root.path}/.specstone/templates').listSync())
        if (f is File && !f.path.endsWith('gnfr.yaml')) f.path,
    ];
    final tracked =
        (git(root, ['ls-files', '.specstone/templates']).stdout as String)
            .trim()
            .split('\n')
            .where((path) => !path.endsWith('gnfr.yaml'));
    expect(onDisk, hasLength(10));
    expect(tracked, hasLength(onDisk.length));
  }, skip: skip);

  test('f06/us01/fr03/e06: containers, as stratum_ui', () async {
    final (root, findings) = await _layout({
      ...containerLegacy,
      _context: '# D-01 — Context\n',
    });

    _expectFiles(
      root,
      present: [
        'docs/prds/features/utilities/FEATURE.md',
        'docs/prds/features/utilities/f01_slot/FEATURE.md',
      ],
      gone: [
        'docs/prds/features/components/co01_utilities/FEATURE.md',
        'docs/prds/features/components/co01_utilities/co01_01_slot/FEATURE.md',
      ],
    );

    final untyped = _untyped(findings);
    expect(untyped, contains('prds/features/utilities/FEATURE.md'));
    expect(
      untyped,
      isNot(contains('prds/features/utilities/f01_slot/FEATURE.md')),
    );
  }, skip: skip);

  group('specEdgeLegacy', () {
    test('f06/us01/fr03/e08: pre-renumber spec numbers', () async {
      final (root, findings) = await _layout(specEdgeLegacy);

      _expectFiles(
        root,
        present: [
          'docs/specs/f02_billing/DOMAIN.md',
          'docs/specs/f02_billing/ERROR.md',
          'docs/specs/api/billing/s07_sequence.md',
        ],
        gone: [
          'docs/specs/api/billing/s04_domain.md',
          'docs/specs/api/billing/s02_errors.md',
        ],
      );
      final untyped = _untyped(findings);
      expect(untyped, contains('specs/api/billing/s07_sequence.md'));
      expect(untyped, isNot(contains('specs/f02_billing/DOMAIN.md')));
      expect(untyped, isNot(contains('specs/f02_billing/ERROR.md')));
    }, skip: skip);

    test(
      'f06/us01/fr03/e12: cross-cutting folders and a legacy topic',
      () async {
        final (root, findings) = await _layout(specEdgeLegacy);

        final topic = File('${root.path}/docs/specs/topics/caching.md');
        expect(topic.existsSync(), isTrue);
        expect(
          topic.readAsStringSync(),
          allOf(
            contains('covers:'),
            contains('api/auth/'),
            contains('api/billing/'),
            isNot(contains('applies_to')),
          ),
        );
        expect(
          File('${root.path}/docs/specs/architecture/caching.schema.json')
              .existsSync(),
          isTrue,
        );
        expect(_untyped(findings), isNot(contains('specs/topics/caching.md')));
      },
      skip: skip,
    );

    test('f06/us01/fr03/e11: many-to-one files and two of one name', () async {
      final (_, findings) = await _layout(specEdgeLegacy);

      expect(
        _untyped(findings),
        containsAll([
          'specs/f02_billing/billing/s01_architecture.md',
          'specs/f02_billing/billing_ui/s01_architecture.md',
        ]),
      );
    }, skip: skip);

    test('f06/us01/fr03/e13: a Global SoT table and its file stay', () async {
      final root = await gitFixture(specEdgeLegacy);
      final index = specEdgeLegacy['docs/specs/INDEX.md']!;

      await _migrate(root);

      expect(
        File('${root.path}/docs/specs/schema.dbml').readAsStringSync(),
        'Table t {}\n',
      );
      expect(
        File('${root.path}/docs/specs/INDEX.md').readAsStringSync(),
        index,
      );
      await _check(root);
      await _migrateAgain(root);
    }, skip: skip);
  });

  test(
    'f06/us01/fr01/e05: a nested project migrates in a run of its own',
    () async {
      final root = await gitFixture(nestedLegacy);
      final app = Directory('${root.path}/example-app');

      final beforeRoot = _bytesUnder(root);
      await _migrate(app, repo: root);
      final afterApp = _bytesUnder(root);
      for (final path in {...beforeRoot.keys, ...afterApp.keys}) {
        if (!path.startsWith('${app.path}${Platform.pathSeparator}')) {
          expect(afterApp[path], beforeRoot[path], reason: path);
        }
      }
      expect(Directory('${app.path}/.specstone').existsSync(), isTrue);

      final beforeApp = <String, List<int>>{
        for (final e in afterApp.entries)
          if (e.key.startsWith('${app.path}${Platform.pathSeparator}'))
            e.key: e.value,
      };
      await _migrate(root);
      final afterRoot = _bytesUnder(root);
      for (final entry in beforeApp.entries) {
        expect(afterRoot[entry.key], entry.value, reason: entry.key);
      }
      expect(Directory('${root.path}/.specstone').existsSync(), isTrue);
      await _check(app);
      await _check(root);
      await _migrateAgain(app);
      await _migrateAgain(root);
    },
    skip: skip,
  );

  test(
    "f06/us01/s6: a feature doc's code pointers stay and check lists them",
    () async {
      final files = {
        ...acmeLegacy,
        'docs/prds/features/f01_login/FEATURE.md':
            acmeLegacy['docs/prds/features/f01_login/FEATURE.md']!.replaceFirst(
              'name: Login\n',
              'name: Login\nimplements:\n  - lib/login.dart\n',
            ),
      };

      final (root, findings) = await _layout(files);

      expect(
        File('${root.path}/docs/prds/features/f01_login/FEATURE.md')
            .readAsStringSync(),
        contains('implements:'),
      );
      expect(
        findings.any(
          (f) =>
              f.kind == 'field_undeclared' && f.message.contains('implements'),
        ),
        isTrue,
      );
    },
    skip: skip,
  );

  test('f06/us01/s7: a requirement with no scenario trace gets no fingerprint '
      'and check lists the missing field', () async {
    final (_, findings) = await _layout(acmeLegacy);

    final missing = findings.where(
      (f) =>
          f.kind == 'required_field_missing' &&
          f.path.endsWith('validate_credentials.md') &&
          f.message.contains('traced_from'),
    );
    expect(missing, isNotEmpty);
    expect(findings.where((f) => f.kind == 'unconfirmed'), isEmpty);
  }, skip: skip);

  test('f06/us01/fr06/e01: a first fingerprint is clean to check', () async {
    final files = {
      for (final e in acmeLegacy.entries)
        if (!e.key.contains('s02_api_')) e.key: e.value,
      'docs/specs/api/auth/s02_api_login.md': '''
---
name: Login API
---

# S-02 — Login API

## FR trace

| FR id | Method |
|-------|--------|
| `us01/fr01_validate_credentials` | POST /login |
''',
    };

    final (root, findings) = await _layout(files);

    final api = File('${root.path}/docs/specs/f01_login/API.md');
    expect(api.existsSync(), isTrue);
    expect(
      api.readAsStringSync(),
      matches(
        RegExp(
          r'^confirmed:\n  - email_login/validate_credentials [0-9a-f]{12}$',
          multiLine: true,
        ),
      ),
    );
    expect(findings.where((f) => f.kind == 'suspect'), isEmpty);
    expect(
      findings.where(
        (f) =>
            f.kind == 'unconfirmed' &&
            f.message.contains('validate_credentials'),
      ),
      isEmpty,
    );
  }, skip: skip);

  test('f06/us01/s10: docs reached through a link migrate in the repository '
      'that holds them', () async {
    final parent = await Directory.systemTemp.createTemp('specstone_link_');
    addTearDown(() => parent.delete(recursive: true));
    final docsRepo = await _gitRepoAt('${parent.path}/docsrepo', acmeLegacy);
    final code = await _gitRepoAt('${parent.path}/code', {
      'src/main.dart': 'void main() {}\n',
    });
    try {
      createRelativeLink('${code.path}/docs', '../docsrepo/docs');
    } on FileSystemException {
      markTestSkipped('this machine cannot create a link');
      return;
    }
    commitAll(code, 'link docs');
    int commits(Directory repo) => int.parse(
      (git(repo, ['rev-list', '--count', 'HEAD']).stdout as String).trim(),
    );
    final codeCommits = commits(code);
    final docsCommits = commits(docsRepo);

    final before = _bytesUnder(code);
    final docsBefore = _bytesUnder(docsRepo);
    final dry = await _run(code, ['migrate', '--dry-run']);
    expect(dry.status, 0, reason: dry.err);
    expect(_bytesUnder(code), before);
    expect(_bytesUnder(docsRepo), docsBefore);

    final run = await _run(code, ['migrate'], console: _owner());

    expect(run.status, 0, reason: run.err);
    expect(commits(docsRepo), docsCommits + 2);
    expect(
      File('${docsRepo.path}/.specstone/config.yaml').existsSync(),
      isTrue,
    );
    expect(git(docsRepo, ['status', '--porcelain']).stdout, isEmpty);
    expect(commits(code), codeCommits);
    expect(git(code, ['status', '--porcelain']).stdout, isEmpty);
    expect(Directory('${code.path}/.specstone').existsSync(), isFalse);

    final findings = await _check(docsRepo);
    expect(findings.where((f) => f.kind == 'suspect'), isEmpty);
    await _migrateAgain(docsRepo);
  }, skip: skip);
}
