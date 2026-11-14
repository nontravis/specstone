@TestOn('windows')
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/shim_sandbox.dart';

void main() {
  // Every PATH a case passes ends with System32, as a real PATH does; it holds
  // no stn.
  final system32 =
      '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32';

  Directory dir(String path) => Directory(path)..createSync(recursive: true);

  String under(Directory parent, String name) => '${parent.path}\\$name';

  int runs(List<String> log) => log.where((line) => line == 'argv').length;

  for (final shell in StnShell.values) {
    // Each argument typed as one word in this shell.
    String quoted(String arg) => switch (shell) {
      StnShell.cmd => '"$arg"',
      StnShell.powershell => "'$arg'",
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
        "run_cli_or_yield S1: the exit status is the specstone run's, 3 here",
        () async {
          final sb = await createShimSandbox();

          final r = await sb.typeStn(
            ['stn check'],
            shell: shell,
            path: '${sb.bin.path};$system32',
            extra: {fakeExitVariable: '3'},
          );

          expect(r.exitCode, 3, reason: '${r.stdout}${r.stderr}');
        },
      );

      test('run_cli_or_yield S1: arguments with spaces, quotes, &, ^, and % '
          'arrive as typed, as typing specstone gives them', () async {
        final sb = await createShimSandbox();
        // Windows PowerShell 5.1 quotes only an argument that holds a space
        // when it starts a batch file, and drops an inner quote for any
        // program, so its words carry each character beside a space.
        final (line, expected) = switch (shell) {
          StnShell.cmd => (
            r'"a b" "x&y" "c^d" "50%" "say \"hi\""',
            ['a b', 'x&y', 'c^d', '50%', 'say "hi"'],
          ),
          StnShell.powershell => (
            "'a b' 'x & y' 'c ^ d' '50 %'",
            ['a b', 'x & y', 'c ^ d', '50 %'],
          ),
        };
        final path = '${sb.bin.path};$system32';

        final viaStn = await sb.typeStn(
          ['stn $line'],
          shell: shell,
          path: path,
        );
        final viaSpecstone = await sb.typeStn(
          ['specstone $line'],
          shell: shell,
          path: path,
        );

        expect(viaStn.exitCode, 0, reason: '${viaStn.stdout}${viaStn.stderr}');
        expect(viaSpecstone.exitCode, 0);
        final log = sb.logOf('specstone');
        final half = log.length ~/ 2;
        expect(log.sublist(0, expected.length + 2), [
          'argv',
          ...expected,
          'stdin',
        ]);
        expect(log.sublist(0, half), log.sublist(half));
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
          "shim got, a user's variable named like a shim work variable "
          'included, and no work variable of its own', () async {
        // The names stn.cmd sets in its inner scope; Windows ignores case.
        const workVariables = [
          'own',
          'split',
          'target',
          'entry',
          'folder',
          'extension',
          'attributes',
          'restore_title',
          'cmdline',
        ];
        final userValues = {
          for (final name in workVariables) name.toUpperCase(): 'user-$name',
        };
        for (final extension in [null, 'exe', 'cmd']) {
          final sb = await createShimSandbox();
          final other = dir(under(sb.root, 'tools'));
          if (extension != null) {
            sb.otherStn(other.path, extension: extension);
          }
          final ran = extension == null ? 'specstone' : 'other';
          final path = '${sb.bin.path};${other.path};$system32';

          final withUser = await sb.typeStn(
            ['stn check'],
            shell: shell,
            path: path,
            extra: userValues,
          );
          final userRun = sb.envOf(ran);
          final bare = await sb.typeStn(
            ['stn check'],
            shell: shell,
            path: path,
          );
          final bareRun = sb.envOf(ran);

          final label = extension ?? 'own specstone';
          expect(withUser.exitCode, 0, reason: '$label: ${withUser.stderr}');
          expect(bare.exitCode, 0, reason: '$label: ${bare.stderr}');
          expect(
            {for (final name in workVariables) name: userRun[name]},
            {for (final name in workVariables) name: 'user-$name'},
            reason: label,
          );
          expect(
            bareRun.keys.toSet().intersection(workVariables.toSet()),
            isEmpty,
            reason: label,
          );
          expect(bareRun['path'], path, reason: label);
          expect(
            bareRun[stnGuardVariable.toLowerCase()],
            extension == null ? isNull : '1',
            reason: label,
          );
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
          'holding stn.cmd and specstone.exe, is skipped, so a later stn runs '
          'and no loop forms', () async {
        final sb = await createShimSandbox();
        final other = dir(under(sb.root, 'tools'));
        sb.otherStn(other.path, exit: 7);
        final junction = under(sb.root, 'junction');
        final made = Process.runSync('cmd', [
          '/d',
          '/c',
          'mklink',
          '/J',
          junction,
          sb.bin.path,
        ]);
        expect(made.exitCode, 0, reason: '${made.stdout}${made.stderr}');

        final r = await sb.typeStn(
          ['stn check'],
          shell: shell,
          path: '${sb.bin.path};$junction;${other.path};$system32',
        );

        expect(r.exitCode, 7, reason: '${r.stdout}${r.stderr}');
        expect(runs(sb.logOf('other')), 1);
        expect(sb.logOf('specstone'), isEmpty);
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
        final lines = [
          for (final line in '${r.stdout}\n${r.stderr}'.split(RegExp(r'\r?\n')))
            if (line.trim().isNotEmpty) line.trim(),
        ];
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

      test('run_cli_or_yield E06: stn upgrade that replaces the installed '
          'stn.cmd with a longer file exits with the upgrade status and runs '
          "no line of the new file after the target's output", () async {
        final sb = await createShimSandbox();
        final shim = File(under(sb.bin, 'stn.cmd'));
        final before = shim.lengthSync();
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

        expect(shim.lengthSync(), greaterThan(before));
        expect(r.exitCode, 5, reason: '${r.stdout}${r.stderr}');
        expect(
          [
            for (final line in '${r.stdout}'.split(RegExp(r'\r?\n')))
              if (line.trim().isNotEmpty) line.trim(),
          ],
          ['[begin]', 'upgraded', '[end 5]'],
        );
        expect(r.stderr, isEmpty);
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
}
