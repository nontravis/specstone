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

  // The `.cmd` stub mirrors the `sh` stub of install_sh_test.dart.
  Future<ScriptSandbox> sandboxWithClaude() async {
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
        'set "OUT=[]"',
        'if defined STUB_MARKETPLACES set "OUT=%STUB_MARKETPLACES%"',
        'echo %OUT%',
        'exit /b 0',
        ':plugins',
        'set "OUT=[]"',
        'if defined STUB_PLUGINS set "OUT=%STUB_PLUGINS%"',
        'echo %OUT%',
        'exit /b 0',
        ':fail',
        'echo boom 1>&2',
        'echo more 1>&2',
        'exit /b 1',
      ].join('\r\n'),
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

    pathTest('f09/us01/fr01/e05: a positional argument is the version, so one '
        'outside the form is refused', () async {
      final sb = await sandboxWith();
      sb.installFake();
      final before = sb.snapshot();

      final r = await runInstall(sb, args: ['0.1']);

      expect(r.exitCode, 1);
      expect(
        flat(r.stderr),
        contains(
          'specstone: 0.1 is not a version of the form '
          'MAJOR.MINOR.PATCH[-<pre-release>]; the install is unchanged',
        ),
      );
      expect(sb.snapshot(), before);
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

      // Refused values the shared list lacks: C1 and C0 controls the refusal
      // must print as `?`, and letters that a case-folding match would take
      // for ASCII (Kelvin sign, long s).
      const extraRefused = [
        '1.2.0\u0085',
        '1.2.0\u009b',
        '1.2.0\u001b]52;c;x\u0007',
        '1.2.0-K',
        '1.2.0-ſ',
      ];

      // A function shadows the cmdlet: it logs each URL and serves the file
      // from ARCHIVES, or fails when STUB_WEB_FAIL is set. The script runs
      // either as `-File` does (a `-Version` taken from the environment, so
      // any character crosses intact) or as the API's `iex "& {...} args"`
      // line, whose args text is HARNESS_ARGS.
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
    exit 0
  }
} else {
  & $env:INSTALL_PS1 -Version $env:SPECSTONE_TEST_VERSION
}
''';

      Future<ProcessResult> runHarness(
        ScriptSandbox sb, {
        bool isIex = false,
        String? version,
        String iexArgs = '',
        bool isDownloadFailing = false,
      }) {
        final file = File('${sb.root.path}\\harness.ps1')
          ..writeAsStringSync(harness);
        return sb.run(
          file.path,
          extra: {
            'ARCHIVES': sb.archives.path,
            'INSTALL_PS1': '${repoRoot().path}\\install.ps1',
            'HARNESS_MODE': isIex ? 'iex' : 'file',
            'HARNESS_ARGS': iexArgs,
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

      String refusal(String version) {
        final shown = version.replaceAll(RegExp(r'[\x00-\x1f\x7f-\x9f]'), '?');
        return 'specstone: $shown$refusalTail';
      }

      // The console code page may not carry a non-ASCII value back intact, so
      // such a refusal is read by its form text alone.
      void expectRefusal(String stderrText, String version) {
        final isAscii = refusal(version).codeUnits.every((unit) => unit < 0x7f);
        expect(
          flat(stderrText),
          contains(flat(isAscii ? refusal(version) : refusalTail)),
        );
      }

      for (final (label, isIex, iexArgs) in [
        ('-File', false, ''),
        ('iex line', true, '-Version 1.2.0-beta.1'),
      ]) {
        pathTest(
          '$chosen E01 ($label): the named version installs from its own '
          'release',
          () async {
            final sb = await sandboxServing('1.2.0-beta.1');

            final r = await runHarness(
              sb,
              isIex: isIex,
              version: '1.2.0-beta.1',
              iexArgs: iexArgs,
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

      for (final version in [...refusedVersions, ...extraRefused]) {
        // An environment value cannot hold NUL; `-Version ''` is no version.
        if (version.isEmpty || version.contains('\u0000')) continue;
        pathTest('$chosen E02, install_cli_and_plugin S8: refuses '
            '${jsonEncode(version)} before any download', () async {
          final sb = await createScriptSandbox();
          sb.installFake();
          final before = sb.snapshot();

          final r = await runHarness(sb, version: version);

          expect(r.exitCode, 1);
          expectRefusal('${r.stderr}', version);
          expect(sb.logOf('web'), isEmpty);
          expect(sb.snapshot(), before);
        });
      }

      for (final version in [
        'v1.2.0',
        '1.2',
        '01.2.0',
        '1.2.0-',
        '1.2.0-beta.01',
        '1.2.0+build.5',
      ]) {
        pathTest(
          '$chosen E02 (iex line): refuses $version as a throw, the session '
          'goes on',
          () async {
            final sb = await createScriptSandbox();
            sb.installFake();
            final before = sb.snapshot();

            final r = await runHarness(
              sb,
              isIex: true,
              iexArgs: '-Version $version',
            );

            expect(r.exitCode, 0, reason: '${r.stderr}');
            expect(flat(r.stdout), contains('CAUGHT=${refusal(version)}'));
            expect(sb.logOf('web'), isEmpty);
            expect(sb.snapshot(), before);
          },
        );
      }

      for (final version in acceptedVersions) {
        pathTest(
          '$chosen: ${jsonEncode(version)} passes the form check and fails '
          'as a download',
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

      pathTest('$chosen E03: a version no release carries fails as a failed '
          'download, the install unchanged', () async {
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
        expect(sb.snapshot(), before);
      });

      // `irm | iex` passes no argument; the API's line may pass an empty one.
      for (final (label, isIex, iexArgs) in [
        ('no argument, as irm | iex', true, ''),
        ("-Version ''", true, "-Version ''"),
        ('-File with no -Version', false, ''),
      ]) {
        pathTest(
          '$chosen E04 ($label): no version fetches the latest release',
          () async {
            final sb = await sandboxServing('0.2.0');

            final r = await runHarness(sb, isIex: isIex, iexArgs: iexArgs);

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
        '$chosen E05: the version already installed is named and nothing is '
        'placed',
        () async {
          final sb = await sandboxServing('1.2.0-beta.1');
          sb.installFake(version: '1.2.0-beta.1');
          final before = sb.snapshot();

          final r = await runHarness(sb, version: '1.2.0-beta.1');

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
      pathTest(
        'f09/us01/fr05/e01: an added marketplace skips the add',
        () async {
          final sb = await sandboxWithClaude();

          final r = await runInstall(
            sb,
            extra: {'STUB_MARKETPLACES': marketplaceJson},
          );

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
        final user = await sandboxWithClaude();
        final project = await sandboxWithClaude();

        final userRun = await runInstall(
          user,
          extra: {
            'STUB_MARKETPLACES': marketplaceJson,
            'STUB_PLUGINS': userPluginJson,
          },
        );
        final projectRun = await runInstall(
          project,
          extra: {
            'STUB_MARKETPLACES': marketplaceJson,
            'STUB_PLUGINS': projectPluginJson,
          },
        );

        expect(userRun.exitCode, 0, reason: '${userRun.stderr}');
        expect(user.logOf('claude'), [listMarketplaces, listPlugins]);
        expect(projectRun.exitCode, 0, reason: '${projectRun.stderr}');
        expect(project.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          installPlugin,
        ]);
      });

      pathTest('f09/us01/fr05/e03, f09/us01/s3: no claude prints both '
          'commands; exit 0', () async {
        final sb = await sandboxWith();

        final r = await runInstall(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          (r.stdout as String).replaceAll('\r\n', '\n'),
          contains(
            'To add the Specstone plugin to Claude Code, run:\n'
            '  claude plugin marketplace add nontravis/specstone\n'
            '  claude plugin install specstone@specstone\n',
          ),
        );
        expect(sb.logOf('claude'), isEmpty);
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

      pathTest('f09/us01/fr05/e04: a failing claude list stops the plugin '
          'step; exit 0', () async {
        final sb = await sandboxWithClaude();

        final r = await runInstall(sb, extra: {'STUB_FAIL': listPlugins});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          flat(r.stderr),
          contains(
            'specstone: claude $listPlugins failed: boom; run it by hand',
          ),
        );
        expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
      });
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
