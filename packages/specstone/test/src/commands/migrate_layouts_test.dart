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

/// Every file under [root] outside a `.git` folder, by its `/`-separated path
/// relative to [root], with its bytes.
Map<String, List<int>> _bytesUnder(Directory root) {
  final prefix = root.path.replaceAll(r'\', '/').length + 1;
  return {
    for (final entity in root.listSync(recursive: true, followLinks: false))
      if (entity is File && !_inGitFolder(entity.path))
        entity.path.replaceAll(r'\', '/').substring(prefix): entity
            .readAsBytesSync(),
  };
}

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
        path: finding['path']! as String,
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

  test('flat, as Specstone', () async {
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

  test('grouped modules, as brick_dartfrog', () async {
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
    expect(onDisk, hasLength(9));
    expect(tracked, hasLength(onDisk.length));
  }, skip: skip);

  test('containers, as stratum_ui', () async {
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

  test('a grouped tree: commit 2 holds the record coverage list, the '
      'project configuration, the ignore file, and the agent files', () async {
    final (root, _) = await _layout({
      ...containerLegacy,
      _context: '# D-01 — Context\n',
      'docs/specs/INDEX.md':
          '# Spec index\n\n## Spec map\n\n'
          '| Code path | Spec path | feature_id | cross-cutting | Notes |\n'
          '|---|---|---|---|---|\n'
          '| `ui/slot/` | `specs/ui/slot/` | `co01_01_slot` | — | slot |\n',
      'docs/specs/ui/slot/s01_architecture.md':
          '---\nname: Slot architecture\nfeature_id: co01_01_slot\n---\n\n'
          '# S-01 — Slot architecture\n',
    });
    const record = 'docs/specs/utilities/f01_slot/IMPLEMENTATION.md';

    final committed =
        (git(root, ['show', '--name-only', '--format=', 'HEAD']).stdout
                as String)
            .trim()
            .split('\n');
    expect(
      committed,
      containsAll([
        record,
        '.specstone/config.yaml',
        '.specstone/.gitignore',
        '.specstone/AGENT.md',
        'AGENTS.md',
      ]),
    );
    expect(
      File('${root.path}/$record').readAsStringSync(),
      contains('covers:\n  - ui/slot/\n'),
    );
    expect(
      File('${root.path}/docs/specs/utilities/f01_slot/ARCHITECTURE.md')
          .readAsStringSync(),
      isNot(contains('covers:')),
    );
  }, skip: skip);

  group('specEdgeLegacy', () {
    test('pre-renumber spec numbers', () async {
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
      expect(untyped, contains('specs/f02_billing/DOMAIN.md'));
      expect(untyped, contains('specs/f02_billing/ERROR.md'));
    }, skip: skip);

    test('cross-cutting folders and a legacy topic', () async {
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
      expect(_untyped(findings), contains('specs/topics/caching.md'));
    }, skip: skip);

    test('many-to-one files and two of one name', () async {
      final (_, findings) = await _layout(specEdgeLegacy);

      expect(
        _untyped(findings),
        containsAll([
          'specs/f02_billing/billing/s01_architecture.md',
          'specs/f02_billing/billing_ui/s01_architecture.md',
        ]),
      );
    }, skip: skip);

    test('a Global SoT table and its file stay', () async {
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

  test('a nested project migrates in a run of its own', () async {
    final root = await gitFixture(nestedLegacy);
    final app = Directory('${root.path}/example-app');

    final beforeRoot = _bytesUnder(root);
    await _migrate(app, repo: root);
    final afterApp = _bytesUnder(root);
    for (final path in {...beforeRoot.keys, ...afterApp.keys}) {
      if (!path.startsWith('example-app/')) {
        expect(afterApp[path], beforeRoot[path], reason: path);
      }
    }
    expect(Directory('${app.path}/.specstone').existsSync(), isTrue);

    final beforeApp = <String, List<int>>{
      for (final e in afterApp.entries)
        if (e.key.startsWith('example-app/')) e.key: e.value,
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
  }, skip: skip);

  test("a feature doc's code pointers stay and check lists them", () async {
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
        (f) => f.kind == 'field_undeclared' && f.message.contains('implements'),
      ),
      isTrue,
    );
  }, skip: skip);

  test('a requirement with no scenario trace gets no fingerprint '
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

  test('a first fingerprint is clean to check', () async {
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
|---|---|
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

  test('a nested project behind a docs link that leaves its folder migrates '
      'after trust, and the outer project stays as it was', () async {
    final root = await gitFixture({
      for (final e in acmeLegacy.entries) 'example/${e.key}': e.value,
      'example/.specstone/config.yaml': 'packs:\n  prd-core: 1.0.0\n',
      'stratum_ui/.specstone/config.yaml': 'packs:\n  prd-core: 1.0.0\n',
      'stratum_ui/example/.keep': '',
    });
    final nested = Directory('${root.path}/stratum_ui/example');
    try {
      createRelativeLink('${nested.path}/docs', '../../example/docs');
    } on FileSystemException {
      markTestSkipped('this machine cannot create a link');
      return;
    }
    commitAll(root, 'link docs');
    int commits() => int.parse(
      (git(root, ['rev-list', '--count', 'HEAD']).stdout as String).trim(),
    );
    final outerBefore = _bytesUnder(Directory('${root.path}/stratum_ui'))
      ..remove('example/docs');
    final before = commits();

    final refused = await _run(nested, ['migrate'], console: _owner());
    expect(refused.status, 73, reason: refused.err);
    expect(commits(), before);
    final trusted = await _run(nested, ['trust'], console: _owner());
    expect(trusted.status, 0, reason: trusted.err);

    final run = await _run(nested, ['migrate'], console: _owner());

    expect(run.status, 0, reason: run.err);
    expect(commits(), before + 2);
    expect(
      File('${root.path}/example/.specstone/config.yaml').existsSync(),
      isTrue,
    );
    final outerAfter = _bytesUnder(Directory('${root.path}/stratum_ui'))
      ..remove('example/docs');
    expect(outerAfter, outerBefore);
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: skip);

  test('a Summary and a Feature goal section the table does not name stay as '
      'written and check lists them', () async {
    const feature = 'docs/prds/features/f01_login/FEATURE.md';
    final (root, findings) = await _layout({
      ...acmeLegacy,
      feature: acmeLegacy[feature]!.replaceFirst(
        '## Feature goal',
        '## Summary\n\nA summary.\n\n## Feature goal',
      ),
    });

    final text = File('${root.path}/$feature').readAsStringSync();
    expect(text, contains('## Summary\n\nA summary.\n\n'));
    expect(text, contains('## Feature goal\n\nLet a user sign in.\n'));
    final undeclared = [
      for (final f in findings)
        if (f.kind == 'section_undeclared' &&
            f.path == 'prds/features/f01_login/FEATURE.md')
          f.message,
    ];
    expect(undeclared, [
      'section Summary is not declared',
      'section Feature goal is not declared',
    ]);
  }, skip: skip);

  test('a number label that names two docs is kept, listed in the plan, and '
      'reported by check as number_label', () async {
    final root = await gitFixture({
      ...acmeLegacy,
      'docs/prds/features/f02_signup/FEATURE.md':
          '---\nname: Signup\n---\n\n# F-02 — Signup\n',
      'docs/prds/features/f02_signup/us01_create/USER_STORY.md':
          '---\nname: Create account\n---\n\n# US-01 — Create account\n',
      'docs/prds/d02_features.md':
          '---\nname: Acme feature index\n---\n\n# D-02 — Feature index\n\n'
          'See US-01 for sign-in and F-01 for login.\n',
    });

    final dry = await _run(root, ['migrate', '--dry-run']);
    expect(dry.status, 0, reason: dry.err);
    expect(dry.out, contains('number labels: '));
    expect(dry.out, contains('; left: 1'));
    await _migrate(root);

    final text = File('${root.path}/docs/prds/FEATURES.md').readAsStringSync();
    expect(text, contains('See US-01 for sign-in and '));
    expect(text, isNot(contains('F-01')));
    final labels = [
      for (final f in await _check(root))
        if (f.kind == 'number_label') f.message,
    ];
    expect(labels, [startsWith('US-01 is a number label')]);
    await _migrateAgain(root);
  }, skip: skip);

  test('a legacy nf that overrides a project NFR gets no kind and check '
      'lists its missing fields', () async {
    const nfPath = 'prds/features/f01_login/us01_email_login/nf01_latency.md';
    final (root, findings) = await _layout({
      ...acmeLegacy,
      'docs/prds/features/f01_login/us01_email_login/'
              'non_functional_requirements/nf01_latency.md':
          '---\nname: Latency\n---\n\n# NF-01 — Latency\n\n## Statement\n\n'
          'This tightens NFR-01: login answers in 300 ms.\n',
    });

    final text = File('${root.path}/docs/$nfPath').readAsStringSync();
    expect(text, isNot(contains('kind:')));
    expect(text, isNot(contains('overrides:')));
    expect(text, isNot(contains('confirmed:')));
    final missing = [
      for (final f in findings)
        if (f.path == nfPath && f.kind == 'required_field_missing') f.message,
    ];
    expect(missing, isNotEmpty);
  }, skip: skip);

  test('docs reached through a link migrate in the repository '
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
    final dryRefused = await _run(code, ['migrate', '--dry-run']);
    expect(dryRefused.status, 73, reason: dryRefused.err);
    expect(dryRefused.out, isEmpty);
    expect(_bytesUnder(docsRepo), docsBefore);

    final refused = await _run(code, ['migrate'], console: _owner());
    expect(refused.status, 73, reason: refused.err);
    expect(_bytesUnder(docsRepo), docsBefore);
    final trusted = await _run(code, ['trust'], console: _owner());
    expect(trusted.status, 0, reason: trusted.err);

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
