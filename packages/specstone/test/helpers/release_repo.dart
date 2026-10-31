import 'dart:io';

import 'package:test/test.dart';

import 'script_sandbox.dart';

/// Creates a fixture repo pair for `tool/release.dart`, deleted by
/// `addTearDown`.
///
/// `origin.git` is a bare repo; `work/` is a hook-free pub workspace cloned
/// state of it with `main` and `develop` pushed and `develop` checked out.
/// [files] replaces or adds files (path relative to `work/`) before the first
/// commit. A `gh` stub sits in `stubs/`; see [ReleaseRepo.release].
Future<ReleaseRepo> createReleaseRepo({
  String version = '0.1.0',
  Map<String, String> files = const {},
}) async {
  final root = await Directory.systemTemp.createTemp('specstone_release_');
  addTearDown(() => root.delete(recursive: true));
  final repo = ReleaseRepo._(
    root: root,
    work: Directory('${root.path}/work'),
    origin: Directory('${root.path}/origin.git'),
  );
  await repo._create(version, files);
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

  /// Runs `dart run tool/release.dart [args]` in `work/`.
  ///
  /// PATH holds `<root>/stubs` first. [gh] sets the stub's variables:
  /// `GH_STUB_AUTH` (`ok` | `none` | `broken`), `GH_STUB_CI` (`success` |
  /// `failure` | `in_progress` | `empty` for no run | `garbage` for non-JSON),
  /// `GH_STUB_RUN` (`success` | `failure`), `GH_STUB_RUN_LATE` (any value:
  /// the first release.yaml `run list` finds no run), `GH_STUB_VIEW`
  /// (`failure` | `later_success` | `broken`: what `run view` answers after a
  /// failed watch), `GH_STUB_RELEASE`
  /// (`absent` | `present`), and `GH_STUB_ON_WATCH` (a shell line run before
  /// `run watch` answers).
  Future<ProcessResult> release(
    List<String> args, {
    Map<String, String> gh = const {},
  }) {
    return Process.run(
      Platform.resolvedExecutable,
      ['run', 'tool/release.dart', ...args],
      workingDirectory: work.path,
      environment: {
        'PATH': '${_stubs.path}:${Platform.environment['PATH'] ?? ''}',
        ...gh,
      },
    );
  }

  /// Runs `git [args]` in [at] (default `work/`); returns trimmed stdout.
  Future<String> git(List<String> args, {Directory? at}) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: (at ?? work).path,
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
    final result = await Process.run('sh', [
      '-c',
      push + r' && git -C "$dir" rev-parse HEAD',
    ]);
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
    'plugin/.claude-plugin/plugin.json':
        '{\n  "name": "specstone",\n  "version": "$v"\n}\n',
    '.gitignore': '.dart_tool/\n',
  };

  Future<void> _writeGhStub() async {
    await _stubs.create();
    final stub = File('${_stubs.path}/gh');
    await stub.writeAsString(_ghStub(root.path));
    final chmod = await Process.run('chmod', ['+x', stub.path]);
    if (chmod.exitCode != 0) {
      throw StateError('chmod failed on the gh stub: ${chmod.stderr}');
    }
  }
}

String _ghStub(String root) =>
    '''
#!/bin/sh
root='$root'
echo "\$*" >> "\$root/gh.log"
log_in() {
  echo 'To get started with GitHub CLI, please run:' >&2
  echo '  gh auth login' >&2
  exit 4
}
case "\$1 \$2" in
  "auth status")
    [ "\${GH_STUB_AUTH:-ok}" = none ] && log_in
    echo 'Logged in to github.com'
    ;;
  "run list")
    [ "\${GH_STUB_AUTH:-ok}" = none ] && log_in
    if [ "\${GH_STUB_AUTH:-ok}" = broken ]; then
      echo 'gh: network down' >&2
      exit 1
    fi
    case "\$*" in
      *release.yaml*)
        if [ -n "\$GH_STUB_RUN_LATE" ] && [ ! -e "\$root/run_listed" ]; then
          touch "\$root/run_listed"
          echo '[]'
          exit 0
        fi
        echo '[{"databaseId": 123456789, "url": "https://github.com/nontravis/specstone/actions/runs/123456789"}]'
        ;;
      *)
        case "\${GH_STUB_CI:-success}" in
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
    [ -n "\$GH_STUB_ON_WATCH" ] && sh -c "\$GH_STUB_ON_WATCH"
    if [ "\${GH_STUB_RUN:-success}" = success ]; then
      touch "\$root/released"
    else
      echo 'release.yaml failed' >&2
      exit 1
    fi
    ;;
  "run view")
    case "\${GH_STUB_VIEW:-failure}" in
      broken)
        echo 'gh: network down' >&2
        exit 1
        ;;
      later_success)
        if [ ! -e "\$root/viewed" ]; then
          touch "\$root/viewed"
          echo '{"status":"in_progress","conclusion":""}'
        else
          echo '{"status":"completed","conclusion":"success"}'
        fi
        ;;
      *) echo '{"status":"completed","conclusion":"failure"}' ;;
    esac
    ;;
  "release view")
    if [ "\${GH_STUB_RELEASE:-absent}" = present ] || [ -e "\$root/released" ]; then
      echo "https://github.com/nontravis/specstone/releases/tag/\$3"
    else
      echo 'release not found' >&2
      exit 1
    fi
    ;;
  *)
    echo "gh stub: unexpected call: \$*" >&2
    exit 2
    ;;
esac
''';
