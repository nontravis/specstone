// Releases a new specstone version from `develop`.
//
// Usage: dart run tool/release.dart X.Y.Z [--dry-run]
// Contract: docs/specs/install_update/s02_api_release.md `## release.dart`.
import 'dart:convert';
import 'dart:io';

/// One place a release version lives.
///
/// [pattern] captures the text before the version as group 1 and the version
/// itself as group 2, so a rewrite keeps everything around it.
final class _VersionSpot {
  new(this.label, this.path, this.pattern);

  final String label;
  final String path;
  final RegExp pattern;
}

const String _missing = '<missing>';

final List<_VersionSpot> _spots = [
  _VersionSpot(
    'packages/specstone_core/lib/src/version.dart',
    'packages/specstone_core/lib/src/version.dart',
    RegExp(r"(const String specstoneVersion = ')(\d+\.\d+\.\d+)"),
  ),
  _VersionSpot(
    'packages/specstone/pubspec.yaml',
    'packages/specstone/pubspec.yaml',
    RegExp(r'(^version: )(\S+)', multiLine: true),
  ),
  _VersionSpot(
    'packages/specstone_core/pubspec.yaml',
    'packages/specstone_core/pubspec.yaml',
    RegExp(r'(^version: )(\S+)', multiLine: true),
  ),
  _VersionSpot(
    'plugin/.claude-plugin/plugin.json',
    'plugin/.claude-plugin/plugin.json',
    RegExp(r'("version"\s*:\s*")([^"]*)'),
  ),
  _VersionSpot(
    'packages/specstone/pubspec.yaml (specstone_core constraint)',
    'packages/specstone/pubspec.yaml',
    RegExp(r'(^\s+specstone_core:\s*\^)(\S+)', multiLine: true),
  ),
];

const String _usage = 'usage: dart run tool/release.dart X.Y.Z [--dry-run]';
const String _dryRunFlag = '--dry-run';

final RegExp _versionForm = RegExp(r'^\d+\.\d+\.\d+$');
const Duration _runPollInterval = Duration(seconds: 5);
const int _runPollTries = 60;

/// A failed check: printed as `release: <message>` on stderr, exit 1.
final class _Refusal implements Exception {
  new(this.message);

  final String message;
}

Future<void> main(List<String> args) async {
  try {
    await _release(args);
  } on _Refusal catch (refusal) {
    stderr.writeln('release: ${refusal.message}');
    exitCode = 1;
  }
}

Future<void> _release(List<String> args) async {
  final version = _parseArgs(args);
  final dryRun = args.contains(_dryRunFlag);

  final root = await _git(['rev-parse', '--show-toplevel']);
  Directory.current = root;
  final branch = await _git(['rev-parse', '--abbrev-ref', 'HEAD']);
  if (branch.startsWith('release/')) {
    // The run again from a release branch is M5-T13.
    return;
  }
  if (branch != 'develop') {
    throw _Refusal('on branch $branch; check out develop to release');
  }

  await _checkCleanTree();
  final head = await _checkDevelopMatchesOrigin();
  await _checkCiPassed(head);
  await _checkVersionAboveCurrent(root, version);
  await _checkTagAbsent(version);

  if (dryRun) {
    _planSteps(version).forEach(stdout.writeln);
    return;
  }
  final tagSha = await _bumpAndTag(root, version);
  await _pushTag(version);
  if (await waitForRun(version, tagSha) != 0) {
    exitCode = 1;
    return;
  }
  final releaseUrl = await _confirmRelease(version);
  exitCode = await land(version, releaseUrl);
}

String _parseArgs(List<String> args) {
  final versions = args.where((a) => a != _dryRunFlag).toList();
  final hasUnknownFlag = versions.any((a) => a.startsWith('--'));
  if (versions.length != 1 || hasUnknownFlag) {
    throw _Refusal(_usage);
  }
  return versions.single;
}

Future<void> _checkCleanTree() async {
  final porcelain = await _git(['status', '--porcelain']);
  if (porcelain.isNotEmpty) {
    throw _Refusal('the working tree is not clean:\n$porcelain');
  }
}

/// Returns the sha of `develop` once it equals `origin/develop`.
Future<String> _checkDevelopMatchesOrigin() async {
  // --no-tags: a fetch must not create the local tag a refusal then leaves.
  await _git(['fetch', '--no-tags', 'origin']);
  final local = await _git(['rev-parse', 'develop']);
  final remote = await _git(['rev-parse', 'origin/develop']);
  if (local != remote) {
    throw _Refusal(
      'develop ($local) differs from origin/develop ($remote); '
      'push or pull until they are equal',
    );
  }
  return local;
}

