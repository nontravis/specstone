// Releases a new specstone version from `develop`.
//
// Usage: dart run tool/release.dart X.Y.Z [--dry-run]
// Contract: docs/specs/install_update/s02_api_release.md `## release.dart`.
import 'dart:convert';
import 'dart:io';

/// The four files holding the five version spots of a release.
///
/// `packages/specstone/pubspec.yaml` holds two: its own `version:` and the
/// `specstone_core: ^X.Y.Z` dependency. The first entry also holds the
/// current version the tool compares against.
const List<String> versionSpotFiles = [
  'packages/specstone_core/lib/src/version.dart',
  'packages/specstone/pubspec.yaml',
  'packages/specstone_core/pubspec.yaml',
  'plugin/.claude-plugin/plugin.json',
];

const String _usage = 'usage: dart run tool/release.dart X.Y.Z [--dry-run]';
const String _dryRunFlag = '--dry-run';

final RegExp _versionForm = RegExp(r'^\d+\.\d+\.\d+$');
final RegExp _currentVersion = RegExp(
  r"""const String specstoneVersion = '(\d+\.\d+\.\d+)';""",
);

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
  await _checkVersionAboveCurrent(version);
  await _checkTagAbsent(version);

  if (dryRun) {
    _planSteps(version).forEach(stdout.writeln);
  }
  // Without --dry-run the bump, tag, and landing follow in M5-T12.
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

Future<String> _readCiRuns(String sha) async {
  const logIn = 'run gh auth login, then release again';
  final ProcessResult result;
  try {
    result = await Process.run('gh', [
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
    ]);
  } on ProcessException catch (error) {
    throw _Refusal(
      'gh is not available (${error.message}); install it and $logIn',
    );
  }
  if (result.exitCode != 0) {
    final said = (result.stderr as String).trim().replaceAll('\n', ' ');
    throw _Refusal('gh cannot read the ci run ($said); $logIn');
  }
  return result.stdout as String;
}

Future<void> _checkVersionAboveCurrent(String version) async {
  final current = await _readCurrentVersion();
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

Future<String> _readCurrentVersion() async {
  final path = versionSpotFiles.first;
  final source = await File(path).readAsString();
  final match = _currentVersion.firstMatch(source);
  if (match == null) {
    throw _Refusal('$path holds no specstoneVersion constant');
  }
  return match.group(1)!;
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
  final ProcessResult result;
  try {
    result = await Process.run('git', args);
  } on ProcessException catch (error) {
    throw _Refusal('git is not available (${error.message})');
  }
  if (result.exitCode != 0) {
    final said = (result.stderr as String).trim();
    throw _Refusal('git ${args.join(' ')} failed: $said');
  }
  return (result.stdout as String).trim();
}
