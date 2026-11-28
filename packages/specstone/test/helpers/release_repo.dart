import 'dart:io';

import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/git_repo.dart'
    show cleanGitEnvironment;
import 'script_sandbox.dart';

/// The temp-folder prefix of the release template; no copy names it.
const releaseTemplatePrefix = 'specstone_release_template_';

final class _ReleaseTemplate {
  new(this.fixture, this.snapshot);

  final Directory fixture;

  /// The kernel module of `tool/release.dart`, outside [fixture] so copies
  /// do not carry it.
  final File snapshot;
}

_ReleaseTemplate? _template;

/// Builds the default release fixture once, for [createReleaseRepo] to copy.
///
/// Call it in `setUpAll`; `addTearDown` deletes the template at the end of
/// the file.
Future<void> buildReleaseTemplate() async {
  final folder = await Directory.systemTemp.createTemp(releaseTemplatePrefix);
  addTearDown(() {
    _template = null;
    return folder.delete(recursive: true);
  });
  final fixture = Directory('${folder.path}/fixture');
  await fixture.create();
  await ReleaseRepo._(
    root: fixture,
    work: Directory('${fixture.path}/work'),
    origin: Directory('${fixture.path}/origin.git'),
  )._create('0.1.0', const {});
  final snapshot = File('${folder.path}/release.dill');
  // The fixture's pub workspace resolves `package:specstone_core`.
  final compile = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'kernel',
    'tool/release.dart',
    '-o',
    snapshot.path,
  ], workingDirectory: '${fixture.path}/work');
  if (compile.exitCode != 0) {
    throw StateError(
      'compiling the release tool exited ${compile.exitCode}: '
      '${compile.stderr}',
    );
  }
  _template = _ReleaseTemplate(fixture, snapshot);
}

/// Creates a fixture repo pair for `tool/release.dart`, deleted by
/// `addTearDown`.
///
/// `origin.git` is a bare repo; `work/` is a hook-free pub workspace cloned
/// state of it with `main` and `develop` pushed and `develop` checked out.
/// [files] replaces or adds files (path relative to `work/`) before the first
/// commit. A `gh` stub sits in `stubs/`; see [ReleaseRepo.release].
///
/// With the default [version] and no [files] it copies the template that
/// [buildReleaseTemplate] built; any other argument builds a fresh fixture.
Future<ReleaseRepo> createReleaseRepo({
  String version = '0.1.0',
  Map<String, String> files = const {},
}) async {
  final template = _template;
  if (template == null) {
    throw StateError('call buildReleaseTemplate in setUpAll first');
  }
  final root = await Directory.systemTemp.createTemp('specstone_release_');
  addTearDown(() => root.delete(recursive: true));
  final repo = ReleaseRepo._(
    root: root,
    work: Directory('${root.path}/work'),
    origin: Directory('${root.path}/origin.git'),
  );
  if (version == '0.1.0' && files.isEmpty) {
    await repo._copyFrom(template.fixture);
  } else {
    await repo._create(version, files);
  }
  return repo;
}

/// A local bare `origin` plus a clone of it, for `tool/release.dart` tests.
final class ReleaseRepo {
  new _({required this.root, required this.work, required this.origin});

  final Directory root;
  final Directory work;
  final Directory origin;

  int _clones = 0;

  Directory get _stubs => Directory('${root.path}/stubs');

  File get _ghLog => File('${root.path}/gh.log');

  /// The environment that puts the `gh` stub first on PATH and points it at
  /// this fixture's folder.
  Map<String, String> get stubEnvironment => {
    'PATH': '${_stubs.path}:${Platform.environment['PATH'] ?? ''}',
    'GH_STUB_ROOT': root.path,
  };

