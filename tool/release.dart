// Releases a new specstone version from `develop`.
//
// Usage: dart run tool/release.dart X.Y.Z [--dry-run]
// Contract: the release operation of api:install_update/version_match.
import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/release_version.dart';

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
    RegExp("(const String specstoneVersion = ')($releaseVersionPattern)(?=';)"),
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

const String _versionFormName = 'MAJOR.MINOR.PATCH[-<pre-release>]';
const Duration _runPollInterval = Duration(seconds: 5);
const int _runPollTries = 60;
const Duration _viewPollInterval = Duration(seconds: 15);
const int _viewPollTries = 360;

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
    await _runAgainFrom(root, version, branch, dryRun: dryRun);
    return;
  }
  if (branch != 'develop') {
    throw _Refusal('on branch $branch; check out develop to release');
  }

  await _checkCleanTree();
  final head = await _checkDevelopMatchesOrigin();
  await _checkMainInDevelop();
  await _checkCiPassed(head);
  await _checkVersionAboveCurrent(root, version);
  await _checkTagAbsent(version);
  _checkSpotsParse(root);

  if (dryRun) {
    _planSteps(
      version,
      isPreRelease: _isPreRelease(version),
    ).forEach(stdout.writeln);
    return;
  }
  final tagSha = await _bumpAndTag(root, version);
  await _pushTag(version);
  await _endingWithRunAgain(version, () => _publishAndLand(version, tagSha));
}

/// Sets the exit code from [steps], which run once the tag is pushed.
///
/// Every refusal from there on says how to run again.
Future<void> _endingWithRunAgain(
  String version,
  Future<int> Function() steps,
) async {
  try {
    exitCode = await steps();
  } on _Refusal catch (refusal) {
    stderr
      ..writeln('release: ${refusal.message}')
      ..writeln('Resolve it, then ${_runAgain(version)}');
    exitCode = 1;
  }
}

/// Runs the release again from [branch], the `release/<version>` branch.
///
/// A published Release only lands; otherwise the tag moves to the branch head
/// and the run is awaited, then the release lands.
Future<void> _runAgainFrom(
  String root,
  String version,
  String branch, {
  required bool dryRun,
}) async {
  if (branch != 'release/$version') {
    final onVersion = branch.substring('release/'.length);
    throw _Refusal(
      'on branch $branch, not release/$version; pass $onVersion to release '
      'it again, or check out develop to release $version for the first time',
    );
  }
  await _checkCleanTree();
  final behind = _spotsNotHolding(root, version);
  if (behind.isNotEmpty) {
    throw _Refusal('the version spots do not all hold $version: $behind');
  }
  await _checkGhLoggedIn();

  final releaseUrl = await _publishedReleaseUrl(version);
  if (dryRun) {
    final awaited = releaseUrl == null ? await _awaitedTagSha(version) : null;
    [
      if (releaseUrl == null && awaited == null) ..._moveTagSteps(version),
      if (awaited != null) _waitStep(version),
      ..._landingSteps(version, isPreRelease: _isPreRelease(version)),
    ].forEach(stdout.writeln);
    return;
  }
  await _endingWithRunAgain(
    version,
    () => releaseUrl == null
        ? _moveTagAndPublish(version)
        : land(version, releaseUrl),
  );
}

Future<void> _checkGhLoggedIn() async {
  final result = await _run('gh', ['auth', 'status']);
  if (result.exitCode != 0) {
    throw _Refusal(
      'gh is not logged in (${_failureLine(result)}); run gh auth login, '
      'then release again',
    );
  }
}

/// Returns the URL of the published Release `v<version>`, else null.
Future<String?> _publishedReleaseUrl(String version) async {
  final result = await _run('gh', [
    'release',
    'view',
    'v$version',
    '--json',
    'url',
    '--jq',
    '.url',
  ]);
  if (result.exitCode == 0) return (result.stdout as String).trim();
  // gh answers a missing Release with exit 1 and this text; anything else
  // (network, login) is not "unpublished" and must not move the tag.
  if (result.exitCode == 1 &&
      '${result.stderr}'.contains('release not found')) {
    return null;
  }
  throw _Refusal(
    'gh failed (reading the Release v$version): ${_failureLine(result)}',
  );
}

