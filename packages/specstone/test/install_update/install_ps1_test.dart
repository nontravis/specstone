@TestOn('windows')
@Tags(['ps1'])
@Timeout(Duration(minutes: 10))
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
  const marketplaceJson =
      '[{"name": "specstone", "source": "github", "repo": '
      '"nontravis/specstone"}]';
  const userPluginJson =
      '[{"id": "specstone@specstone", "version": "0.2.0", "scope": "user"}]';
  const projectPluginJson =
      '[{"id": "specstone@specstone", "version": "0.2.0", "scope": "project"}]';
  const listMarketplaces = 'plugin marketplace list --json';
  const listPlugins = 'plugin list --json';
  const addMarketplace = 'plugin marketplace add nontravis/specstone';
  const installPlugin = 'plugin install specstone@specstone';

  late Directory bundle;

  setUpAll(() async {
    // The bundle folder is the grandparent of bin\specstone.exe.
    bundle = File(await buildSpecstone()).parent.parent;
  });

  // PowerShell wraps a long error line at the console width; compare the text
  // with its whitespace runs folded to one space.
  String flat(Object? text) => '$text'.replaceAll(RegExp(r'\s+'), ' ');

  // Every test may write the real user PATH, so each one holds the lock and
  // gets the PATH it found written back.
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

  // The `.cmd` stub mirrors the `sh` stub of install_sh_test.dart. Each list
  // reply is the file [marketplaces] or [plugins] wrote into the logs folder
  // (`[]` without one): a file carries any JSON text, where an environment
  // value would not.
  Future<ScriptSandbox> sandboxWithClaude({
    String? marketplaces,
    String? plugins,
  }) async {
    final sb = await sandboxWith();
    sb.stub(
      'claude',
      [
        r'>> "%STUB_LOG_DIR%\claude.log" echo %*',
        'if "%*"=="%STUB_FAIL%" goto fail',
        'if "%*"=="$listMarketplaces" goto marketplaces',
        'if "%*"=="$listPlugins" goto plugins',
        'exit /b 0',
        ':marketplaces',
        r'if exist "%STUB_LOG_DIR%\marketplaces.json" (type "%STUB_LOG_DIR%\marketplaces.json") else (echo [])',
        'exit /b 0',
        ':plugins',
        r'if exist "%STUB_LOG_DIR%\plugins.json" (type "%STUB_LOG_DIR%\plugins.json") else (echo [])',
        'exit /b 0',
        ':fail',
        'echo boom 1>&2',
        'echo more 1>&2',
        'exit /b 1',
      ].join('\r\n'),
    );
    for (final (name, text) in [
      ('marketplaces', marketplaces),
      ('plugins', plugins),
    ]) {
      if (text != null) {
        File('${sb.logs.path}\\$name.json').writeAsStringSync(text);
      }
    }
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

  group('install.ps1', () {
    pathTest('f09/us01/fr01, fr02, fr03, f09/us01/s2: an empty home gets the '
        'CLI, the user PATH entry, and the plugin', () async {
      final sb = await sandboxWithClaude();

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
      expect(sb.logOf('claude'), [
        listMarketplaces,
        listPlugins,
        addMarketplace,
        installPlugin,
      ]);
    });

    pathTest('f09/us01/fr01/e03: Windows on ARM64 refuses naming the four '
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

    pathTest('f09/us01/fr01: a 32-bit PowerShell on 64-bit Windows reads '
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

    pathTest('f09/us01/fr01: with neither HOME nor USERPROFILE it '
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

    pathTest('f09/us01/fr02/e03, f09/us01/s6: a damaged zip throws, exit 1, '
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

    pathTest('f09/us01/fr03/e03, f09/us01/fr04/e01: a second run is already '
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

    pathTest('f09/us01/fr04/e01: an entry spelled in another case with a '
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

    pathTest('f09/us01/fr04: a user Path holding %USERPROFILE% keeps that '
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

    pathTest('f09/us01/fr04: a %USERPROFILE% spelling of the folder counts '
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

    pathTest('f09/us01/fr04: an empty user Path gets the entry', () async {
      final sb = await sandboxWith();
      await writeUserPath((value: '', kind: 'String'));

      final r = await runInstall(sb);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((await readUserPath())?.value, binDir(sb));
    });

    pathTest('f09/us01/fr03/e02: a running old specstone.exe is renamed to '
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

    pathTest('f09/us01/fr03/e02, e03: an equal-version run still deletes the '
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

    pathTest('f09/us01/fr03/e02: a still-locked .old stays, and the run '
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

    pathTest('f09/us01/fr03/e02: a file whose .old name a locked leftover '
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
      const chosen =
          'install_update/machine_install/install_cli_and_plugin/'
          'install_chosen_version';
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
      const harness = r'''
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
          '$chosen E01 ($label): the named version installs from its own '
          'release',
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

      pathTest(
        '$chosen E01: powershell -File install.ps1 -Version installs the '
        'named version',
        () async {
          final sb = await sandboxServing('1.2.0-beta.1');

          final r = await runInstall(sb, args: ['-Version', '1.2.0-beta.1']);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            flat(r.stdout),
            contains('specstone 1.2.0-beta.1 installed in ${binDir(sb)}'),
          );
          expect(versionOf('${binDir(sb)}\\specstone.exe'), '1.2.0-beta.1');
        },
      );

      for (final version in refusedVersions) {
        // An environment value cannot hold NUL; `-Version ''` is no version.
        if (version.isEmpty || version.contains('\u0000')) continue;
        pathTest('$chosen E02, install_cli_and_plugin S8: refuses '
            '${named(version)} before any download', () async {
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
      for (final (iexVersion, argsText) in [
        ('v1.2.0', '-Version v1.2.0'),
        ('1.2', '-Version 1.2'),
        ('01.2.0', '-Version 01.2.0'),
        ('1.2.0-', '-Version 1.2.0-'),
        ('1.2.0-beta.01', '-Version 1.2.0-beta.01'),
        ('1.2.0+build.5', '-Version 1.2.0+build.5'),
        ('1.2.0\u0000', '-Version "1.2.0`0"'),
      ]) {
        pathTest(
          '$chosen E02 (iex line): refuses ${named(iexVersion)} as a throw, '
          'the session goes on',
          () async {
            final sb = await createScriptSandbox();
            sb.installFake();
            final before = sb.snapshot();

            final r = await runHarness(
              sb,
              shape: _Shape.iex,
              iexArgs: argsText,
            );

            expect(r.exitCode, 0, reason: '${r.stderr}');
            expect(flat(r.stdout), contains('CAUGHT=${refusal(iexVersion)}'));
            expect(r.stdout, contains('PRINTABLE=True'));
            expect(sb.logOf('web'), isEmpty);
            expect(sb.snapshot(), before);
          },
        );
      }

      pathTest('$chosen E02: a positional argument is the version, so one '
          'outside the form is refused', () async {
        final sb = await sandboxWith();
        sb.installFake();
        final before = sb.snapshot();

        final r = await runInstall(sb, args: ['0.1']);

        expect(r.exitCode, 1);
        expect(flat(r.stderr), contains(refusal('0.1')));
        expect(sb.snapshot(), before);
      });

      pathTest('$chosen E02: a refusal leaves the user PATH and the plugin '
          'alone', () async {
        final sb = await sandboxWithClaude();
        final pathBefore = await readUserPath();

        final r = await runHarness(sb, version: 'v1.2.0');

        expect(r.exitCode, 1);
        expect(await readUserPath(), pathBefore);
        expect(sb.logOf('claude'), isEmpty);
        expect(sb.logOf('web'), isEmpty);
      });

      for (final version in acceptedVersions) {
        pathTest(
          '$chosen: ${named(version)} passes the form check and fails as a '
          'download',
          () async {
            final sb = await createScriptSandbox();

            final r = await runHarness(
              sb,
              version: version,
              isDownloadFailing: true,
            );

            expect(r.exitCode, 1);
            expect(flat(r.stderr), contains(downloadFailed));
            expect(flat(r.stderr), isNot(contains(refusalTail)));
            expect(
              sb.logOf('web').single,
              endsWith('$releases/download/v$version/$asset'),
            );
          },
        );
      }

      for (final (shape, label) in versionShapes) {
        pathTest('$chosen E03 ($label): a version no release carries fails as '
            'a failed download, the install unchanged', () async {
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
        pathTest(
          '$chosen E04 ($label): no version fetches the latest release',
          () async {
            final sb = await sandboxServing('0.2.0');

            final r = await runHarness(sb, shape: shape, iexArgs: iexArgs);

            expect(r.exitCode, 0, reason: '${r.stderr}');
            expect(
              sb.logOf('web').first,
              endsWith('$releases/latest/download/$asset'),
            );
            expect(versionOf('${binDir(sb)}\\specstone.exe'), '0.2.0');
          },
        );
      }

      pathTest(
        '$chosen: irm | iex leaves no \$Version in the caller',
        () async {
          final sb = await sandboxServing('0.2.0');

          final r = await runHarness(sb, shape: _Shape.pipe);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(r.stdout, contains('VERSION_DEFINED=False'));
        },
      );

      for (final (shape, label) in versionShapes) {
        pathTest(
          '$chosen E05 ($label): the version already installed is named and '
          'nothing is placed',
          () async {
            final sb = await sandboxServing('1.2.0-beta.1');
            sb.installFake(version: '1.2.0-beta.1');
            final before = sb.snapshot();

            final r = await runHarness(
              sb,
              shape: shape,
              version: '1.2.0-beta.1',
            );

            expect(r.exitCode, 0, reason: '${r.stderr}');
            expect(
              flat(r.stdout),
              contains('specstone 1.2.0-beta.1 is already installed'),
            );
            expect(r.stdout, isNot(contains('installed in')));
            expect(r.stdout, isNot(contains('latest release')));
            expect(sb.snapshot(), before);
          },
        );
      }

      pathTest('$chosen: a version that differs only in case is another '
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

      pathTest('$chosen: a named version replaces an older CLI', () async {
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

    pathTest('f09/us01/fr02/e01: a download that fails stops with the install '
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

    pathTest('f09/us01/fr02/e02: no SHA256SUMS line is a checksum failure, '
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

    pathTest('f09/us01/fr02: a downloaded binary that does not run is named, '
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

    group('plugin step', () {
      const removeMarketplace = 'plugin marketplace remove specstone';
      const plugin =
          'install_update/machine_install/install_cli_and_plugin/'
          'install_plugin';
      const beta = '1.2.0-beta.1';
      const betaSource = 'nontravis/specstone#v$beta';
      const noClaudeHeader =
          'To add the Specstone plugin to Claude Code, run (the first command '
          'only when a marketplace specstone already exists):\n';
      const unreadableTail = 'its reply could not be read; run it by hand';

      // A `marketplace list --json` reply shaped as a real claude prints it.
      String listOf(List<Map<String, Object?>> entries) =>
          const JsonEncoder.withIndent('  ').convert([
            for (final entry in entries)
              {
                'name': 'specstone',
                ...entry,
                'installLocation': r'C:\Users\x\.claude\plugins\marketplaces\x',
              },
          ]);

      String marketplaceList(Map<String, Object?> entry) => listOf([entry]);

      String officialList({String? ref}) => marketplaceList({
        'source': 'github',
        'repo': 'nontravis/specstone',
        'ref': ?ref,
      });

      String commandLines(String wanted) =>
          '  claude plugin marketplace remove specstone\n'
          '  claude plugin marketplace add $wanted\n'
          '  claude plugin install specstone@specstone\n';

      String leftLine(String source) =>
          'specstone: marketplace specstone comes from $source, not '
          'nontravis/specstone; left as it is\n';

      // Write-Host ends a line with CRLF and does not wrap it.
      String stdoutOf(ProcessResult r) =>
          (r.stdout as String).replaceAll('\r\n', '\n');

      Future<ProcessResult> runPlugin(
        ScriptSandbox sb, {
        String? version,
        Map<String, String> extra = const {},
      }) => runInstall(
        sb,
        args: [
          if (version != null) ...['-Version', version],
        ],
        extra: extra,
      );

      void expectUnreadable(
        ProcessResult r,
        ScriptSandbox sb, {
        required String list,
        required List<String> calls,
        String wanted = 'nontravis/specstone',
      }) {
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          flat(r.stderr),
          contains('specstone: claude $list failed: $unreadableTail'),
        );
        expect(stdoutOf(r), contains(noClaudeHeader + commandLines(wanted)));
        expect(sb.logOf('claude'), calls);
      }

      pathTest(
        'f09/us01/fr05/e01: an added marketplace skips the add',
        () async {
          final sb = await sandboxWithClaude(marketplaces: marketplaceJson);

          final r = await runInstall(sb);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('claude'), [
            listMarketplaces,
            listPlugins,
            installPlugin,
          ]);
        },
      );

      pathTest('f09/us01/fr05/e02: a user-scope specstone@specstone skips the '
          'install; another scope does not', () async {
        final user = await sandboxWithClaude(
          marketplaces: marketplaceJson,
          plugins: userPluginJson,
        );
        final project = await sandboxWithClaude(
          marketplaces: marketplaceJson,
          plugins: projectPluginJson,
        );

        final userRun = await runInstall(user);
        final projectRun = await runInstall(project);

        expect(userRun.exitCode, 0, reason: '${userRun.stderr}');
        expect(user.logOf('claude'), [listMarketplaces, listPlugins]);
        expect(projectRun.exitCode, 0, reason: '${projectRun.stderr}');
        expect(project.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          installPlugin,
        ]);
      });

      pathTest(
        '$plugin: a user entry of another plugin does not count',
        () async {
          final sb = await sandboxWithClaude(
            marketplaces: marketplaceJson,
            plugins:
                '[{"id": "other@specstone", "version": "1.0.0", '
                '"scope": "user"}, {"id": "specstone@specstone", '
                '"version": "0.2.0", "scope": "project"}]',
          );

          final r = await runInstall(sb);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('claude'), [
            listMarketplaces,
            listPlugins,
            installPlugin,
          ]);
        },
      );

      for (final (position, plugins) in <(String, String)>[
        (
          'second',
          '[{"id": "other@specstone", "scope": "user"}, '
              '{"id": "specstone@specstone", "scope": "user"}]',
        ),
        (
          'last',
          '[{"id": "other@specstone", "scope": "user"}, '
              '{"id": "specstone@specstone", "scope": "project"}, '
              '{"id": "specstone@specstone", "scope": "user"}]',
        ),
      ]) {
        pathTest('$plugin E02: the user entry $position among several '
            'plugins skips the install', () async {
          final sb = await sandboxWithClaude(
            marketplaces: marketplaceJson,
            plugins: plugins,
          );

          final r = await runInstall(sb);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
        });
      }

      // A plugin id or scope that reads differently from the plain one is no
      // user install: the install runs.
      for (final (label, entry) in <(String, String)>[
        (
          'an id holding an escaped NUL',
          r'{"id": "specstone@specstone\u0000", "scope": "user"}',
        ),
        (
          'an id written as an array',
          '{"id": ["specstone@specstone"], "scope": "user"}',
        ),
        (
          'a scope written as an array',
          '{"id": "specstone@specstone", "scope": ["user"]}',
        ),
        (
          'a scope in capitals',
          '{"id": "specstone@specstone", "scope": "User"}',
        ),
      ]) {
        pathTest(
          '$plugin E02: $label is no user install; the install runs',
          () async {
            final sb = await sandboxWithClaude(
              marketplaces: marketplaceJson,
              plugins: '[$entry]',
            );

            final r = await runInstall(sb);

            expect(r.exitCode, 0, reason: '${r.stderr}');
            expect(sb.logOf('claude'), [
              listMarketplaces,
              listPlugins,
              installPlugin,
            ]);
          },
        );
      }

      for (final (label, list) in <(String, String)>[
        (
          'a marketplace named specstone-extra',
          '[{"name": "specstone-extra", "source": "github", '
              '"repo": "someone/specstone-extra"}]',
        ),
        (
          'a name written Specstone',
          '[{"name": "Specstone", "source": "github", '
              '"repo": "nontravis/specstone"}]',
        ),
        (
          'a name written as an array',
          '[{"name": ["specstone"], "source": "github", '
              '"repo": "nontravis/specstone"}]',
        ),
        ('an empty list', '[]'),
        (
          'a list without specstone',
          '[{"name": "other", "source": "github", "repo": "someone/other"}]',
        ),
        ('a list of numbers', '[1, 2]'),
        ('a list holding null', '[null]'),
        (
          'a list inside the list',
          '[[{"name": "specstone", "source": "github", '
              '"repo": "nontravis/specstone", "ref": "v1.1.1"}]]',
        ),
      ]) {
        for (final (suffix, version, wanted) in [
          ('without a version', null, 'nontravis/specstone'),
          ('with a version', beta, betaSource),
        ]) {
          pathTest('$plugin: $label is no specstone entry; the add runs '
              '$suffix, then the install', () async {
            final sb = await sandboxWithClaude(marketplaces: list);

            final r = await runPlugin(sb, version: version);

            expect(r.exitCode, 0, reason: '${r.stderr}');
            expect(sb.logOf('claude'), [
              listMarketplaces,
              listPlugins,
              'plugin marketplace add $wanted',
              installPlugin,
            ]);
          });
        }
      }

      for (final (label, version, wanted) in [
        ('without a version', null, 'nontravis/specstone'),
        ('with a version', beta, betaSource),
      ]) {
        pathTest('$plugin E10, f09/us01/fr05/e03, f09/us01/s3: no claude '
            'prints the remove, the add, and the install $label; the CLI '
            'stays; exit 0', () async {
          final sb = await sandboxWith();

          final r = await runPlugin(sb, version: version);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(stdoutOf(r), contains(noClaudeHeader + commandLines(wanted)));
          expect(sb.logOf('claude'), isEmpty);
          expect(versionOf('${binDir(sb)}\\specstone.exe'), specstoneVersion);
        });
      }

      pathTest('$plugin E01: the official marketplace with no ref needs '
          'nothing without a version', () async {
        final sb = await sandboxWithClaude(
          marketplaces: officialList(),
          plugins: userPluginJson,
        );

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
        expect(r.stdout, isNot(contains('re-added')));
      });

      pathTest('$plugin E01: the official marketplace at the wanted ref needs '
          'nothing with a version', () async {
        final sb = await sandboxWithClaude(
          marketplaces: officialList(ref: 'v$beta'),
          plugins: userPluginJson,
        );

        final r = await runPlugin(sb, version: beta);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
      });

      pathTest('$plugin E01: the official marketplace at the wanted ref still '
          'installs a missing plugin', () async {
        final sb = await sandboxWithClaude(
          marketplaces: officialList(ref: 'v$beta'),
        );

        final r = await runPlugin(sb, version: beta);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          installPlugin,
        ]);
      });

      pathTest('$plugin E08, install_cli_and_plugin S7: a pinned marketplace '
          'with no version goes back to main', () async {
        final sb = await sandboxWithClaude(
          marketplaces: officialList(ref: 'v$beta'),
        );

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          removeMarketplace,
          addMarketplace,
          installPlugin,
        ]);
        expect(
          stdoutOf(r),
          contains(
            'specstone: marketplace specstone re-added from '
            'nontravis/specstone\n',
          ),
        );
      });

      pathTest('$plugin E08, install_cli_and_plugin S7: an unpinned '
          'marketplace with a version moves to the tag', () async {
        final sb = await sandboxWithClaude(marketplaces: officialList());

        final r = await runPlugin(sb, version: beta);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          removeMarketplace,
          'plugin marketplace add $betaSource',
          installPlugin,
        ]);
        expect(
          stdoutOf(r),
          contains(
            'specstone: marketplace specstone re-added from $betaSource\n',
          ),
        );
      });

      pathTest('$plugin E08: a marketplace at another tag moves to the '
          'wanted tag', () async {
        final sb = await sandboxWithClaude(
          marketplaces: officialList(ref: 'v1.1.1'),
        );

        final r = await runPlugin(sb, version: beta);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          removeMarketplace,
          'plugin marketplace add $betaSource',
          installPlugin,
        ]);
      });

      pathTest('$plugin E08: a ref holding an escaped NUL is another ref, so '
          'the marketplace moves', () async {
        final sb = await sandboxWithClaude(
          marketplaces:
              '[{"name": "specstone", "source": "github", '
              '"repo": "nontravis/specstone", "ref": "v$beta\\u0000"}]',
          plugins: userPluginJson,
        );

        final r = await runPlugin(sb, version: beta);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          removeMarketplace,
          'plugin marketplace add $betaSource',
          installPlugin,
        ]);
      });

      // A ref that is null, a number, or empty reads as no ref.
      for (final (label, ref) in <(String, String)>[
        ('null', 'null'),
        ('a number', '5'),
        ('an empty string', '""'),
      ]) {
        final list =
            '[{"name": "specstone", "source": "github", '
            '"repo": "nontravis/specstone", "ref": $ref}]';

        pathTest('$plugin E01: a ref of $label reads as no ref; nothing '
            'moves without a version', () async {
          final sb = await sandboxWithClaude(
            marketplaces: list,
            plugins: userPluginJson,
          );

          final r = await runInstall(sb);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
        });

        pathTest('$plugin E08: a ref of $label reads as no ref; the '
            'marketplace moves to the tag of a version', () async {
          final sb = await sandboxWithClaude(marketplaces: list);

          final r = await runPlugin(sb, version: beta);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('claude'), [
            listMarketplaces,
            listPlugins,
            removeMarketplace,
            'plugin marketplace add $betaSource',
            installPlugin,
          ]);
        });
      }

      pathTest('$plugin E08: the remove uninstalled the plugin, so the '
          'install runs although the earlier list held it', () async {
        final sb = await sandboxWithClaude(
          marketplaces: officialList(ref: 'v$beta'),
          plugins: userPluginJson,
        );

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), contains(installPlugin));
      });

      pathTest('$plugin E09: a failing add after the remove names the add; no '
          'install; exit 0', () async {
        final sb = await sandboxWithClaude(
          marketplaces: officialList(ref: 'v$beta'),
        );

        final r = await runInstall(sb, extra: {'STUB_FAIL': addMarketplace});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          flat(r.stderr),
          contains(
            'specstone: claude $addMarketplace failed: boom; run it by hand',
          ),
        );
        expect(r.stdout, isNot(contains('re-added')));
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          removeMarketplace,
          addMarketplace,
        ]);
        expect(versionOf('${binDir(sb)}\\specstone.exe'), specstoneVersion);
      });

      pathTest('$plugin E09: a failing remove names the remove; no add, no '
          'install; exit 0', () async {
        final sb = await sandboxWithClaude(
          marketplaces: officialList(ref: 'v$beta'),
        );

        final r = await runInstall(sb, extra: {'STUB_FAIL': removeMarketplace});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          flat(r.stderr),
          contains(
            'specstone: claude $removeMarketplace failed: boom; run it by '
            'hand',
          ),
        );
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          removeMarketplace,
        ]);
      });

      // Each entry is the Owner's own source, never removed: E11 and its
      // look-alikes (a path holding `}` and `"`, repos that differ by case or
      // by a near-miss name, repo values written as an array or with an
      // escape, a soft hyphen, or a NUL, a directory or git source that
      // names the official repo, a source type with no key to read, urls
      // with userinfo, and a non-ASCII path shown as `?`).
      for (final (label, entry, source)
          in <(String, Map<String, Object?>, String)>[
            (
              'a directory',
              {'source': 'directory', 'path': '/work/specstone'},
              '/work/specstone',
            ),
            (
              'a fork',
              {'source': 'github', 'repo': 'someone/specstone'},
              'someone/specstone',
            ),
            (
              'a directory path holding } and a quote',
              {
                'source': 'directory',
                'path': '/work/a}b"c, "name": "specstone',
              },
              '/work/a}b"c, "name": "specstone',
            ),
            (
              'a repo that differs by case',
              {'source': 'github', 'repo': 'NonTravis/Specstone'},
              'NonTravis/Specstone',
            ),
            (
              'a git source with a GitHub URL',
              {
                'source': 'git',
                'url': 'https://github.com/nontravis/specstone.git',
              },
              'https://github.com/nontravis/specstone.git',
            ),
            (
              'the near-miss repo nontravis/specstone-fork',
              {'source': 'github', 'repo': 'nontravis/specstone-fork'},
              'nontravis/specstone-fork',
            ),
            (
              'the near-miss repo xnontravis/specstone',
              {'source': 'github', 'repo': 'xnontravis/specstone'},
              'xnontravis/specstone',
            ),
            (
              'the near-miss repo nontravis/specstone.git',
              {'source': 'github', 'repo': 'nontravis/specstone.git'},
              'nontravis/specstone.git',
            ),
            (
              'a repo written as an array',
              {
                'source': 'github',
                'repo': ['nontravis/specstone'],
              },
              'an unknown source',
            ),
            (
              'a repo holding an escaped NUL',
              {'source': 'github', 'repo': 'nontravis/specstone\u0000'},
              r'nontravis/specstone\u0000',
            ),
            (
              'a repo holding a soft hyphen',
              {'source': 'github', 'repo': 'nontravis/spec\u00adstone'},
              'nontravis/spec?stone',
            ),
            (
              'a source written GitHub',
              {'source': 'GitHub', 'repo': 'nontravis/specstone'},
              'an unknown source',
            ),
            (
              'a repo key written in capitals',
              {'source': 'github', 'Repo': 'nontravis/specstone'},
              'an unknown source',
            ),
            (
              'a directory entry that names the official repo',
              {
                'source': 'directory',
                'repo': 'nontravis/specstone',
                'path': '/work/specstone',
              },
              '/work/specstone',
            ),
            (
              'a git entry that names the official repo',
              {
                'source': 'git',
                'repo': 'nontravis/specstone',
                'url': 'https://example.com/specstone.git',
              },
              'https://example.com/specstone.git',
            ),
            (
              'a Windows directory path',
              {'source': 'directory', 'path': r'C:\work\x'},
              r'C:\work\x',
            ),
            (
              'a non-ASCII path, shown as a question mark',
              {'source': 'directory', 'path': '/work/café'},
              '/work/caf?',
            ),
            (
              'a repo holding a zero-width space, equal only by culture rules',
              {'source': 'github', 'repo': 'nontravis/specstone\u200b'},
              'nontravis/specstone?',
            ),
            (
              'a git url with user and token before the host',
              {
                'source': 'git',
                'url': 'https://user:token@example.com/specstone.git',
              },
              'https://example.com/specstone.git',
            ),
            (
              'a git url with an at sign after the host',
              {'source': 'git', 'url': 'https://token@example.com/a/b@c?x=y@z'},
              'https://example.com/a/b@c?x=y@z',
            ),
            (
              'a source type with no key to read',
              {'source': 'settings'},
              'an unknown source',
            ),
            (
              'an npm source',
              {'source': 'npm', 'package': 'specstone'},
              'an unknown source',
            ),
          ]) {
        for (final (suffix, version, wanted) in [
          ('without a version', null, 'nontravis/specstone'),
          if (label == 'a directory' || label == 'a fork')
            ('with a version', beta, betaSource),
        ]) {
          pathTest(
            '$plugin E11: $label is never removed $suffix; the '
            'commands print; the install runs for a missing plugin',
            () async {
              final sb = await sandboxWithClaude(
                marketplaces: marketplaceList(entry),
              );

              final r = await runPlugin(sb, version: version);

              expect(r.exitCode, 0, reason: '${r.stderr}');
              expect(
                stdoutOf(r),
                contains(leftLine(source) + commandLines(wanted)),
              );
              expect(sb.logOf('claude'), [
                listMarketplaces,
                listPlugins,
                installPlugin,
              ]);
            },
          );
        }
      }

      pathTest('$plugin E11: another source with the plugin installed runs no '
          'install', () async {
        final sb = await sandboxWithClaude(
          marketplaces: marketplaceList({
            'source': 'directory',
            'path': '/work/specstone',
          }),
          plugins: userPluginJson,
        );

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(stdoutOf(r), contains(leftLine('/work/specstone')));
        expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
      });

      pathTest('$plugin E11: an official-looking value inside another key '
          'does not make the entry official', () async {
        final sb = await sandboxWithClaude(
          marketplaces: marketplaceList({
            'source': 'directory',
            'path': '/w", "source": "github", "repo": "nontravis/specstone',
          }),
          plugins: userPluginJson,
        );

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(stdoutOf(r), contains('left as it is\n'));
        expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
      });

      // An escape other than \" and \\ stays as typed, so no escaped value
      // equals the plain official one (L19).
      for (final (label, repo) in <(String, String)>[
        ('an escaped slash', r'nontravis\/specstone'),
        ('a unicode escape', r'nontravis\u002fspecstone'),
      ]) {
        pathTest('$plugin E11: $label in a repo stays as typed, so the entry '
            'is another source', () async {
          final sb = await sandboxWithClaude(
            marketplaces:
                '[{"name": "specstone", "source": "github", '
                '"repo": "$repo"}]',
            plugins: userPluginJson,
          );

          final r = await runInstall(sb);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            stdoutOf(r),
            contains(leftLine(repo) + commandLines('nontravis/specstone')),
          );
          expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
        });
      }

      pathTest('$plugin E11: an escape in the source also makes the entry '
          'another source, so a version never removes it', () async {
        final sb = await sandboxWithClaude(
          marketplaces:
              r'[{"name": "specstone", "source": "githu\u0062", '
              '"repo": "nontravis/specstone"}]',
          plugins: userPluginJson,
        );

        final r = await runPlugin(sb, version: beta);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(stdoutOf(r), contains('left as it is\n'));
        expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
      });

      pathTest(
        '$plugin E06: a key named Values does not hide a repeated key',
        () async {
          final sb = await sandboxWithClaude(
            marketplaces:
                '[{"name": "specstone", "source": "github", "Values": 1, '
                '"repo": "nontravis/specstone", "repo": "x/y"}]',
          );

          final r = await runInstall(sb);

          expectUnreadable(
            r,
            sb,
            list: listMarketplaces,
            calls: [listMarketplaces],
          );
        },
      );

      // JSON forbids a raw control character inside a string, so the walk
      // refuses any of them as json_scan does (L18, L20). A lone CR also
      // splits a line of native output, so it may reach the walk as a line
      // feed; the reply is refused either way.
      for (final (label, path) in <(String, String)>[
        ('an escape character', '/w\u001b[2Jx'),
        ('a carriage return', '/a\r/b'),
        ('a tab', '/a\t/b'),
      ]) {
        pathTest(
          '$plugin E06: a raw $label inside a string stops the step',
          () async {
            final sb = await sandboxWithClaude(
              marketplaces:
                  '[{"name": "specstone", "source": "directory", '
                  '"path": "$path"}]',
              plugins: userPluginJson,
            );

            final r = await runInstall(sb);

            expectUnreadable(
              r,
              sb,
              list: listMarketplaces,
              calls: [listMarketplaces],
            );
          },
        );
      }

      // Only an entry's own keys are read: a key deeper in a value, even one
      // written with a quote or a backslash, or one that PowerShell reserves
      // for its own members, never stops the step. Nesting is unbounded.
      pathTest('$plugin: keys deeper in a marketplace entry do not stop the '
          'step', () async {
        final deep = '${'[' * 150}1${']' * 150}';
        final sb = await sandboxWithClaude(
          marketplaces:
              '[{"name": "specstone", "source": "github", '
              '"repo": "nontravis/specstone", '
              r'"settings": {"we\"ird\\key": 1, "psobject": 2}, '
              '"psobject": 3, "deep": $deep}]',
          plugins: userPluginJson,
        );

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stderr, isEmpty);
        expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
      });

      pathTest('$plugin: a key with a quote deeper in a plugin entry does '
          'not stop the step', () async {
        final sb = await sandboxWithClaude(
          marketplaces: officialList(),
          plugins: const JsonEncoder.withIndent('  ').convert([
            {
              'id': 'specstone@specstone',
              'scope': 'user',
              'mcpServers': {'we"ird': <String, Object?>{}},
            },
          ]),
        );

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stderr, isEmpty);
        expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
      });

      pathTest('$plugin: a brace and a quote inside a plugin string do not '
          'hide the user entry', () async {
        final sb = await sandboxWithClaude(
          marketplaces: officialList(),
          plugins: const JsonEncoder.withIndent('  ').convert([
            {
              'id': 'other@x',
              'scope': 'project',
              'installPath': '/a}b"c, "scope": "user',
            },
            {'id': 'specstone@specstone', 'scope': 'user'},
          ]),
        );

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
      });

      pathTest('$plugin: a name written inside another entry is not '
          'specstone', () async {
        final sb = await sandboxWithClaude(
          marketplaces: marketplaceList({
            'name': 'other',
            'source': 'directory',
            'path': '/w", "name": "specstone',
          }),
        );

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          addMarketplace,
          installPlugin,
        ]);
      });

      // Each reply exits 0 but is not read for sure (L18, L20): the step stops
      // with E06's failure line, prints the three commands, and runs nothing
      // after the list.
      for (final (label, reply) in <(String, String)>[
        ('text that is not JSON', 'not json at all'),
        ('text before the JSON', 'Loading marketplaces...\n${officialList()}'),
        ('text after the JSON', '${officialList()}\nDone.'),
        (
          'a top-level object',
          '{"name": "specstone", "source": "github", '
              '"repo": "nontravis/specstone"}',
        ),
        ('an empty reply', ''),
        (
          'two specstone entries',
          listOf([
            {'source': 'github', 'repo': 'nontravis/specstone'},
            {'source': 'directory', 'path': '/work/specstone'},
          ]),
        ),
        (
          'a repeated key',
          '[{"name": "specstone", "source": "github", '
              '"repo": "nontravis/specstone", "repo": "x/y"}]',
        ),
        (
          'a repeated key with the official value last',
          '[{"name": "specstone", "source": "github", '
              '"repo": "x/fork", "repo": "nontravis/specstone"}]',
        ),
        (
          'a bare key before a repeated one with the official value last',
          '[{"name":"specstone","source":"github",repo:"someone/fork",'
              '"repo":"nontravis/specstone","ref":"v1.1.1"}]',
        ),
        (
          'an escaped key beside the official pair',
          '[{"name": "specstone", "source": "github", '
              r'"repo": "nontravis/specstone", "re\u0070o": "attacker/x"}]',
        ),
        (
          'a single-quoted key',
          '[{"name": "specstone", "source": "github", '
              "'repo': \"nontravis/specstone\"}]",
        ),
        (
          'a single-quoted value',
          "[{\"name\": \"specstone\", \"source\": 'github'}]",
        ),
        (
          'a raw line feed inside a string',
          '[{"name": "specstone", "source": "directory", "path": "/a\n/b"}]',
        ),
        ('a no-break space before the list', '\u00a0${officialList()}'),
        (
          'a comma before the closing bracket',
          '[{"name": "specstone", "source": "github"},]',
        ),
        (
          'a nested object as source',
          '[{"name": "specstone", "source": {"kind": "github"}}]',
        ),
        (
          'an array as source',
          '[{"name": "specstone", "source": ["github"], '
              '"repo": "nontravis/specstone"}]',
        ),
        (
          'a number as source',
          '[{"name": "specstone", "source": 5, "repo": "nontravis/specstone"}]',
        ),
        ('no source', '[{"name": "specstone", "repo": "nontravis/specstone"}]'),
        (
          'a list cut short',
          '[{"name": "specstone", "source": "github", '
              '"repo": "nontravis/specstone", "ref": "v$beta"',
        ),
      ]) {
        pathTest('$plugin E06: a marketplace list that is $label stops the '
            'step; the commands print; exit 0', () async {
          final sb = await sandboxWithClaude(
            marketplaces: reply,
            plugins: userPluginJson,
          );

          final r = await runInstall(sb);

          expectUnreadable(
            r,
            sb,
            list: listMarketplaces,
            calls: [listMarketplaces],
          );
          expect(versionOf('${binDir(sb)}\\specstone.exe'), specstoneVersion);
        });
      }

      pathTest('$plugin E06: an unreadable marketplace list prints the wanted '
          'source of a version', () async {
        final sb = await sandboxWithClaude(marketplaces: 'not json at all');

        final r = await runPlugin(sb, version: beta);

        expectUnreadable(
          r,
          sb,
          list: listMarketplaces,
          calls: [listMarketplaces],
          wanted: betaSource,
        );
      });

      for (final (label, reply) in <(String, String)>[
        ('text that is not JSON', 'not json at all'),
        ('text after the JSON', '$userPluginJson\nDone.'),
        ('an empty reply', ''),
        ('a top-level object', '{"id": "specstone@specstone"}'),
        (
          'a repeated scope key',
          '[{"id": "specstone@specstone", "scope": "project", '
              '"scope": "user"}]',
        ),
        (
          'an escaped key',
          r'[{"id": "specstone@specstone", "sc\u006fpe": "user"}]',
        ),
        ('a list cut short', '[{"id": "specstone@specstone", "scope": "user"'),
      ]) {
        pathTest('$plugin E06: a plugin list that is $label stops the step; '
            'the commands print; exit 0', () async {
          final sb = await sandboxWithClaude(
            marketplaces: officialList(ref: 'v$beta'),
            plugins: reply,
          );

          final r = await runInstall(sb);

          expectUnreadable(
            r,
            sb,
            list: listPlugins,
            calls: [listMarketplaces, listPlugins],
          );
        });
      }

      pathTest('$plugin E06: an unreadable plugin list prints the wanted '
          'source of a version', () async {
        final sb = await sandboxWithClaude(
          marketplaces: officialList(ref: 'v$beta'),
          plugins: 'not json at all',
        );

        final r = await runPlugin(sb, version: beta);

        expectUnreadable(
          r,
          sb,
          list: listPlugins,
          calls: [listMarketplaces, listPlugins],
          wanted: betaSource,
        );
      });

      // Selection is by name, wherever the entry sits in the list and
      // whatever the others say about the official repo.
      final others = <Map<String, Object?>>[
        {
          'name': 'other',
          'source': 'github',
          'repo': 'someone/other',
          'ref': 'main',
        },
        {'name': 'mirror', 'source': 'github', 'repo': 'nontravis/specstone'},
      ];
      final pinned = <String, Object?>{
        'source': 'github',
        'repo': 'nontravis/specstone',
        'ref': 'v$beta',
      };
      for (final (position, entries) in <(String, List<Map<String, Object?>>)>[
        ('first', [pinned, ...others]),
        ('in the middle', [others[0], pinned, others[1]]),
        ('last', [...others, pinned]),
      ]) {
        pathTest('$plugin E08: the specstone marketplace $position among '
            'several is the one moved', () async {
          final sb = await sandboxWithClaude(marketplaces: listOf(entries));

          final r = await runInstall(sb);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('claude'), [
            listMarketplaces,
            listPlugins,
            removeMarketplace,
            addMarketplace,
            installPlugin,
          ]);
        });
      }

      for (final (position, mirrorFirst) in [
        ('before', true),
        ('after', false),
      ]) {
        pathTest('$plugin E11: another marketplace on the official repo '
            '$position a folder specstone does not make it official', () async {
          final folder = {'source': 'directory', 'path': '/work/specstone'};
          final sb = await sandboxWithClaude(
            marketplaces: listOf([
              if (mirrorFirst) others[1],
              folder,
              if (!mirrorFirst) others[1],
            ]),
            plugins: userPluginJson,
          );

          final r = await runInstall(sb);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(stdoutOf(r), contains(leftLine('/work/specstone')));
          expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
        });
      }

      pathTest('$plugin: another name holding the official repo is not '
          'specstone; the add runs', () async {
        final sb = await sandboxWithClaude(
          marketplaces: listOf([others[0], others[1]]),
        );

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          addMarketplace,
          installPlugin,
        ]);
      });

      pathTest('f09/us01/fr05/e04: a failing claude plugin install names its '
          'first stderr line; exit 0', () async {
        final sb = await sandboxWithClaude();

        final r = await runInstall(sb, extra: {'STUB_FAIL': installPlugin});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          flat(r.stderr),
          contains(
            'specstone: claude $installPlugin failed: boom; run it by hand',
          ),
        );
        expect(versionOf('${binDir(sb)}\\specstone.exe'), specstoneVersion);
      });

      for (final (label, list) in [
        ('marketplace', listMarketplaces),
        ('plugin', listPlugins),
      ]) {
        pathTest('$plugin E06, f09/us01/fr05/e04: a failing $label list stops '
            'the plugin step; exit 0', () async {
          final sb = await sandboxWithClaude();

          final r = await runInstall(sb, extra: {'STUB_FAIL': list});

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            flat(r.stderr),
            contains('specstone: claude $list failed: boom; run it by hand'),
          );
          expect(sb.logOf('claude'), [
            listMarketplaces,
            if (list == listPlugins) listPlugins,
          ]);
        });
      }
    });

    group('PATH search (G8-R10)', () {
      final system = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final systemEntries =
          '$system\\System32;$system\\System32\\WindowsPowerShell\\v1.0';

      // A planted claude.cmd sits in the run folder and in a relative
      // `planted` folder; it only records that it ran.
      void plantClaude(ScriptSandbox sb) {
        for (final folder in ['.', 'planted']) {
          File('${sb.root.path}\\$folder\\claude.cmd')
            ..createSync(recursive: true)
            ..writeAsStringSync(
              '@echo off\r\n> "%STUB_LOG_DIR%\\planted-claude.ran" echo ran\r\n',
            );
        }
      }

      bool plantedRan(ScriptSandbox sb) =>
          File('${sb.logs.path}\\planted-claude.ran').existsSync();

      final pathsWithRelativeEntries = <String, String Function(String)>{
        'a dot': (stubs) => '.;$stubs;$systemEntries',
        'a leading empty entry': (stubs) => ';$stubs;$systemEntries',
        'a middle empty entry': (stubs) => '$stubs;;$systemEntries',
        'a relative folder': (stubs) => 'planted;$stubs;$systemEntries',
        'a quoted absolute entry': (stubs) => '.;"$stubs";$systemEntries',
      };

      for (final MapEntry(key: label, value: pathOf)
          in pathsWithRelativeEntries.entries) {
        pathTest('$label on PATH never starts a program from there; the '
            'absolute claude runs', () async {
          final sb = await sandboxWithClaude();
          plantClaude(sb);

          final r = await runInstall(
            sb,
            extra: {'PATH': pathOf(sb.stubs.path)},
          );

          expect(plantedRan(sb), isFalse);
          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('claude'), [
            listMarketplaces,
            listPlugins,
            addMarketplace,
            installPlugin,
          ]);
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
            "try { Get-Content -Raw '$script' | Invoke-Expression } "
            r"catch { 'CAUGHT=' + $_.Exception.Message }; "
            '$after';
        return Process.run(
          'powershell',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
          environment: sb.env({...archiveEnv(sb), ...extra}),
          includeParentEnvironment: false,
          workingDirectory: sb.root.path,
        );
      }

      const printNoCurrentFolder =
          r"'NOCWD=<' + $env:NoDefaultCurrentDirectoryInExePath + '>'";

      // The `.cmd` shim that npm writes runs a bare `node` when no node.exe
      // sits beside it, and cmd.exe tries the current folder before PATH.
      // The stub claude runs a bare `node`, which the stubs folder answers;
      // the run folder holds a node.cmd that only records that it ran.
      pathTest('a bare node that claude.cmd runs starts from the absolute '
          'entry, never from the run folder', () async {
        final sb = await sandboxWith();
        sb
          ..stub(
            'claude',
            [
              r'>> "%STUB_LOG_DIR%\claude.log" echo %*',
              'call node %*',
              'exit /b 0',
            ].join('\r\n'),
          )
          ..stub(
            'node',
            [r'>> "%STUB_LOG_DIR%\node.log" echo %*', 'echo []'].join('\r\n'),
          );
        File('${sb.root.path}\\node.cmd').writeAsStringSync(
          '@echo off\r\n> "%STUB_LOG_DIR%\\planted-node.ran" echo ran\r\n',
        );

        final r = await runInstall(sb);

        expect(File('${sb.logs.path}\\planted-node.ran').existsSync(), isFalse);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('node'), [
          listMarketplaces,
          listPlugins,
          addMarketplace,
          installPlugin,
        ]);
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
        plantClaude(sb);
        final script = '${repoRoot().path}\\install.ps1';
        final path = '.;${sb.stubs.path};$systemEntries';
        final command =
            "Get-Content -Raw '$script' | Invoke-Expression; "
            r"'PATH=' + $env:Path";

        final r = await Process.run(
          'powershell',
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

    pathTest("f09/us01/fr01: irm | iex leaves the session's "
        'ErrorActionPreference as it was', () async {
      final sb = await sandboxWith();
      final script = '${repoRoot().path}\\install.ps1';
      // The script runs at the top scope, as `irm | iex` runs it; a leaked
      // strict mode would make the undefined variable throw.
      final command =
          "Get-Content -Raw '$script' | Invoke-Expression; "
          r"'STRICT=' + ($null -eq $notDefinedAnywhere); "
          r"'EAP=' + $ErrorActionPreference";

      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
        environment: sb.env(archiveEnv(sb)),
        includeParentEnvironment: false,
        workingDirectory: sb.root.path,
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, contains('STRICT=True'));
      expect((r.stdout as String).trim(), endsWith('EAP=Continue'));
    });
  });
}
