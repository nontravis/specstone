import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

/// Where the install scripts are fetched from, ending in `/`.
const String installScriptBase =
    'https://raw.githubusercontent.com/nontravis/specstone/main/';

/// The arguments `claude` takes to update the Specstone plugin.
const List<String> _pluginUpdateArguments = [
  'plugin',
  'update',
  'specstone@specstone',
];

/// The program, arguments, and environment of one `claude plugin update`.
typedef _ClaudeStart = ({
  String program,
  List<String> arguments,
  Map<String, String> environment,
});

/// The Windows variable that keeps a program lookup out of the current folder.
const String _noCurrentFolderLookup = 'NoDefaultCurrentDirectoryInExePath';

/// How long a connection may take to open.
const Duration _connectTimeout = Duration(seconds: 30);

/// How long the script body may stay silent before the fetch gives up.
const Duration _idleTimeout = Duration(seconds: 60);

/// The last line `specstone upgrade` prints.
const String _restartLine =
    'Restart Claude Code to load the new CLI and plugin.';

/// A fault code of `specstone upgrade` from the `s05_errors.md` catalog.
///
/// [wire] is the snake_case code printed in the error envelope; [exitStatus]
/// is the process exit status for the fault.
enum UpgradeFaultCode {
  installNotManaged('install_not_managed', 78),
  installScriptFailed('install_script_failed', 69);

  new(this.wire, this.exitStatus);

  /// The snake_case code printed in the error envelope.
  final String wire;

  /// The process exit status for the fault.
  final int exitStatus;
}

/// The one fault `specstone upgrade` raises for a refused or failed run.
///
/// [message] is plain text with no location prefix.
final class UpgradeFault implements SpecstoneFault {
  new(this.code, this.message);

  /// The catalog code of this fault.
  final UpgradeFaultCode code;

  /// Plain human text with no location prefix.
  final String message;

  @override
  int get exitStatus => code.exitStatus;

  @override
  Map<String, Object> toJson() => {
    'error': {'code': code.wire, 'message': message},
  };

  @override
  String toText() => message;
}

/// Returns the folder [executable] runs from when it is not the managed one.
///
/// The managed folder is `<home>/.specstone/bin`. Returns null when
/// [executable] runs from it; returns its folder as given when it runs from
/// elsewhere or when [home] is null, since no home names no managed folder.
/// Both folders are compared with symlinks resolved, and without case when
/// [windows].
String? unmanagedBinFolder(
  String executable,
  Directory? home, {
  required bool windows,
}) {
  final binFolder = File(executable).parent;
  if (home == null) return binFolder.path;
  final managed = Directory(
    '${home.path}${Platform.pathSeparator}.specstone'
    '${Platform.pathSeparator}bin',
  );
  final same =
      _comparable(binFolder, windows: windows) ==
      _comparable(managed, windows: windows);
  return same ? null : binFolder.path;
}

// Resolves symlinks of an existing folder, so macOS `/var` and `/private/var`
// compare equal; a missing folder falls back to its normalized absolute path.
String _comparable(Directory folder, {required bool windows}) {
  final path = folder.existsSync()
      ? folder.resolveSymbolicLinksSync()
      : folder.absolute.uri.normalizePath().toFilePath(windows: windows);
  final bare = path.length > 1 && path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
  return windows ? bare.toLowerCase() : bare;
}

/// Upgrades the CLI and the plugin to the latest release.
///
/// Refuses unless the running binary sits in `<home>/.specstone/bin`.
class UpgradeCommand extends SpecstoneCommand {
  /// Creates the command; each argument defaults to the running process.
  ///
  /// - [scriptBase]: where the install scripts are fetched from.
  /// - [executable]: the path of the running binary.
  /// - [environment]: the environment `HOME` is read from.
  /// - [windows]: whether to compare paths without case.
  new({
    Uri? scriptBase,
    String? executable,
    Map<String, String>? environment,
    bool? windows,
  }) : scriptBase = scriptBase ?? Uri.parse(installScriptBase),
       executable = executable ?? Platform.resolvedExecutable,
       environment = environment ?? Platform.environment,
       windows = windows ?? Platform.isWindows;

  /// Where the install scripts are fetched from.
  final Uri scriptBase;

  /// The path of the running binary.
  final String executable;

  /// The environment the home folder is read from.
  final Map<String, String> environment;

  /// Whether paths compare without case.
  final bool windows;

  @override
  String get name => 'upgrade';

  @override
  String get description =>
      'Upgrade the CLI and the plugin to the latest release.';

  @override
  bool get takesArguments => false;

  @override
  Future<int> run() async {
    final folder = unmanagedBinFolder(
      executable,
      homeFrom(environment),
      windows: windows,
    );
    if (folder != null) {
      return fail(
        UpgradeFault(
          UpgradeFaultCode.installNotManaged,
          'specstone upgrade updates only a CLI installed in '
          '~/.specstone/bin; this one runs from $folder',
        ),
        asJson: false,
      );
    }
    final Directory temp;
    try {
      temp = await Directory.systemTemp.createTemp('specstone_upgrade_');
    } on FileSystemException catch (e) {
      return fail(
        UpgradeFault(
          UpgradeFaultCode.installScriptFailed,
          'specstone upgrade: could not create a temp folder: ${e.message}; '
          'the install is unchanged',
        ),
        asJson: false,
      );
    }
    try {
      final failure = await _installCli(temp);
      if (failure != null) return fail(failure, asJson: false);
    } finally {
      await _remove(temp);
    }
    await _updatePlugin();
    specstoneRunner.out.writeln(_restartLine);
    return 0;
  }

