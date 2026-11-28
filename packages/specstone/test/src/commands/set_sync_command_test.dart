// Test names are matrix literals, so long names stay whole.
// ignore_for_file: lines_longer_than_80_chars

@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/console.dart';
import 'package:specstone_core/src/consistency_check/code_fingerprint.dart';
import 'package:test/test.dart';

import '../../../../specstone_core/test/helpers/check_fixture.dart' as check;
import '../../../../specstone_core/test/helpers/write_fixture.dart';
import '../../helpers/built_cli.dart';
import '../../helpers/write_runner.dart';

const _conflictMessage =
    '--sync takes no doc address, --base, --field, --title, --batch, '
    '--stamp, --remove-task, or --replace';

/// A console that counts how often a command reads stdin.
final class _CountingConsole implements Console {
  int reads = 0;

  @override
  bool get stdinIsTerminal => false;

  @override
  bool get stdoutIsTerminal => false;

  @override
  bool get stderrIsTerminal => false;

  @override
  bool get noColor => false;

  @override
  String? get approveModeVariable => null;

  @override
  Future<String> readAll() async {
    reads++;
    return '';
  }

  @override
  String? readLine() => null;
}

Map<String, Object?> _error(StringBuffer text) =>
    (jsonDecode(text.toString()) as Map<String, Object?>)['error']!
        as Map<String, Object?>;

