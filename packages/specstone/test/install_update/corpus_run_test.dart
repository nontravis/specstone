@TestOn('!windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';
import '../helpers/temp_tree.dart';

const _planHash = 'abc123';

/// One canned finding a fake `check --json` prints.
final class _Canned {
  const new(this.kind, this.path, this.line);

  final String kind;
  final String path;
  final int line;
}

String _checkJson(List<_Canned> findings) => jsonEncode({
  'findings': [
    for (final f in findings)
      {'kind': f.kind, 'path': f.path, 'line': f.line, 'message': 'm'},
  ],
});

/// Writes an executable `sh` script that fakes a built `specstone`.
///
/// [touches] is a file `migrate --yes` creates in the working folder;
/// [failsIfPresent] makes `migrate --dry-run` exit 9 when that file exists;
/// [cwdLog] receives the working folder `--version` runs in.
Future<String> _fakeBinary({
  required String version,
  required List<_Canned> findings,
  int dryRunExit = 0,
  String formatJson = '{"files":[]}',
  int formatExit = 0,
  int? checkExit,
  String? touches,
  String? failsIfPresent,
  String? cwdLog,
}) async {
  final dir = await writeTree({});
  final file = File('${dir.path}/specstone');
  final check = _checkJson(findings);
  final exitOfCheck = checkExit ?? (findings.isEmpty ? 0 : 1);
  final guard = failsIfPresent == null
      ? ''
      : '[ -e "$failsIfPresent" ] && exit 9; ';
  final touch = touches == null ? '' : '; touch "$touches"';
  final pwdLine = cwdLog == null ? '' : '; pwd > "$cwdLog"';
  file.writeAsStringSync('''
#!/bin/sh
case "\$1 \$2" in
  "--version ") echo "$version"$pwdLine ;;
  "migrate --dry-run") ${guard}echo "plan $_planHash"; echo "dry run: nothing written"; exit $dryRunExit ;;
  "migrate --yes") [ "\$3 \$4" = "--plan $_planHash" ] || exit 3$touch ;;
  "format --json") echo '$formatJson'; exit $formatExit ;;
  "check --json") echo '$check'; exit $exitOfCheck ;;
  *) exit 4 ;;
esac
''');
  await Process.run('chmod', ['+x', file.path]);
  return file.path;
}

Future<String> _fixtureProject() async {
  final dir = await writeTree({'docs/a.md': '# a\n'});
  for (final args in [
    ['init', '-q'],
    ['add', '-A'],
    [
      '-c',
      'user.name=t',
      '-c',
      'user.email=t@localhost',
      'commit',
      '-q',
      '-m',
      'snapshot',
    ],
  ]) {
    final r = await Process.run('git', args, workingDirectory: dir.path);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }
  return dir.path;
}

Future<ProcessResult> _run({
  required String project,
  required String oldBinary,
  required String newBinary,
  required String out,
  String? workingDirectory,
}) => Process.run(Platform.resolvedExecutable, [
  'run',
  '${repoRoot().path}/tool/corpus_run.dart',
  '--project',
  project,
  '--ref',
  'HEAD',
  '--old',
  oldBinary,
  '--new',
  newBinary,
  '--out',
  out,
], workingDirectory: workingDirectory ?? repoRoot().path);

String _basename(String path) => path.split('/').last;

void main() {
  const timeout = Timeout(Duration(minutes: 2));

  // D9
  test(
    'the same findings on both builds give exit 0 and no diff line',
    () async {
      final project = await _fixtureProject();
      const findings = [_Canned('required_section_missing', 'docs/a.md', 3)];
      final out = '${(await writeTree({})).path}/diff.txt';
      final r = await _run(
        project: project,
        oldBinary: await _fakeBinary(version: '2.0.0', findings: findings),
        newBinary: await _fakeBinary(version: '2.1.0', findings: findings),
        out: out,
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final lines = File(out).readAsLinesSync();
      expect(lines, hasLength(3));
      expect(lines[0], startsWith('old: '));
      expect(lines[0], endsWith(' 2.0.0'));
      expect(lines[1], startsWith('new: '));
      expect(lines[1], endsWith(' 2.1.0'));
      expect(lines[2], 'ref: HEAD');
    },
    timeout: timeout,
  );

  // D9
  test('a finding only the new build holds is a + line and exit 1, '
      'one only the old build holds is a - line', () async {
    final project = await _fixtureProject();
    final out = '${(await writeTree({})).path}/diff.txt';
    final r = await _run(
      project: project,
      oldBinary: await _fakeBinary(
        version: '2.0.0',
        findings: const [
          _Canned('format_drift', 'docs/a.md', 1),
          _Canned('required_section_missing', 'docs/a.md', 3),
        ],
      ),
      newBinary: await _fakeBinary(
        version: '2.1.0',
        findings: const [
          _Canned('required_section_missing', 'docs/a.md', 3),
          _Canned('template_text_left', 'docs/a.md', 7),
        ],
      ),
      out: out,
    );
    expect(r.exitCode, 1, reason: '${r.stderr}');
    final lines = File(out).readAsLinesSync().skip(3).toList();
    expect(lines, [
      '+ template_text_left docs/a.md:7',
      '- format_drift docs/a.md:1',
    ]);
  }, timeout: timeout);

  // D9
  test('a doc format refuses is a format_refused key, '
      'not a broken run', () async {
    final project = await _fixtureProject();
    final out = '${(await writeTree({})).path}/diff.txt';
    final r = await _run(
      project: project,
      oldBinary: await _fakeBinary(version: '2.0.0', findings: const []),
      newBinary: await _fakeBinary(
        version: '2.1.0',
        findings: const [],
        formatExit: 1,
        formatJson:
            '{"files":[{"path":"docs/a.md","status":"refused"},'
            '{"path":"docs/b.md","status":"unchanged"}]}',
      ),
      out: out,
    );
    expect(r.exitCode, 1, reason: '${r.stderr}');
    expect(File(out).readAsLinesSync().skip(3), [
      '+ format_refused docs/a.md:0',
    ]);
  }, timeout: timeout);

  // D9, Review Focus 5
  test('a build that refuses migrate is exit 2 naming side and step, '
      'with no out file', () async {
    final project = await _fixtureProject();
    final out = '${(await writeTree({})).path}/diff.txt';
    final r = await _run(
      project: project,
      oldBinary: await _fakeBinary(
        version: '2.0.0',
        findings: const [],
        dryRunExit: 70,
      ),
      newBinary: await _fakeBinary(version: '2.1.0', findings: const []),
      out: out,
    );
    expect(r.exitCode, 2);
    expect(r.stderr, allOf(contains('old'), contains('migrate')));
    expect(File(out).existsSync(), isFalse);
  }, timeout: timeout);

  // D9
  test('relative project, binaries, and out resolve against the working '
      'folder the run starts in', () async {
    final project = await _fixtureProject();
    final oldBinary = await _fakeBinary(version: '2.0.0', findings: const []);
    final newBinary = await _fakeBinary(version: '2.1.0', findings: const []);
    final outDir = await writeTree({});
    final base = File(project).parent.path;
    String rel(String path) => path.substring(base.length + 1);
    final r = await _run(
      project: rel(project),
      oldBinary: rel(oldBinary),
      newBinary: rel(newBinary),
      out: rel('${outDir.path}/diff.txt'),
      workingDirectory: base,
    );
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(File('${outDir.path}/diff.txt').existsSync(), isTrue);
  }, timeout: timeout);

  // D9
  test('a binary that does not exist is exit 2 naming the side and step, '
      'with no out file', () async {
    final project = await _fixtureProject();
    final out = '${(await writeTree({})).path}/diff.txt';
    final r = await _run(
      project: project,
      oldBinary: await _fakeBinary(version: '2.0.0', findings: const []),
      newBinary: '${(await writeTree({})).path}/missing',
      out: out,
    );
    expect(r.exitCode, 2);
    expect(r.stderr, allOf(contains('new'), contains('--version')));
    expect(r.stderr, isNot(contains('Unhandled')));
    expect(File(out).existsSync(), isFalse);
  }, timeout: timeout);

  // D9
  test('a check exit above 1 is exit 2 naming the step', () async {
    final project = await _fixtureProject();
    final out = '${(await writeTree({})).path}/diff.txt';
    final r = await _run(
      project: project,
      oldBinary: await _fakeBinary(version: '2.0.0', findings: const []),
      newBinary: await _fakeBinary(
        version: '2.1.0',
        findings: const [],
        checkExit: 2,
      ),
      out: out,
    );
    expect(r.exitCode, 2);
    expect(r.stderr, allOf(contains('new'), contains('check')));
    expect(File(out).existsSync(), isFalse);
  }, timeout: timeout);

  // D9
  test('a stale out file does not survive a broken run', () async {
    final project = await _fixtureProject();
    final out = File('${(await writeTree({})).path}/diff.txt')
      ..writeAsStringSync('stale');
    final r = await _run(
      project: project,
      oldBinary: await _fakeBinary(
        version: '2.0.0',
        findings: const [],
        dryRunExit: 70,
      ),
      newBinary: await _fakeBinary(version: '2.1.0', findings: const []),
      out: out.path,
    );
    expect(r.exitCode, 2);
    expect(out.existsSync(), isFalse);
  }, timeout: timeout);

  // D9
  test('each build runs on its own copy: the old build write is never '
      'seen by the new build or the real project, and the copies are '
      'removed', () async {
    final project = await _fixtureProject();
    final logs = await writeTree({});
    final oldCwd = '${logs.path}/old.cwd';
    final newCwd = '${logs.path}/new.cwd';
    final out = '${logs.path}/diff.txt';
    final r = await _run(
      project: project,
      oldBinary: await _fakeBinary(
        version: '2.0.0',
        findings: const [],
        touches: 'MARK',
        cwdLog: oldCwd,
      ),
      newBinary: await _fakeBinary(
        version: '2.1.0',
        findings: const [],
        failsIfPresent: 'MARK',
        cwdLog: newCwd,
      ),
      out: out,
    );
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final oldWork = File(oldCwd).readAsStringSync().trim();
    final newWork = File(newCwd).readAsStringSync().trim();
    expect(oldWork, isNot(newWork));
    expect(_basename(oldWork), 'old');
    expect(_basename(newWork), 'new');
    expect(Directory(oldWork).existsSync(), isFalse);
    expect(Directory(newWork).existsSync(), isFalse);
    expect(File('$project/MARK').existsSync(), isFalse);
    final status = await Process.run('git', [
      'status',
      '--porcelain',
    ], workingDirectory: project);
    expect(status.stdout, isEmpty);
  }, timeout: timeout);
}