  // Deletes [temp]; a failure is reported and never changes the exit status.
  Future<void> _remove(Directory temp) async {
    try {
      await temp.delete(recursive: true);
    } on FileSystemException catch (e) {
      specstoneRunner.err.writeln(
        'specstone upgrade: could not remove ${temp.path}: ${e.message}',
      );
    }
  }

  // Fetches the install script into [temp], then runs it with the terminal
  // passed through. Returns null on success.
  Future<UpgradeFault?> _installCli(Directory temp) async {
    final fileName = windows ? 'install.ps1' : 'install.sh';
    final url = scriptBase.resolve(fileName);
    final script = File('${temp.path}${Platform.pathSeparator}$fileName');
    final fetchFailure = await _fetch(url, script);
    if (fetchFailure != null) {
      return UpgradeFault(
        UpgradeFaultCode.installScriptFailed,
        'specstone upgrade could not fetch $url: $fetchFailure',
      );
    }
    final shell = windows ? 'powershell' : '/bin/sh';
    final program = windows
        ? findExecutable(shell, environment, isWindows: true)
        : shell;
    if (program == null) {
      return UpgradeFault(
        UpgradeFaultCode.installScriptFailed,
        'specstone upgrade: could not start $shell for $url: no $shell on an '
        'absolute PATH entry; the install is unchanged',
      );
    }
    final arguments = windows
        ? ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script.path]
        : [script.path];
    try {
      final process = await Process.start(
        program,
        arguments,
        mode: ProcessStartMode.inheritStdio,
        environment: environment,
        includeParentEnvironment: false,
      );
      final status = await process.exitCode;
      if (status == 0) return null;
      return UpgradeFault(
        UpgradeFaultCode.installScriptFailed,
        'specstone upgrade: $url exited $status; '
        'the install is as the script left it',
      );
    } on ProcessException catch (e) {
      return UpgradeFault(
        UpgradeFaultCode.installScriptFailed,
        'specstone upgrade: could not start $shell for $url: ${e.message}; '
        'the install is unchanged',
      );
    }
  }

  // Writes the body of [url] to [file] only when the whole body arrived.
  // Returns why it did not, or null.
  Future<String?> _fetch(Uri url, File file) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(_idleTimeout);
      final status = response.statusCode;
      final quiet = response.timeout(_idleTimeout);
      if (status < 200 || status >= 300) {
        await quiet.drain<void>();
        return 'HTTP $status';
      }
      // HttpClient throws on a body cut short, so a finished fold is complete.
      final body = await quiet.fold(
        BytesBuilder(copy: false),
        (builder, chunk) => builder..add(chunk),
      );
      await file.writeAsBytes(body.takeBytes());
      return null;
    } on IOException catch (e) {
      return e is HttpException ? e.message : '$e';
    } on TimeoutException {
      return 'no data for ${_idleTimeout.inSeconds} s';
    } finally {
      client.close(force: true);
    }
  }

  // Runs `claude plugin update`, or prints the command when `claude` is not on
  // the PATH. A failure is reported on `err` and never changes the exit status.
  Future<void> _updatePlugin() async {
    final out = specstoneRunner.out;
    final command = 'claude ${_pluginUpdateArguments.join(' ')}';
    final start = _claudeStart();
    if (start == null) {
      out
        ..writeln('To update the Specstone plugin, run:')
        ..writeln(command);
      return;
    }
    final failure = await _runClaude(start, out);
    if (failure != null) {
      specstoneRunner.err.writeln(
        'specstone: $command failed: $failure; run it by hand',
      );
    }
  }

  // Returns the absolute program that runs `claude plugin update`, or null when
  // there is none. A `claude.cmd` runs through the absolute `cmd.exe`: a bare
  // name starts from the current folder on Windows, and so does the `node` a
  // `.cmd` shim names, which `NoDefaultCurrentDirectoryInExePath` stops.
  _ClaudeStart? _claudeStart() {
    final claude = findExecutable(
      'claude',
      environment,
      isWindows: windows,
      windowsExtensions: const ['.exe', '.cmd'],
    );
    if (claude == null) return null;
    if (!claude.endsWith('.cmd')) {
      return (
        program: claude,
        arguments: _pluginUpdateArguments,
        environment: environment,
      );
    }
    final shell = findExecutable('cmd', environment, isWindows: true);
    if (shell == null) return null;
    return (
      program: shell,
      arguments: ['/c', claude, ..._pluginUpdateArguments],
      environment: {...environment, _noCurrentFolderLookup: '1'},
    );
  }

  // Returns the first non-blank, trimmed stderr line of a failed run,
  // `exit <status>` when it wrote none, or null on success.
  Future<String?> _runClaude(_ClaudeStart start, StringSink out) async {
    try {
      final process = await Process.start(
        start.program,
        start.arguments,
        environment: start.environment,
        includeParentEnvironment: false,
      );
      const decoder = Utf8Decoder(allowMalformed: true);
      final stderrText = process.stderr.transform(decoder).join();
      await process.stdout.transform(decoder).forEach(out.write);
      final status = await process.exitCode;
      if (status == 0) return null;
      final firstLine = const LineSplitter()
          .convert(await stderrText)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .firstOrNull;
      return firstLine ?? 'exit $status';
    } on ProcessException catch (e) {
      return e.message;
    }
  }
}