/// Moves the tag to the head of the release branch and awaits its run.
///
/// A run of the pushed tag still queued or in progress is awaited instead,
/// and the tag stays: moving it would cancel the run that is publishing.
Future<int> _moveTagAndPublish(String version) async {
  final awaited = await _awaitedTagSha(version);
  if (awaited != null) {
    if (awaited != await _git(['rev-parse', 'HEAD'])) {
      stdout.writeln(
        'v$version at $awaited is still being released; commits made on '
        'release/$version since then ship with the next version.',
      );
    }
    return _publishAndLand(version, awaited);
  }

  await _pushRunAgainRef(['origin', 'release/$version']);
  await _git(['tag', '-f', 'v$version']);
  await _pushRunAgainRef(['--force', 'origin', 'v$version']);
  return _publishAndLand(version, await _git(['rev-parse', 'HEAD']));
}

/// Returns the commit of `origin`'s tag when its release run has not ended.
///
/// Refuses when the tag already points at HEAD and its run failed, since
/// moving it would start no new run. Returns null when the tag may move.
Future<String?> _awaitedTagSha(String version) async {
  final remote = await _git(['ls-remote', 'origin', 'refs/tags/v$version']);
  if (remote.isEmpty) return null;
  final tagSha = remote.split(RegExp(r'\s')).first;
  final runs = await _releaseRuns(version, tagSha);
  switch (runs) {
    case [{'status': final String status}, ...] when status != 'completed':
      return tagSha;
    case [{'status': 'completed', 'conclusion': final Object? end}, ...]
        when end != 'success' && tagSha == await _git(['rev-parse', 'HEAD']):
      throw _Refusal(
        'v$version already points at HEAD and its run failed; commit a fix '
        'or re-run the workflow',
      );
  }
  return null;
}

Future<void> _pushRunAgainRef(List<String> pushArgs) async {
  try {
    await _git(['push', ...pushArgs]);
  } on _Refusal catch (failure) {
    throw _Refusal('${failure.message}; main and develop are untouched');
  }
}

