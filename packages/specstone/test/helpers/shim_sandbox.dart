import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'script_sandbox.dart';

/// The loop guard variable the `stn` shim sets before a hand-off.
const stnGuardVariable = 'SPECSTONE_STN_GUARD';

/// The environment variable whose value is the fake `specstone`'s exit status.
const fakeExitVariable = 'FAKE_EXIT';

/// The environment variable that, set to `1`, makes a Windows recorder read
/// its stdin; unset, it leaves stdin to the shell that typed `stn`.
const readStdinVariable = 'STUB_READ_STDIN';

/// The shell a Windows run types `stn` in.
enum StnShell { cmd, powershell }

/// Creates a [ShimSandbox] under a new temp folder.
///
/// The folder is deleted by `addTearDown`. The sandbox's
/// `<home>/.specstone/bin/` holds a copy of the repo's shim (`stn`, or
/// `stn.cmd` on Windows) and a fake `specstone` that records its argv,
/// stdin, `PATH`, and the guard's value to a log and exits with the status in
/// `FAKE_EXIT` (0 when unset). On Windows the fake is a compiled
/// `specstone.exe`, compiled once per run.
Future<ShimSandbox> createShimSandbox() async {
  final root = await Directory.systemTemp.createTemp('specstone_shim_');
  addTearDown(() => root.delete(recursive: true));
  final sandbox = ShimSandbox(root: root);
  return sandbox._fill();
}

/// A temp home holding the installed shim, a fake `specstone`, and runs of it.
final class ShimSandbox {
  new({required this.root}) : home = Directory(_join(root.path, 'home'));

  static final bool _windows = Platform.isWindows;

  static final String _separator = Platform.pathSeparator;

  static const _lenientUtf8 = Utf8Decoder(allowMalformed: true);

  static final String _systemRoot =
      Platform.environment['SystemRoot'] ?? r'C:\Windows';

  static final String _cmd = '$_systemRoot\\System32\\cmd.exe';

  static final String _powershell =
      '$_systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';

  // The compiled Windows recorder; `dart compile exe` takes seconds.
  static List<int>? _recorderCache;

  final Directory root;

  /// The temp home the shim is installed under.
  final Directory home;

  /// The folder holding the installed `stn` and the fake `specstone`.
  Directory get bin =>
      Directory(_join(home.path, '.specstone${_separator}bin'));

  /// The folder holding the run logs.
  Directory get logs => Directory(_join(root.path, 'logs'));

  /// The file another tool's `stn.ps1` creates when it runs.
  File get ps1Marker => File(_join(logs.path, 'ps1.ran'));

  Directory get _tmp => Directory(_join(root.path, 'tmp'));

  /// Returns the log lines of [name], or none when it wrote no log.
  List<String> logOf(String name) {
    final file = File(_join(logs.path, '$name.log'));
    return file.existsSync() ? file.readAsLinesSync() : const [];
  }

  /// Returns the environment the last Windows run of [name] got, keys
  /// lower-cased since Windows names ignore case, or none when it never ran.
  Map<String, String> envOf(String name) {
    final file = File(_join(logs.path, '$name.env'));
    if (!file.existsSync()) return const {};
    return {
      for (final line in file.readAsLinesSync())
        // A key such as `=C:` starts with `=`; its value follows the next one.
        if (line.indexOf('=', 1) case final at when at > 0)
          line.substring(0, at).toLowerCase(): line.substring(at + 1),
    };
  }

  /// Writes another tool's recording `stn` in [folder], exiting with [exit].
  ///
  /// The other `stn` records to the `other` log, so `logOf('other')` shows
  /// whether and how it ran. On Windows [extension] (`exe`, `cmd`, `bat`,
  /// `com`, or `ps1`) picks the file; a `stn.ps1` records nothing and creates
  /// [ps1Marker]. POSIX ignores [extension].
  void otherStn(String folder, {int exit = 0, String extension = 'cmd'}) {
    if (_windows) {
      _writeWindowsOther(folder, exit, extension);
      return;
    }
    _writeRecorder(File('$folder/stn'), 'other', '$exit');
  }

  /// Runs the installed POSIX shim with exactly [path] as `PATH` and none of
  /// the parent environment, plus [extra].
  ///
  /// [stdinText], when given, is piped into the shim. The run fails after
  /// [timeout], so a walk that loops fails the test instead of hanging it.
  Future<ProcessResult> runStn(
    List<String> args, {
    required String path,
    Map<String, String> extra = const {},
    String? stdinText,
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_windows) {
      throw UnsupportedError('runStn runs the POSIX shim; use typeStn');
    }
    return _run(
      '/bin/sh',
      ['${bin.path}/stn', ...args],
      environment: {
        'HOME': home.path,
        'PATH': path,
        'STUB_LOG_DIR': logs.path,
        ...extra,
      },
      stdinText: stdinText,
      timeout: timeout,
    );
  }

