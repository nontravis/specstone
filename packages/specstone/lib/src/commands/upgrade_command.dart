import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/specstone_command.dart';
import 'package:specstone/src/models/latest_release.dart';
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

/// Ends an untrusted tag that an error message cuts.
const String _cutMark = '...';

/// The code point that stands for each character an error message hides.
const int _maskRune = 0x3f;

/// A fault code of `specstone upgrade`.
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

// Shows reply text as printable ASCII only, so it cannot drive the terminal or
// reorder the line it is printed on: every other character, a whole code point
// at a time, shows as `?`. A text over [_maxEchoedTagLength] characters is cut
// to that length, the last characters being [_cutMark].
String _printable(String text) {
  final runes = text.runes.take(_maxEchoedTagLength + 1).toList();
  final isCut = runes.length > _maxEchoedTagLength;
  final kept = isCut
      ? runes.take(_maxEchoedTagLength - _cutMark.length)
      : runes;
  final shown = String.fromCharCodes(
    kept.map((rune) => _isPrintableAscii(rune) ? rune : _maskRune),
  );
  return isCut ? '$shown$_cutMark' : shown;
}

bool _isPrintableAscii(int rune) => rune >= 0x20 && rune <= 0x7e;

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

/// Reads the Version of the latest full release from the `tag_name` of [url].
///
/// The reply is untrusted, so it must be a JSON object holding `v<Version>`.
/// The result holds the Version, or null with the reason when the read fails.
/// A completed [abandon] closes the request at once, so a caller that stops
/// waiting leaves nothing pending.
Future<LatestRelease> readLatestRelease(
  Uri url, {
  Future<void>? abandon,
}) async {
  final _Reply(:body, :failure) = await _get(url, abandon: abandon);
  if (body == null) return LatestRelease(version: null, failure: failure);
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(body));
  } on FormatException {
    return const LatestRelease(version: null, failure: 'the body is not JSON');
  }
  final tag = json is Map<String, Object?> ? json['tag_name'] : null;
  if (tag is! String) {
    return const LatestRelease(version: null, failure: 'no tag_name');
  }
  final version = tag.startsWith('v')
      ? ReleaseVersion.tryParse(tag.substring(1))
      : null;
  if (version != null) return LatestRelease(version: version, failure: null);
  return LatestRelease(
    version: null,
    failure: 'tag_name ${_printable(tag)} is not v<Version>',
  );
}

// Returns the body of one complete 2xx reply of [url], else why there is none:
// `HTTP <status>`, `no data for 60 s`, or the I/O or decoder message.
Future<_Reply> _get(Uri url, {Future<void>? abandon}) async {
  final client = HttpClient()..connectionTimeout = _connectTimeout;
  unawaited(abandon?.then((_) => client.close(force: true)));
  try {
    final request = await client.getUrl(url);
    // A redirect could lead off GitHub, so a 3xx counts as a failed status.
    request.followRedirects = false;
    final response = await request.close().timeout(_idleTimeout);
    final status = response.statusCode;
    // An error body is never read: the closed client drops it, so it cannot
    // stall, fail to decode, or grow without a cap.
    if (status < 200 || status >= 300) {
      return _Reply(body: null, failure: 'HTTP $status');
    }
    final quiet = response.timeout(_idleTimeout);
    // HttpClient throws on a body cut short, so a finished loop is complete.
    final body = BytesBuilder(copy: false);
    await for (final chunk in quiet) {
      body.add(chunk);
      if (body.length > _maxReplyBytes) {
        return const _Reply(
          body: null,
          failure: 'the reply is over $_maxReplyMiB MiB',
        );
      }
    }
    return _Reply(body: body.takeBytes(), failure: null);
  } on IOException catch (e) {
    return _Reply(body: null, failure: e is HttpException ? e.message : '$e');
  } on FormatException catch (e) {
    // The SDK's decoder of a `Content-Encoding` reply throws it on bad data.
    return _Reply(body: null, failure: e.message);
  } on TimeoutException {
    return _Reply(
      body: null,
      failure: 'no data for ${_idleTimeout.inSeconds} s',
    );
  } finally {
    client.close(force: true);
  }
}

/// Upgrades the CLI to the latest release.
///
/// Refuses unless the running binary sits in `<home>/.specstone/bin`. A
/// pre-release CLI that is not below the latest full release stays as it is.
/// Each exit-0 path ends by running the installed binary's `folder`, so the
/// stale-project line names the working folder's fix.
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
  String get description => 'Upgrade the CLI to the latest release.';

  @override
  bool get takesArguments => false;

  @override
  Future<int> run() async {
    final home = homeFrom(environment);
    final folder = unmanagedBinFolder(executable, home, windows: windows);
    if (home == null || folder != null) {
      return fail(
        UpgradeFault(
          UpgradeFaultCode.installNotManaged,
          'specstone upgrade updates only a CLI installed in '
          '~/.specstone/bin; this one runs from ${folder ?? File(executable).parent.path}',
        ),
        asJson: false,
      );
    }
    final kept = await _keepNewerPreRelease(home);
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
    await _nameProjectFix(home);
    return 0;
  }

  // Returns null to go on to the install script, else the exit status to stop
  // with: 0 after a pre-release CLI that is not below the latest full release
  // is kept, 69 when that release cannot be read.
  Future<int?> _keepNewerPreRelease(Directory home) async {
    final running = ReleaseVersion.tryParse(runningVersion);
    if (running == null || !running.isPreRelease) return null;
    final LatestRelease(:version, :failure) = await readLatestRelease(
      latestReleaseUrl,
    );
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
    specstoneRunner.out.writeln(
      'specstone $running is newer than the latest release $version; '
      'nothing to upgrade',
    );
    await _nameProjectFix(home);
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
    final _Reply(:body, :failure) = await _get(url);
    if (body == null) return failure;
    try {
      await file.writeAsBytes(body);
      return null;
    } on FileSystemException catch (e) {
      return '$e';
    }
  }

  // Runs the installed binary's `folder` in the working folder and passes its
  // stderr on when that run exits 0; a run that cannot start or exits non-zero
  // shows nothing, since the CLI step succeeded. Stdout is dropped.
  Future<void> _nameProjectFix(Directory home) async {
    final separator = Platform.pathSeparator;
    final binary =
        '${home.path}$separator.specstone${separator}bin$separator'
        '${windows ? 'specstone.exe' : 'specstone'}';
    const decoder = Utf8Codec(allowMalformed: true);
    try {
      final result = await Process.run(
        binary,
        const ['folder'],
        workingDirectory: specstoneRunner.workingDirectory.path,
        environment: environment,
        includeParentEnvironment: false,
        stdoutEncoding: decoder,
        stderrEncoding: decoder,
      );
      if (result.exitCode == 0) specstoneRunner.err.write(result.stderr);
    } on IOException {
      return;
    }
  }
}

/// The body of one complete 2xx reply, or null with the reason there is none.
final class _Reply {
  const new({required this.body, required this.failure});

  final List<int>? body;
  final String? failure;
}
