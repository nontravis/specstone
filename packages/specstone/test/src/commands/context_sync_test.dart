import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:specstone_core/src/consistency_check/models/file_fingerprint.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart';
import '../../../../specstone_core/test/helpers/target_fixture.dart';

import '../../helpers/read_fixture.dart';

/// Returns the `error` object `--json` writes to [err].
Map<String, Object?> _errorOf(StringBuffer err) =>
    (jsonDecode(err.toString()) as Map<String, Object?>)['error']!
        as Map<String, Object?>;

/// Runs `context` with [args] on a fresh project, expects exit 64 with no
/// reports folder, and returns the `error` object.
Future<Map<String, Object?>> _refused(List<String> args) async {
  final project = await writeReadProject(extra: {'app/lib/main.dart': ''});
  final (:runner, :out, :err) = readRunner(project);
  expect(await runner.run(['context', ...args, '--json']), 64);
  expect(Directory('${project.path}/.specstone/reports').existsSync(), isFalse);
  return _errorOf(err);
}

/// One stdout line of the sync index.
final class _GroupLine {
  const new(this.scope, this.route, this.file);

  final String scope;
  final String route;
  final String file;
}

List<_GroupLine> _groupLines(StringBuffer out) => [
  for (final line in out.toString().trimRight().split('\n'))
    switch (line.split(' · ')) {
      [final scope, final route, final file] => _GroupLine(scope, route, file),
      _ => throw StateError('not a group line: $line'),
    },
];

/// Changes the code the login record and the architecture doc point at.
void _changeLogin(Directory project) =>
    File('${project.path}/app/lib/login.dart')
        .writeAsStringSync('int changed = 1;\n', mode: FileMode.append);

/// Writes the two-target project whose records both name the flutter code's
/// fingerprint, so only the jaspr record reads as changed.
Future<Directory> _twinProjectWithJasprChanged() async {
  final project = await writeTwinProject();
  final flutterText = File('${project.path}/flutter_ws/app/lib/login.dart')
      .readAsStringSync();
  final fingerprint = fileCodeFingerprint(
    utf8.encode(flutterText),
    path: 'app/lib/login.dart',
  );
  final entry =
      'email_login/check_password:app/lib/login.dart:checkPassword '
      '$fingerprint';
  final folder = folderCodeFingerprint([
    FileFingerprint(path: 'app/lib/login.dart', fingerprint: fingerprint),
  ]);
  for (final target in ['flutter', 'jaspr']) {
    File(
        '${project.path}/.specstone/records/$target/f01_login/IMPLEMENTATION.md',
      )
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "---\nstatuses:\n  - 'email_login/check_password:implemented'\n"
        "implements:\n  - '$entry'\n"
        'covers:\n  - app/lib/ $folder\n---\n\n# Record\n',
      );
  }
  return project;
}

