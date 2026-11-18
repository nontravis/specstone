@TestOn('windows')
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../helpers/built_stn.dart';
import '../helpers/shim_sandbox.dart';

// One typed argument line, the argv a recorder must log for it when it is
// known, and whether cmd runs with delayed expansion.
typedef _ArgumentCase = ({
  String line,
  List<String>? expected,
  bool delayedExpansion,
});

// The argument lines typed in [shell] after `stn`.
//
// Windows PowerShell 5.1 quotes only an argument that holds a space when it
// starts a batch file, and drops an inner quote for any program, so its words
// carry each character beside a space.
List<_ArgumentCase> _argumentCases(StnShell shell) => switch (shell) {
  StnShell.cmd => <_ArgumentCase>[
    (
      line: r'"a b" "x&y" "c^d" "50%" "say \"hi\""',
      expected: ['a b', 'x&y', 'c^d', '50%', 'say "hi"'],
      delayedExpansion: false,
    ),
    (line: '"odd', expected: null, delayedExpansion: false),
    (line: '%PATH%', expected: null, delayedExpansion: false),
    (line: '"a!b" !PATH!', expected: null, delayedExpansion: true),
  ],
  StnShell.powershell => <_ArgumentCase>[
    (
      line: "'a b' 'x & y' 'c ^ d' '50 %'",
      expected: ['a b', 'x & y', 'c ^ d', '50 %'],
      delayedExpansion: false,
    ),
  ],
};