Future<void> _checkCiPassed(String sha) async {
  final output = await _readCiRuns(sha);
  final Object? runs;
  try {
    runs = jsonDecode(output);
  } on FormatException {
    throw _Refusal('gh printed no JSON for the ci run of develop $sha');
  }
  switch (runs) {
    case [{'status': 'completed', 'conclusion': 'success'}, ...]:
      return;
    case [
      {'status': final Object? status, 'conclusion': final Object? end},
      ...,
    ]:
      final state = status == 'completed' ? end : status;
      throw _Refusal('the ci run on develop $sha is $state, not success');
    default:
      throw _Refusal('no ci run found on develop $sha');
  }
}

Future<String> _readCiRuns(String sha) => _gh([
  'run',
  'list',
  '--workflow',
  'ci.yaml',
  '--commit',
  sha,
  '--limit',
  '1',
  '--json',
  'status,conclusion',
], 'reading the ci run');

Future<void> _checkVersionAboveCurrent(String root, String version) async {
  final current = _readCurrentVersion(root);
  if (!_versionForm.hasMatch(version)) {
    throw _Refusal(
      '$version is not in the form MAJOR.MINOR.PATCH; '
      'the current version is $current',
    );
  }
  if (_compare(version, current) <= 0) {
    throw _Refusal(
      '$version is not greater than the current version $current; '
      'give MAJOR.MINOR.PATCH above it',
    );
  }
}

String _readCurrentVersion(String root) {
  final current = readSpots(root)[_spots.first.label]!;
  if (current == _missing) {
    throw _Refusal('${_spots.first.path} holds no specstoneVersion constant');
  }
  return current;
}

/// Compares two `MAJOR.MINOR.PATCH` strings field by field.
int _compare(String a, String b) {
  final left = a.split('.').map(BigInt.parse).toList();
  final right = b.split('.').map(BigInt.parse).toList();
  for (var i = 0; i < left.length; i++) {
    final order = left[i].compareTo(right[i]);
    if (order != 0) return order;
  }
  return 0;
}

Future<void> _checkTagAbsent(String version) async {
  final tag = 'v$version';
  if ((await _git(['tag', '--list', tag])).isNotEmpty) {
    throw _Refusal('tag $tag already exists locally');
  }
  final remote = await _git([
    'ls-remote',
    '--tags',
    'origin',
    'refs/tags/$tag',
  ]);
  if (remote.isNotEmpty) {
    throw _Refusal('tag $tag already exists on origin');
  }
}

List<String> _planSteps(String v) {
  final fastForward =
      'fast-forward main to v$v; fast-forward develop to origin/develop; '
      'merge release/$v into develop';
  return [
    'create release/$v from develop',
    'set $v in the five version spots',
    're-read the five spots; run dart pub get --enforce-lockfile',
    'commit "chore: release $v"; tag v$v on it',
    'push tag v$v',
    'wait for the release.yaml run of v$v',
    'fetch origin; check origin/main and local develop before moving any ref',
    fastForward,
    'push main and develop in one atomic push; delete release/$v',
  ];
}

Future<String> _git(List<String> args) async {
  final result = await _run('git', args);
  if (result.exitCode != 0) {
    throw _Refusal('git ${args.join(' ')} failed: ${_failureLine(result)}');
  }
  // Trailing only: the leading space of a porcelain status line is data.
  return (result.stdout as String).trimRight();
}

Future<ProcessResult> _run(String executable, List<String> args) async {
  try {
    return await Process.run(executable, args);
  } on ProcessException catch (error) {
    if (executable == 'gh') {
      throw _Refusal(
        'gh is not available (${error.message}); install it and run '
        'gh auth login, then release again',
      );
    }
    throw _Refusal('$executable is not available (${error.message})');
  }
}

/// Returns the stdout of a `gh` call, or refuses naming why it failed.
Future<String> _gh(List<String> args, String doing) async {
  final result = await _run('gh', args);
  // gh exits 4 when it is not logged in.
  if (result.exitCode == 4) {
    throw _Refusal(
      'gh is not logged in ($doing); run gh auth login, then release again',
    );
  }
  if (result.exitCode != 0) {
    throw _Refusal('gh failed ($doing): ${_failureLine(result)}');
  }
  return result.stdout as String;
}

