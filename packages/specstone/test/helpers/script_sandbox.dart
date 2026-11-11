import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package_root.dart';

/// Returns the code repo root, two levels above the specstone package.
Directory repoRoot() {
  final path = Directory.fromUri(packageRoot().uri.resolve('../../')).path;
  return Directory(
    path.endsWith(Platform.pathSeparator)
        ? path.substring(0, path.length - 1)
        : path,
  );
}

/// Creates a [ScriptSandbox] under a new temp folder.
///
/// The folder is deleted by `addTearDown`. On POSIX a `uname` stub answers
/// `STUB_UNAME_S` (default `Linux`) for `-s` and `STUB_UNAME_M` (default
/// `x86_64`) for `-m`.
Future<ScriptSandbox> createScriptSandbox() async {
  final root = await Directory.systemTemp.createTemp('specstone_sandbox_');
  addTearDown(() => root.delete(recursive: true));
  final sandbox = ScriptSandbox._(root);
  for (final folder in [
    sandbox.home,
    sandbox.stubs,
    sandbox.archives,
    sandbox.logs,
    sandbox._tmp,
  ]) {
    await folder.create();
  }
  if (!Platform.isWindows) {
    sandbox.stub('uname', r'''
case "$1" in
  -s) echo "${STUB_UNAME_S:-Linux}" ;;
  -m) echo "${STUB_UNAME_M:-x86_64}" ;;
esac''');
  }
  return sandbox;
}

/// A temp home, PATH stubs, fake release archives, and script runs.
final class ScriptSandbox {
  new _(this.root)
    : home = Directory(_under(root, 'home')),
      stubs = Directory(_under(root, 'stubs')),
      archives = Directory(_under(root, 'archives')),
      logs = Directory(_under(root, 'logs')),
      _tmp = Directory(_under(root, 'tmp'));

  static final bool _windows = Platform.isWindows;

  // Windows PowerShell 5.1 renders a progress bar for archive and copy
  // cmdlets, which costs seconds per call; every sandbox call turns it off.
  static const _quiet = r"$ProgressPreference = 'SilentlyContinue'; ";

  // Zip bytes by bundle path, or `fake:<version>` for the fake release. One
  // archive build serves every test of a run that asks for the same bundle.
  static final Map<String, List<int>> _zipCache = {};
  static final String _separator = Platform.pathSeparator;

  static String _under(Directory parent, String name) =>
      '${parent.path}$_separator$name';

  final Directory root;
  final Directory home;
  final Directory stubs;
  final Directory archives;
  final Directory logs;
  final Directory _tmp;

  /// Returns the environment a script runs with, then applies [extra].
  ///
  /// A value of `''` in [extra] removes that key.
  Map<String, String> env([Map<String, String> extra = const {}]) {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final base = _windows
        ? {
            'HOME': home.path,
            'USERPROFILE': home.path,
            'PATH':
                '${stubs.path};$systemRoot\\System32;'
                '$systemRoot\\System32\\WindowsPowerShell\\v1.0',
            'SystemRoot': systemRoot,
            'ComSpec': '$systemRoot\\System32\\cmd.exe',
            // PowerShell finds the `.cmd` stubs through PATHEXT.
            'PATHEXT': '.COM;.EXE;.BAT;.CMD',
            'TEMP': _tmp.path,
            'TMP': _tmp.path,
            'STUB_LOG_DIR': logs.path,
            'PROCESSOR_ARCHITECTURE': 'AMD64',
            // Without these a Windows PowerShell 5.1 child finds no module
            // analysis cache and analyzes every module again on its first
            // cmdlet. Nothing else of the user profile reaches the child.
            'PSModulePath': ?Platform.environment['PSModulePath'],
            _cacheVariable: _moduleAnalysisCachePath(),
          }
        : {
            'HOME': home.path,
            'PATH': '${stubs.path}:/usr/bin:/bin:/usr/sbin:/sbin',
            'SHELL': '/bin/zsh',
            'TMPDIR': _tmp.path,
            'STUB_LOG_DIR': logs.path,
          };
    return {...base, ...extra}..removeWhere((_, value) => value.isEmpty);
  }

  /// Writes an executable [name] to the stubs folder that runs [body].
  void stub(String name, String body) {
    if (_windows) {
      File(_under(stubs, '$name.cmd'))
          .writeAsStringSync('@echo off\r\n$body\r\n');
      return;
    }
    final file = File(_under(stubs, name))
      ..writeAsStringSync('#!/bin/sh\n$body\n');
    _chmodExecutable(file);
  }

  /// Returns the lines of the `<name>.log` file in the logs folder.
  List<String> logOf(String name) {
    final file = File(_under(logs, '$name.log'));
    return file.existsSync() ? file.readAsLinesSync() : const [];
  }