void main() {
  test(
    '--for sync with no --out is argument_missing and names --out',
    () async {
      final error = await _refused(['login', '--for', 'sync']);
      expect(error['code'], 'argument_missing');
      expect(
        error['message'],
        'context needs --out, such as specstone context --for sync --out',
      );
    },
  );

  test('--for sync with --out <path> is argument_invalid', () async {
    final error = await _refused([
      'login',
      '--for',
      'sync',
      '--out',
      'sync.txt',
    ]);
    expect(error['code'], 'argument_invalid');
  });

  test('--for sync with two targets is argument_invalid', () async {
    final error = await _refused([
      'login',
      'login/email_login',
      '--for',
      'sync',
      '--out',
    ]);
    expect(error['code'], 'argument_invalid');
  });

  test('--for sync with a story target is argument_invalid', () async {
    final error = await _refused([
      'login/email_login',
      '--for',
      'sync',
      '--out',
    ]);
    expect(error['code'], 'argument_invalid');
  });

  test('--for sync with a spec doc target is argument_invalid', () async {
    final error = await _refused([
      'architecture:login',
      '--for',
      'sync',
      '--out',
    ]);
    expect(error['code'], 'argument_invalid');
  });

  test('--for sync with --no-project is argument_conflict', () async {
    final error = await _refused([
      'login',
      '--for',
      'sync',
      '--out',
      '--no-project',
    ]);
    expect(error['code'], 'argument_conflict');
  });

  test('--for sync with --budget is argument_conflict', () async {
    final error = await _refused([
      'login',
      '--for',
      'sync',
      '--out',
      '--budget',
      '5',
    ]);
    expect(error['code'], 'argument_conflict');
  });

  test('--for sync with --code is argument_conflict', () async {
    final error = await _refused([
      '--code',
      'app/lib/main.dart',
      '--for',
      'sync',
      '--out',
    ]);
    expect(error['code'], 'argument_conflict');
  });

  test('--for sync with --summary is argument_conflict', () async {
    final error = await _refused([
      'login',
      '--for',
      'sync',
      '--out',
      '--summary',
    ]);
    expect(error['code'], 'argument_conflict');
  });

  test('--for sync on a project with no changed code says so', () async {
    final project = await writeCheckProject();
    final (:runner, :out, :err) = readRunner(project);

    expect(await runner.run(['context', '--for', 'sync', '--out']), 0);

    expect(out.toString(), 'no code changed since its docs were compared\n');
    expect(
      Directory('${project.path}/.specstone/reports').existsSync(),
      isFalse,
    );
  });

  test('--for sync lists each group with its route and file', () async {
    final project = await writeCheckProject();
    _changeLogin(project);
    final (:runner, :out, :err) = readRunner(project);

    expect(await runner.run(['context', '--for', 'sync', '--out']), 0);

    final [group] = _groupLines(out);
    expect(group.scope, 'feature:login');
    expect(group.route, 'engineer');
    expect(File(group.file).isAbsolute, isTrue);
    expect(File(group.file).existsSync(), isTrue);
    expect(
      File(group.file).parent.path,
      endsWith('.specstone${Platform.pathSeparator}reports'),
    );
    expect(group.file, endsWith('feature-login.sync.txt'));
  });

  test('--for sync --json gives the same groups as one object', () async {
    final project = await writeCheckProject();
    _changeLogin(project);
    final (:runner, :out, :err) = readRunner(project);
    expect(await runner.run(['context', '--for', 'sync', '--out']), 0);
    final [text] = _groupLines(out);
    final (runner: jsonRunner, out: jsonOut, err: _) = readRunner(project);

    expect(
      await jsonRunner.run(['context', '--for', 'sync', '--out', '--json']),
      0,
    );

    final groups =
        (jsonDecode(jsonOut.toString()) as Map<String, Object?>)['groups']!
            as List<Object?>;
    expect(groups, [
      {'scope': text.scope, 'route': text.route, 'out': text.file},
    ]);
  });

  test('--for sync with a feature lists its group when unchanged', () async {
    final project = await writeCheckProject();
    final (:runner, :out, :err) = readRunner(project);

    expect(await runner.run(['context', 'login', '--for', 'sync', '--out']), 0);

    final [group] = _groupLines(out);
    expect(group.scope, 'feature:login');
    expect(File(group.file).existsSync(), isTrue);
  });

  test("--for sync --target keeps only that target's work", () async {
    final project = await _twinProjectWithJasprChanged();
    final (:runner, :out, :err) = readRunner(project);
    expect(
      await runner.run([
        'context',
        '--for',
        'sync',
        '--out',
        '--target',
        'flutter',
      ]),
      0,
    );
    expect(out.toString(), 'no code changed since its docs were compared\n');
    final (runner: jasprRunner, out: jasprOut, err: _) = readRunner(project);

    expect(
      await jasprRunner.run([
        'context',
        '--for',
        'sync',
        '--out',
        '--target',
        'jaspr',
      ]),
      0,
    );

    final [group] = _groupLines(jasprOut);
    expect(group.scope, 'feature:login');
    expect(group.file, endsWith('feature-login.sync.jaspr.txt'));
  });

  test('--for nope is argument_invalid and names the five modes', () async {
    final (:runner, :out, :err) = readRunner(await writeReadProject());
    expect(
      await runner.run(['context', 'login', '--for', 'nope', '--json']),
      64,
    );
    final error = _errorOf(err);
    expect(error['code'], 'argument_invalid');
    expect(
      error['message'],
      '--for takes query, implement, design, sync, or review, not nope',
    );
    expect(error['message'], contains('review'));
  });
}