/// Returns the first non-empty stderr line, else the first stdout line.
String _failureLine(ProcessResult result) {
  for (final stream in [result.stderr, result.stdout]) {
    for (final line in LineSplitter.split(stream as String)) {
      if (line.trim().isNotEmpty) return line.trim();
    }
  }
  return 'exit code ${result.exitCode}';
}

/// Returns each version spot's label mapped to the version it holds.
///
/// A spot whose file or line is absent maps to `<missing>`. [root] is the
/// repo root.
Map<String, String> readSpots(String root) => {
  for (final spot in _spots) spot.label: _readSpot(root, spot),
};

String _readSpot(String root, _VersionSpot spot) {
  final file = File('$root/${spot.path}');
  if (!file.existsSync()) return _missing;
  return spot.pattern.firstMatch(file.readAsStringSync())?.group(2) ?? _missing;
}

void _writeSpots(String root, String version) {
  for (final spot in _spots) {
    final file = File('$root/${spot.path}');
    file.writeAsStringSync(
      file.readAsStringSync().replaceFirstMapped(
        spot.pattern,
        (match) => '${match[1]}$version',
      ),
    );
  }
}

String _runAgain(String version) =>
    'run dart run tool/release.dart $version again from release/$version';

/// Bumps the five spots on `release/<version>`, commits, and tags.
///
/// Returns the tagged commit. A spot left behind or a failed
/// `dart pub get` undoes the bump and refuses before the commit.
Future<String> _bumpAndTag(String root, String version) async {
  await _git(['switch', '-c', 'release/$version']);
  _writeSpots(root, version);

  final behind = readSpots(root).entries.where((e) => e.value != version);
  if (behind.isNotEmpty) {
    await _undoBump(
      version,
      'after the bump these spots do not hold $version: '
      '${behind.map((e) => '${e.key} holds ${e.value}').join('; ')}',
    );
  }
  final pub = await _run(Platform.resolvedExecutable, [
    'pub',
    'get',
    '--enforce-lockfile',
  ]);
  if (pub.exitCode != 0) {
    await _undoBump(
      version,
      'dart pub get --enforce-lockfile rejected the bump: '
      '${_solvingLine(pub)}',
    );
  }

  await _git(['add', ..._spots.map((spot) => spot.path).toSet()]);
  await _git(['commit', '-q', '-m', 'chore: release $version']);
  await _git(['tag', 'v$version']);
  return _git(['rev-parse', 'HEAD']);
}

/// Returns pub's version-solving line, else its first error line.
String _solvingLine(ProcessResult pub) {
  final lines = LineSplitter.split('${pub.stderr}\n${pub.stdout}');
  return lines.firstWhere(
    (line) => line.contains('version solving failed'),
    orElse: () => _failureLine(pub),
  );
}

/// Restores the spots, checks out `develop`, deletes the release branch, and
/// refuses with [message]. Nothing was pushed.
Future<void> _undoBump(String version, String message) async {
  await _git(['checkout', '--', '.']);
  await _git(['switch', 'develop']);
  await _git(['branch', '-D', 'release/$version']);
  throw _Refusal('$message; nothing was pushed');
}

Future<void> _pushTag(String version) async {
  try {
    await _git(['push', 'origin', 'v$version']);
  } on _Refusal catch (failure) {
    throw _Refusal(
      '${failure.message}; main and develop are untouched, and '
      'release/$version and v$version stay. ${_runAgain(version)}',
    );
  }
}

/// Waits for the `release.yaml` run of the tag at [tagSha] to end.
///
/// Returns 0 when the run succeeded. On a failed run it prints the failure
/// on stderr and returns 1.
Future<int> waitForRun(String version, String tagSha) async {
  final run = await _findRun(version, tagSha);
  final watch = await _run('gh', [
    'run',
    'watch',
    '${run.id}',
    '--exit-status',
  ]);
  if (watch.exitCode == 0) return 0;
  stderr.writeln(
    'release: the release.yaml run of v$version failed: ${run.url}; '
    'main and develop are untouched. Fix on release/$version, then run '
    'dart run tool/release.dart $version from that branch',
  );
  return 1;
}

