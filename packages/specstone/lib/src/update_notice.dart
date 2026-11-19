import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/commands/upgrade_command.dart';
import 'package:specstone/src/console.dart';
import 'package:specstone/src/models/latest_release.dart';
import 'package:specstone_core/specstone_core.dart';

// MARK: - Constants

/// The variable that turns the update check off when it holds any text.
const String _offVariable = 'SPECSTONE_NO_UPDATE_NOTIFIER';

/// The variable every CI system sets; any text turns the update check off.
const String _ciVariable = 'CI';

/// How long a check keeps the next one away.
const Duration _checkInterval = Duration(hours: 24);

/// The commands that never check: `upgrade` reads the release itself, and
/// `hook post-edit` speaks to a program.
const Set<String> _noCheckCommands = {'upgrade', 'hook post-edit'};

/// The file in the install folder that marks a local build.
const String _localBuildFile = 'build.txt';

// MARK: - UpdateNotice

/// The daily check for a newer release, run beside one command.
///
/// `start` records the check and sends the request without waiting for it;
/// `lineAfter`, called once the command's output has ended, abandons the
/// request and returns the notice. Neither throws.
final class UpdateNotice {
  /// Creates the check of one command; each unset argument is the running
  /// process's own.
  ///
  /// - [console]: tells whether stdout and stderr are terminals.
  /// - [environment]: holds the switches that turn the check off.
  /// - [home]: the folder whose `.specstone/` holds the record, or null.
  /// - [executable]: the path of the running binary.
  /// - [latestReleaseUrl]: where the latest full release is read from.
  /// - [runningVersion]: the Version of the running binary.
  /// - [clock]: the time of the check.
  /// - [windows]: whether paths compare without case.
  new({
    required Console console,
    required Map<String, String> environment,
    required Directory? home,
    String? executable,
    Uri? latestReleaseUrl,
    String? runningVersion,
    DateTime Function()? clock,
    bool? windows,
  }) : _console = console,
       _environment = environment,
       _home = home,
       _executable = executable ?? Platform.resolvedExecutable,
       _latestReleaseUrl = latestReleaseUrl ?? Uri.parse(latestReleaseApi),
       _runningVersion = runningVersion ?? specstoneVersion,
       _clock = clock ?? DateTime.now,
       _windows = windows ?? Platform.isWindows;

  final Console _console;
  final Map<String, String> _environment;
  final Directory? _home;
  final String _executable;
  final Uri _latestReleaseUrl;
  final String _runningVersion;
  final DateTime Function() _clock;
  final bool _windows;

  final _abandoned = Completer<void>();
  var _started = false;
  ReleaseVersion? _kept;
  ReleaseVersion? _read;

  /// Starts the check of the command named by [command], its names from the
  /// top: nothing happens when a check condition fails or the record cannot
  /// be written.
  void start(List<String> command) {
    try {
      final file = _recordFile();
      if (file == null || !_checks(command)) return;
      final record = _readRecord(file);
      final now = _clock();
      if (record != null && _isWithinInterval(record.checkedAt, now)) return;
      final kept = record?.latest;
      _writeRecord(file, now, kept);
      _kept = kept;
      _started = true;
      unawaited(_request(file, now));
    } on Object {
      // A check that cannot start leaves the command as it is.
    }
  }

  /// Abandons the request and returns the notice line, or null when there is
  /// none; call it once the command's output has ended.
  String? lineAfter() {
    abandon();
    if (!_started) return null;
    final latest = _read ?? _kept;
    final running = ReleaseVersion.tryParse(_runningVersion);
    if (latest == null || running == null || latest.compareTo(running) <= 0) {
      return null;
    }
    return 'specstone $latest is out (this is $running); '
        'run specstone upgrade';
  }

  /// Closes the request when it is still open, so nothing keeps the process
  /// alive; safe to call again.
  void abandon() {
    if (!_abandoned.isCompleted) _abandoned.complete();
  }

  // MARK: - Conditions

  // The cheap conditions come first; the file lookups last.
  bool _checks(List<String> command) {
    if (_noCheckCommands.contains(command.join(' '))) return false;
    if (_isSet(_offVariable) || _isSet(_ciVariable)) return false;
    if (!_console.stdoutIsTerminal || !_console.stderrIsTerminal) return false;
    final isManaged =
        unmanagedBinFolder(_executable, _home, windows: _windows) == null;
    return isManaged && !_isLocalBuild();
  }

  bool _isSet(String name) => (_environment[name] ?? '').isNotEmpty;

  bool _isLocalBuild() {
    final sep = Platform.pathSeparator;
    final installFolder = File(_executable).parent.parent.path;
    return File('$installFolder${sep}lib$sep$_localBuildFile').existsSync();
  }

  bool _isWithinInterval(DateTime checkedAt, DateTime now) {
    final age = now.difference(checkedAt);
    return !age.isNegative && age < _checkInterval;
  }

  // MARK: - Request

  Future<void> _request(File file, DateTime checkedAt) async {
    try {
      final LatestRelease(:version) = await readLatestRelease(
        _latestReleaseUrl,
        abandon: _abandoned.future,
      );
      if (version == null || _abandoned.isCompleted) return;
      _read = version;
      _writeRecord(file, checkedAt, version);
    } on Object {
      // A failed request leaves the record as the start write left it.
    }
  }

  // MARK: - Record

  File? _recordFile() {
    final home = _home;
    if (home == null) return null;
    final sep = Platform.pathSeparator;
    return File('${home.path}$sep.specstone${sep}update-check.json');
  }

  // Returns null for a record that is missing or does not read as its shape.
  _Record? _readRecord(File file) {
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?> || !json.containsKey('latest')) {
        return null;
      }
      final checkedAt = json['checkedAt'];
      final latest = json['latest'];
      if (checkedAt is! String) return null;
      final time = DateTime.tryParse(checkedAt);
      if (time == null) return null;
      if (latest == null) return _Record(checkedAt: time, latest: null);
      final version = latest is String ? ReleaseVersion.tryParse(latest) : null;
      return version == null ? null : _Record(checkedAt: time, latest: version);
    } on Object {
      return null;
    }
  }

  void _writeRecord(File file, DateTime checkedAt, ReleaseVersion? latest) {
    final text = jsonEncode({
      'checkedAt': checkedAt.toUtc().toIso8601String(),
      'latest': latest?.toString(),
    });
    writeFileAtomic(file, utf8.encode(text));
  }
}

/// The Version and the time of the last release check.
final class _Record {
  const new({required this.checkedAt, required this.latest});

  final DateTime checkedAt;
  final ReleaseVersion? latest;
}
