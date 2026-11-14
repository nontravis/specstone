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

  // A junction to the sandbox's install folder, removed before the sandbox:
  // a recursive delete through it would follow it into the install folder.
  String makeJunction(ShimSandbox sb) {
    final junction = '${sb.root.path}\\junction';
    final made = Process.runSync('cmd', [
      '/d',
      '/c',
      'mklink',
      '/J',
      junction,
      sb.bin.path,
    ]);
    expect(made.exitCode, 0, reason: '${made.stdout}${made.stderr}');
    addTearDown(() => Process.runSync('cmd', ['/d', '/c', 'rmdir', junction]));
    return junction;
  }

  int runs(List<String> log) => log.where((line) => line == 'argv').length;

  Directory dir(String path) => Directory(path)..createSync(recursive: true);

  String under(Directory parent, String name) => '${parent.path}\\$name';

  // The argv of each run in a recorder log, one list per run.
  List<List<String>> argvOfRuns(List<String> log) {
    final result = <List<String>>[];
    var inArgv = false;
    for (final line in log) {
      if (line == 'argv') {
        result.add([]);
        inArgv = true;
      } else if (line == 'stdin') {
        inArgv = false;
      } else if (inArgv) {
        result.last.add(line);
      }
    }
    return result;
  }

  // The log of two runs, `stn` first and `specstone` second, as two equal
  // halves.
  void expectTwoEqualRuns(ShimSandbox sb, {String reason = ''}) {
    final log = sb.logOf('specstone');
    final half = log.length ~/ 2;
    expect(runs(log), 2, reason: reason);
    expect(log.sublist(0, half), log.sublist(half), reason: reason);
  }

  for (final shell in StnShell.values) {
    // Each argument typed as one word in this shell.
    String quoted(String arg) => switch (shell) {
      StnShell.cmd => '"$arg"',
      StnShell.powershell => "'$arg'",
    };

    // The line that runs the program at [full] with [arguments] by its path.
    String byPath(String full, String arguments) => switch (shell) {
      StnShell.cmd => '"$full" $arguments',
      StnShell.powershell => "& '$full' $arguments",
    };

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

      test('run_cli_or_yield S3: another stn.exe, then another stn.cmd, on a '
          'later entry runs with the arguments as typed, the unchanged PATH, '
          'and the guard set; the specstone does not run; the exit status is '
          "that stn's", () async {
        for (final (extension, exit) in [('exe', 7), ('cmd', 8)]) {
          final sb = await createShimSandbox();
          final other = dir(under(sb.root, 'tools'));
          sb.otherStn(other.path, exit: exit, extension: extension);
          final path = '${sb.bin.path};${other.path};$system32';

          final r = await sb.typeStn(
            ['stn ${quoted('a b')} ${quoted('x & y')}'],
            shell: shell,
            path: path,
          );

          expect(
            r.exitCode,
            exit,
            reason: '$extension: ${r.stdout}${r.stderr}',
          );
          expect(sb.logOf('other'), [
            'argv',
            'a b',
            'x & y',
            'stdin',
            '',
            'path',
            path,
            'guard',
            '1',
          ], reason: extension);
          expect(sb.logOf('specstone'), isEmpty, reason: extension);
        }
      });

      test('run_cli_or_yield E03: inside one entry, stn.exe comes before '
          'stn.cmd, before stn.bat, before stn.com', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'tools'));
        const order = [('exe', 11), ('cmd', 12), ('bat', 13), ('com', 14)];
        for (final (extension, exit) in order) {
          sb.otherStn(other.path, exit: exit, extension: extension);
        }
        final path = '${sb.bin.path};${other.path};$system32';

        for (final (extension, exit) in order) {
          final r = await sb.typeStn(['stn check'], shell: shell, path: path);

          expect(
            r.exitCode,
            exit,
            reason: '$extension: ${r.stdout}${r.stderr}',
          );
          File(under(other, 'stn.$extension')).deleteSync();
        }
        expect(runs(sb.logOf('other')), order.length);
        expect(sb.logOf('specstone'), isEmpty);
      });

      test('run_cli_or_yield E03, E10: inside one entry, a stn.ps1 loses to '
          'stn.exe, stn.cmd, stn.bat, and stn.com; no refusal', () async {
        for (final (extension, exit) in [
          ('exe', 21),
          ('cmd', 22),
          ('bat', 23),
          ('com', 24),
        ]) {
          final sb = await createShimSandbox();
          final other = dir(under(sb.root, 'tools'));
          sb
            ..otherStn(other.path, extension: 'ps1')
            ..otherStn(other.path, exit: exit, extension: extension);

          final r = await sb.typeStn(
            ['stn check'],
            shell: shell,
            path: '${sb.bin.path};${other.path};$system32',
          );

          expect(
            r.exitCode,
            exit,
            reason: '$extension: ${r.stdout}${r.stderr}',
          );
          expect('${r.stdout}${r.stderr}', isNot(contains('another stn')));
          expect(runs(sb.logOf('other')), 1, reason: extension);
          expect(sb.ps1Marker.existsSync(), isFalse, reason: extension);
          expect(sb.logOf('specstone'), isEmpty, reason: extension);
        }
      });

      test('run_cli_or_yield statement: the target gets the environment the '
          'shim got, the loop guard added on a hand-off only', () async {
        for (final extension in [null, 'exe', 'cmd']) {
          final sb = await createShimSandbox();
          final other = dir(under(sb.root, 'tools'));
          if (extension != null) {
            sb.otherStn(other.path, extension: extension);
          }
          final ran = extension == null ? 'specstone' : 'other';
          final path = '${sb.bin.path};${other.path};$system32';
          // The same target typed by name or path, so the shell hands it the
          // environment a run with no stn in between gets.
          final direct = switch (extension) {
            null => 'specstone check',
            _ => byPath(under(other, 'stn.$extension'), 'check'),
          };

          final viaDirect = await sb.typeStn(
            [direct],
            shell: shell,
            path: path,
          );
          final directEnv = sb.envOf(ran);
          final viaStn = await sb.typeStn(
            ['stn check'],
            shell: shell,
            path: path,
          );
          final stnEnv = sb.envOf(ran);

          final label = extension ?? 'own specstone';
          expect(viaDirect.exitCode, 0, reason: '$label: ${viaDirect.stderr}');
          expect(viaStn.exitCode, 0, reason: '$label: ${viaStn.stderr}');
          expect(directEnv, isNotEmpty, reason: label);
          expect(
            stnEnv[stnGuardVariable.toLowerCase()],
            extension == null ? isNull : '1',
            reason: label,
          );
          expect(
            {...stnEnv}..remove(stnGuardVariable.toLowerCase()),
            directEnv,
            reason: label,
          );
          expect(stnEnv['path'], path, reason: label);
        }
      });

      test('run_cli_or_yield E01: the guard set runs the specstone beside it '
          'even with another stn on a later entry', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'tools'));
        sb.otherStn(other.path, extension: 'exe');

        final r = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path: '${sb.bin.path};${other.path};$system32',
          extra: {stnGuardVariable: '1'},
        );

        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(sb.logOf('specstone').sublist(0, 2), ['argv', 'check']);
        expect(sb.logOf('other'), isEmpty);
      });

      test('run_cli_or_yield E02: relative, dot, empty, and tilde entries are '
          'skipped even when each holds a stn', () async {
        final sb = await createShimSandbox();
        // A stn in `rel`, found only if the walk ran a relative entry from the
        // working folder; one in the working folder itself for the empty and
        // dot entries; one in HOME, found only if the walk expanded `~`.
        sb.otherStn(dir(under(sb.root, 'rel')).path);
        sb.otherStn(sb.root.path);
        sb.otherStn(sb.home.path);

        final r = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path: '${sb.bin.path};rel;.;;~;$system32',
          // cmd looks in the working folder before the PATH unless this is
          // set; the case is about the shim's walk, not cmd's own lookup.
          extra: {'NoDefaultCurrentDirectoryInExePath': '1'},
        );

        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(sb.logOf('other'), isEmpty);
        expect(sb.logOf('specstone').sublist(0, 2), ['argv', 'check']);
      });

      test('run_cli_or_yield E08: the install folder again with a trailing '
          r'\ or in upper case is skipped, so a later stn runs and no loop '
          'forms', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'tools'));
        sb.otherStn(other.path, exit: 7);

        final withSlash = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path: '${sb.bin.path};${sb.bin.path}\\;${other.path};$system32',
        );
        final upperCase = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path:
              '${sb.bin.path};${sb.bin.path.toUpperCase()};'
              '${other.path};$system32',
        );

        expect(withSlash.exitCode, 7, reason: '${withSlash.stderr}');
        expect(upperCase.exitCode, 7, reason: '${upperCase.stderr}');
        // Both runs handed off to the other stn; neither ran the shim again,
        // or the specstone log would hold a run and the exits would be 0.
        expect(runs(sb.logOf('other')), 2);
        expect(sb.logOf('specstone'), isEmpty);
      });

      test('run_cli_or_yield E08: a junction to the install folder, a folder '
          'holding stn.exe and specstone.exe, is skipped, so a later stn runs '
          'and no loop forms', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'tools'));
        sb.otherStn(other.path, exit: 7);
        final junction = makeJunction(sb);

        final r = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path: '${sb.bin.path};$junction;${other.path};$system32',
        );

        expect(r.exitCode, 7, reason: '${r.stdout}${r.stderr}');
        expect(runs(sb.logOf('other')), 1);
        expect(sb.logOf('specstone'), isEmpty);
      });

      test('run_cli_or_yield E08: a junction to the install folder with no '
          'specstone.exe beside a stn.exe copy is still skipped by its final '
          'path', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'tools'));
        sb.otherStn(other.path, exit: 7);
        final junction = makeJunction(sb);
        // With the marker pair broken, only the final path tells the junction
        // from another tool's stn.exe: a compare that misses it runs
        // `junction\stn.exe`, which finds no specstone.exe and exits 1.
        File(under(sb.bin, 'specstone.exe')).deleteSync();

        final r = await sb.typeStn(
          ['stn x'],
          shell: shell,
          path: '$junction;${other.path};$system32',
        );

        expect(r.exitCode, 7, reason: '${r.stdout}${r.stderr}');
        expect(sb.logOf('other').sublist(0, 2), ['argv', 'x']);
        expect(runs(sb.logOf('other')), 1);
      });

      test('run_cli_or_yield E09: a folder named stn.exe is skipped; a later '
          'stn.cmd file counts', () async {
        final sb = await createShimSandbox();
        final withDir = dir(under(sb.root, 'one'));
        dir(under(withDir, 'stn.exe'));
        final real = dir(under(sb.root, 'two'));
        sb.otherStn(real.path, exit: 9);

        final skipped = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path: '${sb.bin.path};${withDir.path};$system32',
        );
        final later = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path: '${sb.bin.path};${withDir.path};${real.path};$system32',
        );

        expect(skipped.exitCode, 0, reason: '${skipped.stderr}');
        expect(sb.logOf('specstone').sublist(0, 2), ['argv', 'check']);
        expect(later.exitCode, 9, reason: '${later.stderr}');
        expect(sb.logOf('other').sublist(0, 2), ['argv', 'check']);
      });

      test('run_cli_or_yield E10, S5: a stn.ps1 first on the walk prints one '
          'line naming it and specstone, exits 1, and starts neither the '
          'specstone, PowerShell, nor a later stn', () async {
        final sb = await createShimSandbox();
        final tools = dir(under(sb.root, 'tools'));
        sb.otherStn(tools.path, extension: 'ps1');
        final later = dir(under(sb.root, 'later'));
        sb.otherStn(later.path, exit: 7, extension: 'exe');
        final refusal =
            'another stn at ${under(tools, 'stn.ps1')}; use specstone';

        final r = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path: '${sb.bin.path};${tools.path};${later.path};$system32',
        );

        expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
        final lines = nonBlank('${r.stdout}\n${r.stderr}');
        switch (shell) {
          case StnShell.cmd:
            expect(lines, [refusal]);
          case StnShell.powershell:
            // Windows PowerShell 5.1 may decorate a native command's stderr
            // when its own stderr is a pipe; the line itself appears once.
            expect(lines.where((line) => line.contains(refusal)), hasLength(1));
        }
        expect(sb.ps1Marker.existsSync(), isFalse);
        expect(sb.logOf('specstone'), isEmpty);
        expect(sb.logOf('other'), isEmpty);
      });

      test('run_cli_or_yield E11: stn typed twice in one session hands off '
          'both times; between them the session holds no guard', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'tools'));
        sb.otherStn(other.path, exit: 4);
        final (echo, unset) = switch (shell) {
          StnShell.cmd => (
            'echo guard=[%$stnGuardVariable%]',
            // cmd keeps an undefined %name% as typed.
            'guard=[%$stnGuardVariable%]',
          ),
          StnShell.powershell => (
            'echo "guard=[\$env:$stnGuardVariable]"',
            'guard=[]',
          ),
        };

        final r = await sb.typeStn(
          ['stn one', echo, 'stn two'],
          shell: shell,
          path: '${sb.bin.path};${other.path};$system32',
        );

        expect(r.exitCode, 4, reason: '${r.stdout}${r.stderr}');
        expect(r.stdout, contains(unset));
        final log = sb.logOf('other');
        expect(runs(log), 2);
        expect(log.where((line) => line == '1'), hasLength(2));
        expect(sb.logOf('specstone'), isEmpty);
      });

      test('run_cli_or_yield E12: another stn.cmd gets an argument holding & '
          'only inside quotes, and %name% expands, as typing that stn.cmd '
          'first gives', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'tools'));
        sb.otherStn(other.path, extension: 'cmd');
        final path = '${sb.bin.path};${other.path};$system32';
        final extra = {'FOO': 'bar'};
        final arguments = '${quoted('x & y')} %FOO%';

        final viaStn = await sb.typeStn(
          ['stn $arguments'],
          shell: shell,
          path: path,
          extra: extra,
        );
        final typedFirst = await sb.typeStn(
          [byPath(under(other, 'stn.cmd'), arguments)],
          shell: shell,
          path: path,
          extra: extra,
        );

        expect(viaStn.exitCode, 0, reason: '${viaStn.stdout}${viaStn.stderr}');
        expect(typedFirst.exitCode, 0, reason: '${typedFirst.stderr}');
        expect(argvOfRuns(sb.logOf('other')), [
          ['x & y', 'bar'],
          ['x & y', 'bar'],
        ]);
      });

      test('run_cli_or_yield E12: the batch hand-off uses ComSpec, not a '
          'cmd.exe on PATH', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'tools'));
        sb.otherStn(other.path, exit: 8, extension: 'cmd');
        // A recording cmd.exe in a later absolute entry and in the working
        // folder; a hand-off that searched for cmd.exe would run one of them,
        // log its own argv, and never run the batch file.
        final planted = dir(under(sb.root, 'planted'));
        final recorder = File(under(other, 'stn-recorder.exe'))
            .readAsBytesSync();
        for (final folder in [planted.path, sb.root.path]) {
          File(under(Directory(folder), 'cmd.exe')).writeAsBytesSync(recorder);
        }

        final r = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path: '${sb.bin.path};${other.path};${planted.path};$system32',
          extra: {'NoDefaultCurrentDirectoryInExePath': '1'},
        );

        expect(r.exitCode, 8, reason: '${r.stdout}${r.stderr}');
        expect(argvOfRuns(sb.logOf('other')), [
          ['check'],
        ]);
      });

      test(
        'review focus 1, 3: a spaced PATH entry holds one entry; no argument '
        'reaches the target as none',
        () async {
          final sb = await createShimSandbox();
          final other = dir(under(sb.root, 'space tools'));
          sb.otherStn(other.path, exit: 2);
          final path = '${sb.bin.path};${other.path};$system32';

          final r = await sb.typeStn(['stn'], shell: shell, path: path);

          expect(r.exitCode, 2, reason: '${r.stdout}${r.stderr}');
          expect(sb.logOf('other'), [
            'argv',
            'stdin',
            '',
            'path',
            path,
            'guard',
            '1',
          ]);
        },
      );

      test('review focus 2: a quoted PATH entry holding a ; is read as the one '
          'folder inside the quotes', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'semi;colon tools'));
        sb.otherStn(other.path, exit: 6);
        final path = '${sb.bin.path};"${other.path}";$system32';

        final r = await sb.typeStn(['stn check'], shell: shell, path: path);

        expect(r.exitCode, 6, reason: '${r.stdout}${r.stderr}');
        expect(sb.logOf('other'), [
          'argv',
          'check',
          'stdin',
          '',
          'path',
          path,
          'guard',
          '1',
        ]);
      });

      test('review focus 4: stdin piped into stn reaches the target', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'tools'));
        sb.otherStn(other.path);
        final line = switch (shell) {
          StnShell.cmd => 'echo piped bytes| stn get',
          StnShell.powershell => "'piped bytes' | stn get",
        };

        final r = await sb.typeStn(
          [line],
          shell: shell,
          path: '${sb.bin.path};${other.path};$system32',
          extra: {readStdinVariable: '1'},
        );

        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(sb.logOf('other').sublist(0, 4), [
          'argv',
          'get',
          'stdin',
          'piped bytes',
        ]);
      });

      test(
        'review focus 5: a missing absolute entry is skipped with empty stderr',
        () async {
          final sb = await createShimSandbox();
          final missing = under(sb.root, 'no such folder');

          final r = await sb.typeStn(
            ['stn check'],
            shell: shell,
            path: '${sb.bin.path};$missing;$system32',
          );

          expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
          expect(r.stderr, isEmpty);
          expect(sb.logOf('specstone').sublist(0, 2), ['argv', 'check']);
        },
      );
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
