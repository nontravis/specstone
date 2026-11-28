@TestOn('windows')
@Tags(['ps1', 'integration'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

void main() {
  const otherItems = r'C:\Windows;C:\Tools';

  // PowerShell wraps a long error line at the console width; compare the text
  // with its whitespace runs folded to one space.
  String flat(Object? text) => '$text'.replaceAll(RegExp(r'\s+'), ' ');

  // A test that can write the real user PATH holds the lock and gets the PATH
  // it found written back; a refusal before any removal writes nothing, so it
  // is a plain `test`.
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
    pathTest('bin, lib, and the user PATH '
        'item go; packs and the update record stay; no plugin command '
        'prints', () async {
      final sb = await installedSandbox();
      File('${sb.home.path}\\.specstone\\update-check.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"checkedAt":"2026-11-15"}\n');
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
        File('${sb.home.path}\\.specstone\\update-check.json')
            .readAsStringSync(),
        '{"checkedAt":"2026-11-15"}\n',
      );
      expect(
        File('${sb.home.path}\\work\\app\\.specstone\\docs\\index.md')
            .readAsStringSync(),
        '# doc\n',
      );
    });

    pathTest('a running specstone.exe stops the uninstall', () async {
      final sb = await installedSandbox();
      final exe = '${binDir(sb)}\\specstone.exe';
      // The fake exe sleeps for any argument but `--version`, so the process
      // keeps its image file locked until it is killed.
      final running = await Process.start(
        exe,
        const ['check'],
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
      expect(r.stdout, isNot(contains('plugin')));
      expect(File(exe).existsSync(), isTrue);
      expect(Directory(libDir(sb)).existsSync(), isTrue);
      expect(sb.snapshot(), before);
      expect((await readUserPath())?.value, pathBefore);
      expect(pathBefore, contains(binDir(sb)));
    });

    pathTest('a removal that fails for a reason other than a '
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
    });

    pathTest('a user PATH that cannot be written is named and left as it '
        'was; the folders go, exit 1', () async {
      final sb = await installedSandbox();
      final pathBefore = (await readUserPath())?.value;
      // Registered after the lock's own teardowns, so it runs before the PATH
      // is written back, which needs the right this test took away.
      addTearDown(() => denyUserPathWrite(isDenied: false));
      await denyUserPathWrite(isDenied: true);

      final r = await sb.run('uninstall.ps1');

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        contains(
          'specstone: could not write the user PATH: remove ${binDir(sb)} '
          'from it yourself',
        ),
      );
      expect(Directory(binDir(sb)).existsSync(), isFalse);
      expect(Directory(libDir(sb)).existsSync(), isFalse);
      expect((await readUserPath())?.value, pathBefore);
      expect(pathBefore, contains(binDir(sb)));
      final lines = (r.stdout as String).trimRight().split(RegExp(r'\r?\n'));
      expect(lines, ['Removed ${binDir(sb)}', 'Removed ${libDir(sb)}']);
    });

    pathTest('the PATH item is found in another case and with '
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

    pathTest('an ExpandString Path keeps its kind and its '
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

    pathTest('nothing installed says so and '
        'prints no plugin command', () async {
      final sb = await createScriptSandbox();
      await writeUserPath((value: otherItems, kind: 'String'));

      final r = await sb.run('uninstall.ps1');

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((r.stdout as String).trimRight().split(RegExp(r'\r?\n')), [
        'specstone: nothing to remove',
      ]);
      expect(r.stderr, '');
      expect(sb.snapshot(), isEmpty);
      expect((await readUserPath())?.value, otherItems);
    });

    pathTest('claude on the PATH is never run', () async {
      final sb = await installedSandbox();
      sb.stub('claude', r'>> "%STUB_LOG_DIR%\claude.log" echo %*');

      final r = await sb.run('uninstall.ps1');

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(sb.logOf('claude'), isEmpty);
      expect(r.stdout, isNot(contains('plugin')));
    });

    test('with neither HOME nor USERPROFILE it refuses', () async {
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
    });

    pathTest('ErrorActionPreference is as it was after irm | iex', () async {
      final sb = await createScriptSandbox();
      final script = '${repoRoot().path}\\uninstall.ps1';
      // The script runs at the top scope, as `irm | iex` runs it; a leaked
      // strict mode would make the undefined variable throw.
      final command =
          '$importSessionModules'
          "Get-Content -Raw '$script' | Invoke-Expression; "
          r"'STRICT=' + ($null -eq $notDefinedAnywhere); "
          r"'EAP=' + $ErrorActionPreference";

      final r = await runPowerShell(
        'iex-session',
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
    pathTest('PATH is as it was after irm | iex runs the script', () async {
      final sb = await createScriptSandbox();
      final script = '${repoRoot().path}\\uninstall.ps1';
      final path = '.;;planted;${sb.env()['PATH']}';
      final command =
          '$importSessionModules'
          "Get-Content -Raw '$script' | Invoke-Expression; "
          r"'PATH=' + $env:Path";

      final r = await runPowerShell(
        'iex-session',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
        environment: sb.env({'PATH': path}),
        includeParentEnvironment: false,
        workingDirectory: sb.root.path,
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((r.stdout as String).trim(), endsWith('PATH=$path'));
    });

    // The script starts no program by name, so no planted program shows its
    // PATH; the one place the narrowed PATH shows is `$env:Path` while it
    // runs. This copy of the script prints it, and the variable that would
    // make cmd.exe skip the current folder, right before the removals.
    Future<String> probeScript(ScriptSandbox sb) async {
      const anchor = r'$results = @((Remove-Folder';
      final text = File('${repoRoot().path}\\uninstall.ps1').readAsStringSync();
      expect(text, contains(anchor));
      final probe = File('${sb.root.path}\\uninstall_probe.ps1')
        ..writeAsStringSync(
          text.replaceFirst(
            anchor,
            r"Write-Host ('NARROWED=' + $env:Path); "
            "Write-Host ('NOCWD=<' + "
            r"$env:NoDefaultCurrentDirectoryInExePath + '>'); "
            '$anchor',
          ),
          encoding: ascii,
        );
      return probe.path;
    }

    String valueOf(Object? stdout, String key) => [
      for (final line in '$stdout'.split(RegExp(r'\r?\n')))
        if (line.startsWith('$key=')) line.substring(key.length + 1),
    ].single;

    pathTest('an empty, ., ~, or relative PATH entry is dropped before any '
        'program starts, and the rest keep their order', () async {
      final sb = await installedSandbox();
      final probe = await probeScript(sb);
      final system = sb.env()['PATH']!;

      final r = await sb.run(
        probe,
        extra: {'PATH': r'.;;planted;~;~\bin;C:\Windows;' + system},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(valueOf(r.stdout, 'NARROWED'), r'C:\Windows;' + system);
    });

    pathTest('the absolute entries stay, a quoted one holding a semicolon '
        'is quoted again, and NoDefaultCurrentDirectoryInExePath stays '
        'unset', () async {
      final sb = await installedSandbox();
      final probe = await probeScript(sb);
      final system = sb.env()['PATH']!;

      final r = await sb.run(
        probe,
        extra: {'PATH': r'C:/Tools;"C:\Pro;gram";\\server\share;' + system},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        valueOf(r.stdout, 'NARROWED'),
        r'C:/Tools;"C:\Pro;gram";\\server\share;' + system,
      );
      expect(valueOf(r.stdout, 'NOCWD'), '<>');
    });

    pathTest('the user PATH item comes from the registry as written, not '
        'from the session PATH', () async {
      final sb = await installedSandbox();
      const sessionOnly = r'C:\session\only';

      final r = await sb.run(
        'uninstall.ps1',
        extra: {'PATH': '${sb.env()['PATH']};$sessionOnly;${binDir(sb)}'},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((await readUserPath())?.value, otherItems);

      final second = await createScriptSandbox();
      second.installFake();
      await writeUserPath((value: otherItems, kind: 'String'));

      final r2 = await second.run(
        'uninstall.ps1',
        extra: {'PATH': '${second.env()['PATH']};${binDir(second)}'},
      );

      expect(r2.exitCode, 0, reason: '${r2.stderr}');
      expect((await readUserPath())?.value, otherItems);
      expect(r2.stdout, isNot(contains('from the user PATH')));
    });

    pathTest('USERPROFILE stands in when HOME is unset, and HOME wins over a '
        'different USERPROFILE', () async {
      final sb = await installedSandbox();
      final other = Directory('${sb.root.path}\\profile_home')..createSync();
      File('${other.path}\\.specstone\\bin\\specstone.exe')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');

      final wins = await sb.run(
        'uninstall.ps1',
        extra: {'USERPROFILE': other.path},
      );

      expect(wins.exitCode, 0, reason: '${wins.stderr}');
      expect(Directory(binDir(sb)).existsSync(), isFalse);
      expect(
        File('${other.path}\\.specstone\\bin\\specstone.exe').existsSync(),
        isTrue,
      );

      final fallback = await installedSandbox();
      final r = await fallback.run('uninstall.ps1', extra: {'HOME': ''});

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(Directory(binDir(fallback)).existsSync(), isFalse);
      expect((await readUserPath())?.value, otherItems);
    });
  });
}
