@TestOn('windows')
@Tags(['ps1'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

void main() {
  const pluginLine = 'claude plugin uninstall specstone@specstone';
  const otherItems = r'C:\Windows;C:\Tools';

  // PowerShell wraps a long error line at the console width; compare the text
  // with its whitespace runs folded to one space.
  String flat(Object? text) => '$text'.replaceAll(RegExp(r'\s+'), ' ');

  // Every test may write the real user PATH, so each one holds the lock and
  // gets the PATH it found written back.
  void pathTest(String name, Future<void> Function() body) =>
      test(name, () => withUserPathLock(body));

  String binDir(ScriptSandbox sb) => '${sb.home.path}\\.specstone\\bin';
  String libDir(ScriptSandbox sb) => '${sb.home.path}\\.specstone\\lib';

  // Builds the state install.ps1 leaves (bin\\, lib\\, the bin folder last on
  // the user PATH after [otherItems]) straight in the sandbox: the install is
  // fixture here, and running it costs tens of seconds on Windows.
  Future<ScriptSandbox> installedSandbox() async {
    final sb = await createScriptSandbox();
    sb.installFake();
    await writeUserPath((value: '$otherItems;${binDir(sb)}', kind: 'String'));
    return sb;
  }

  group('uninstall.ps1', () {
    pathTest('f09/us03/fr01, fr02, f09/us03/s2: bin, lib, and the user PATH '
        'item go; packs stay; plugin command last', () async {
      final sb = await installedSandbox();
      File('${sb.home.path}\\.specstone\\packs\\mine\\pack.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: mine\n');
      File('${sb.home.path}\\work\\app\\.specstone\\docs\\index.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('# doc\n');

      final r = await sb.run('uninstall.ps1');

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stderr, '');
      expect((r.stdout as String).trimRight().split(RegExp(r'\r?\n')), [
        'Removed ${binDir(sb)}',
        'Removed ${libDir(sb)}',
        'Removed ${binDir(sb)} from the user PATH',
        pluginLine,
      ]);
      expect(Directory(binDir(sb)).existsSync(), isFalse);
      expect(Directory(libDir(sb)).existsSync(), isFalse);
      expect((await readUserPath())?.value, otherItems);
      expect(
        File('${sb.home.path}\\.specstone\\packs\\mine\\pack.yaml')
            .readAsStringSync(),
        'name: mine\n',
      );
      expect(
        File('${sb.home.path}\\work\\app\\.specstone\\docs\\index.md')
            .readAsStringSync(),
        '# doc\n',
      );
    });

    pathTest('f09/us03/fr01/e06, f09/us03/fr02/e03, f09/us03/s6: a running '
        'specstone.exe stops the uninstall', () async {
      final sb = await installedSandbox();
      final exe = '${binDir(sb)}\\specstone.exe';
      // The fake exe sleeps for any argument but `--version`, so the process
      // keeps its image file locked until it is killed.
      final running = await Process.start(
        exe,
        const ['mcp'],
        environment: sb.env(),
        includeParentEnvironment: false,
        workingDirectory: sb.root.path,
      );
      addTearDown(() async {
        running.kill();
        await running.exitCode;
      });
      final before = sb.snapshot();
      final pathBefore = (await readUserPath())?.value;

      final r = await sb.run('uninstall.ps1');

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        contains(
          'specstone: cannot uninstall while specstone (PID ${running.pid}) '
          'runs from ${binDir(sb)}; stop it and run the uninstall line again',
        ),
      );
      expect(r.stdout, isNot(contains(pluginLine)));
      expect(File(exe).existsSync(), isTrue);
      expect(Directory(libDir(sb)).existsSync(), isTrue);
      expect(sb.snapshot(), before);
      expect((await readUserPath())?.value, pathBefore);
      expect(pathBefore, contains(binDir(sb)));
    });

    pathTest('f09/us03/fr01: a removal that fails for a reason other than a '
        'lock leaves that folder; the rest goes, exit 1', () async {
      final sb = await installedSandbox();
      final lib = Directory(libDir(sb));
      final victim = lib.listSync(recursive: true).whereType<File>().first;
      // Deleting needs DELETE on the file or DELETE_CHILD on its folder, so
      // deny both. Denying write data too makes the lock probe's exclusive
      // open fail with no lock, so the uninstall must go on, not refuse.
      Future<void> icacls(List<String> args) async {
        final result = await Process.run('icacls', args);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      }

      await icacls([victim.path, '/deny', '*S-1-1-0:(WD,D)']);
      await icacls([victim.parent.path, '/deny', '*S-1-1-0:(DC)']);
      addTearDown(() async {
        await Process.run('icacls', [
          victim.parent.path,
          '/remove:d',
          '*S-1-1-0',
        ]);
        await Process.run('icacls', [victim.path, '/remove:d', '*S-1-1-0']);
      });

      final r = await sb.run('uninstall.ps1');

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        contains('specstone: could not remove ${libDir(sb)}'),
      );
      expect(Directory(binDir(sb)).existsSync(), isFalse);
      expect(lib.existsSync(), isTrue);
      expect((await readUserPath())?.value, otherItems);
      final lines = (r.stdout as String).trimRight().split(RegExp(r'\r?\n'));
      expect(lines, contains('Removed ${binDir(sb)}'));
      expect(lines.last, pluginLine);
    });

    pathTest('f09/us03/fr01: the PATH item is found in another case and with '
        'a trailing backslash', () async {
      final sb = await installedSandbox();
      await writeUserPath((
        value: r'C:\Windows;' + binDir(sb).toUpperCase() + r'\;C:\Tools',
        kind: 'String',
      ));

      final r = await sb.run('uninstall.ps1');

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((await readUserPath())?.value, otherItems);
    });

    pathTest('f09/us03/fr01: an ExpandString Path keeps its kind and its '
        '%VAR% items', () async {
      final sb = await installedSandbox();
      await writeUserPath((
        value: r'%SystemRoot%\Tools;' + binDir(sb),
        kind: 'ExpandString',
      ));

      final r = await sb.run('uninstall.ps1');

      expect(r.exitCode, 0, reason: '${r.stderr}');
      final path = await readUserPath();
      expect(path?.value, r'%SystemRoot%\Tools');
      expect(path?.kind, 'ExpandString');
    });

    pathTest('f09/us03/fr01/e04, f09/us03/s5: nothing installed says so and '
        'names the plugin command', () async {
      final sb = await createScriptSandbox();
      await writeUserPath((value: otherItems, kind: 'String'));

      final r = await sb.run('uninstall.ps1');

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((r.stdout as String).trimRight().split(RegExp(r'\r?\n')), [
        'specstone: nothing to remove',
        pluginLine,
      ]);
      expect(r.stderr, '');
      expect(sb.snapshot(), isEmpty);
      expect((await readUserPath())?.value, otherItems);
    });

    pathTest('f09/us03/fr02/e01: claude on the PATH is never run', () async {
      final sb = await installedSandbox();
      sb.stub('claude', r'>> "%STUB_LOG_DIR%\claude.log" echo %*');

      final r = await sb.run('uninstall.ps1');

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(sb.logOf('claude'), isEmpty);
      expect(
        (r.stdout as String).trimRight().split(RegExp(r'\r?\n')).last,
        pluginLine,
      );
    });

    pathTest(
      'f09/us03/fr01: with neither HOME nor USERPROFILE it refuses',
      () async {
        final sb = await createScriptSandbox();

        final r = await sb.run(
          'uninstall.ps1',
          extra: {'HOME': '', 'USERPROFILE': ''},
        );

        expect(r.exitCode, 1);
        expect(
          flat(r.stderr),
          contains('specstone: no home folder: HOME and USERPROFILE are unset'),
        );
      },
    );

    pathTest("f09/us03/fr01: irm | iex leaves the session's "
        'ErrorActionPreference as it was', () async {
      final sb = await createScriptSandbox();
      final script = '${repoRoot().path}\\uninstall.ps1';
      // The script runs at the top scope, as `irm | iex` runs it; a leaked
      // strict mode would make the undefined variable throw.
      final command =
          "Get-Content -Raw '$script' | Invoke-Expression; "
          r"'STRICT=' + ($null -eq $notDefinedAnywhere); "
          r"'EAP=' + $ErrorActionPreference";

      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
        environment: sb.env(),
        includeParentEnvironment: false,
        workingDirectory: sb.root.path,
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, contains('STRICT=True'));
      expect((r.stdout as String).trim(), endsWith('EAP=Continue'));
    });

    // The script starts no program by name, so a planted one cannot show the
    // search; what a run shows is that the session's PATH comes back whole.
    pathTest("G8-R10: irm | iex leaves the session's PATH as it was", () async {
      final sb = await createScriptSandbox();
      final script = '${repoRoot().path}\\uninstall.ps1';
      final path = '.;;planted;${sb.env()['PATH']}';
      final command =
          "Get-Content -Raw '$script' | Invoke-Expression; "
          r"'PATH=' + $env:Path";

      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
        environment: sb.env({'PATH': path}),
        includeParentEnvironment: false,
        workingDirectory: sb.root.path,
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((r.stdout as String).trim(), endsWith('PATH=$path'));
    });
  });
}
