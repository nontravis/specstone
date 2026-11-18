@TestOn('windows')
@Tags(['ps1'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/specstone_core.dart';
import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/version_cases.dart';
import '../helpers/built_cli.dart';
import '../helpers/script_sandbox.dart';

// The shapes install.ps1 runs in: `-File`, the API's `iex "& {...}"` line,
// and `irm | iex`.
enum _Shape { file, iex, pipe }

void main() {
  const asset = 'specstone-windows-x64.zip';
  const supported = 'supported: macOS arm64, macOS x64, Linux x64, Windows x64';
  late Directory bundle;

  setUpAll(() async {
    // The bundle folder is the grandparent of bin\specstone.exe.
    bundle = File(await buildSpecstone()).parent.parent;
  });

  // PowerShell wraps a long error line at the console width; compare the text
  // with its whitespace runs folded to one space.
  String flat(Object? text) => '$text'.replaceAll(RegExp(r'\s+'), ' ');

  // A test that can write the real user PATH holds the lock and gets the PATH
  // it found written back; a refusal or a failed download before the PATH step
  // writes nothing, so it is a plain `test`.
  void pathTest(String name, Future<void> Function() body) =>
      test(name, () => withUserPathLock(body));

  Future<ScriptSandbox> sandboxWith({
    bool damaged = false,
    bool withSumsLine = true,
  }) async {
    final sb = await createScriptSandbox();
    await sb.writeArchive(
      'windows-x64',
      bundle: bundle,
      damaged: damaged,
      withSumsLine: withSumsLine,
    );
    return sb;
  }

  Map<String, String> archiveEnv(ScriptSandbox sb) => {
    'SPECSTONE_ARCHIVE_DIR': sb.archives.path,
  };

  Future<ProcessResult> runInstall(
    ScriptSandbox sb, {
    List<String> args = const [],
    Map<String, String> extra = const {},
  }) => sb.run('install.ps1', args: args, extra: {...archiveEnv(sb), ...extra});

  String binDir(ScriptSandbox sb) => '${sb.home.path}\\.specstone\\bin';

  String versionOf(String exe) {
    final result = Process.runSync(exe, ['--version']);
    return (result.stdout as String).trim();
  }

  Future<int> userPathCount(String folder) async {
    final entries = (await readUserPath())?.value.split(';') ?? <String>[];
    return entries
        .where(
          (entry) =>
              entry.trim().replaceAll(RegExp(r'\\+$'), '').toLowerCase() ==
              folder.toLowerCase(),
        )
        .length;
  }

  // Starts [exe] and returns once it holds its file open; the fake sleeps.
  Future<Process> startLocked(String exe) async {
    final process = await Process.start(exe, const []);
    addTearDown(process.kill);
    return process;
  }

  // Kills [process] and waits until the OS lets [file] be written again.
  Future<void> stopAndUnlock(Process process, File file) async {
    process.kill();
    await process.exitCode;
    for (var attempt = 0; attempt < 50; attempt++) {
      try {
        file.openSync(mode: FileMode.append).closeSync();
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    fail('${file.path} stayed locked after its process exited');
  }

  List<String> oldFilesUnder(ScriptSandbox sb) => [
    for (final folder in ['bin', 'lib'])
      if (Directory('${sb.home.path}\\.specstone\\$folder').existsSync())
        for (final entity in Directory(
          '${sb.home.path}\\.specstone\\$folder',
        ).listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.old')) entity.path,
  ];

  // Denies the current user the right to add a file to [folder]; the deny is
  // removed at teardown, and the teardown is registered before the deny.
  Future<void> denyAddFile(Directory folder) async {
    final who = (Process.runSync('whoami', const []).stdout as String).trim();
    addTearDown(() => Process.run('icacls', [folder.path, '/remove:d', who]));
    final r = await Process.run('icacls', [folder.path, '/deny', '$who:(WD)']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  }

  // Denies the current user the right to set a value under the registry key
  // HKCU\Environment, so the user PATH cannot be written; the deny is removed
  // at teardown, and the teardown is registered before the deny.
  Future<void> denyUserPathWrites() async {
    const open =
        r'$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey( '
        "'Environment', "
        '[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, '
        "[System.Security.AccessControl.RegistryRights]'ChangePermissions, "
        "ReadPermissions'); "
        r'$who = [Security.Principal.WindowsIdentity]::GetCurrent().Name; '
        r'$rule = New-Object System.Security.AccessControl.RegistryAccessRule( '
        r"$who, 'SetValue', 'None', 'None', 'Deny'); "
        r'$acl = $k.GetAccessControl(); ';
    Future<ProcessResult> change(String role, String step) => runPowerShell(
      role,
      ['-NoProfile', '-Command', '$open$step; \$k.SetAccessControl(\$acl)'],
    );
    addTearDown(
      () =>
          change('allow-path-writes', r'$acl.RemoveAccessRuleSpecific($rule)'),
    );
    final r = await change('deny-path-writes', r'$acl.AddAccessRule($rule)');
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }

  // Sets the user PATH to a multi-string registry value of [items].
  Future<void> writeMultiStringUserPath(List<String> items) async {
    const script =
        r'$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey( '
        r"'Environment', $true); "
        r"$k.SetValue('Path', [string[]]($env:SPECSTONE_TEST_ITEMS -split "
        r"'\|'), 'MultiString')";
    final r = await runPowerShell(
      'write-multi-path',
      ['-NoProfile', '-Command', script],
      environment: {'SPECSTONE_TEST_ITEMS': items.join('|')},
    );
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }

  // Returns the registry kind of the user PATH and its items joined by `|`.
  Future<UserPath> readMultiStringUserPath() async {
    const script =
        r'$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey( '
        "'Environment'); "
        r"$k.GetValueKind('Path'); "
        r"@($k.GetValue('Path', '', 'DoNotExpandEnvironmentNames')) -join '|'";
    final r = await runPowerShell('read-multi-path', [
      '-NoProfile',
      '-Command',
      script,
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final lines = (r.stdout as String).trim().split(RegExp(r'\r?\n'));
    return (kind: lines.first, value: lines.last);
  }

  group('install.ps1', () {
    // The sandbox strips the environment of a PowerShell 5.1 child; one that
    // inherits the PowerShell 7 module folders of the runner loses
    // Get-FileHash, and every install fails far from the cause. The probe
    // imports by name, as install.ps1 does, so it stays fast.
    test(
      'the sandbox PowerShell finds the cmdlets install.ps1 calls',
      () async {
        final sb = await createScriptSandbox();
        const names = ['Get-FileHash', 'Expand-Archive', 'Invoke-WebRequest'];
        const importLine = 'Import-Module -Name Microsoft.PowerShell.Archive';
        final script = File('${sb.root.path}\\probe.ps1')
          ..writeAsStringSync(
            [
              importLine,
              for (final name in names)
                '"$name=\$([bool](Get-Command $name -ErrorAction Ignore))"',
            ].join('\r\n'),
          );

        final r = await sb.run(script.path);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        for (final name in names) {
          expect(flat(r.stdout), contains('$name=True'));
        }
      },
    );

    pathTest('an empty home gets the '
        'CLI and the user PATH entry', () async {
      final sb = await sandboxWith();

      final r = await runInstall(sb);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(versionOf('${binDir(sb)}\\specstone.exe'), specstoneVersion);
      expect(await userPathCount(binDir(sb)), 1);
      expect(
        flat(r.stdout),
        contains(
          'Added ${binDir(sb)} to the user PATH. '
          'Open a new PowerShell window to use specstone.',
        ),
      );
    });

    test('Windows on ARM64 refuses naming the four '
        'targets, exit 1', () async {
      final sb = await createScriptSandbox();

      final r = await runInstall(
        sb,
        extra: {'PROCESSOR_ARCHITECTURE': 'ARM64'},
      );

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        contains('specstone: unsupported machine Windows ARM64; $supported'),
      );
      expect(sb.snapshot(), isEmpty);
    });

    test('a 32-bit PowerShell on 64-bit Windows reads '
        'PROCESSOR_ARCHITEW6432 first', () async {
      final sb = await createScriptSandbox();

      final r = await runInstall(
        sb,
        extra: {
          'PROCESSOR_ARCHITECTURE': 'x86',
          'PROCESSOR_ARCHITEW6432': 'ARM64',
        },
      );

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        contains('specstone: unsupported machine Windows ARM64; $supported'),
      );
      expect(sb.snapshot(), isEmpty);
    });

    test('with neither HOME nor USERPROFILE it '
        'refuses', () async {
      final sb = await sandboxWith();

      final r = await runInstall(sb, extra: {'HOME': '', 'USERPROFILE': ''});

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        contains('specstone: no home folder: HOME and USERPROFILE are unset'),
      );
      expect(sb.snapshot(), isEmpty);
    });

    test('a damaged zip throws, exit 1, '
        'the install unchanged', () async {
      final sb = await sandboxWith(damaged: true);
      sb.installFake();
      final before = sb.snapshot();

      final r = await runInstall(sb);

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        contains(
          'specstone: checksum mismatch for $asset; the install is unchanged',
        ),
      );
      expect(sb.snapshot(), before);
    });

    pathTest('a second run is already '
        'the latest; one PATH item', () async {
      final sb = await sandboxWith();
      final first = await runInstall(sb);
      expect(first.exitCode, 0, reason: '${first.stderr}');

      final second = await runInstall(sb);

      expect(second.exitCode, 0, reason: '${second.stderr}');
      expect(
        flat(second.stdout),
        contains('specstone $specstoneVersion is already the latest release'),
      );
      expect(second.stdout, isNot(contains('to the user PATH')));
      expect(await userPathCount(binDir(sb)), 1);
    });

    pathTest('an entry spelled in another case with a '
        'trailing backslash counts as there', () async {
      final sb = await sandboxWith();
      final folder = binDir(sb);
      final saved = await readUserPath();
      await writeUserPath((
        value: [?saved?.value, '${folder.toUpperCase()}\\'].join(';'),
        kind: 'String',
      ));

      final r = await runInstall(sb);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(await userPathCount(folder), 1);
      expect(r.stdout, isNot(contains('to the user PATH')));
    });

    pathTest('a user Path holding %USERPROFILE% keeps that '
        'literal entry and its ExpandString kind', () async {
      final sb = await sandboxWith();
      await writeUserPath((
        value: r'%USERPROFILE%\tools;C:\Windows',
        kind: 'ExpandString',
      ));

      final r = await runInstall(sb);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      final path = await readUserPath();
      expect(path?.kind, 'ExpandString');
      expect(path?.value, startsWith(r'%USERPROFILE%\tools;C:\Windows;'));
      expect(await userPathCount(binDir(sb)), 1);
    });

    pathTest('a %USERPROFILE% spelling of the folder counts '
        'as there', () async {
      final sb = await sandboxWith();
      const spelled = r'%USERPROFILE%\.specstone\bin';
      await writeUserPath((
        value: 'C:\\Windows;$spelled',
        kind: 'ExpandString',
      ));

      final r = await runInstall(sb);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, isNot(contains('to the user PATH')));
      expect((await readUserPath())?.value, 'C:\\Windows;$spelled');
    });

    pathTest('an empty user Path gets the entry', () async {
      final sb = await sandboxWith();
      await writeUserPath((value: '', kind: 'String'));

      final r = await runInstall(sb);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((await readUserPath())?.value, binDir(sb));
    });

    pathTest('a user PATH that cannot be written is named with the line to '
        'add, and the install goes on, exit 0', () async {
      final sb = await sandboxWith();
      sb.stub('git', 'exit /b 127');
      await denyUserPathWrites();

      final r = await runInstall(sb);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        flat(r.stderr),
        contains(
          'specstone: could not write the user PATH: '
          'add ${binDir(sb)} to it yourself',
        ),
      );
      expect(r.stdout, isNot(contains('to the user PATH')));
      expect(
        flat(r.stdout),
        contains('specstone: git 2.25 or later is missing'),
      );
      expect(versionOf('${binDir(sb)}\\specstone.exe'), specstoneVersion);
    });

    pathTest('a user PATH that is not a string value stays as it is, with '
        'the line to add by hand', () async {
      final sb = await sandboxWith();
      await writeMultiStringUserPath([r'C:\Windows', r'C:\tools']);

      final r = await runInstall(sb);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        flat(r.stderr),
        contains(
          'specstone: the user PATH has an unexpected type (MultiString) and '
          'is left as it is: add ${binDir(sb)} to it yourself',
        ),
      );
      expect(r.stdout, isNot(contains('to the user PATH')));
      final path = await readMultiStringUserPath();
      expect(path.kind, 'MultiString');
      expect(path.value, r'C:\Windows|C:\tools');
      expect(versionOf('${binDir(sb)}\\specstone.exe'), specstoneVersion);
    });

    pathTest('a running old specstone.exe is renamed to '
        '.old; the next run deletes it', () async {
      final sb = await sandboxWith();
      final exe = File('${binDir(sb)}\\specstone.exe');
      await sb.compileFakeCli('0.0.1', exe.path);
      final running = await startLocked(exe.path);

      final first = await runInstall(sb);

      expect(first.exitCode, 0, reason: '${first.stderr}');
      final old = File('${exe.path}.old');
      expect(old.existsSync(), isTrue);
      expect(versionOf(exe.path), specstoneVersion);

      await stopAndUnlock(running, old);
      await sb.compileFakeCli('0.0.2', exe.path);

      final second = await runInstall(sb);

      expect(second.exitCode, 0, reason: '${second.stderr}');
      // The copying run renames lib\ files too, so lib\ may hold .old files.
      expect(oldFilesUnder(sb), contains(old.path));
      expect(oldFilesUnder(sb).where((path) => !path.contains(r'\lib\')), [
        old.path,
      ]);
      expect(versionOf(old.path), '0.0.2');
      expect(versionOf(exe.path), specstoneVersion);
    });

    pathTest('an equal-version run still deletes the '
        '.old leftovers', () async {
      final sb = await sandboxWith();
      final first = await runInstall(sb);
      expect(first.exitCode, 0, reason: '${first.stderr}');
      final install = '${sb.home.path}\\.specstone';
      File('$install\\bin\\specstone.exe.old').writeAsStringSync('old');
      File('$install\\lib\\sqlite3.dll.old').writeAsStringSync('old');
      Directory('$install\\lib\\nested').createSync();
      File('$install\\lib\\nested\\x.dll.old').writeAsStringSync('old');

      final second = await runInstall(sb);

      expect(second.exitCode, 0, reason: '${second.stderr}');
      expect(
        flat(second.stdout),
        contains('specstone $specstoneVersion is already the latest release'),
      );
      expect(oldFilesUnder(sb), isEmpty);
      expect(versionOf('$install\\bin\\specstone.exe'), specstoneVersion);
    });

    pathTest('a still-locked .old stays, and the run '
        'succeeds', () async {
      final sb = await sandboxWith();
      final old = File('${binDir(sb)}\\specstone.exe.old');
      await sb.compileFakeCli('0.0.1', old.path);
      final running = await startLocked(old.path);

      final first = await runInstall(sb);

      expect(first.exitCode, 0, reason: '${first.stderr}');
      expect(old.existsSync(), isTrue);
      expect(versionOf('${binDir(sb)}\\specstone.exe'), specstoneVersion);

      await stopAndUnlock(running, old);
      final second = await runInstall(sb);

      expect(second.exitCode, 0, reason: '${second.stderr}');
      expect(old.existsSync(), isFalse);
    });

    pathTest('a file whose .old name a locked leftover '
        'holds is renamed to the next free .old name', () async {
      final sb = await sandboxWith();
      final exe = File('${binDir(sb)}\\specstone.exe');
      final old = File('${exe.path}.old');
      await sb.compileFakeCli('0.0.1', old.path);
      exe.writeAsStringSync('an older install that does not run');
      final running = await startLocked(old.path);

      final first = await runInstall(sb);

      expect(first.exitCode, 0, reason: '${first.stderr}');
      expect(old.existsSync(), isTrue);
      expect(File('${exe.path}.2.old').readAsStringSync(), contains('older'));
      expect(versionOf(exe.path), specstoneVersion);

      await stopAndUnlock(running, old);
      final second = await runInstall(sb);

      expect(second.exitCode, 0, reason: '${second.stderr}');
      expect(oldFilesUnder(sb), isEmpty);
    });

    group('install by version', () {
      const releases = 'https://github.com/nontravis/specstone/releases';
      const refusalTail =
          ' is not a version of the form MAJOR.MINOR.PATCH[-<pre-release>]; '
          'the install is unchanged';
      const downloadFailed =
          'specstone: download failed for $asset; the install is unchanged';

      // The shapes that carry a version: `powershell -File install.ps1
      // -Version X` and the API's `iex "& {...} -Version X"` line.
      const versionShapes = [(_Shape.file, '-File'), (_Shape.iex, 'iex line')];

      // A function shadows the cmdlet: it logs each URL and serves the file
      // from ARCHIVES, or fails when STUB_WEB_FAIL is set. The script runs as
      // `-File` does (a `-Version` taken from the environment, so any
      // character crosses intact), as the API's `iex "& {...} args"` line
      // (args text from HARNESS_ARGS), or as `irm | iex` does (the text piped
      // to Invoke-Expression). A refusal prints whether its text was printable
      // ASCII before the host encodes it; the pipe run prints whether the
      // caller still holds `$Version`.
      //
      // The two `forms` modes run the script once per line of HARNESS_FORMS
      // (a UTF-8 text in base64 per line) in one session, as `-File` does
      // and as the iex line does with the line as its args, and print one
      // line per form: `FORM <n> RAN`, or `FORM <n> PRINTABLE=<bool>
      // CAUGHT=<message>`. Each PowerShell start costs seconds on a runner,
      // so the form lists run here and not one process per form.
      const harness =
          '$importSessionModules\n'
          r'''
function Invoke-WebRequest {
  param([switch]$UseBasicParsing, [int]$TimeoutSec, [string]$Uri, [string]$OutFile)
  Add-Content -LiteralPath (Join-Path $env:STUB_LOG_DIR 'web.log') -Value $Uri
  if ($env:STUB_WEB_FAIL) { throw 'web stub: 404' }
  Copy-Item -LiteralPath (Join-Path $env:ARCHIVES ($Uri.Split('/')[-1])) -Destination $OutFile
}
if ($env:HARNESS_MODE -eq 'iex') {
  $installText = Get-Content -Raw -LiteralPath $env:INSTALL_PS1
  try {
    Invoke-Expression "& {$installText} $env:HARNESS_ARGS"
  } catch {
    'CAUGHT=' + $_.Exception.Message
    'PRINTABLE=' + ($_.Exception.Message -cmatch '\A[\x20-\x7E]*\z')
    exit 0
  }
} elseif ($env:HARNESS_MODE -eq 'pipe') {
  Get-Content -Raw -LiteralPath $env:INSTALL_PS1 | Invoke-Expression
  'VERSION_DEFINED=' + ($null -ne (Get-Variable -Name Version -ErrorAction SilentlyContinue))
} elseif ($env:HARNESS_MODE -eq 'forms' -or $env:HARNESS_MODE -eq 'iexforms') {
  $installText = Get-Content -Raw -LiteralPath $env:INSTALL_PS1
  $index = 0
  foreach ($encoded in Get-Content -LiteralPath $env:HARNESS_FORMS) {
    $form = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
    try {
      if ($env:HARNESS_MODE -eq 'iexforms') {
        Invoke-Expression "& {$installText} $form"
      } else {
        & $env:INSTALL_PS1 -Version $form
      }
      "FORM $index RAN"
    } catch {
      "FORM $index PRINTABLE=" + ($_.Exception.Message -cmatch '\A[\x20-\x7E]*\z') + ' CAUGHT=' + $_.Exception.Message
    }
    $index++
  }
} else {
  try {
    & $env:INSTALL_PS1 -Version $env:SPECSTONE_TEST_VERSION
  } catch {
    'PRINTABLE=' + ($_.Exception.Message -cmatch '\A[\x20-\x7E]*\z')
    throw
  }
}
''';

      // [version] goes to `-Version` as an environment value in the `-File`
      // shape and as a bare token in the iex line; [iexArgs] replaces the
      // line's arguments.
      Future<ProcessResult> runHarness(
        ScriptSandbox sb, {
        _Shape shape = _Shape.file,
        String? version,
        String? iexArgs,
        bool isDownloadFailing = false,
      }) {
        final file = File('${sb.root.path}\\harness.ps1')
          ..writeAsStringSync(harness);
        return sb.run(
          file.path,
          extra: {
            'ARCHIVES': sb.archives.path,
            'INSTALL_PS1': '${repoRoot().path}\\install.ps1',
            'HARNESS_MODE': shape.name,
            'HARNESS_ARGS':
                iexArgs ?? (version == null ? '' : '-Version $version'),
            'SPECSTONE_TEST_VERSION': ?version,
            'STUB_WEB_FAIL': isDownloadFailing ? '1' : '',
          },
        );
      }

      // Runs every text of [forms] through one session of the script and
      // returns the printed `FORM` lines, one per form, in order. A form of
      // the iex shape is the line's argument text.
      Future<List<String>> runForms(
        ScriptSandbox sb,
        List<String> forms, {
        _Shape shape = _Shape.file,
        bool isDownloadFailing = false,
      }) async {
        final file = File('${sb.root.path}\\harness.ps1')
          ..writeAsStringSync(harness);
        final encoded = [
          for (final form in forms) base64.encode(utf8.encode(form)),
        ];
        final list = File('${sb.root.path}\\forms.txt')
          ..writeAsStringSync('${encoded.join('\n')}\n');
        final r = await sb.run(
          file.path,
          extra: {
            'ARCHIVES': sb.archives.path,
            'INSTALL_PS1': '${repoRoot().path}\\install.ps1',
            'HARNESS_MODE': shape == _Shape.iex ? 'iexforms' : 'forms',
            'HARNESS_FORMS': list.path,
            'STUB_WEB_FAIL': isDownloadFailing ? '1' : '',
          },
        );
        expect(r.exitCode, 0, reason: '${r.stderr}');
        final lines = [
          for (final line in (r.stdout as String).split(RegExp(r'\r?\n')))
            if (line.startsWith('FORM ')) line,
        ];
        expect(lines, hasLength(forms.length), reason: '${r.stdout}');
        return lines;
      }

      Future<ScriptSandbox> sandboxServing(String version) async {
        final sb = await createScriptSandbox();
        await sb.writeArchive('windows-x64', version: version);
        return sb;
      }

      // The refusal shows only printable ASCII; every other character is `?`.
      String refusal(String version) {
        final shown = version.replaceAll(RegExp(r'[^\x20-\x7e]'), '?');
        return 'specstone: $shown$refusalTail';
      }

      // A test name holds no raw control or non-ASCII character.
      String named(String version) => jsonEncode(version).replaceAllMapped(
        RegExp(r'[^\x20-\x7e]'),
        (match) =>
            '\\u${match[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
      );

      for (final (shape, label) in versionShapes) {
        pathTest(
          'the named version installs from its own release ($label)',
          () async {
            final sb = await sandboxServing('1.2.0-beta.1');

            final r = await runHarness(
              sb,
              shape: shape,
              version: '1.2.0-beta.1',
            );

            expect(r.exitCode, 0, reason: '${r.stderr}');
            final log = sb.logOf('web');
            expect(log, hasLength(2));
            expect(
              log.first,
              endsWith('$releases/download/v1.2.0-beta.1/$asset'),
            );
            expect(
              log.last,
              endsWith('$releases/download/v1.2.0-beta.1/SHA256SUMS'),
            );
            expect(versionOf('${binDir(sb)}\\specstone.exe'), '1.2.0-beta.1');
          },
        );
      }

      pathTest('powershell -File install.ps1 -Version installs the '
          'named version', () async {
        final sb = await sandboxServing('1.2.0-beta.1');

        final r = await runInstall(sb, args: ['-Version', '1.2.0-beta.1']);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          flat(r.stdout),
          contains('specstone 1.2.0-beta.1 installed in ${binDir(sb)}'),
        );
        expect(versionOf('${binDir(sb)}\\specstone.exe'), '1.2.0-beta.1');
      });

      // Every refused form runs in one session; a NUL crosses in the base64
      // text, which an environment value could not carry. `-Version ''` is no
      // version.
      test('each refused form is '
          'refused before any download', () async {
        final forms = [
          for (final v in refusedVersions)
            if (v.isNotEmpty) v,
        ];
        final sb = await createScriptSandbox();
        sb.installFake();
        final before = sb.snapshot();

        final lines = await runForms(sb, forms);

        for (final (index, version) in forms.indexed) {
          expect(
            flat(lines[index]),
            flat('FORM $index PRINTABLE=True CAUGHT=${refusal(version)}'),
            reason: named(version),
          );
        }
        expect(sb.logOf('web'), isEmpty);
        expect(sb.snapshot(), before);
      });

      // One plain form and one outside ASCII cross the real process boundary:
      // the second is the one a host encoding could change.
      for (final version in ['v1.2.0', '1.2.0-\u00e9']) {
        test('a process given '
            '${named(version)} refuses before any download', () async {
          final sb = await createScriptSandbox();
          sb.installFake();
          final before = sb.snapshot();

          final r = await runHarness(sb, version: version);

          expect(r.exitCode, 1);
          expect(flat(r.stderr), contains(flat(refusal(version))));
          expect(r.stdout, contains('PRINTABLE=True'));
          expect(sb.logOf('web'), isEmpty);
          expect(sb.snapshot(), before);
        });
      }

      // The iex line reads a bare token; a NUL needs a quoted one.
      const iexForms = [
        ('v1.2.0', '-Version v1.2.0'),
        ('1.2', '-Version 1.2'),
        ('01.2.0', '-Version 01.2.0'),
        ('1.2.0-', '-Version 1.2.0-'),
        ('1.2.0-beta.01', '-Version 1.2.0-beta.01'),
        ('1.2.0+build.5', '-Version 1.2.0+build.5'),
        ('1.2.0\u0000', '-Version "1.2.0`0"'),
      ];
      test('every refused form is a throw, the session goes on '
          '(iex line)', () async {
        final sb = await createScriptSandbox();
        sb.installFake();
        final before = sb.snapshot();

        final lines = await runForms(sb, [
          for (final (_, argsText) in iexForms) argsText,
        ], shape: _Shape.iex);

        for (final (index, (version, _)) in iexForms.indexed) {
          expect(
            flat(lines[index]),
            flat('FORM $index PRINTABLE=True CAUGHT=${refusal(version)}'),
            reason: named(version),
          );
        }
        expect(sb.logOf('web'), isEmpty);
        expect(sb.snapshot(), before);
      });

      test('a process given a refused form throws and the session goes on '
          '(iex line)', () async {
        final sb = await createScriptSandbox();
        sb.installFake();
        final before = sb.snapshot();

        final r = await runHarness(
          sb,
          shape: _Shape.iex,
          iexArgs: '-Version v1.2.0',
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(flat(r.stdout), contains('CAUGHT=${refusal('v1.2.0')}'));
        expect(r.stdout, contains('PRINTABLE=True'));
        expect(sb.logOf('web'), isEmpty);
        expect(sb.snapshot(), before);
      });

      test('a positional argument is the version, so one '
          'outside the form is refused', () async {
        final sb = await sandboxWith();
        sb.installFake();
        final before = sb.snapshot();

        final r = await runInstall(sb, args: ['0.1']);

        expect(r.exitCode, 1);
        expect(flat(r.stderr), contains(refusal('0.1')));
        expect(sb.snapshot(), before);
      });

      pathTest('a refusal leaves the user PATH alone', () async {
        final sb = await sandboxWith();
        final pathBefore = await readUserPath();

        final r = await runHarness(sb, version: 'v1.2.0');

        expect(r.exitCode, 1);
        expect(await readUserPath(), pathBefore);
        expect(sb.logOf('web'), isEmpty);
      });

      test('every accepted form passes the form check and fails as a '
          'download', () async {
        final sb = await createScriptSandbox();

        final lines = await runForms(
          sb,
          acceptedVersions,
          isDownloadFailing: true,
        );

        final web = sb.logOf('web');
        expect(web, hasLength(acceptedVersions.length));
        for (final (index, version) in acceptedVersions.indexed) {
          expect(
            flat(lines[index]),
            allOf(
              startsWith('FORM $index PRINTABLE=True CAUGHT='),
              contains(downloadFailed),
              isNot(contains(refusalTail)),
            ),
            reason: named(version),
          );
          expect(
            web[index],
            endsWith('$releases/download/v$version/$asset'),
            reason: named(version),
          );
        }
      });

      for (final (shape, label) in versionShapes) {
        test('a version no release carries fails as a failed download, '
            'the install unchanged ($label)', () async {
          final sb = await createScriptSandbox();
          sb.installFake();
          final before = sb.snapshot();

          final r = await runHarness(
            sb,
            shape: shape,
            version: '9.9.9',
            isDownloadFailing: true,
          );

          expect(
            flat(shape == _Shape.iex ? r.stdout : r.stderr),
            contains(downloadFailed),
          );
          expect(sb.snapshot(), before);
        });
      }

      // `irm | iex` passes no argument; the API's line may pass an empty one.
      for (final (label, shape, iexArgs) in [
        ('irm | iex, no argument', _Shape.pipe, null),
        ('iex line, no argument', _Shape.iex, ''),
        ("iex line, -Version ''", _Shape.iex, "-Version ''"),
        (r'-File, -Version $null', _Shape.file, null),
      ]) {
        pathTest('no version fetches the latest release ($label)', () async {
          final sb = await sandboxServing('0.2.0');

          final r = await runHarness(sb, shape: shape, iexArgs: iexArgs);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            sb.logOf('web').first,
            endsWith('$releases/latest/download/$asset'),
          );
          expect(versionOf('${binDir(sb)}\\specstone.exe'), '0.2.0');
        });
      }

      pathTest(r'irm | iex leaves no $Version in the caller', () async {
        final sb = await sandboxServing('0.2.0');

        final r = await runHarness(sb, shape: _Shape.pipe);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, contains('VERSION_DEFINED=False'));
      });

      test(r'a refused pipe run leaves no $Version in the caller when the run '
          'refuses', () async {
        final sb = await createScriptSandbox();
        final script = '${repoRoot().path}\\install.ps1';
        final command =
            '$importSessionModules'
            "try { Get-Content -Raw '$script' | Invoke-Expression } "
            r"catch { 'CAUGHT=' + $_.Exception.Message }; "
            "'VERSION_DEFINED=' + "
            r'($null -ne (Get-Variable -Name Version -ErrorAction '
            'SilentlyContinue))';

        final r = await runPowerShell(
          'iex-session',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
          environment: sb.env({'PROCESSOR_ARCHITECTURE': 'ARM64'}),
          includeParentEnvironment: false,
          workingDirectory: sb.root.path,
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          flat(r.stdout),
          contains('CAUGHT=specstone: unsupported machine Windows ARM64'),
        );
        expect(r.stdout, contains('VERSION_DEFINED=False'));
      });

      test('an unknown release answers non-2xx and the run exits 1 with the '
          'install unchanged', () async {
        final sb = await createScriptSandbox();
        sb.installFake();
        final before = sb.snapshot();

        final r = await runHarness(
          sb,
          version: '9.9.9',
          isDownloadFailing: true,
        );

        expect(r.exitCode, 1);
        expect(flat(r.stderr), contains(downloadFailed));
        expect(
          sb.logOf('web').single,
          endsWith('$releases/download/v9.9.9/$asset'),
        );
        expect(sb.snapshot(), before);
      });

      for (final (shape, label) in versionShapes) {
        pathTest('the version already installed is named and nothing is placed '
            '($label)', () async {
          final sb = await sandboxServing('1.2.0-beta.1');
          sb.installFake(version: '1.2.0-beta.1');
          final before = sb.snapshot();

          final r = await runHarness(sb, shape: shape, version: '1.2.0-beta.1');

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            flat(r.stdout),
            contains('specstone 1.2.0-beta.1 is already installed'),
          );
          expect(r.stdout, isNot(contains('installed in')));
          expect(r.stdout, isNot(contains('latest release')));
          expect(sb.snapshot(), before);
        });
      }

      pathTest('a version that differs only in case is another '
          'version and installs', () async {
        final sb = await sandboxServing('1.0.0-A');
        sb.installFake(version: '1.0.0-a');

        final r = await runHarness(sb, version: '1.0.0-A');

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          flat(r.stdout),
          contains('specstone 1.0.0-A installed in ${binDir(sb)}'),
        );
        expect(versionOf('${binDir(sb)}\\specstone.exe'), '1.0.0-A');
      });

      pathTest('a named version replaces an older CLI', () async {
        final sb = await sandboxServing('1.2.0-beta.1');
        sb.installFake();

        final r = await runHarness(sb, version: '1.2.0-beta.1');

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          flat(r.stdout),
          contains('specstone 1.2.0-beta.1 installed in ${binDir(sb)}'),
        );
        expect(versionOf('${binDir(sb)}\\specstone.exe'), '1.2.0-beta.1');
      });
    });

    pathTest('a download that fails stops with the install '
        'unchanged, exit 1', () async {
      final sb = await createScriptSandbox();
      sb.installFake();
      final before = sb.snapshot();

      final r = await runInstall(sb);

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        contains(
          'specstone: download failed for $asset; the install is unchanged',
        ),
      );
      expect(sb.snapshot(), before);
    });

    pathTest('no SHA256SUMS line is a checksum failure, '
        'exit 1', () async {
      final sb = await sandboxWith(withSumsLine: false);

      final r = await runInstall(sb);

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        contains(
          'specstone: checksum mismatch for $asset; the install is unchanged',
        ),
      );
      expect(sb.snapshot(), isEmpty);
    });

    pathTest('a downloaded binary that does not run is named, '
        'install unchanged', () async {
      final sb = await createScriptSandbox();
      final broken = Directory('${sb.root.path}\\broken')
        ..createSync(recursive: true);
      Directory('${broken.path}\\lib').createSync();
      File('${broken.path}\\lib\\x.dll').writeAsStringSync('x');
      Directory('${broken.path}\\bin').createSync();
      File('${broken.path}\\bin\\specstone.exe')
          .writeAsStringSync('not an exe');
      await sb.writeArchive('windows-x64', bundle: broken);
      sb.installFake();
      final before = sb.snapshot();

      final r = await runInstall(sb);

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        contains(
          'specstone: the downloaded specstone does not run (exit 1); '
          'the install is unchanged',
        ),
      );
      expect(sb.snapshot(), before);
    });

    pathTest('a run leaves the personal packs folder as it was', () async {
      final sb = await sandboxWith();
      File('${sb.home.path}\\.specstone\\packs\\mine.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: mine');
      Map<String, String> packsOf(Map<String, String> files) => {
        for (final MapEntry(:key, :value) in files.entries)
          if (key.startsWith('.specstone/packs/')) key: value,
      };
      final before = packsOf(sb.snapshot());
      expect(before, {'.specstone/packs/mine.yaml': 'name: mine'});

      final r = await runInstall(sb);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(packsOf(sb.snapshot()), before);
    });

    pathTest('an empty home gets an install folder holding only bin and '
        'lib', () async {
      final sb = await sandboxWith();

      final r = await runInstall(sb);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      final names = [
        for (final entity in Directory(
          '${sb.home.path}\\.specstone',
        ).listSync())
          entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
      ]..sort();
      expect(names, ['bin', 'lib']);
    });

    test('a copy that fails removes the copied files, puts the renamed ones '
        'back, and names the file', () async {
      final sb = await sandboxWith();
      final install = '${sb.home.path}\\.specstone';
      File('$install\\lib\\libold.dll')
        ..createSync(recursive: true)
        ..writeAsStringSync('old');
      final bin = Directory('$install\\bin')..createSync(recursive: true);
      final before = sb.snapshot();
      await denyAddFile(bin);

      final r = await runInstall(sb);

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        matches(
          RegExp(
            'specstone: could not place ${RegExp.escape(bin.path)}\\\\.+: '
            'run the install again',
          ),
        ),
      );
      expect(sb.snapshot(), before);
      expect(oldFilesUnder(sb), isEmpty);
    });

    group('download steps', () {
      const downloadFailed =
          'specstone: download failed for $asset; the install is unchanged';
      const latest = 'https://github.com/nontravis/specstone/releases/latest';

      // A function shadows Invoke-WebRequest: it logs `<TimeoutSec>|<Uri>|
      // <OutFile>`, then serves the file from ARCHIVES, or throws as a
      // timed-out request does when STUB_WEB_TIMEOUT is set.
      const webStub =
          '$importSessionModules\n'
          r'''
function Invoke-WebRequest {
  param([switch]$UseBasicParsing, [int]$TimeoutSec, [string]$Uri, [string]$OutFile)
  Add-Content -LiteralPath (Join-Path $env:STUB_LOG_DIR 'web.log') -Value "$TimeoutSec|$Uri|$OutFile"
  if ($env:STUB_WEB_TIMEOUT) { throw 'The operation has timed out.' }
  Copy-Item -LiteralPath (Join-Path $env:ARCHIVES ($Uri.Split('/')[-1])) -Destination $OutFile
}
& $env:INSTALL_PS1
''';

      Future<ProcessResult> runWebStub(
        ScriptSandbox sb, {
        bool isTimingOut = false,
      }) {
        final file = File('${sb.root.path}\\web_stub.ps1')
          ..writeAsStringSync(webStub);
        return sb.run(
          file.path,
          extra: {
            'ARCHIVES': sb.archives.path,
            'INSTALL_PS1': '${repoRoot().path}\\install.ps1',
            'STUB_WEB_TIMEOUT': isTimingOut ? '1' : '',
          },
        );
      }

      test('a download that gets no answer within 30 seconds fails, exit 1, '
          'the install unchanged', () async {
        final sb = await createScriptSandbox();
        sb.installFake();
        final before = sb.snapshot();

        final r = await runWebStub(sb, isTimingOut: true);

        expect(r.exitCode, 1);
        expect(flat(r.stderr), contains(downloadFailed));
        expect(sb.logOf('web').first, startsWith('30|'));
        expect(sb.snapshot(), before);
      });

      test('a temporary folder that cannot be made stops with the install '
          'unchanged, exit 1', () async {
        final sb = await createScriptSandbox();
        sb.installFake();
        final before = sb.snapshot();
        final notAFolder = File('${sb.root.path}\\not_a_folder')
          ..writeAsStringSync('a file, so no folder fits under it');

        final r = await runInstall(
          sb,
          extra: {'TEMP': notAFolder.path, 'TMP': notAFolder.path},
        );

        expect(r.exitCode, 1);
        expect(
          flat(r.stderr),
          contains(
            'specstone: could not make a temporary folder in '
            '${notAFolder.path}\\; the install is unchanged',
          ),
        );
        expect(sb.snapshot(), before);
      });

      pathTest('the archive and SHA256SUMS come from the latest release into '
          'one temporary folder', () async {
        final sb = await sandboxWith();

        final r = await runWebStub(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        final calls = [for (final line in sb.logOf('web')) line.split('|')];
        expect(calls, hasLength(2));
        expect(calls[0][1], '$latest/download/$asset');
        expect(calls[1][1], '$latest/download/SHA256SUMS');
        final folders = {for (final call in calls) File(call[2]).parent.path};
        expect(folders, hasLength(1));
        expect(folders.single, startsWith('${sb.root.path}\\tmp\\specstone.'));
        expect(File(calls[0][2]).uri.pathSegments.last, asset);
        expect(File(calls[1][2]).uri.pathSegments.last, 'SHA256SUMS');
      });
    });

    group('no plugin step', () {
      for (final (label, args) in [
        ('a plain install', <String>[]),
        ('an install by version', ['-Version', '1.2.0-beta.1']),
      ]) {
        pathTest('$label runs no claude command and prints no plugin '
            'line', () async {
          final sb = await sandboxWith();
          sb.stub('claude', r'>> "%STUB_LOG_DIR%\claude.log" echo %*');

          final r = await runInstall(sb, args: args);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('claude'), isEmpty);
          for (final word in ['Claude', 'plugin', 'marketplace']) {
            expect(r.stdout, isNot(contains(word)));
            expect(r.stderr, isNot(contains(word)));
          }
        });
      }
    });

    group('prerequisite warnings', () {
      const gitCommand = 'winget install Git.Git';
      const floorLine =
          'specstone: git 2.25 or later is missing; install it with '
          '$gitCommand\n';

      // Write-Host ends a line with CRLF.
      String stdoutOf(ProcessResult r) =>
          (r.stdout as String).replaceAll('\r\n', '\n');

      // The stub answers `git --version` as the named build does; null
      // leaves a git that fails, as a machine with no usable git does.
      void stubGit(ScriptSandbox sb, String? version) => sb.stub(
        'git',
        version == null ? 'exit /b 127' : 'echo git version $version',
      );

      pathTest('git 2.45.1.windows.1 warns about nothing', () async {
        final sb = await sandboxWith();
        stubGit(sb, '2.45.1.windows.1');

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(stdoutOf(r), isNot(contains('specstone: git')));
        expect(stdoutOf(r), isNot(contains('Git for Windows')));
        expect(stdoutOf(r), isNot(contains('Claude Code')));
      });

      pathTest(
        'a git build that names no windows warns about nothing',
        () async {
          final sb = await sandboxWith();
          stubGit(sb, '2.45.1');

          final r = await runInstall(sb);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(stdoutOf(r), isNot(contains('specstone: git')));
          expect(stdoutOf(r), isNot(contains('Git for Windows')));
        },
      );

      pathTest('git 2.20.0.windows.1 warns naming the floor only', () async {
        final sb = await sandboxWith();
        stubGit(sb, '2.20.0.windows.1');

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(stdoutOf(r), contains(floorLine));
        expect(stdoutOf(r), isNot(contains('Git for Windows')));
      });

      pathTest('no git warns once naming the floor and winget; the install '
          'still ran and its exit status is kept', () async {
        final sb = await sandboxWith();
        stubGit(sb, null);

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(stdoutOf(r), contains(floorLine));
        expect(stdoutOf(r), isNot(contains('Git for Windows')));
        expect(stdoutOf(r), isNot(contains('Claude Code')));
        expect(versionOf('${binDir(sb)}\\specstone.exe'), specstoneVersion);
      });

      pathTest(
        'a machine with no git prints exactly one warning line',
        () async {
          final sb = await sandboxWith();
          stubGit(sb, null);

          final r = await runInstall(sb);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          final warnings = [
            for (final line in stdoutOf(r).split('\n'))
              if (line.startsWith('specstone: ')) line,
          ];
          expect(warnings, [floorLine.trimRight()]);
        },
      );

      pathTest('a git on a relative PATH entry only is missing', () async {
        final sb = await sandboxWith();
        final system = Platform.environment['SystemRoot'] ?? r'C:\Windows';
        for (final folder in ['.', 'planted']) {
          File('${sb.root.path}\\$folder\\git.cmd')
            ..createSync(recursive: true)
            ..writeAsStringSync(
              '@echo off\r\n> "%STUB_LOG_DIR%\\planted-git.ran" echo ran\r\n',
            );
        }

        final r = await runInstall(
          sb,
          extra: {
            'PATH':
                '.;planted;${sb.stubs.path};$system\\System32;'
                '$system\\System32\\WindowsPowerShell\\v1.0',
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(stdoutOf(r), contains(floorLine));
        expect(File('${sb.logs.path}\\planted-git.ran').existsSync(), isFalse);
      });
    });

    group('PATH search', () {
      final system = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final systemEntries =
          '$system\\System32;$system\\System32\\WindowsPowerShell\\v1.0';

      // A planted git.cmd sits in the run folder and in a relative
      // `planted` folder; it only records that it ran.
      void plantGit(ScriptSandbox sb) {
        for (final folder in ['.', 'planted']) {
          File('${sb.root.path}\\$folder\\git.cmd')
            ..createSync(recursive: true)
            ..writeAsStringSync(
              '@echo off\r\n> "%STUB_LOG_DIR%\\planted-git.ran" echo ran\r\n',
            );
        }
      }

      bool plantedRan(ScriptSandbox sb) =>
          File('${sb.logs.path}\\planted-git.ran').existsSync();

      final pathsWithRelativeEntries = <String, String Function(String)>{
        'a dot': (stubs) => '.;$stubs;$systemEntries',
        'a leading empty entry': (stubs) => ';$stubs;$systemEntries',
        'a middle empty entry': (stubs) => '$stubs;;$systemEntries',
        'a relative folder': (stubs) => 'planted;$stubs;$systemEntries',
        'a quoted absolute entry': (stubs) => '.;"$stubs";$systemEntries',
      };

      for (final MapEntry(key: label, value: pathOf)
          in pathsWithRelativeEntries.entries) {
        pathTest('$label on PATH starts no program from there; the '
            'absolute git runs', () async {
          final sb = await sandboxWith();
          sb.stub(
            'git',
            [
              r'>> "%STUB_LOG_DIR%\git.log" echo %*',
              'echo git version 2.45.1.windows.1',
            ].join('\r\n'),
          );
          plantGit(sb);

          final r = await runInstall(
            sb,
            extra: {'PATH': pathOf(sb.stubs.path)},
          );

          expect(plantedRan(sb), isFalse);
          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('git'), ['--version']);
        });
      }

      // A drive root spelled with `/`, a UNC path, and a quoted entry that
      // holds a `;` are absolute; the script keeps them, quoting the last
      // again, so the git stub in each is found and runs.
      final absoluteSpellings = <String, String Function(ScriptSandbox)>{
        'a drive entry spelled with slashes': (sb) =>
            sb.stubs.path.replaceAll(r'\', '/'),
        'a UNC entry': (sb) =>
            '\\\\localhost\\${sb.stubs.path[0]}\$${sb.stubs.path.substring(2)}',
        'a quoted entry holding a semicolon': (sb) {
          final folder = Directory('${sb.root.path}\\semi;colon dir')
            ..createSync();
          File('${sb.stubs.path}\\git.cmd').copySync('${folder.path}\\git.cmd');
          return '"${folder.path}"';
        },
      };

      for (final MapEntry(key: label, value: spell)
          in absoluteSpellings.entries) {
        pathTest('$label stays on the PATH the script searches; the git '
            'there runs', () async {
          final sb = await sandboxWith();
          sb.stub(
            'git',
            [
              r'>> "%STUB_LOG_DIR%\git.log" echo %*',
              'echo git version 2.45.1.windows.1',
            ].join('\r\n'),
          );

          final r = await runInstall(
            sb,
            extra: {'PATH': '${spell(sb)};$systemEntries'},
          );

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('git'), ['--version']);
          expect(r.stdout, isNot(contains('specstone: git')));
        });
      }

      // Runs install.ps1 as `irm | iex` does, in one PowerShell session that
      // survives a refusal, then runs [after] in that same session.
      Future<ProcessResult> runIex(
        ScriptSandbox sb,
        String after, {
        Map<String, String> extra = const {},
      }) {
        final script = '${repoRoot().path}\\install.ps1';
        final command =
            '$importSessionModules'
            "try { Get-Content -Raw '$script' | Invoke-Expression } "
            r"catch { 'CAUGHT=' + $_.Exception.Message }; "
            '$after';
        return runPowerShell(
          'iex-session',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
          environment: sb.env({...archiveEnv(sb), ...extra}),
          includeParentEnvironment: false,
          workingDirectory: sb.root.path,
        );
      }

      const printNoCurrentFolder =
          r"'NOCWD=<' + $env:NoDefaultCurrentDirectoryInExePath + '>'";

      // A `.cmd` program on the PATH may run a bare `node`, and cmd.exe tries
      // the current folder before PATH. The stub git runs a bare `node`,
      // which the stubs folder answers; the run folder holds a node.cmd that
      // only records that it ran.
      pathTest('a bare node that git.cmd runs starts from the absolute '
          'entry, never from the run folder', () async {
        final sb = await sandboxWith();
        sb
          ..stub('git', ['call node %*', 'exit /b 0'].join('\r\n'))
          ..stub(
            'node',
            [
              r'>> "%STUB_LOG_DIR%\node.log" echo %*',
              'echo git version 2.45.1.windows.1',
            ].join('\r\n'),
          );
        File('${sb.root.path}\\node.cmd').writeAsStringSync(
          '@echo off\r\n> "%STUB_LOG_DIR%\\planted-node.ran" echo ran\r\n',
        );

        final r = await runInstall(sb);

        expect(File('${sb.logs.path}\\planted-node.ran').existsSync(), isFalse);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('node'), ['--version']);
      });

      // A null value leaves the key out of the child environment.
      for (final MapEntry(key: label, value: before) in <String, String?>{
        'unset': null,
        'set to 0': '0',
      }.entries) {
        pathTest('irm | iex leaves NoDefaultCurrentDirectoryInExePath as it '
            'was ($label)', () async {
          final sb = await sandboxWith();

          final r = await runIex(
            sb,
            "$printNoCurrentFolder; 'PRESENT=' + "
            '(Test-Path Env:NoDefaultCurrentDirectoryInExePath)',
            extra: {'NoDefaultCurrentDirectoryInExePath': ?before},
          );

          final printedValue = before ?? '';
          final isPresent = before == null ? 'False' : 'True';
          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            flat(r.stdout).trim(),
            endsWith('NOCWD=<$printedValue> PRESENT=$isPresent'),
          );
        });
      }

      pathTest('a refusal under irm | iex leaves PATH and '
          'NoDefaultCurrentDirectoryInExePath as they were', () async {
        final sb = await sandboxWith(damaged: true);
        final path = '.;${sb.stubs.path};$systemEntries';

        final r = await runIex(
          sb,
          "$printNoCurrentFolder; 'PATH=' + \$env:Path",
          extra: {'PATH': path},
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          flat(r.stdout),
          contains(
            'CAUGHT=specstone: checksum mismatch for $asset; '
            'the install is unchanged',
          ),
        );
        expect(flat(r.stdout), contains('NOCWD=<>'));
        expect((r.stdout as String).trim(), endsWith('PATH=$path'));
      });

      pathTest("irm | iex leaves the session's PATH as it was", () async {
        final sb = await sandboxWith();
        plantGit(sb);
        final script = '${repoRoot().path}\\install.ps1';
        final path = '.;${sb.stubs.path};$systemEntries';
        final command =
            '$importSessionModules'
            "Get-Content -Raw '$script' | Invoke-Expression; "
            r"'PATH=' + $env:Path";

        final r = await runPowerShell(
          'iex-session',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
          environment: sb.env({...archiveEnv(sb), 'PATH': path}),
          includeParentEnvironment: false,
          workingDirectory: sb.root.path,
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(plantedRan(sb), isFalse);
        expect((r.stdout as String).trim(), endsWith('PATH=$path'));
      });
    });

    pathTest("irm | iex leaves the session's "
        'ErrorActionPreference and module auto-loading as they were', () async {
      final sb = await sandboxWith();
      final script = '${repoRoot().path}\\install.ps1';
      // The script runs at the top scope, as `irm | iex` runs it; a leaked
      // strict mode would make the undefined variable throw, and a leaked
      // $PSModuleAutoLoadingPreference would stop the session's auto-loading.
      final command =
          '$importSessionModules'
          "Get-Content -Raw '$script' | Invoke-Expression; "
          r"'AUTOLOAD=' + ($null -eq $PSModuleAutoLoadingPreference); "
          r"'STRICT=' + ($null -eq $notDefinedAnywhere); "
          r"'EAP=' + $ErrorActionPreference";

      final r = await runPowerShell(
        'iex-session',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
        environment: sb.env(archiveEnv(sb)),
        includeParentEnvironment: false,
        workingDirectory: sb.root.path,
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, contains('AUTOLOAD=True'));
      expect(r.stdout, contains('STRICT=True'));
      expect((r.stdout as String).trim(), endsWith('EAP=Continue'));
    });

    group('name another stn at install', () {
      final system = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final systemEntries =
          '$system\\System32;$system\\System32\\WindowsPowerShell\\v1.0';

      String notice(String path) =>
          'specstone: another stn is at $path; '
          'stn is not installed, type specstone to run the CLI';

      // Writes another tool's `stn` file named [extension] in [folder] and
      // returns its path.
      String otherStn(String folder, String extension) {
        final file = File('$folder\\stn.$extension')
          ..createSync(recursive: true)
          ..writeAsStringSync('rem another tool\r\n');
        return file.path;
      }

      // The sandbox PATH plus [entries], the sandbox stubs kept.
      String pathWith(ScriptSandbox sb, List<String> entries) =>
          [sb.stubs.path, ...entries, systemEntries].join(';');

      // The version the fake archive's specstone.exe prints.
      const shimArchiveVersion = '0.2.0';

      // The fake archive stages the compiled stn.exe beside specstone.exe; the
      // built bundle holds no shim.
      Future<ScriptSandbox> sandboxWithShim() async {
        final sb = await createScriptSandbox();
        await sb.writeArchive('windows-x64', version: shimArchiveVersion);
        return sb;
      }

      pathTest(
        r'another stn.exe on the PATH leaves no bin\stn.exe and prints the '
        'notice once',
        () async {
          final sb = await sandboxWithShim();
          final tools = Directory('${sb.root.path}\\space tools')..createSync();
          final found = otherStn(tools.path, 'exe');

          final r = await runInstall(
            sb,
            extra: {
              'PATH': pathWith(sb, [
                '${sb.home.path}\\.specstone\\bin',
                tools.path,
              ]),
            },
          );

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(flat(r.stdout), contains(notice(found)));
          expect(
            'another stn'.allMatches(flat(r.stdout)).length,
            1,
            reason: '${r.stdout}',
          );
          expect(File('${binDir(sb)}\\specstone.exe').existsSync(), isTrue);
          expect(File('${binDir(sb)}\\stn.exe').existsSync(), isFalse);
          expect(File('${binDir(sb)}\\stn.cmd').existsSync(), isFalse);
        },
      );

      pathTest('an earlier stn.ps1 is named before a later stn.exe', () async {
        final sb = await sandboxWithShim();
        final earlier = otherStn('${sb.root.path}\\earlier', 'ps1');
        final later = otherStn('${sb.root.path}\\later', 'exe');

        final r = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, [
              '${sb.home.path}\\.specstone\\bin',
              '${sb.root.path}\\earlier',
              '${sb.root.path}\\later',
            ]),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(flat(r.stdout), contains(notice(earlier)));
        expect(flat(r.stdout), isNot(contains(later)));
        expect(File('${binDir(sb)}\\stn.exe').existsSync(), isFalse);
        expect(File('${binDir(sb)}\\stn.cmd').existsSync(), isFalse);
      });

      pathTest('two kinds in one entry name the earlier kind', () async {
        // Each case plants the later kind first, so only the kind order, not
        // the creation order, can make the earlier kind win.
        const cases = [
          (later: 'cmd', earlier: 'exe'),
          (later: 'bat', earlier: 'cmd'),
          (later: 'com', earlier: 'bat'),
          (later: 'ps1', earlier: 'com'),
        ];
        for (final (:later, :earlier) in cases) {
          final sb = await sandboxWithShim();
          final folder = '${sb.root.path}\\mixed';
          otherStn(folder, later);
          final found = otherStn(folder, earlier);

          final r = await runInstall(
            sb,
            extra: {
              'PATH': pathWith(sb, [
                '${sb.home.path}\\.specstone\\bin',
                folder,
              ]),
            },
          );

          final reason = '$earlier before $later; ${r.stderr}';
          expect(r.exitCode, 0, reason: reason);
          expect(flat(r.stdout), contains(notice(found)), reason: reason);
          expect(File('${binDir(sb)}\\stn.exe').existsSync(), isFalse);
        }
      });

      pathTest(
        'a rerun after another stn appears removes the placed stn.exe',
        () async {
          for (final sameVersion in [true, false]) {
            final sb = await sandboxWithShim();
            final bin = '${sb.home.path}\\.specstone\\bin';
            final first = await runInstall(
              sb,
              extra: {
                'PATH': pathWith(sb, [bin]),
              },
            );
            expect(first.exitCode, 0, reason: '${first.stderr}');
            expect(File('$bin\\stn.exe').existsSync(), isTrue);
            final tools = Directory('${sb.root.path}\\tools')..createSync();
            final found = otherStn(tools.path, 'cmd');
            if (!sameVersion) {
              await sb.writeArchive('windows-x64', version: '0.3.0');
            }
            final entries = {
              'PATH': pathWith(sb, [bin, tools.path]),
            };

            final r = await runInstall(sb, extra: entries);

            final reason = 'same Version: $sameVersion; ${r.stderr}';
            expect(r.exitCode, 0, reason: reason);
            expect(flat(r.stdout), contains(notice(found)), reason: reason);
            expect(File('$bin\\stn.exe').existsSync(), isFalse, reason: reason);
            if (!sameVersion) {
              final again = await runInstall(sb, extra: entries);
              expect(again.exitCode, 0, reason: '${again.stderr}');
              expect(
                File('$bin\\stn.exe.old').existsSync(),
                isFalse,
                reason: reason,
              );
              expect(
                File('$bin\\stn.exe').existsSync(),
                isFalse,
                reason: reason,
              );
            }
          }
        },
      );

      pathTest(
        'no other stn at the installed version with stn.exe missing leaves '
        'bin as it is',
        () async {
          final sb = await sandboxWithShim();
          final bin = '${sb.home.path}\\.specstone\\bin';
          final entries = {
            'PATH': pathWith(sb, [bin]),
          };
          final first = await runInstall(sb, extra: entries);
          expect(first.exitCode, 0, reason: '${first.stderr}');
          File('$bin\\stn.exe').deleteSync();

          final r = await runInstall(sb, extra: entries);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(flat(r.stdout), isNot(contains('another stn')));
          expect(File('$bin\\stn.exe').existsSync(), isFalse);
        },
      );

      pathTest(
        'a placed stn.exe that will not go reports the failed delete',
        () async {
          final sb = await sandboxWithShim();
          final bin = '${sb.home.path}\\.specstone\\bin';
          final first = await runInstall(
            sb,
            extra: {
              'PATH': pathWith(sb, [bin]),
            },
          );
          expect(first.exitCode, 0, reason: '${first.stderr}');
          final tools = Directory('${sb.root.path}\\tools')..createSync();
          final found = otherStn(tools.path, 'cmd');
          final held = File('$bin\\stn.exe').openSync();
          addTearDown(held.closeSync);

          final r = await runInstall(
            sb,
            extra: {
              'PATH': pathWith(sb, [bin, tools.path]),
            },
          );

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(flat(r.stdout), contains(notice(found)));
          expect(
            flat(r.stderr),
            contains(
              'specstone: could not remove $bin\\stn.exe: '
              'delete it yourself',
            ),
          );
          expect(File('$bin\\stn.exe').existsSync(), isTrue);
          expect(File('$bin\\stn.exe.old').existsSync(), isFalse);
        },
      );

      pathTest('a placed stn.exe that runs and will not delete is renamed to '
          '.old, and a later run deletes it', () async {
        final sb = await sandboxWithShim();
        final bin = '${sb.home.path}\\.specstone\\bin';
        final first = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, [bin]),
          },
        );
        expect(first.exitCode, 0, reason: '${first.stderr}');
        final stn = File('$bin\\stn.exe');
        final old = File('${stn.path}.old');
        await sb.compileFakeCli('0.0.1', stn.path);
        final running = await startLocked(stn.path);
        final tools = Directory('${sb.root.path}\\tools')..createSync();
        final found = otherStn(tools.path, 'cmd');
        final entries = {
          'PATH': pathWith(sb, [bin, tools.path]),
        };

        final second = await runInstall(sb, extra: entries);

        expect(second.exitCode, 0, reason: '${second.stderr}');
        expect(flat(second.stdout), contains(notice(found)));
        expect(second.stderr, isNot(contains('could not remove')));
        expect(stn.existsSync(), isFalse);
        expect(old.existsSync(), isTrue);

        await stopAndUnlock(running, old);
        final third = await runInstall(sb, extra: entries);

        expect(third.exitCode, 0, reason: '${third.stderr}');
        expect(old.existsSync(), isFalse);
        expect(stn.existsSync(), isFalse);
      });

      pathTest('a missing stn.exe comes back with the next Version', () async {
        final sb = await sandboxWithShim();
        final bin = '${sb.home.path}\\.specstone\\bin';
        final entries = {
          'PATH': pathWith(sb, [bin]),
        };
        final first = await runInstall(sb, extra: entries);
        expect(first.exitCode, 0, reason: '${first.stderr}');
        File('$bin\\stn.exe').deleteSync();
        await sb.writeArchive('windows-x64', version: '0.3.0');

        final r = await runInstall(sb, extra: entries);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(versionOf('$bin\\specstone.exe'), '0.3.0');
        expect(File('$bin\\stn.exe').existsSync(), isTrue);
      });

      pathTest('the failed removal line comes after the notice in one '
          'output stream', () async {
        final sb = await sandboxWithShim();
        final bin = '${sb.home.path}\\.specstone\\bin';
        final first = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, [bin]),
          },
        );
        expect(first.exitCode, 0, reason: '${first.stderr}');
        final tools = Directory('${sb.root.path}\\tools')..createSync();
        final found = otherStn(tools.path, 'cmd');
        final held = File('$bin\\stn.exe').openSync();
        addTearDown(held.closeSync);
        // One pipe for both streams, so the text shows the order written.
        final wrapper = File('${sb.root.path}\\merged.cmd')
          ..writeAsStringSync(
            '@echo off\r\n'
            'powershell -NoProfile -ExecutionPolicy Bypass -File '
            '"${repoRoot().path}\\install.ps1" 2>&1\r\n',
          );

        final r = await Process.run(
          'cmd',
          ['/d', '/c', wrapper.path],
          environment: sb.env({
            ...archiveEnv(sb),
            'PATH': pathWith(sb, [bin, tools.path]),
          }),
          includeParentEnvironment: false,
          workingDirectory: sb.root.path,
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        final text = flat(r.stdout);
        final removal =
            'specstone: could not remove $bin\\stn.exe: delete it yourself';
        expect(text, contains(notice(found)));
        expect(text, contains(removal));
        expect(text.indexOf(removal), greaterThan(text.indexOf(notice(found))));
      });

      pathTest('an upgrade renames the running stn.exe to .old, places none '
          'beside another stn, and a later run deletes the .old', () async {
        for (final hasOther in [false, true]) {
          final sb = await sandboxWithShim();
          final bin = '${sb.home.path}\\.specstone\\bin';
          final tools = Directory('${sb.root.path}\\tools')..createSync();
          if (hasOther) otherStn(tools.path, 'cmd');
          final entries = {
            'PATH': pathWith(sb, [bin, if (hasOther) tools.path]),
          };
          final first = await runInstall(
            sb,
            extra: {
              'PATH': pathWith(sb, [bin]),
            },
          );
          expect(first.exitCode, 0, reason: '${first.stderr}');
          final stn = File('$bin\\stn.exe');
          final old = File('${stn.path}.old');
          await sb.compileFakeCli('0.0.1', stn.path);
          final running = await startLocked(stn.path);
          await sb.writeArchive('windows-x64', version: '0.3.0');

          final upgrade = await runInstall(sb, extra: entries);

          final reason = 'another stn: $hasOther; ${upgrade.stderr}';
          expect(upgrade.exitCode, 0, reason: reason);
          expect(versionOf('$bin\\specstone.exe'), '0.3.0', reason: reason);
          expect(old.existsSync(), isTrue, reason: reason);
          expect(stn.existsSync(), !hasOther, reason: reason);

          await stopAndUnlock(running, old);
          final later = await runInstall(sb, extra: entries);

          expect(later.exitCode, 0, reason: '${later.stderr}');
          expect(old.existsSync(), isFalse, reason: reason);
        }
      });

      pathTest('two other stn name the earlier entry only', () async {
        final sb = await sandboxWithShim();
        final first = otherStn('${sb.root.path}\\first', 'exe');
        final second = otherStn('${sb.root.path}\\second', 'exe');

        final r = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, [
              '${sb.home.path}\\.specstone\\bin',
              '${sb.root.path}\\first',
              '${sb.root.path}\\second',
            ]),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(flat(r.stdout), contains(notice(first)));
        expect(flat(r.stdout), isNot(contains(second)));
      });

      pathTest('without another stn the run prints no notice', () async {
        final sb = await sandboxWithShim();

        final r = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, ['${sb.home.path}\\.specstone\\bin']),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(flat(r.stdout), isNot(contains('another stn')));
        expect(File('${binDir(sb)}\\stn.exe').existsSync(), isTrue);
      });

      pathTest('a stn on only a relative entry prints no notice', () async {
        final sb = await sandboxWithShim();
        otherStn('${sb.root.path}\\rel', 'exe');

        final r = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, ['rel', '.', '']),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(flat(r.stdout), isNot(contains('another stn')));
        expect(File('${binDir(sb)}\\stn.exe').existsSync(), isTrue);
      });

      pathTest('the install folder spelled with a trailing '
          'backslash, another case, a quoted spelling, or through a junction '
          'prints no notice', () async {
        final sb = await sandboxWithShim();
        final linked = '${sb.root.path}\\linked';
        final target = Directory('${sb.home.path}\\.specstone\\bin')
          ..createSync(recursive: true);
        final junction = Process.runSync('cmd', [
          '/d',
          '/c',
          'mklink',
          '/J',
          linked,
          target.path,
        ]);
        expect(
          junction.exitCode,
          0,
          reason: '${junction.stdout}${junction.stderr}',
        );

        for (final entry in [
          '${target.path}\\',
          target.path.toUpperCase(),
          '"${target.path}"',
          '"${target.path}\\"',
          linked,
        ]) {
          final r = await runInstall(
            sb,
            extra: {
              'PATH': pathWith(sb, [entry]),
            },
          );

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(flat(r.stdout), isNot(contains('another stn')), reason: entry);
          expect(File('${binDir(sb)}\\stn.exe').existsSync(), isTrue);
        }
      });

      pathTest('a folder named stn.exe prints no notice', () async {
        final sb = await sandboxWithShim();
        Directory('${sb.root.path}\\tools\\stn.exe')
            .createSync(recursive: true);

        final r = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, ['${sb.root.path}\\tools']),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(flat(r.stdout), isNot(contains('another stn')));
        expect(File('${binDir(sb)}\\stn.exe').existsSync(), isTrue);
      });

      pathTest(
        'a file named plain stn with no extension prints no notice',
        () async {
          final sb = await sandboxWithShim();
          File('${sb.root.path}\\tools\\stn')
            ..createSync(recursive: true)
            ..writeAsStringSync('another tool');

          final r = await runInstall(
            sb,
            extra: {
              'PATH': pathWith(sb, ['${sb.root.path}\\tools']),
            },
          );

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(flat(r.stdout), isNot(contains('another stn')));
          expect(File('${binDir(sb)}\\stn.exe').existsSync(), isTrue);
        },
      );

      pathTest('a folder holding stn.exe and specstone.exe is skipped as a '
          'Specstone install', () async {
        final sb = await sandboxWithShim();
        final copy = '${sb.root.path}\\other install';
        otherStn(copy, 'exe');
        File('$copy\\specstone.exe').writeAsStringSync('fake');
        final later = otherStn('${sb.root.path}\\later', 'exe');
        final bin = '${sb.home.path}\\.specstone\\bin';

        final alone = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, [bin, copy]),
          },
        );
        final withLater = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, [bin, copy, '${sb.root.path}\\later']),
          },
        );

        expect(alone.exitCode, 0, reason: '${alone.stderr}');
        expect(flat(alone.stdout), isNot(contains('another stn')));
        expect(withLater.exitCode, 0, reason: '${withLater.stderr}');
        expect(flat(withLater.stdout), contains(notice(later)));
        expect(flat(withLater.stdout), isNot(contains(copy)));
      });

      pathTest('a folder holding stn.cmd and specstone.exe is no marker, '
          'so its stn.cmd is named', () async {
        final sb = await sandboxWithShim();
        final copy = '${sb.root.path}\\old install';
        final found = otherStn(copy, 'cmd');
        File('$copy\\specstone.exe').writeAsStringSync('fake');

        final r = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, ['${sb.home.path}\\.specstone\\bin', copy]),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(flat(r.stdout), contains(notice(found)));
      });

      pathTest('a folder named stn.exe is no marker file, so the stn.cmd '
          'beside a specstone.exe file is named', () async {
        final sb = await sandboxWithShim();
        final copy = '${sb.root.path}\\folder marker';
        Directory('$copy\\stn.exe').createSync(recursive: true);
        final found = otherStn(copy, 'cmd');
        File('$copy\\specstone.exe').writeAsStringSync('fake');

        final r = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, ['${sb.home.path}\\.specstone\\bin', copy]),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(flat(r.stdout), contains(notice(found)));
      });

      pathTest('a quoted PATH entry holding a ; is read as the one '
          'folder inside the quotes', () async {
        final sb = await sandboxWithShim();
        final tools = Directory('${sb.root.path}\\tools;a')..createSync();
        final found = otherStn(tools.path, 'exe');

        final r = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, ['"${tools.path}"']),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(flat(r.stdout), contains(notice(found)));
      });

      pathTest('a missing absolute entry is skipped with nothing '
          'on stderr', () async {
        final sb = await sandboxWithShim();

        final r = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, ['${sb.root.path}\\no such folder']),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(flat(r.stderr), isNot(contains('stn')));
        expect(flat(r.stdout), isNot(contains('another stn')));
      });

      pathTest('api install step 5: a run at the installed Version prints the '
          'notice too', () async {
        final sb = await sandboxWithShim();
        sb.installFake(version: shimArchiveVersion);
        final tools = Directory('${sb.root.path}\\tools')..createSync();
        final found = otherStn(tools.path, 'exe');

        final r = await runInstall(
          sb,
          extra: {
            'PATH': pathWith(sb, [tools.path]),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(flat(r.stdout), contains('is already the latest release'));
        expect(flat(r.stdout), contains(notice(found)));
      });
    });
  });
}