/// Polls until `gh` lists the `release.yaml` run of the tag commit.
Future<({int id, String url})> _findRun(String version, String tagSha) async {
  for (var attempt = 1; attempt <= _runPollTries; attempt++) {
    final output = await _gh([
      'run',
      'list',
      '--workflow',
      'release.yaml',
      '--commit',
      tagSha,
      '--limit',
      '1',
      '--json',
      'databaseId,url',
    ], 'finding the release.yaml run of v$version');
    final Object? runs;
    try {
      runs = jsonDecode(output);
    } on FormatException {
      throw _Refusal(
        'gh printed no JSON for the release.yaml run of v$version',
      );
    }
    if (runs case [
      {'databaseId': final int id, 'url': final String url},
      ...,
    ]) {
      return (id: id, url: url);
    }
    if (attempt < _runPollTries) await Future<void>.delayed(_runPollInterval);
  }
  throw _Refusal(
    'no release.yaml run of v$version appeared in '
    '${_runPollInterval.inSeconds * _runPollTries} s; main and develop are '
    'untouched. ${_runAgain(version)}',
  );
}

/// Returns the URL of the published Release `v<version>`.
Future<String> _confirmRelease(String version) async {
  try {
    final url = await _gh([
      'release',
      'view',
      'v$version',
      '--json',
      'url',
      '--jq',
      '.url',
    ], 'confirming the Release v$version');
    return url.trim();
  } on _Refusal catch (failure) {
    throw _Refusal(
      '${failure.message}; main and develop are untouched. '
      '${_runAgain(version)}',
    );
  }
}

/// Lands the published Release: moves `main` and `develop`, pushes both
/// atomically, and deletes `release/<version>`.
///
/// Both checks run before any ref moves. Returns 0 on success; on a failed
/// check or push it prints why on stderr, leaves local and remote as they
/// were, and returns 1.
Future<int> land(String version, String releaseUrl) async {
  final tag = 'v$version';
  final branch = 'release/$version';
  await _git(['fetch', 'origin']);

  final blocked = await _landingBlock(tag);
  if (blocked != null) return _stopLanding(version, blocked);

  final main = await _git(['rev-parse', 'main']);
  final develop = await _git(['rev-parse', 'develop']);
  try {
    await _git(['switch', 'main']);
    await _git(['merge', '--ff-only', tag]);
    await _git(['switch', 'develop']);
    await _git(['merge', '--ff-only', 'origin/develop']);
    await _git(['merge', '--no-edit', branch]);
    await _git(['push', '--atomic', 'origin', 'main', 'develop']);
  } on _Refusal catch (failure) {
    // A merge that stopped half way is undone before the refs go back.
    await _run('git', ['merge', '--abort']);
    await _git(['switch', branch]);
    await _git(['update-ref', 'refs/heads/main', main]);
    await _git(['update-ref', 'refs/heads/develop', develop]);
    return _stopLanding(
      version,
      '${failure.message}; main and develop are back where they were.',
    );
  }

  await _git(['branch', '-d', branch]);
  if ((await _git(['ls-remote', '--heads', 'origin', branch])).isNotEmpty) {
    await _git(['push', 'origin', '--delete', branch]);
  }
  stdout.writeln('Released $tag: $releaseUrl; main and develop pushed');
  return 0;
}

/// Returns what the first failed landing check prints, else null.
Future<String?> _landingBlock(String tag) async {
  if (!await _isAncestor('origin/main', tag)) {
    final held = await _git(['log', '-1', '--format=%h %s', 'origin/main']);
    return 'origin/main holds $held, which $tag does not contain: '
        'a second release reached main.';
  }
  if (!await _isAncestor('develop', 'origin/develop')) {
    final lacking = await _git([
      'log',
      '--format=  %h %s',
      'origin/develop..develop',
    ]);
    return 'local develop holds commits origin/develop lacks:\n$lacking';
  }
  return null;
}

Future<bool> _isAncestor(String ancestor, String descendant) async {
  final result = await _run('git', [
    'merge-base',
    '--is-ancestor',
    ancestor,
    descendant,
  ]);
  return switch (result.exitCode) {
    0 => true,
    1 => false,
    _ => throw _Refusal(
      'git merge-base --is-ancestor $ancestor $descendant failed: '
      '${_failureLine(result)}',
    ),
  };
}

/// Prints [reason] with the closing lines of a stopped landing; returns 1.
int _stopLanding(String version, String reason) {
  stderr
    ..writeln('release: $reason')
    ..writeln('Nothing was pushed; the Release v$version stays published.')
    ..writeln('Resolve it, then ${_runAgain(version)}');
  return 1;
}