  /// Writes the release archive for [target] and a `SHA256SUMS` beside it.
  ///
  /// The archive holds `bin/`, `lib/libfake.so`, `LICENSE`, and
  /// `THIRD_PARTY_NOTICES`; `bin/specstone` prints [version] unless [bundle],
  /// a `dart build cli` output folder, supplies `bin/` and `lib/`.
  /// [damaged] records the hash of other bytes; [withSumsLine] false records
  /// only another asset's line.
  Future<File> writeArchive(
    String target, {
    String version = '0.2.0',
    Directory? bundle,
    bool damaged = false,
    bool withSumsLine = true,
  }) async {
    final zip = target == 'windows-x64';
    final asset = 'specstone-$target.${zip ? 'zip' : 'tar.gz'}';
    final archive = File(_under(archives, asset));
    final cacheKey = bundle?.path ?? 'fake:$version';
    final cached = zip ? _zipCache[cacheKey] : null;
    if (cached != null) {
      await archive.writeAsBytes(cached);
    } else {
      final stage = await root.createTemp('stage_');
      await _fillStage(stage, version: version, bundle: bundle);
      await _pack(stage, archive, zip: zip);
      if (zip) _zipCache[cacheKey] = archive.readAsBytesSync();
    }

    final bytes = archive.readAsBytesSync();
    final hashed = damaged ? [...bytes, 0] : bytes;
    final sums = File(_under(archives, 'SHA256SUMS'));
    final kept = [
      if (sums.existsSync())
        for (final line in sums.readAsLinesSync())
          if (!line.endsWith('  $asset')) line,
    ];
    final entry = withSumsLine
        ? '${sha256.convert(hashed)}  $asset'
        : '${sha256.convert(utf8.encode('other'))}  specstone-other.tar.gz';
    if (withSumsLine || kept.isEmpty) kept.add(entry);
    await sums.writeAsString('${kept.join('\n')}\n');
    return archive;
  }

  /// Puts an installed binary and a library under `home/.specstone`.
  ///
  /// On Windows the binary is a compiled fake (see [compileFakeCli]), so this
  /// takes a few seconds there.
  void installFake({String version = '0.1.0'}) {
    final install = _under(home, '.specstone');
    if (_windows) {
      _compileFakeCliSync(
        version,
        '$install${_separator}bin${_separator}specstone.exe',
      );
    } else {
      final binary = File('$install/bin/specstone')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho $version\n');
      _chmodExecutable(binary);
    }
    File('$install${_separator}lib${_separator}libold.so')
      ..createSync(recursive: true)
      ..writeAsStringSync('old');
  }

  /// Compiles a fake specstone to [outPath] and returns [outPath].
  ///
  /// The exe prints [version] for `--version` and sleeps 120 seconds for any
  /// other arguments, so a test can start it and hold its file locked. It is
  /// compiled in a temp folder outside the workspace, where no build hook is
  /// involved.
  Future<String> compileFakeCli(String version, String outPath) async =>
      _compileFakeCliSync(version, outPath);

  /// Returns every file under [home] as a relative `/` path to its content.
  Map<String, String> snapshot() {
    final prefix = home.path.length + 1;
    return {
      for (final file in home.listSync(recursive: true).whereType<File>())
        file.path.substring(prefix).replaceAll(r'\', '/'): latin1.decode(
          file.readAsBytesSync(),
        ),
    };
  }