void main() {
  late Directory scratch;

  setUp(() => scratch = Directory.systemTemp.createTempSync('set_sync_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  /// Writes [text] to a sync file in [scratch] and returns its path.
  String syncFile(String text) {
    final file = File('${scratch.path}/sync.txt')..writeAsStringSync(text);
    return file.path;
  }

  test('each input beside --sync exits 64 as argument_conflict naming --sync and every input, inside and outside a project, and reads no stdin', () async {
    final inside = await writeWriteProject();
    final file = syncFile('? login a.dart:f 0123456789ab\n');
    for (final root in [inside, scratch]) {
      for (final beside in [
        ['architecture:login'],
        ['--base', 'e3b0c44298fc'],
        ['--field', 'tasks'],
        ['--title'],
        ['--batch', file],
        ['--stamp', 'a.dart:f=0123456789ab'],
        ['--remove-task', 'ENG-42'],
        ['--replace'],
      ]) {
        final console = _CountingConsole();
        final (:runner, :out, :err) = writeRunner(root, console: console);

        expect(
          await runner.run(['set', '--sync', file, ...beside]),
          64,
          reason: '${root.path} $beside',
        );

        expect(err.toString(), '$_conflictMessage\n', reason: '$beside');
        expect(out.toString(), isEmpty, reason: '$beside');
        expect(console.reads, 0, reason: '$beside');
      }
    }
  });

  test(
    '--sync beside --json reports argument_conflict in the error envelope',
    () async {
      final file = syncFile('');
      final (:runner, :out, :err) = writeRunner(scratch);

      expect(
        await runner.run(['set', '--sync', file, '--field', 'tasks', '--json']),
        64,
      );

      expect(out.toString(), isEmpty);
      expect(_error(err), {
        'code': 'argument_conflict',
        'message': _conflictMessage,
      });
    },
  );

  test('a missing path or a folder exits 64 as argument_invalid outside a project, as --batch does', () async {
    for (final path in ['${scratch.path}/missing.txt', scratch.path]) {
      for (final flag in ['--sync', '--batch']) {
        final (:runner, :out, :err) = writeRunner(scratch);

        expect(
          await runner.run(['set', flag, path, '--json']),
          64,
          reason: '$flag $path',
        );

        expect(out.toString(), isEmpty, reason: '$flag $path');
        expect(_error(err)['code'], 'argument_invalid', reason: '$flag $path');
        expect(
          _error(err)['message'],
          'cannot read $path',
          reason: '$flag $path',
        );
      }
    }
  });

  test('a malformed sync file exits 64 naming each refused line as path line code message outside a project', () async {
    final file = syncFile(
      '==> verdicts <==\n'
      'match login a.dart:f 0123456789ab\n'
      'frobnicate login x\n'
      'remove-task ENG-42\n',
    );
    final (:runner, :out, :err) = writeRunner(scratch);

    expect(await runner.run(['set', '--sync', file]), 64);

    expect(out.toString(), isEmpty);
    final lines = err.toString().trimRight().split('\n');
    expect(lines, hasLength(2));
    expect(lines[0], startsWith('$file:3: argument_invalid: '));
    expect(lines[1], startsWith('$file:4: argument_invalid: '));
  });

  test('a stdin pipe nobody closes never holds a --sync run', () async {
    final binary = await buildSpecstone();
    final file = syncFile('frobnicate login x\n');
    final home = testHome().path;

    final process = await Process.start(
      binary,
      ['set', '--sync', file],
      workingDirectory: scratch.path,
      environment: {'HOME': home, 'USERPROFILE': home},
    );
    addTearDown(process.kill);
    final err = process.stderr.transform(utf8.decoder).join();
    unawaited(process.stdout.drain<void>());

    final code = await process.exitCode.timeout(const Duration(seconds: 30));

    expect(code, 64);
    expect(await err, contains(':1: argument_invalid: '));
  });

  group('a judged file', () {
    const record = 'implementation:login';
    const covered = 'app/lib/login.dart';
    const stale = '0123456789ab';
    const signIn = 'implementation:login email_login:$covered:SignInPage';
    const point = 'mismatch $signIn: the page has no title';

    final fingerprint = fileCodeFingerprint(
      utf8.encode(check.checkProjectFiles()[covered]!),
      path: covered,
    );
    final unjudged = '? $signIn $fingerprint';

    Future<Directory> project() => check.writeCheckProject(
      extra: check.doc(check.loginRecord, '  - app/lib/\n', '  - $covered\n'),
      unfingerprinted: {check.loginRecord},
    );

    String recordText(Directory root) =>
        File('${root.path}/${check.loginRecord}').readAsStringSync();

    test('a refused file prints one path line code message stderr line per refused line and exits by the catalog', () async {
      final root = await project();
      final before = recordText(root);
      const staleLine =
          'stamp_stale: $covered changed after $stale; judge it again';
      const unjudgedLine =
          'verdict_unjudged: the verdict is still ?; write match, planned, or mismatch';
      final cases = [
        (['match $record $covered $stale'], ['2: $staleLine'], 75),
        (
          [unjudged, 'match $record $covered $stale'],
          ['2: $unjudgedLine', '3: $staleLine'],
          64,
        ),
      ];
      for (final (lines, refused, status) in cases) {
        final file = syncFile('==> verdicts <==\n${lines.join('\n')}\n');
        final (:runner, :out, :err) = writeRunner(root);

        expect(await runner.run(['set', '--sync', file]), status);

        expect(out.toString(), isEmpty, reason: '$lines');
        expect(
          err.toString(),
          refused.map((line) => '$file:$line\n').join(),
          reason: '$lines',
        );
        expect(recordText(root), before, reason: '$lines');
      }
    });

    test('a malformed sync file with --json prints a lines array of entries with code, message, file, and line', () async {
      final cases = [
        (
          () async => scratch,
          'frobnicate login x\nremove-task ENG-42\n',
          ['1 argument_invalid', '2 argument_invalid'],
        ),
        (
          project,
          '$unjudged\nmatch $record $covered $stale\n',
          ['1 verdict_unjudged', '2 stamp_stale'],
        ),
      ];
      for (final (root, text, expected) in cases) {
        final file = syncFile(text);
        final (:runner, :out, :err) = writeRunner(await root());

        expect(await runner.run(['set', '--sync', file, '--json']), 64);

        expect(out.toString(), isEmpty, reason: text);
        final error = _error(err);
        final entries = (error['lines']! as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(
          [for (final e in entries) '${e['line']} ${e['code']}'],
          expected,
          reason: text,
        );
        expect(entries.map((e) => e['file']), [file, file], reason: text);
        expect(error['code'], entries.first['code'], reason: text);
        expect(error['line'], 1, reason: text);
        expect(error['file'], file, reason: text);
        expect(error['message'], entries.first['message'], reason: text);
      }
    });

    test('a written file prints each doc naming line, then its Mismatches part, exit 0', () async {
      final root = await project();
      final file = syncFile('match $record $covered $fingerprint\n$point\n');
      final (:runner, :out, :err) = writeRunner(root);

      expect(await runner.run(['set', '--sync', file]), 0, reason: '$err');

      expect(err.toString(), isEmpty);
      expect(recordText(root), contains('  - $covered $fingerprint\n'));
      expect(recordText(root), isNot(contains('draft: true')));
      final base = getDoc(root, record)['base'];
      expect(
        out.toString(),
        '==> login (implementation) · ${check.loginRecord} · base $base <==\n'
        'Mismatches:\n$point\n',
      );
    });

    test(
      'a written file with --json gives docs, mismatches, and warnings',
      () async {
        final root = await project();
        final file = syncFile('match $record $covered $fingerprint\n$point\n');
        final (:runner, :out, :err) = writeRunner(root);

        expect(
          await runner.run(['set', '--sync', file, '--json']),
          0,
          reason: '$err',
        );

        final json = jsonDecode(out.toString()) as Map<String, Object?>;
        expect(json['docs'], [
          {
            'path': check.loginRecord,
            'name': 'login',
            'docType': 'implementation',
            'base': getDoc(root, record)['base'],
          },
        ]);
        expect(json['mismatches'], [point]);
        expect(json['warnings'], isEmpty);
      },
    );
  });
}