void main() {
  // Every PATH a case passes ends with System32, as a real PATH does; it holds
  // no stn.
  final system32 =
      '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32';

  List<String> nonBlank(Object? text) => [
    for (final line in '$text'.split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  int runs(List<String> log) => log.where((line) => line == 'argv').length;

  Directory dir(String path) => Directory(path)..createSync(recursive: true);

  String under(Directory parent, String name) => '${parent.path}\\$name';

  // The log of two runs, `stn` first and `specstone` second, as two equal
  // halves.
  void expectTwoEqualRuns(ShimSandbox sb, {String reason = ''}) {
    final log = sb.logOf('specstone');
    final half = log.length ~/ 2;
    expect(runs(log), 2, reason: reason);
    expect(log.sublist(0, half), log.sublist(half), reason: reason);
  }

  for (final shell in StnShell.values) {
    // The line that runs the program at [full] with [arguments] by its path.
    String byPath(String full, String arguments) => switch (shell) {
      StnShell.cmd => '"$full" $arguments',
      StnShell.powershell => "& '$full' $arguments",
    };

    group('${shell.name}:', () {
      test('stn.exe runs the specstone.exe beside it, '
          'passing argv and PATH, exit 0', () async {
        final sb = await createShimSandbox();
        final path = '${sb.bin.path};$system32';

        final r = await sb.typeStn(
          ['stn check docs/prds'],
          shell: shell,
          path: path,
        );

        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(sb.logOf('specstone'), [
          'argv',
          'check',
          'docs/prds',
          'stdin',
          '',
          'path',
          path,
        ]);
        expect(sb.logOf('other'), isEmpty);
      });

      test("the exit status is the specstone run's", () async {
        for (final status in ['3', '-1073741510']) {
          final sb = await createShimSandbox();
          final path = '${sb.bin.path};$system32';
          final extra = {fakeExitVariable: status};

          final viaStn = await sb.typeStn(
            ['stn check'],
            shell: shell,
            path: path,
            extra: extra,
          );
          final viaSpecstone = await sb.typeStn(
            ['specstone check'],
            shell: shell,
            path: path,
            extra: extra,
          );

          expect(
            viaStn.exitCode,
            viaSpecstone.exitCode,
            reason: '$status: ${viaStn.stdout}${viaStn.stderr}',
          );
          if (status == '3') expect(viaStn.exitCode, 3);
          expectTwoEqualRuns(sb, reason: status);
        }
      });

      test('arguments arrive as typing specstone gives '
          'them', () async {
        for (final (:line, :expected, :delayedExpansion) in _argumentCases(
          shell,
        )) {
          final sb = await createShimSandbox();
          final path = '${sb.bin.path};$system32';

          final viaStn = await sb.typeStn(
            ['stn $line'],
            shell: shell,
            path: path,
            delayedExpansion: delayedExpansion,
          );
          final viaSpecstone = await sb.typeStn(
            ['specstone $line'],
            shell: shell,
            path: path,
            delayedExpansion: delayedExpansion,
          );

          expect(
            viaStn.exitCode,
            0,
            reason: '$line: ${viaStn.stdout}${viaStn.stderr}',
          );
          expect(viaSpecstone.exitCode, 0, reason: line);
          expectTwoEqualRuns(sb, reason: line);
          if (expected != null) {
            expect(sb.logOf('specstone').sublist(0, expected.length + 2), [
              'argv',
              ...expected,
              'stdin',
            ], reason: line);
          }
        }
      });

      test('stn with no arguments gives the target none', () async {
        final sb = await createShimSandbox();
        final path = '${sb.bin.path};$system32';

        final r = await sb.typeStn(['stn'], shell: shell, path: path);

        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(sb.logOf('specstone'), ['argv', 'stdin', '', 'path', path]);
      });

      test('stn.EXE and a quoted full path holding a space '
          'drop the whole program name', () async {
        final sb = await createShimSandbox();
        final path = '${sb.bin.path};$system32';
        // A folder with a space, so a program name read up to the first space
        // would leave `y\stn.exe"` in the tail.
        final spaced = Directory('${sb.root.path}\\x y')..createSync();
        for (final name in ['stn.exe', 'specstone.exe']) {
          File('${sb.bin.path}\\$name').copySync('${spaced.path}\\$name');
        }
        final full = '${spaced.path}\\stn.exe';
        final (upper, quoted) = switch (shell) {
          StnShell.cmd => ('stn.EXE check', '"$full" "a b"'),
          StnShell.powershell => ('stn.EXE check', "& '$full' 'a b'"),
        };

        final first = await sb.typeStn([upper], shell: shell, path: path);
        final second = await sb.typeStn([quoted], shell: shell, path: path);

        expect(first.exitCode, 0, reason: '${first.stdout}${first.stderr}');
        expect(second.exitCode, 0, reason: '${second.stdout}${second.stderr}');
        expect(sb.logOf('specstone'), [
          for (final argument in ['check', 'a b']) ...[
            'argv',
            argument,
            'stdin',
            '',
            'path',
            path,
          ],
        ]);
      });

      test('piped stdin, stdout redirected to a file, '
          'and stdout piped reach the target as with specstone', () async {
        const echoed = 'recorded out';
        // A recorder that reads stdin would take the lines cmd is still to
        // read, so only the stdin case sets it.
        final extra = {writeStdoutVariable: echoed};

        // Each case types the same line with `stn` and with `specstone`.
        final lines = switch (shell) {
          StnShell.cmd => (
            stdin: (String name) => 'echo piped bytes| $name get',
            file: (String name) => '$name get > $name.txt',
            pipe: (String name) => '$name get | more',
          ),
          StnShell.powershell => (
            stdin: (String name) => "'piped bytes' | $name get",
            file: (String name) =>
                '$name get | Out-File -Encoding ascii $name.txt',
            pipe: (String name) => '$name get | more',
          ),
        };

        final sb = await createShimSandbox();
        final path = '${sb.bin.path};$system32';
        Future<ProcessResult> type(String line, {bool readsStdin = false}) =>
            sb.typeStn(
              [line],
              shell: shell,
              path: path,
              extra: {...extra, if (readsStdin) readStdinVariable: '1'},
            );

        for (final name in ['stn', 'specstone']) {
          final stdin = await type(lines.stdin(name), readsStdin: true);
          expect(stdin.exitCode, 0, reason: '$name: ${stdin.stderr}');
        }
        expectTwoEqualRuns(sb, reason: 'stdin');
        expect(sb.logOf('specstone').sublist(0, 4), [
          'argv',
          'get',
          'stdin',
          'piped bytes',
        ]);

        for (final name in ['stn', 'specstone']) {
          final file = await type(lines.file(name));
          expect(file.exitCode, 0, reason: '$name: ${file.stderr}');
        }
        for (final name in ['stn', 'specstone']) {
          final written = File('${sb.root.path}\\$name.txt');
          expect(written.existsSync(), isTrue, reason: name);
          expect(written.readAsStringSync().trim(), echoed, reason: name);
        }

        for (final name in ['stn', 'specstone']) {
          final piped = await type(lines.pipe(name));
          expect(piped.exitCode, 0, reason: '$name: ${piped.stderr}');
          expect(nonBlank(piped.stdout), contains(echoed), reason: name);
        }
      });

      test('stderr redirected to a file reaches the '
          'target as with specstone, apart from stdout', () async {
        const out = 'recorded out';
        const err = 'recorded err';
        final sb = await createShimSandbox();
        final path = '${sb.bin.path};$system32';
        // PowerShell 5.1 wraps a native command's redirected stderr in error
        // records, so its case redirects inside a cmd it starts.
        String redirect(String name) => switch (shell) {
          StnShell.cmd => '$name get 2> $name.err',
          StnShell.powershell => 'cmd /d /c "$name get 2> $name.err"',
        };

        for (final name in ['stn', 'specstone']) {
          final r = await sb.typeStn(
            [redirect(name)],
            shell: shell,
            path: path,
            extra: {writeStdoutVariable: out, writeStderrVariable: err},
          );

          expect(r.exitCode, 0, reason: '$name: ${r.stdout}${r.stderr}');
          expect(nonBlank(r.stdout), contains(out), reason: name);
          expect(r.stdout, isNot(contains(err)), reason: name);
          final written = File('${sb.root.path}\\$name.err');
          expect(written.existsSync(), isTrue, reason: name);
          expect(written.readAsStringSync().trim(), err, reason: name);
        }
      });

      test('a missing specstone.exe prints one stderr '
          'line naming its path and exits 1', () async {
        final sb = await createShimSandbox();
        final target = '${sb.bin.path}\\specstone.exe';
        File(target).deleteSync();

        final r = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path: '${sb.bin.path};$system32',
        );

        expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
        expect(nonBlank(r.stdout), isEmpty);
        final naming = [
          for (final line in nonBlank(r.stderr))
            if (line.toLowerCase().contains(target.toLowerCase())) line,
        ];
        expect(naming, hasLength(1), reason: r.stderr as String);
        // Windows PowerShell 5.1 may decorate a native command's stderr when
        // its own stderr is a pipe; cmd shows the one line alone.
        if (shell == StnShell.cmd) {
          expect(nonBlank(r.stderr), naming);
        }
      });

      test('the target gets the environment the shim got, '
          'nothing added', () async {
        final sb = await createShimSandbox();
        final path = '${sb.bin.path};$system32';

        // The same target typed by name, so the shell hands it the environment
        // a run with no stn in between gets.
        final viaDirect = await sb.typeStn(
          ['specstone check'],
          shell: shell,
          path: path,
        );
        final directEnv = sb.envOf('specstone');
        final viaStn = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path: path,
        );
        final stnEnv = sb.envOf('specstone');

        expect(viaDirect.exitCode, 0, reason: '${viaDirect.stderr}');
        expect(viaStn.exitCode, 0, reason: '${viaStn.stderr}');
        expect(directEnv, isNotEmpty);
        expect(stnEnv, directEnv);
        expect(stnEnv['path'], path);
      });

      test('another stn.cmd earlier on the PATH never runs', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'tools'));
        sb.otherStn(other.path, exit: 8);

        final r = await sb.typeStn(
          [byPath(under(sb.bin, 'stn.exe'), 'check')],
          shell: shell,
          path: '${other.path};${sb.bin.path};$system32',
        );

        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(sb.logOf('specstone').sublist(0, 2), ['argv', 'check']);
        expect(sb.logOf('other'), isEmpty);
      });

      test('stn upgrade replaces the running stn.exe and '
          "exits with the upgrade's status", () async {
        final sb = await createShimSandbox();
        final shim = File(under(sb.bin, 'stn.exe'));
        final before = shim.readAsBytesSync();
        final lines = switch (shell) {
          StnShell.cmd => [
            'echo [begin]',
            'stn upgrade',
            'echo [end %ERRORLEVEL%]',
          ],
          StnShell.powershell => [
            "echo '[begin]'",
            'stn upgrade',
            r'echo "[end $LASTEXITCODE]"',
          ],
        };

        final r = await sb.typeStn(
          lines,
          shell: shell,
          path: '${sb.bin.path};$system32',
          extra: {fakeExitVariable: '5'},
        );

        expect(r.exitCode, 5, reason: '${r.stdout}${r.stderr}');
        expect(File(under(sb.bin, 'stn.exe.old')).existsSync(), isTrue);
        final after = shim.readAsBytesSync();
        final marker = utf8.encode(upgradeMarker);
        expect(after.length, before.length + marker.length);
        expect(after.sublist(after.length - marker.length), marker);
        expect(nonBlank(r.stdout), ['[begin]', 'upgraded', '[end 5]']);
        expect(r.stderr, isEmpty);
      });
    });
  }

  group('a killed shim:', () {
    // Whether a process with this pid runs, by its row in `tasklist`.
    bool isRunning(int pid) {
      final r = Process.runSync('tasklist', [
        '/FI',
        'PID eq $pid',
        '/NH',
        '/FO',
        'CSV',
      ]);
      return '${r.stdout}'.contains('"$pid"');
    }

    Future<bool> eventually(
      bool Function() holds, {
      Duration timeout = const Duration(seconds: 5),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (!holds()) {
        if (DateTime.now().isAfter(deadline)) return false;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return true;
    }

    int? readPid(File file) =>
        file.existsSync() ? int.tryParse(file.readAsStringSync().trim()) : null;

    test('killing stn.exe ends the target; the '
        "target's own child lives on", () async {
      final sb = await createShimSandbox();
      final shim = await sb.startStn(
        ['check'],
        path: '${sb.bin.path};$system32',
        extra: {holdVariable: '1'},
      );
      unawaited(shim.stdout.drain<void>());
      unawaited(shim.stderr.drain<void>());
      final targetPidFile = File('${sb.logs.path}\\specstone.pid');
      final grandchildPidFile = File('${sb.logs.path}\\grandchild.pid');
      var targetEnded = false;
      // Registered after the sandbox's own tear-down, so it runs first and
      // frees the files the processes hold. A pid the test saw end may be
      // reused, so only a pid it did not see end is killed.
      addTearDown(() async {
        shim.kill();
        final pids = [
          if (!targetEnded) readPid(targetPidFile),
          readPid(grandchildPidFile),
        ];
        for (final pid in pids) {
          if (pid != null) Process.killPid(pid);
        }
        for (final pid in pids) {
          if (pid != null) await eventually(() => !isRunning(pid));
        }
      });

      expect(
        await eventually(
          () =>
              readPid(targetPidFile) != null &&
              readPid(grandchildPidFile) != null,
          timeout: const Duration(seconds: 15),
        ),
        isTrue,
        reason: 'the target and its child write their pids',
      );
      final target = readPid(targetPidFile)!;
      final grandchild = readPid(grandchildPidFile)!;
      expect(isRunning(target), isTrue);

      expect(Process.killPid(shim.pid), isTrue);

      targetEnded = await eventually(() => !isRunning(target));
      expect(
        targetEnded,
        isTrue,
        reason: 'the target ends within 5 s of stn.exe',
      );
      expect(isRunning(grandchild), isTrue);
    });
  });

  group('the built file:', () {
    Future<String> installedExe() async {
      final sb = await createShimSandbox();
      return '${sb.bin.path}\\stn.exe';
    }

    test('stn.exe imports no VC++ runtime DLL', () async {
      final bytes = File(await installedExe()).readAsBytesSync();

      final text = latin1.decode(bytes).toLowerCase();

      expect(text, isNot(contains('vcruntime')));
      expect(text, isNot(contains('api-ms-win-crt-')));
    });

    test('FileVersion and ProductVersion of '
        'stn.exe equal the -Version build.ps1 got', () async {
      final exe = (await installedExe()).replaceAll("'", "''");

      final command =
          "\$v = [Diagnostics.FileVersionInfo]::GetVersionInfo('$exe'); "
          r'$v.FileVersion; $v.ProductVersion';

      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        command,
      ]);

      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(nonBlank(r.stdout), [specstoneVersion, specstoneVersion]);
    });
  });

  test('build.ps1 refuses a -Version outside '
      'MAJOR.MINOR.PATCH[-pre]', () async {
    final out = await Directory.systemTemp.createTemp('specstone_stn_refuse_');
    addTearDown(() => out.delete(recursive: true));
    final exe = '${out.path}\\stn.exe';

    for (final version in ['1.2', 'v1.2.0']) {
      final r = await runStnBuild(exe, version);

      expect(r.exitCode, isNot(0), reason: '$version: ${r.stdout}');
      expect(File(exe).existsSync(), isFalse, reason: version);
      expect(nonBlank(r.stderr), hasLength(1), reason: version);
      expect(r.stderr, contains(version));
    }
  });
}
