import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone_core/specstone_core.dart';

const String _rawContentBase =
    'https://raw.githubusercontent.com/nontravis/specstone/';

/// Where the install scripts are fetched from, ending in `/`.
const String installScriptBase = '${_rawContentBase}main/';

/// Names the latest full, published release in its `tag_name`.
const String latestReleaseApi =
    'https://api.github.com/repos/nontravis/specstone/releases/latest';

/// The variable that pins the version the install script installs.
const String _pinnedVersionVariable = 'SPECSTONE_VERSION';

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

/// How many MiB a reply may hold before the read gives up.
const int _maxReplyMiB = 1;

/// The same limit in bytes.
const int _maxReplyBytes = _maxReplyMiB * 1024 * 1024;

/// How many characters of an untrusted tag an error message echoes, the mark
/// of a cut one included.
const int _maxEchoedTagLength = 64;

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

final RegExp _unprintable = RegExp(
  r'[\x00-\x1f\x7f-\x9f]|\p{Cf}|\p{Zl}|\p{Zp}',
  unicode: true,
);

// Masks the control, format, and separator characters of reply text, so it
// cannot drive the terminal or reorder the line it is printed on. A text over
// [_maxEchoedTagLength] characters is cut to that length, the last one `…`.
String _printable(String text) {
  final runes = text.replaceAll(_unprintable, '?').runes.toList();
  if (runes.length <= _maxEchoedTagLength) return String.fromCharCodes(runes);
  return '${String.fromCharCodes(runes.take(_maxEchoedTagLength - 1))}…';
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
/// Refuses unless the running binary sits in `<home>/.specstone/bin`. A
/// pre-release CLI that is not below the latest full release stays as it is.
class UpgradeCommand extends SpecstoneCommand {
  /// Creates the command; each argument defaults to the running process.
  ///
  /// - [scriptBase]: where the install scripts are fetched from.
  /// - [latestReleaseUrl]: where the latest full release is read from.
  /// - [runningVersion]: the Version of the running binary.
  /// - [executable]: the path of the running binary.
  /// - [environment]: the environment `HOME` is read from.
  /// - [windows]: whether to compare paths without case.
  new({
    Uri? scriptBase,
    Uri? latestReleaseUrl,
    String? runningVersion,
    String? executable,
    Map<String, String>? environment,
    bool? windows,
  }) : scriptBase = scriptBase ?? Uri.parse(installScriptBase),
       latestReleaseUrl = latestReleaseUrl ?? Uri.parse(latestReleaseApi),
       runningVersion = runningVersion ?? specstoneVersion,
       executable = executable ?? Platform.resolvedExecutable,
       environment = environment ?? Platform.environment,
       windows = windows ?? Platform.isWindows;

  /// Where the install scripts are fetched from.
  final Uri scriptBase;

  /// Where the latest full release is read from.
  final Uri latestReleaseUrl;

  /// The Version of the running binary.
  final String runningVersion;

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
    final kept = await _keepNewerPreRelease();
    if (kept != null) return kept;
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

  // Returns null to go on to the install script, else the exit status to stop
  // with: 0 after a pre-release CLI that is not below the latest full release
  // is kept, 69 when that release cannot be read.
  Future<int?> _keepNewerPreRelease() async {
    final running = ReleaseVersion.tryParse(runningVersion);
    if (running == null || !running.isPreRelease) return null;
    final (:version, :failure) = await _readLatestRelease();
    if (version == null) {
      return fail(
        UpgradeFault(
          UpgradeFaultCode.installScriptFailed,
          'specstone upgrade could not read the latest release from '
          '$latestReleaseUrl: $failure',
        ),
        asJson: false,
      );
    }
    if (running.compareTo(version) < 0) return null;
    specstoneRunner.out
      ..writeln(
        'specstone $running is newer than the latest release $version; '
        'nothing to upgrade',
      )
      ..writeln(
        'To put the plugin on $running too, run: ${_installLineFor(running)}',
      );
    return 0;
  }

  // Reads the Version of the latest full release from the `tag_name` of
  // [latestReleaseUrl]; the reply is untrusted, so it must be a JSON object
  // holding `v<Version>`.
  Future<({ReleaseVersion? version, String? failure})>
  _readLatestRelease() async {
    final (:body, :failure) = await _get(latestReleaseUrl);
    if (body == null) return (version: null, failure: failure);
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException {
      return (version: null, failure: 'the body is not JSON');
    }
    final tag = json is Map<String, Object?> ? json['tag_name'] : null;
    if (tag is! String) return (version: null, failure: 'no tag_name');
    final version = tag.startsWith('v')
        ? ReleaseVersion.tryParse(tag.substring(1))
        : null;
    if (version != null) return (version: version, failure: null);
    return (
      version: null,
      failure: 'tag_name ${_printable(tag)} is not v<Version>',
    );
  }

  // The install line of the version, which fetches the script of its own tag
  // since `main` holds the last full release's script.
  String _installLineFor(ReleaseVersion version) => windows
      ? 'iex "& {\$(irm ${_rawContentBase}v$version/install.ps1)} '
            '-Version $version"'
      : 'curl -fsSL ${_rawContentBase}v$version/install.sh | '
            '$_pinnedVersionVariable=$version sh';

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
        environment: _withoutPinnedVersion(),
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

  // The environment of the upgrade without the version an install by version
  // exported, so the script takes the latest full release; Windows names
  // compare without case.
  Map<String, String> _withoutPinnedVersion() => {
    for (final MapEntry(:key, :value) in environment.entries)
      if ((windows ? key.toUpperCase() : key) != _pinnedVersionVariable)
        key: value,
  };

  // Writes the body of [url] to [file] only when the whole body arrived.
  // Returns why it did not, or null.
  Future<String?> _fetch(Uri url, File file) async {
    final (:body, :failure) = await _get(url);
    if (body == null) return failure;
    try {
      await file.writeAsBytes(body);
      return null;
    } on FileSystemException catch (e) {
      return '$e';
    }
  }

  // Returns the body of one complete 2xx reply of [url], else why there is
  // none: `HTTP <status>`, `no data for 60 s`, or the I/O or decoder message.
  Future<({List<int>? body, String? failure})> _get(Uri url) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final request = await client.getUrl(url);
      // A redirect could lead off GitHub, so a 3xx counts as a failed status.
      request.followRedirects = false;
      final response = await request.close().timeout(_idleTimeout);
      final status = response.statusCode;
      final quiet = response.timeout(_idleTimeout);
      if (status < 200 || status >= 300) {
        await quiet.drain<void>();
        return (body: null, failure: 'HTTP $status');
      }
      // HttpClient throws on a body cut short, so a finished loop is complete.
      final body = BytesBuilder(copy: false);
      await for (final chunk in quiet) {
        body.add(chunk);
        if (body.length > _maxReplyBytes) {
          return (body: null, failure: 'the reply is over $_maxReplyMiB MiB');
        }
      }
      return (body: body.takeBytes(), failure: null);
    } on IOException catch (e) {
      return (body: null, failure: e is HttpException ? e.message : '$e');
    } on FormatException catch (e) {
      // The SDK's decoder of a `Content-Encoding` reply throws it on bad data.
      return (body: null, failure: e.message);
    } on TimeoutException {
      return (body: null, failure: 'no data for ${_idleTimeout.inSeconds} s');
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
