import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/git_repo.dart';
import '../../../../specstone_core/test/helpers/legacy_fixture.dart';
import '../../../../specstone_core/test/helpers/relative_link.dart';
import '../../../../specstone_core/test/helpers/shipped_pins.dart';
import '../../../../specstone_core/test/helpers/upgrade_fixture.dart';
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
  commitAll(root, 'docs');
  return root;
}

void main() {
  final skip = hasGit ? null : 'git is not available';

  test('a nested project migrates in a run of its own', () async {
    acmeInTestHome();
    final root = await gitFixture({
      ...upgradeFiles(),
      for (final MapEntry(:key, :value) in upgradeFiles().entries)
        'example-app/$key': value,
    });
    final app = Directory('${root.path}/example-app');

    final beforeRoot = _bytesUnder(root);
    await _migrate(app, repo: root);
    final afterApp = _bytesUnder(root);
    for (final path in {...beforeRoot.keys, ...afterApp.keys}) {
      if (!path.startsWith('example-app/')) {
        expect(afterApp[path], beforeRoot[path], reason: path);
      }
    }
    expect(
      File('${app.path}/.specstone/config.yaml').readAsStringSync(),
      contains('acme: 1.1.0'),
    );

    final beforeApp = <String, List<int>>{
      for (final e in afterApp.entries)
        if (e.key.startsWith('example-app/')) e.key: e.value,
    };
    await _migrate(root);
    final afterRoot = _bytesUnder(root);
    for (final entry in beforeApp.entries) {
      expect(afterRoot[entry.key], entry.value, reason: entry.key);
    }
    expect(
      File('${root.path}/.specstone/config.yaml').readAsStringSync(),
      contains('acme: 1.1.0'),
    );
    await _check(app);
    await _check(root);
    await _migrateAgain(app);
    await _migrateAgain(root);
  }, skip: skip);

  test('a nested project behind a docs link that leaves its folder migrates '
      'after trust, and the outer project stays as it was', () async {
    acmeInTestHome();
    final root = await gitFixture({
      for (final e in upgradeFiles().entries) 'example/${e.key}': e.value,
      'stratum_ui/.specstone/config.yaml': shippedPinsConfig(),
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
      File('${root.path}/example/.specstone/config.yaml').readAsStringSync(),
      contains('acme: 1.1.0'),
    );
    final outerAfter = _bytesUnder(Directory('${root.path}/stratum_ui'))
      ..remove('example/docs');
    expect(outerAfter, outerBefore);
    expect(git(root, ['status', '--porcelain']).stdout, isEmpty);
  }, skip: skip);

  test('docs reached through a link migrate in the repository '
      'that holds them', () async {
    final parent = await Directory.systemTemp.createTemp('specstone_link_');
    addTearDown(() => parent.delete(recursive: true));
    acmeInTestHome();
    final docsRepo = await _gitRepoAt(
      '${parent.path}/docsrepo',
      upgradeFiles(),
    );
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
      File('${docsRepo.path}/.specstone/config.yaml').readAsStringSync(),
      contains('acme: 1.1.0'),
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