Future<int> _publishAndLand(String version, String tagSha) async {
  if (await waitForRun(version, tagSha) != 0) return 1;
  final releaseUrl = await _confirmRelease(version);
  return land(version, releaseUrl);
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

/// Refuses when `origin/main` holds commits `develop` lacks.
Future<void> _checkMainInDevelop() async {
  if (await _isAncestor('origin/main', 'develop')) return;
  final lacking = await _git([
    'log',
    '--format=  %h %s',
    'develop..origin/main',
  ]);
  throw _Refusal(
    'origin/main holds commits develop lacks; merge main into develop first:\n'
    '$lacking',
  );
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
  final next = ReleaseVersion.tryParse(version);
  if (next == null) {
    throw _Refusal(
      '$version is not a version of the form $_versionFormName; '
      'the current version is $current',
    );
  }
  if (next.compareTo(current) <= 0) {
    throw _Refusal(
      '$version is not greater than the current version $current; '
      'give a version of the form $_versionFormName above it',
    );
  }
}

ReleaseVersion _readCurrentVersion(String root) {
  final current = ReleaseVersion.tryParse(readSpots(root)[_spots.first.label]!);
  if (current == null) {
    throw _Refusal('${_spots.first.path} holds no specstoneVersion constant');
  }
  return current;
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

List<String> _planSteps(String v, {required bool isPreRelease}) => [
  'create release/$v from develop',
  'set $v in the five version spots',
  're-read the five spots; run dart pub get --enforce-lockfile',
  'commit "chore: release $v"; tag v$v on it',
  'push tag v$v',
  _waitStep(v),
  ..._landingSteps(v, isPreRelease: isPreRelease),
];

List<String> _moveTagSteps(String v) => [
  'push release/$v',
  'move tag v$v to the head of release/$v; push it',
  _waitStep(v),
];

String _waitStep(String v) => 'wait for the release.yaml run of v$v';

List<String> _landingSteps(String v, {required bool isPreRelease}) {
  if (isPreRelease) {
    return [
      'fetch origin; check local develop before moving any ref',
      'fast-forward develop to origin/develop; merge release/$v into develop',
      'push develop alone; main stays where it is; delete release/$v',
    ];
  }
  final fastForward =
      'fast-forward main to v$v; fast-forward develop to origin/develop; '
      'merge release/$v into develop';
  return [
    'fetch origin; check origin/main and local develop before moving any ref',
    fastForward,
    'push main and develop in one atomic push; delete release/$v',
  ];
}

/// Returns whether [version] holds a pre-release part.
///
/// Every caller holds a version the Version form accepted: the first run
/// refuses any other in [_checkVersionAboveCurrent], and a run again reaches
/// here only after the first spot matched the form's pattern.
bool _isPreRelease(String version) =>
    ReleaseVersion.tryParse(version)!.isPreRelease;

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

/// Refuses when a spot's file is absent or holds no line to rewrite.
///
/// Runs before the first write so a refusal leaves nothing to undo.
void _checkSpotsParse(String root) {
  for (final spot in _spots) {
    if (_readSpot(root, spot) == _missing) {
      throw _Refusal('${spot.label} holds no version line to set');
    }
  }
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

/// Returns `<label> holds <value>` for each spot not at [version], joined by
/// `; `; empty when all five hold it.
String _spotsNotHolding(String root, String version) =>
    readSpots(root).entries
        .where((e) => e.value != version)
        .map((e) => '${e.key} holds ${e.value}')
        .join('; ');

/// Bumps the five spots on `release/<version>`, commits, and tags.
///
/// Returns the tagged commit. A spot left behind or a failed
/// `dart pub get` undoes the bump and refuses before the commit.
Future<String> _bumpAndTag(String root, String version) async {
  await _git(['switch', '-c', 'release/$version']);
  _writeSpots(root, version);

  final behind = _spotsNotHolding(root, version);
  if (behind.isNotEmpty) {
    await _undoBump(
      version,
      'after the bump these spots do not hold $version: $behind',
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
/// on stderr and returns 1. When `gh run watch` fails, the run is polled with
/// `gh run view` for up to 90 minutes; a gh error or that limit refuses.
Future<int> waitForRun(String version, String tagSha) async {
  final run = await _findRun(version, tagSha);
  stdout.writeln('Waiting for the release.yaml run of v$version: ${run.url}');
  // Streams to the terminal, so the Owner sees the steps of a 20-40 minute run.
  final watch = await Process.start('gh', [
    'run',
    'watch',
    '${run.id}',
    '--exit-status',
  ], mode: ProcessStartMode.inheritStdio);
  if (await watch.exitCode == 0) return 0;
  // A token without the watch scope fails `gh run watch` on every release,
  // so the run is polled with `gh run view` instead.
  return _pollRun(version, run);
}

/// Polls the run with `gh run view` until it completes, then acts on it.
Future<int> _pollRun(String version, ({int id, String url}) run) async {
  for (var attempt = 1; attempt <= _viewPollTries; attempt++) {
    final view = await _gh([
      'run',
      'view',
      '${run.id}',
      '--json',
      'status,conclusion',
    ], 'reading the release.yaml run of v$version');
    final Object? state;
    try {
      state = jsonDecode(view);
    } on FormatException {
      throw _Refusal(
        'gh printed no JSON for the release.yaml run of v$version',
      );
    }
    if (state case {'status': 'completed', 'conclusion': final Object? end}) {
      if (end == 'success') return 0;
      if (end == 'failure') {
        stderr.writeln(
          'release: the release.yaml run of v$version failed: ${run.url}; '
          'main and develop are untouched. Fix on release/$version, then run '
          'dart run tool/release.dart $version from that branch',
        );
        return 1;
      }
      throw _Refusal(
        'the release.yaml run of v$version ended as $end (${run.url}); '
        'main and develop are untouched',
      );
    }
    if (attempt < _viewPollTries) await Future<void>.delayed(_viewPollInterval);
  }
  throw _Refusal(
    'the release.yaml run of v$version (${run.url}) did not end within '
    '${(_viewPollInterval * _viewPollTries).inMinutes} minutes; '
    'main and develop are untouched',
  );
}

/// Returns the `release.yaml` push runs of the commit [sha], newest first.
///
/// Lists the commit's push runs and keeps those of the workflow path, rather
/// than naming the file to `gh run list --workflow`, which resolves it on the
/// default branch and answers 404 until `main` holds `release.yaml`.
Future<List<Object?>> _releaseRuns(String version, String sha) async {
  final output = await _gh([
    'api',
    'repos/{owner}/{repo}/actions/runs?head_sha=$sha&event=push',
  ], 'finding the release.yaml run of v$version');
  final Object? body;
  try {
    body = jsonDecode(output);
  } on FormatException {
    throw _Refusal('gh printed no JSON for the release.yaml run of v$version');
  }
  if (body case {'workflow_runs': final List<Object?> runs}) {
    return [
      for (final run in runs)
        if (run case {'path': final String path} when _isReleaseWorkflow(path))
          run,
    ];
  }
  throw _Refusal(
    'gh printed no workflow runs for the release.yaml run of v$version',
  );
}

/// Whether [path] names `release.yaml`, with or without a `@<ref>` suffix.
bool _isReleaseWorkflow(String path) =>
    path.split('@').first == '.github/workflows/release.yaml';

/// Polls until `gh` lists the `release.yaml` run of the tag commit.
Future<({int id, String url})> _findRun(String version, String tagSha) async {
  for (var attempt = 1; attempt <= _runPollTries; attempt++) {
    final runs = await _releaseRuns(version, tagSha);
    if (runs case [{'id': final int id, 'html_url': final String url}, ...]) {
      return (id: id, url: url);
    }
    if (attempt < _runPollTries) await Future<void>.delayed(_runPollInterval);
  }
  throw _Refusal(
    'no release.yaml run of v$version appeared in '
    '${_runPollInterval.inSeconds * _runPollTries} s; main and develop are '
    'untouched',
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
    throw _Refusal('${failure.message}; main and develop are untouched');
  }
}

/// Lands the published Release and deletes `release/<version>`.
///
/// A full release moves `main` and `develop` and pushes both atomically; a
/// pre-release moves `develop` alone and never writes `main`. Every check runs
/// before any ref moves. Returns 0 on success; on a failed check or push it
/// prints why on stderr, leaves local and remote as they were, and returns 1.
Future<int> land(String version, String releaseUrl) async {
  final tag = 'v$version';
  final branch = 'release/$version';
  final isPreRelease = _isPreRelease(version);
  await _checkLocalTagIsOrigins(tag);
  await _git(['fetch', 'origin']);

  final blocked = await _landingBlock(tag, isPreRelease: isPreRelease);
  if (blocked != null) return _stopLanding(version, blocked);

  final pushed = isPreRelease ? ['develop'] : ['main', 'develop'];
  final heads = {
    for (final name in pushed) name: await _git(['rev-parse', name]),
  };
  try {
    if (!isPreRelease) {
      await _git(['switch', 'main']);
      await _git(['merge', '--ff-only', tag]);
    }
    await _git(['switch', 'develop']);
    await _git(['merge', '--ff-only', 'origin/develop']);
    await _git(['merge', '--no-edit', branch]);
    await _git(['push', if (!isPreRelease) '--atomic', 'origin', ...pushed]);
  } on _Refusal catch (failure) {
    // A merge that stopped half way is undone before the refs go back.
    await _run('git', ['merge', '--abort']);
    await _git(['switch', branch]);
    for (final MapEntry(key: name, value: sha) in heads.entries) {
      await _git(['update-ref', 'refs/heads/$name', sha]);
    }
    final back = isPreRelease
        ? 'develop is back where it was.'
        : 'main and develop are back where they were.';
    return _stopLanding(version, '${failure.message}; $back');
  }

  final pushedNames = isPreRelease ? 'develop' : 'main and develop';
  stdout.writeln('Released $tag: $releaseUrl; $pushedNames pushed');
  try {
    await _git(['branch', '-d', branch]);
    if ((await _git(['ls-remote', '--heads', 'origin', branch])).isNotEmpty) {
      await _git(['push', 'origin', '--delete', branch]);
    }
  } on _Refusal catch (failure) {
    // The release is out; a branch left behind is the owner's to delete.
    stderr.writeln('release: could not delete $branch: ${failure.message}');
  }
  return 0;
}

/// Refuses when the local [tag] is not the commit `origin` holds for it.
///
/// `main` fast-forwards to the local tag, so a local tag that never reached
/// `origin` would put `main` on a commit that was not released.
Future<void> _checkLocalTagIsOrigins(String tag) async {
  final local = await _git(['rev-parse', tag]);
  final remote = await _git(['ls-remote', 'origin', 'refs/tags/$tag']);
  final origin = remote.split(RegExp(r'\s')).first;
  if (local != origin) {
    throw _Refusal(
      'local $tag ($local) differs from $tag on origin ($origin); '
      'main and develop are untouched',
    );
  }
}

/// Returns what the first failed landing check prints, else null.
///
/// A pre-release skips the `origin/main` check: it never writes `main`.
Future<String?> _landingBlock(String tag, {required bool isPreRelease}) async {
  if (!isPreRelease && !await _isAncestor('origin/main', tag)) {
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