  /// Runs [script] with `env(extra)` and none of the parent environment.
  ///
  /// [script] is relative to [repoRoot] unless absolute; [args] follow it.
  /// POSIX runs it through [shell]; Windows runs it through PowerShell.
  Future<ProcessResult> run(
    String script, {
    List<String> args = const [],
    Map<String, String> extra = const {},
    String? stdinText,
    String shell = '/bin/sh',
  }) async {
    final path = _isAbsolute(script)
        ? script
        : '${repoRoot().path}$_separator$script';
    final watch = Stopwatch()..start();
    final process = await Process.start(
      _windows ? 'powershell' : shell,
      _windows
          ? ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path, ...args]
          : [path, ...args],
      environment: env(extra),
      includeParentEnvironment: false,
      workingDirectory: root.path,
    );
    final stdout = process.stdout.transform(_lenientUtf8).join();
    final stderr = process.stderr.transform(_lenientUtf8).join();
    if (stdinText != null) process.stdin.write(stdinText);
    // A script that never reads stdin closes the pipe early; that is fine.
    await process.stdin.close().catchError((Object _) {});
    final result = ProcessResult(
      process.pid,
      await process.exitCode,
      await stdout,
      await stderr,
    );
    if (_windows) _reportSpawn('run', watch);
    return result;
  }

  static const _lenientUtf8 = Utf8Decoder(allowMalformed: true);

  static bool _isAbsolute(String path) =>
      path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

  // Compiled fake exe bytes by version; `dart compile exe` takes seconds.
  static final Map<String, List<int>> _fakeCliCache = {};

  static String _compileFakeCliSync(String version, String outPath) {
    final cached = _fakeCliCache[version];
    if (cached != null) {
      File(outPath)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(cached);
      return outPath;
    }
    final scratch = Directory.systemTemp.createTempSync('specstone_fake_cli_');
    try {
      final source = File(_under(scratch, 'fake_cli.dart'))
        ..writeAsStringSync(
          "import 'dart:io';\n"
          'void main(List<String> a) {\n'
          "  if (a.contains('--version')) {\n"
          "    print('$version');\n"
          '  } else {\n'
          '    sleep(const Duration(seconds: 120));\n'
          '  }\n'
          '}\n',
        );
      final compiled = _under(scratch, 'fake_cli.exe');
      final result = Process.runSync(Platform.resolvedExecutable, [
        'compile',
        'exe',
        source.path,
        '-o',
        compiled,
      ]);
      if (result.exitCode != 0) {
        throw StateError(
          'dart compile exe failed: ${result.stdout}\n${result.stderr}',
        );
      }
      File(outPath).parent.createSync(recursive: true);
      File(compiled).copySync(outPath);
      _fakeCliCache[version] = File(compiled).readAsBytesSync();
      return outPath;
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }

  static void _chmodExecutable(File file) {
    final result = Process.runSync('chmod', ['755', file.path]);
    if (result.exitCode != 0) {
      throw StateError('chmod ${file.path} failed: ${result.stderr}');
    }
  }

  static Future<void> _fillStage(
    Directory stage, {
    required String version,
    required Directory? bundle,
  }) async {
    if (bundle != null) {
      await _copyFolderContents(bundle, stage);
    } else {
      final bin = '${stage.path}${_separator}bin';
      if (_windows) {
        _compileFakeCliSync(version, '$bin${_separator}specstone.exe');
      } else {
        final binary = File('$bin${_separator}specstone')
          ..createSync(recursive: true)
          ..writeAsStringSync('#!/bin/sh\necho $version\n');
        _chmodExecutable(binary);
      }
      File('${stage.path}${_separator}lib${_separator}libfake.so')
        ..createSync(recursive: true)
        ..writeAsStringSync('fake');
    }
    File(_under(stage, 'LICENSE')).writeAsStringSync('license\n');
    File(_under(stage, 'THIRD_PARTY_NOTICES')).writeAsStringSync('notices\n');
  }

  static Future<void> _copyFolderContents(Directory from, Directory to) async {
    final copy =
        '${_quiet}Copy-Item -Path "${from.path}\\*" '
        '-Destination "${to.path}" -Recurse';
    final result = _windows
        ? await runPowerShell('copy', ['-NoProfile', '-Command', copy])
        : await Process.run('cp', ['-R', '${from.path}/.', to.path]);
    if (result.exitCode != 0) {
      throw StateError('copy of ${from.path} failed: ${result.stderr}');
    }
  }

  static Future<void> _pack(
    Directory stage,
    File archive, {
    required bool zip,
  }) async {
    // Compress-Archive is slow and refuses an existing archive.
    final compress =
        '${_quiet}Add-Type -AssemblyName System.IO.Compression.FileSystem; '
        'if (Test-Path -LiteralPath "${archive.path}") { '
        'Remove-Item -LiteralPath "${archive.path}" -Force }; '
        '[System.IO.Compression.ZipFile]::CreateFromDirectory('
        '"${stage.path}", "${archive.path}")';
    final result = zip
        ? await runPowerShell('pack', ['-NoProfile', '-Command', compress])
        : await Process.run('tar', [
            '-czf',
            archive.path,
            '-C',
            stage.path,
            for (final entry in stage.listSync())
              entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
          ]);
    if (result.exitCode != 0) {
      throw StateError('packing ${archive.path} failed: ${result.stderr}');
    }
  }
}

/// The raw user PATH: the registry value unexpanded, and its kind.
typedef UserPath = ({String value, String kind});

/// Returns the Windows user PATH as the registry holds it, or null if unset.
///
/// The value is read unexpanded (`%VAR%` stays literal) and crosses the
/// process boundary as base64, so a non-ASCII entry survives the code page.
Future<UserPath?> readUserPath() async {
  const script =
      r'$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey( '
      "'Environment'); "
      r"if (@($k.GetValueNames()) -contains 'Path') { "
      r"$v = $k.GetValue('Path', '', 'DoNotExpandEnvironmentNames'); "
      r"$kind = $k.GetValueKind('Path'); "
      r'$b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($v)); '
      r'"$kind $b" }';
  final result = await runPowerShell('read-path', [
    '-NoProfile',
    '-Command',
    script,
  ]);
  if (result.exitCode != 0) {
    throw StateError('reading the user PATH failed: ${result.stderr}');
  }
  final line = (result.stdout as String).trim();
  if (line.isEmpty) return null;
  // An empty Path prints only its kind.
  final parts = line.split(' ');
  final encoded = parts.length > 1 ? parts[1] : '';
  return (value: utf8.decode(base64.decode(encoded)), kind: parts[0]);
}