  /// Runs `tool/release.dart [args]` in `work/` from the template's kernel
  /// snapshot, which `dart <snapshot>` runs as `dart run` would.
  ///
  /// PATH holds `<root>/stubs` first. [gh] sets the stub's variables:
  /// `GH_STUB_AUTH` (`ok` | `none` | `broken`), `GH_STUB_CI` (`success` |
  /// `failure` | `in_progress` | `empty` for no run | `garbage` for non-JSON),
  /// `GH_STUB_RUN` (`success` | `failure`), `GH_STUB_RUN_STATE` (a run
  /// status such as `in_progress` or `completed`, added with the `GH_STUB_RUN`
  /// conclusion to the release.yaml run in the `gh api` runs answer),
  /// `GH_STUB_RUN_LATE` (any value: the first runs answer after the ci watch
  /// lacks the release.yaml run; the stub always answers
  /// `run list --workflow release.yaml` with a 404, as gh does before the
  /// default branch holds the file), `GH_STUB_BRANCH_CI` (`success` |
  /// `failure` | `cancelled`: how the ci run of the release branch head ends,
  /// as `run watch 223456789` and `run view 223456789` answer), and
  /// `GH_STUB_BRANCH_CI_LATE` (any value: the first runs answer lacks that
  /// ci run), `GH_STUB_BRANCH_CI_VIEW` (`broken`: `run watch 223456789` and
  /// `run view 223456789` exit 1 with a gh error), `GH_STUB_VIEW`
  /// (`failure` | `later_success` | `cancelled` | `garbage` | `broken`: what
  /// `run view` answers after a failed watch), `GH_STUB_RELEASE`
  /// (`absent` | `present` | `broken`), `GH_STUB_ON_CI_WATCH` (a shell line
  /// run before `run watch 223456789` answers), and `GH_STUB_ON_WATCH` (a
  /// shell line run before `run watch 123456789` answers). A hook that exits
  /// non-zero fails its gh call with exit 3 and a stderr line naming the hook.
  /// `GH_STUB_RUN_STATE_AFTER_CI` (a run status) replaces `GH_STUB_RUN_STATE`
  /// once the ci watch has run, `GH_STUB_PATH_REF` (any value) gives each run
  /// path a `@refs/heads/release/0.2.0` suffix, and `GH_STUB_CI_OLDER` (any
  /// value) lists a second, older ci run (id 223456788) after the newest.
  ///
  /// Every runs answer also lists a decoy run of `other.yaml`.
  Future<ProcessResult> release(
    List<String> args, {
    Map<String, String> gh = const {},
  }) {
    final template = _template;
    if (template == null) {
      throw StateError('call buildReleaseTemplate in setUpAll first');
    }
    return Process.run(
      Platform.resolvedExecutable,
      [template.snapshot.path, ...args],
      workingDirectory: work.path,
      environment: {...cleanGitEnvironment(), ...stubEnvironment, ...gh},
      includeParentEnvironment: false,
    );
  }