  /// Types [lines] one by one at a Windows [shell] prompt, with exactly [path]
  /// as `PATH` and a minimal environment plus [extra].
  ///
  /// cmd reads the lines as a cmd window would (`cmd /d /q /k`, fed through
  /// stdin), and prints its prompt before each line, `/q` or not, so its
  /// `PROMPT` is a bare line break, a blank line a case skips; PowerShell runs
  /// them as one `-Command`. The exit status is the last line's. The run
  /// fails after [timeout].
  Future<ProcessResult> typeStn(
    List<String> lines, {
    required StnShell shell,
    required String path,
    Map<String, String> extra = const {},
    Duration timeout = const Duration(seconds: 60),
  }) {
    if (!_windows) {
      throw UnsupportedError('typeStn types into cmd or PowerShell');
    }
    final environment = _windowsEnvironment(path, extra);
    return switch (shell) {
      StnShell.cmd => _run(
        _cmd,
        ['/d', '/q', '/k', 'rem'],
        environment: {...environment, 'PROMPT': r'$_'},
        stdinText: '${[...lines, 'exit %ERRORLEVEL%'].join('\r\n')}\r\n',
        timeout: timeout,
      ),
      StnShell.powershell => _run(
        _powershell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '${lines.join('; ')}; exit \$LASTEXITCODE',
        ],
        environment: environment,
        timeout: timeout,
      ),
    };
  }

  Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    required Map<String, String> environment,
    required Duration timeout,
    String? stdinText,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: environment,
      includeParentEnvironment: false,
      workingDirectory: root.path,
    );
    final stdout = process.stdout.transform(_lenientUtf8).join();
    final stderr = process.stderr.transform(_lenientUtf8).join();
    if (stdinText != null) process.stdin.write(stdinText);
    // A target that never reads stdin closes the pipe early; that is fine.
    await process.stdin.close().catchError((Object _) {});
    final code = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill();
        throw TimeoutException('stn did not exit within $timeout', timeout);
      },
    );
    return ProcessResult(process.pid, code, await stdout, await stderr);
  }

  Future<ShimSandbox> _fill() async {
    await bin.create(recursive: true);
    await logs.create();
    if (_windows) {
      await _tmp.create();
      _recorderCache ??= await _compileRecorder();
      await _shimSource('stn.cmd').copy(_join(bin.path, 'stn.cmd'));
      _writeRecorderExe(File(_join(bin.path, 'specstone.exe')));
    } else {
      final installed = await _shimSource('stn').copy('${bin.path}/stn');
      _makeExecutable(installed);
      _writeRecorder(File('${bin.path}/specstone'), 'specstone');
    }
    return this;
  }

  /// Writes an executable `/bin/sh` [file] that records its argv, stdin,
  /// `PATH`, and the guard's value to the log [name], then runs [exit], a
  /// literal or a shell expression such as `'${FAKE_EXIT:-0}'`.
  void _writeRecorder(File file, String name, [String? exit]) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync('''
#!/bin/sh
log="\$STUB_LOG_DIR/$name.log"
printf 'argv\\n' >> "\$log"
for a in "\$@"; do printf '%s\\n' "\$a" >> "\$log"; done
printf 'stdin\\n%s\\n' "\$(cat 2>/dev/null)" >> "\$log"
printf 'path\\n%s\\n' "\$PATH" >> "\$log"
printf 'guard\\n%s\\n' "\${$stnGuardVariable:-unset}" >> "\$log"
exit ${exit ?? '\${$fakeExitVariable:-0}'}
''');
    _makeExecutable(file);
  }

  Map<String, String> _windowsEnvironment(
    String path,
    Map<String, String> extra,
  ) => {
    'HOME': home.path,
    'USERPROFILE': home.path,
    'PATH': path,
    'SystemRoot': _systemRoot,
    'ComSpec': _cmd,
    'PATHEXT': '.COM;.EXE;.BAT;.CMD',
    'TEMP': _tmp.path,
    'TMP': _tmp.path,
    'STUB_LOG_DIR': logs.path,
    'PROCESSOR_ARCHITECTURE': 'AMD64',
    // The runner's PSModulePath lists PowerShell 7 modules a 5.1 child
    // cannot import; the child gets its own module folder only.
    'PSModulePath': '$_systemRoot\\System32\\WindowsPowerShell\\v1.0\\Modules',
    ...extra,
  };

  void _writeWindowsOther(String folder, int exit, String extension) {
    switch (extension) {
      case 'exe' || 'com':
        _writeRecorderExe(File(_join(folder, 'stn.$extension')));
        File(_join(folder, 'stn.$extension.exit')).writeAsStringSync('$exit');
      case 'cmd' || 'bat':
        final recorder = File(_join(folder, 'stn-recorder.exe'));
        if (!recorder.existsSync()) _writeRecorderExe(recorder);
        File(_join(folder, 'stn.$extension')).writeAsStringSync(
          '@"%~dp0stn-recorder.exe" %*\r\n@exit /b $exit\r\n',
        );
      case 'ps1':
        File(_join(folder, 'stn.ps1')).writeAsStringSync(
          "New-Item -ItemType File -Force -Path '${ps1Marker.path}'"
          ' | Out-Null\r\nexit $exit\r\n',
        );
      default:
        throw ArgumentError.value(extension, 'extension', 'not a stn kind');
    }
  }

  static void _writeRecorderExe(File file) {
    final bytes = _recorderCache;
    if (bytes == null) {
      throw StateError('createShimSandbox compiles the recorder first');
    }
    file
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  // Compiled in a temp folder outside the workspace, where no build hook is
  // involved, as `ScriptSandbox` compiles its fake CLI.
  static Future<List<int>> _compileRecorder() async {
    final scratch = await Directory.systemTemp.createTemp('specstone_stn_rec_');
    try {
      final source = File(_join(scratch.path, 'recorder.dart'))
        ..writeAsStringSync(_recorderSource);
      final compiled = _join(scratch.path, 'recorder.exe');
      final result = await Process.run(Platform.resolvedExecutable, [
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
      return File(compiled).readAsBytesSync();
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  static File _shimSource(String name) {
    final shim = File('${repoRoot().path}/packages/specstone/bin/$name');
    if (!shim.existsSync()) {
      throw StateError('no shim at ${shim.path}');
    }
    return shim;
  }

  static String _join(String parent, String name) => '$parent$_separator$name';

  static void _makeExecutable(File file) {
    final result = Process.runSync('chmod', ['755', file.path]);
    if (result.exitCode != 0) {
      throw StateError('chmod ${file.path} failed: ${result.stderr}');
    }
  }
}

// The Windows recorder: logs argv, stdin (read only when STUB_READ_STDIN is
// 1), PATH, and the guard to <STUB_LOG_DIR>\<name>.log, name `specstone` for
// specstone.exe and `other` for any other file. Its exit status is the number
// in `<its path>.exit`, else FAKE_EXIT for specstone, else 0. Each run also
// writes its whole environment to <name>.env. Given `upgrade`, specstone.exe
// replaces the stn.cmd beside it with a file twice its length whose every
// line prints REREAD, prints `upgraded`, then exits.
const _recorderSource = r'''
import 'dart:io';

Future<void> main(List<String> args) async {
  final program = Platform.resolvedExecutable;
  final folder = File(program).parent.path;
  final base = program.substring(folder.length + 1).toLowerCase();
  final name = base.startsWith('specstone.') ? 'specstone' : 'other';
  final env = Platform.environment;
  final input = <String>[];
  if (env['STUB_READ_STDIN'] == '1') {
    for (var l = stdin.readLineSync(); l != null; l = stdin.readLineSync()) {
      input.add(l);
    }
  }
  final log = [
    'argv',
    ...args,
    'stdin',
    input.join('\n'),
    'path',
    env['PATH'] ?? '',
    'guard',
    env['SPECSTONE_STN_GUARD'] ?? 'unset',
  ];
  File('${env['STUB_LOG_DIR']}\\$name.log')
      .writeAsStringSync('${log.join('\n')}\n', mode: FileMode.append);
  final variables = [for (final e in env.entries) '${e.key}=${e.value}'];
  File('${env['STUB_LOG_DIR']}\\$name.env')
      .writeAsStringSync('${variables.join('\n')}\n');
  if (name == 'specstone' && args.isNotEmpty && args.first == 'upgrade') {
    final shim = File('$folder\\stn.cmd');
    final wanted = 2 * shim.lengthSync();
    final text = StringBuffer('@echo off\r\n');
    for (var i = 0; text.length <= wanted; i++) {
      text.write('echo REREAD $i\r\n');
    }
    shim.writeAsStringSync(text.toString());
    stdout.writeln('upgraded');
  }
  final exitFile = File('$program.exit');
  exitCode = exitFile.existsSync()
      ? int.parse(exitFile.readAsStringSync().trim())
      : name == 'specstone'
      ? int.tryParse(env['FAKE_EXIT'] ?? '') ?? 0
      : 0;
  await stdout.flush();
}
''';