/// Sets the Windows user PATH to [path] with its kind, or deletes it if null.
///
/// An empty value is written as an empty value, not deleted.
Future<void> writeUserPath(UserPath? path) async {
  const script =
      r'$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey( '
      r"'Environment', $true); "
      r'if ($env:SPECSTONE_TEST_USER_PATH_KIND) { '
      r'$v = [Text.Encoding]::UTF8.GetString( '
      '[Convert]::FromBase64String( '
      r'[string]$env:SPECSTONE_TEST_USER_PATH_B64)); '
      r"$k.SetValue('Path', $v, $env:SPECSTONE_TEST_USER_PATH_KIND) } "
      r"elseif (@($k.GetValueNames()) -contains 'Path') { "
      r"$k.DeleteValue('Path') }";
  final result = await runPowerShell(
    'write-path',
    ['-NoProfile', '-Command', script],
    environment: {
      if (path != null) ...{
        'SPECSTONE_TEST_USER_PATH_B64': base64.encode(utf8.encode(path.value)),
        'SPECSTONE_TEST_USER_PATH_KIND': path.kind,
      },
    },
  );
  if (result.exitCode != 0) {
    throw StateError('writing the user PATH failed: ${result.stderr}');
  }
}

const _cacheVariable = 'PSModuleAnalysisCachePath';
const _timingVariable = 'SPECSTONE_PS_TIMING';

/// Runs `powershell` with [args] as `Process.run` does and, when
/// `SPECSTONE_PS_TIMING=1`, prints the spawn's elapsed time under [role].
///
/// The child gets the suite's module analysis cache unless [environment]
/// names one.
Future<ProcessResult> runPowerShell(
  String role,
  List<String> args, {
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  String? workingDirectory,
}) async {
  final watch = Stopwatch()..start();
  final result = await Process.run(
    'powershell',
    args,
    environment: {_cacheVariable: _moduleAnalysisCachePath(), ...?environment},
    includeParentEnvironment: includeParentEnvironment,
    workingDirectory: workingDirectory,
  );
  _reportSpawn(role, watch);
  return result;
}

// The reporters attach the name of the running test to a printed line: the
// expanded one prints it with the line, the JSON file names it by test id.
void _reportSpawn(String role, Stopwatch watch) {
  if (Platform.environment[_timingVariable] != '1') return;
  // ignore: avoid_print, the expanded log names where the time of a slow ps1 test goes.
  print('powershell $role: ${watch.elapsedMilliseconds} ms');
}

String? _cachePath;

/// Returns the module analysis cache file the PowerShell children of the
/// running test share.
///
/// A Windows PowerShell 5.1 child started without `LOCALAPPDATA` finds no
/// cache and analyzes every module on its first cmdlet. The file is a copy of
/// the runner's own cache, made once per test into a folder the test's
/// teardown deletes; without a source it is a path in that folder that no
/// child has written yet. Call it from a test or a `setUp`, as
/// `addTearDown` needs.
String _moduleAnalysisCachePath() {
  final existing = _cachePath;
  if (existing != null) return existing;
  final folder = Directory.systemTemp.createTempSync('specstone_ps_cache_');
  addTearDown(() {
    _cachePath = null;
    folder.deleteSync(recursive: true);
  });
  final target = File('${folder.path}${Platform.pathSeparator}$_cacheFile');
  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (localAppData != null) {
    final source = Directory(
      '$localAppData${Platform.pathSeparator}Microsoft'
      '${Platform.pathSeparator}Windows${Platform.pathSeparator}PowerShell',
    );
    final cache = File('${source.path}${Platform.pathSeparator}$_cacheFile');
    if (cache.existsSync()) cache.copySync(target.path);
  }
  return _cachePath = target.path;
}

const _cacheFile = 'ModuleAnalysisCache';

/// Runs [body] while holding an exclusive lock on the machine's user PATH.
///
/// Several test files write the real user PATH, and the OS runs them in
/// parallel; the lock is a file in the system temp folder. The PATH found
/// on entry is written back before the lock is released.
Future<T> withUserPathLock<T>(Future<T> Function() body) async {
  final lock = await File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'specstone_user_path.lock',
  ).open(mode: FileMode.append);
  // A teardown, not a `finally`: package:test abandons a timed-out body, and
  // only teardowns still run, so a hung test cannot keep the lock or the PATH.
  addTearDown(lock.close);
  await lock.lock(FileLock.blockingExclusive);
  final saved = await readUserPath();
  addTearDown(() => writeUserPath(saved));
  return body();
}
