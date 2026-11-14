@TestOn('windows')
@Timeout(Duration(minutes: 3))
library;

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

  // The log of two runs, `stn` first and `specstone` second, as two equal
  // halves.
  void expectTwoEqualRuns(ShimSandbox sb, {String reason = ''}) {
    final log = sb.logOf('specstone');
    final half = log.length ~/ 2;
    expect(runs(log), 2, reason: reason);
    expect(log.sublist(0, half), log.sublist(half), reason: reason);
  }

  for (final shell in StnShell.values) {
    group('${shell.name}:', () {
      test('run_cli_or_yield S1: no other stn runs the specstone beside it, '
          'passing argv, PATH, and no guard, exit 0', () async {
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
          'guard',
          'unset',
        ]);
        expect(sb.logOf('other'), isEmpty);
      });

      test(
        "run_cli_or_yield S1: the exit status is the specstone run's",
        () async {
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
        },
      );

      test('run_cli_or_yield S1: arguments arrive as typing specstone gives '
          'them', () async {
        // Windows PowerShell 5.1 quotes only an argument that holds a space
        // when it starts a batch file, and drops an inner quote for any
        // program, so its words carry each character beside a space.
        final cases = switch (shell) {
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

        for (final (:line, :expected, :delayedExpansion) in cases) {
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

      test(
        'review focus 3: stn with no arguments gives the target none',
        () async {
          final sb = await createShimSandbox();
          final path = '${sb.bin.path};$system32';

          final r = await sb.typeStn(['stn'], shell: shell, path: path);

          expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
          expect(sb.logOf('specstone'), [
            'argv',
            'stdin',
            '',
            'path',
            path,
            'guard',
            'unset',
          ]);
        },
      );

      test('review focus 4: stn.EXE and a quoted full path holding a space '
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
            'guard',
            'unset',
          ],
        ]);
      });

      test('run_cli_or_yield E15: piped stdin, stdout redirected to a file, '
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

      test('run_cli_or_yield E15: stderr redirected to a file reaches the '
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

      test('run_cli_or_yield E16: a missing specstone.exe prints one stderr '
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
    });
  }

  group('the built file:', () {
    Future<String> installedExe() async {
      final sb = await createShimSandbox();
      return '${sb.bin.path}\\stn.exe';
    }

    test('package_archive E05: stn.exe imports no VC++ runtime DLL', () async {
      final bytes = File(await installedExe()).readAsBytesSync();

      final text = latin1.decode(bytes).toLowerCase();

      expect(text, isNot(contains('vcruntime')));
      expect(text, isNot(contains('api-ms-win-crt-')));
    });

    test('package_archive Verification: FileVersion and ProductVersion of '
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

  test('package_archive: build.ps1 refuses a -Version outside '
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