  /// Runs `git [args]` in [at] (default `work/`); returns trimmed stdout.
  Future<String> git(List<String> args, {Directory? at}) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: (at ?? work).path,
      environment: cleanGitEnvironment(),
      includeParentEnvironment: false,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'git ${args.join(' ')} exited ${result.exitCode}: ${result.stderr}',
      );
    }
    return (result.stdout as String).trim();
  }

  /// Returns `origin`'s refs as ref name to sha (`git ls-remote origin`).
  Future<Map<String, String>> originRefs() async {
    final output = await git(['ls-remote', 'origin']);
    return {
      for (final line in output.split('\n').where((l) => l.isNotEmpty))
        line.split('\t').last: line.split('\t').first,
    };
  }

  /// Returns everything a refusal must leave alone.
  ///
  /// That is `refs/heads/*`, `refs/tags/*`, the working tree status, and the
  /// bare origin's refs. `refs/remotes/*` is out: the tool's own `git fetch`
  /// moves it with no change the tool makes.
  Future<String> state() async {
    const refs = ['for-each-ref', 'refs/heads', 'refs/tags'];
    return [
      await git(refs),
      await git(['status', '--porcelain']),
      await git(['for-each-ref'], at: origin),
    ].join('\n--\n');
  }

  /// Returns the lines the `gh` stub logged, one per call.
  List<String> ghCalls() {
    if (!_ghLog.existsSync()) return [];
    return _ghLog.readAsLinesSync().where((line) => line.isNotEmpty).toList();
  }

  /// Writes [content] to [path] in `work/` and commits it with [message].
  Future<void> commitFile(String path, String content, String message) async {
    final file = File('${work.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    await git(['add', path]);
    await git(['commit', '-q', '-m', message]);
  }

  /// Commits [file] on [branch] from a second clone and pushes it.
  ///
  /// Returns the pushed sha.
  Future<String> pushFromOtherClone(
    String branch, {
    String file = 'other.txt',
  }) async {
    final push = pushFromOtherCloneCommand(branch, file: file);
    final result = await Process.run(
      'sh',
      ['-c', push + r' && git -C "$dir" rev-parse HEAD'],
      environment: cleanGitEnvironment(),
      includeParentEnvironment: false,
    );
    if (result.exitCode != 0) {
      throw StateError('push from other clone failed: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  /// Returns [pushFromOtherClone] as one `sh -c` line.
  ///
  /// For `GH_STUB_ON_WATCH`, to move `origin` while the tool waits. The line
  /// leaves the clone's folder in the shell variable `dir`.
  String pushFromOtherCloneCommand(String branch, {String file = 'other.txt'}) {
    final dir = '${root.path}/other_${_clones++}';
    const identity =
        '-c user.email=other@example.com -c user.name=Other '
        '-c commit.gpgsign=false';
    return "dir='$dir' && git clone -q --branch $branch '${origin.path}' "
        '"\$dir" && echo "\$dir" >> "\$dir/$file" '
        '&& git -C "\$dir" add $file '
        '&& git -C "\$dir" $identity commit -q -m other '
        '&& git -C "\$dir" push -q origin $branch';
  }

  Future<void> _copyFrom(Directory fixture) async {
    final copy = await Process.run('cp', [
      '-Rp',
      '${fixture.path}/.',
      root.path,
    ]);
    if (copy.exitCode != 0) {
      throw StateError('copying the release template failed: ${copy.stderr}');
    }
    await git(['remote', 'set-url', 'origin', origin.path]);
  }

  Future<void> _create(String version, Map<String, String> files) async {
    await origin.create();
    await git(['init', '-q', '--bare', '-b', 'main'], at: origin);
    await work.create();
    final tree = {..._tree(version), ...files};
    for (final MapEntry(:key, :value) in tree.entries) {
      final file = File('${work.path}/$key');
      await file.parent.create(recursive: true);
      await file.writeAsString(value);
    }
    await Directory('${work.path}/tool').create();
    await File('${repoRoot().path}/tool/release.dart')
        .copy('${work.path}/tool/release.dart');
    // The tool imports the real Version, so the fixture carries its two files.
    for (final path in [
      'lib/release_version.dart',
      'lib/src/release_version.dart',
    ]) {
      await File('${repoRoot().path}/packages/specstone_core/$path')
          .copy('${work.path}/packages/specstone_core/$path');
    }
    await _writeGhStub();

    await git(['init', '-q', '-b', 'main']);
    for (final setting in [
      ['user.email', 'owner@example.com'],
      ['user.name', 'Owner'],
      ['commit.gpgsign', 'false'],
      ['tag.gpgsign', 'false'],
    ]) {
      await git(['config', ...setting]);
    }
    final pub = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
    ], workingDirectory: work.path);
    if (pub.exitCode != 0) {
      throw StateError('dart pub get failed in the fixture: ${pub.stderr}');
    }
    await git(['add', '-A']);
    await git(['commit', '-q', '-m', 'init']);
    await git(['remote', 'add', 'origin', origin.path]);
    await git(['push', '-q', 'origin', 'main']);
    await git(['checkout', '-q', '-b', 'develop']);
    await git(['push', '-q', '-u', 'origin', 'develop']);
  }

  Map<String, String> _tree(String v) => {
    'pubspec.yaml': '''
name: fixture_workspace
publish_to: none
environment:
  sdk: ^3.13.5
workspace:
  - packages/specstone_core
  - packages/specstone
dependencies:
  specstone_core:
''',
    'packages/specstone_core/pubspec.yaml':
        '''
name: specstone_core
version: $v
environment:
  sdk: ^3.13.5
resolution: workspace
''',
    'packages/specstone_core/lib/src/version.dart':
        "const String specstoneVersion = '$v';\n",
    'packages/specstone/pubspec.yaml':
        '''
name: specstone
version: $v
environment:
  sdk: ^3.13.5
resolution: workspace
dependencies:
  specstone_core: ^$v
''',
    '.gitignore': '.dart_tool/\n',
  };

  Future<void> _writeGhStub() async {
    await _stubs.create();
    final stub = File('${_stubs.path}/gh');
    await stub.writeAsString(_ghStub());
    final chmod = await Process.run('chmod', ['+x', stub.path]);
    if (chmod.exitCode != 0) {
      throw StateError('chmod failed on the gh stub: ${chmod.stderr}');
    }
  }
}

String _ghStub() => r'''
#!/bin/sh
root="${GH_STUB_ROOT:?GH_STUB_ROOT is not set}"
echo "$*" >> "$root/gh.log"
log_in() {
  echo 'To get started with GitHub CLI, please run:' >&2
  echo '  gh auth login' >&2
  exit 4
}
# Runs a test hook; a hook that fails fails the gh call, naming the hook.
run_hook() {
  [ -z "$2" ] && return 0
  if ! sh -c "$2"; then
    echo "gh stub: hook $1 failed: $2" >&2
    exit 3
  fi
}
case "$1 $2" in
  "auth status")
    [ "${GH_STUB_AUTH:-ok}" = none ] && log_in
    echo 'Logged in to github.com'
    ;;
  "api repos/{owner}/{repo}/actions/runs?head_sha="*)
    [ "${GH_STUB_AUTH:-ok}" = none ] && log_in
    if [ "${GH_STUB_AUTH:-ok}" = broken ]; then
      echo 'gh: network down' >&2
      exit 1
    fi
    decoy='{"id": 1, "html_url": "https://github.com/nontravis/specstone/actions/runs/1", "path": ".github/workflows/other.yaml", "status": "completed", "conclusion": "failure"}'
    runs="$decoy"
    # A run's path carries @<ref> when its workflow ran on a ref.
    path_ref=''
    [ -n "$GH_STUB_PATH_REF" ] && path_ref='@refs/heads/release/0.2.0'
    # The ci run of the branch head, left out of the first answer when late.
    if [ -n "$GH_STUB_BRANCH_CI_LATE" ] && [ ! -e "$root/ci_listed" ]; then
      touch "$root/ci_listed"
    else
      runs="$runs"', {"id": 223456789, "html_url": "https://github.com/nontravis/specstone/actions/runs/223456789", "path": ".github/workflows/ci.yaml'"$path_ref"'"}'
      # A second, older ci run of the same commit comes after the newest.
      if [ -n "$GH_STUB_CI_OLDER" ]; then
        runs="$runs"', {"id": 223456788, "html_url": "https://github.com/nontravis/specstone/actions/runs/223456788", "path": ".github/workflows/ci.yaml'"$path_ref"'"}'
      fi
    fi
    run_state="$GH_STUB_RUN_STATE"
    if [ -n "$GH_STUB_RUN_STATE_AFTER_CI" ] && [ -e "$root/ci_watched" ]; then
      run_state="$GH_STUB_RUN_STATE_AFTER_CI"
    fi
    state=''
    if [ -n "$run_state" ]; then
      state=', "status": "'"$run_state"'", "conclusion": "'"${GH_STUB_RUN:-success}"'"'
    fi
    # The release.yaml run, left out of the first answer after the ci watch
    # when late.
    if [ -n "$GH_STUB_RUN_LATE" ] && [ -e "$root/ci_watched" ] && [ ! -e "$root/run_listed" ]; then
      touch "$root/run_listed"
    else
      runs="$runs"', {"id": 123456789, "html_url": "https://github.com/nontravis/specstone/actions/runs/123456789", "path": ".github/workflows/release.yaml'"$path_ref"'"'"$state"'}'
    fi
    echo '{"total_count": 3, "workflow_runs": ['"$runs"']}'
    ;;
  "run list")
    [ "${GH_STUB_AUTH:-ok}" = none ] && log_in
    if [ "${GH_STUB_AUTH:-ok}" = broken ]; then
      echo 'gh: network down' >&2
      exit 1
    fi
    case "$*" in
      *release.yaml*)
        # Real gh resolves --workflow by file name on the default branch, which
        # does not hold release.yaml until the first release lands.
        echo 'HTTP 404: workflow release.yaml not found on the default branch' >&2
        exit 1
        ;;
      *)
        case "${GH_STUB_CI:-success}" in
          success) echo '[{"status":"completed","conclusion":"success"}]' ;;
          failure) echo '[{"status":"completed","conclusion":"failure"}]' ;;
          empty) echo '[]' ;;
          garbage) echo 'this is not json' ;;
          *) echo '[{"status":"in_progress","conclusion":""}]' ;;
        esac
        ;;
    esac
    ;;
  "run watch")
    if [ "$3" = 223456789 ]; then
      run_hook GH_STUB_ON_CI_WATCH "$GH_STUB_ON_CI_WATCH"
      touch "$root/ci_watched"
      if [ "${GH_STUB_BRANCH_CI_VIEW:-ok}" = broken ]; then
        echo 'gh: network down' >&2
        exit 1
      fi
      if [ "${GH_STUB_BRANCH_CI:-success}" != success ]; then
        echo 'ci failed' >&2
        exit 1
      fi
    else
      run_hook GH_STUB_ON_WATCH "$GH_STUB_ON_WATCH"
      if [ "${GH_STUB_RUN:-success}" = success ]; then
        touch "$root/released"
      else
        echo 'release.yaml failed' >&2
        exit 1
      fi
    fi
    ;;
  "run view")
    if [ "$3" = 223456789 ]; then
      if [ "${GH_STUB_BRANCH_CI_VIEW:-ok}" = broken ]; then
        echo 'gh: network down' >&2
        exit 1
      fi
      case "${GH_STUB_BRANCH_CI:-success}" in
        success) echo '{"status":"completed","conclusion":"success"}' ;;
        *) echo '{"status":"completed","conclusion":"'"$GH_STUB_BRANCH_CI"'"}' ;;
      esac
      exit 0
    fi
    case "${GH_STUB_VIEW:-failure}" in
      broken)
        echo 'gh: network down' >&2
        exit 1
        ;;
      cancelled) echo '{"status":"completed","conclusion":"cancelled"}' ;;
      garbage) echo 'this is not json' ;;
      later_success)
        if [ ! -e "$root/viewed" ]; then
          touch "$root/viewed"
          echo '{"status":"in_progress","conclusion":""}'
        else
          echo '{"status":"completed","conclusion":"success"}'
        fi
        ;;
      *) echo '{"status":"completed","conclusion":"failure"}' ;;
    esac
    ;;
  "release view")
    if [ "${GH_STUB_RELEASE:-absent}" = broken ]; then
      echo 'gh: network down' >&2
      exit 1
    fi
    if [ "${GH_STUB_RELEASE:-absent}" = present ] || [ -e "$root/released" ]; then
      echo "https://github.com/nontravis/specstone/releases/tag/$3"
    else
      echo 'release not found' >&2
      exit 1
    fi
    ;;
  *)
    echo "gh stub: unexpected call: $*" >&2
    exit 2
    ;;
esac
''';
