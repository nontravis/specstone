import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/git_repo.dart' show commitAll, git;
import 'script_sandbox.dart';

/// Compiles `tool/install_local.dart` and returns the path of the exe.
///
/// The tool is copied into a new temp folder outside the workspace and
/// compiled there, where no build hook is involved (as
/// `ScriptSandbox.compileFakeCli` does). The folder is the scratch package
/// `install_local_scratch`, holding copies of the two `specstone_core`
/// `Version` libraries. Call it from `setUpAll`: the folder is deleted by
/// `addTearDown` after the group.
Future<String> compileInstallLocal() async {
  final separator = Platform.pathSeparator;
  final scratch = await Directory.systemTemp.createTemp(
    'specstone_install_local_',
  );
  addTearDown(() => scratch.delete(recursive: true));
  final root = repoRoot().path;
  const environment = 'environment:\n  sdk: ^3.13.5\n';
  void writeScratch(String relative, String content) =>
      File('${scratch.path}$separator$relative')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
  writeScratch(
    'pubspec.yaml',
    'name: install_local_scratch\n$environment'
        'dependencies:\n  specstone_core:\n    path: core\n',
  );
  writeScratch(
    'core${separator}pubspec.yaml',
    'name: specstone_core\n$environment',
  );
  for (final file in [
    'release_version.dart',
    'src${separator}release_version.dart',
  ]) {
    writeScratch(
      'core${separator}lib$separator$file',
      File(
        '$root${separator}packages${separator}specstone_core'
        '${separator}lib$separator$file',
      ).readAsStringSync(),
    );
  }
  writeScratch(
    'tool${separator}install_local.dart',
    File('$root${separator}tool${separator}install_local.dart')
        .readAsStringSync(),
  );
  final exe =
      '${scratch.path}${separator}install_local'
      '${Platform.isWindows ? '.exe' : ''}';
  for (final args in [
    ['pub', 'get', '--offline'],
    ['compile', 'exe', 'tool${separator}install_local.dart', '-o', exe],
  ]) {
    final result = await Process.run(
      Platform.resolvedExecutable,
      args,
      workingDirectory: scratch.path,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'dart ${args.take(2).join(' ')} failed: '
        '${result.stdout}\n${result.stderr}',
      );
    }
  }
  return exe;
}

const _versionPath = 'packages/specstone_core/lib/src/version.dart';

/// The shim's path in the checkout, relative to its root.
const String shimPath = 'packages/specstone/bin/stn';

/// Creates a sandbox, a git checkout, and `dart` and `git` stubs; POSIX only.
///
/// The checkout is `<sandbox.root>/check out/`, on `develop`, with
/// `feature/example` one commit ahead; both are deleted by `addTearDown`. Each
/// branch commits an executable [shimPath] whose body names the branch.
Future<InstallLocalRepo> createInstallLocalRepo() async {
  final sandbox = await createScriptSandbox();
  final work = Directory('${sandbox.root.path}/check out');
  await work.create();
  return InstallLocalRepo._(sandbox, work)
    .._fillCheckout()
    .._writeStubs();
}

/// Runs the compiled tool against a fixture checkout, with logging stubs.
///
/// The `dart` and `git` stubs log each call to `dart.log` and `git.log`; the
/// `dart` stub fails per `STUB_DART_PUB=fail` and `STUB_DART_BUILD=fail`, and
/// waits for `<logs>/release` per `STUB_DART_BUILD=wait`; under
/// `STUB_DART_LOCK=1` its build step leaves a read-only `locked/` folder
/// beside the build output, which a delete of the temp folder cannot remove.
final class InstallLocalRepo {
  new _(this.sandbox, this.work);

  final ScriptSandbox sandbox;
  final Directory work;

  /// Runs [tool] in `work/`, with `sandbox.env()`, [env] over it, [unset] out.
  Future<ProcessResult> run(
    String tool, {
    List<String> args = const [],
    Map<String, String> env = const {},
    List<String> unset = const [],
  }) => Process.run(
    tool,
    args,
    workingDirectory: work.path,
    environment: _environment(env, unset),
    includeParentEnvironment: false,
  );

  /// Starts [tool] in `work/`; the environment is as [run] builds it.
  Future<Process> start(
    String tool, {
    List<String> args = const [],
    Map<String, String> env = const {},
    List<String> unset = const [],
  }) => Process.start(
    tool,
    args,
    workingDirectory: work.path,
    environment: _environment(env, unset),
    includeParentEnvironment: false,
  );

  /// Returns the full sha of [ref] in the checkout.
  String sha(String ref) => _git(['rev-parse', ref]);

  /// Returns the short sha of [ref] in the checkout.
  String shortSha(String ref) => _git(['rev-parse', '--short', ref]);

  /// Returns everything a refusal must leave alone in the checkout.
  ///
  /// That is the branch, `HEAD`, the status with untracked files listed, and
  /// both diffs.
  Future<String> checkoutState() async => [
    _git(['rev-parse', '--abbrev-ref', 'HEAD']),
    _git(['rev-parse', 'HEAD']),
    _git(['status', '--porcelain', '--untracked-files=all']),
    _git(['diff']),
    _git(['diff', '--cached']),
  ].join('\n--\n');

  /// Returns the `worktree <path>` lines of `git worktree list --porcelain`.
  List<String> worktrees() =>
      LineSplitter.split(_git(['worktree', 'list', '--porcelain']))
          .where((line) => line.startsWith('worktree '))
          .toList();

  /// Whether the sandbox `TMPDIR` holds nothing.
  bool get tmpIsEmpty =>
      Directory('${sandbox.root.path}/tmp').listSync().isEmpty;

  Map<String, String> _environment(
    Map<String, String> env,
    List<String> unset,
  ) => {...sandbox.env(), ...env}..removeWhere((key, _) => unset.contains(key));

  // The fixture calls skip the `git` stub: they run through the process PATH.
  String _git(List<String> args) {
    final result = git(work, args);
    if (result.exitCode != 0) {
      throw StateError(
        'git ${args.join(' ')} exited ${result.exitCode}: ${result.stderr}',
      );
    }
    // Trailing only: the leading space of a porcelain status line is data.
    return (result.stdout as String).trimRight();
  }

  void _write(String path, String content) => File('${work.path}/$path')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);

  // Commits as an executable, as the real shim is, with [marker] as its body.
  void _writeShim(String marker) {
    _write(shimPath, '#!/bin/sh\n# shim $marker\n');
    final result = Process.runSync('chmod', ['755', '${work.path}/$shimPath']);
    if (result.exitCode != 0) {
      throw StateError('chmod $shimPath failed: ${result.stderr}');
    }
  }

  void _fillCheckout() {
    _git(['init', '-q', '-b', 'develop']);
    _write(_versionPath, "const String specstoneVersion = '0.9.0';\n");
    _write('marker.txt', 'develop\n');
    _write('packages/specstone/bin/specstone.dart', 'void main() {}\n');
    _writeShim('develop');
    commitAll(work, 'init');
    _git(['tag', 'v0.9.0']);
    _git(['checkout', '-q', '-b', 'topic']);
    _write('topic.txt', 'topic\n');
    commitAll(work, 'topic');
    _git(['checkout', '-q', 'develop']);
    _git(['merge', '-q', '--no-ff', '-m', 'merge topic', 'topic']);
    _git(['checkout', '-q', '-b', 'feature/example']);
    _write('marker.txt', 'feature\n');
    _writeShim('feature');
    commitAll(work, 'feature');
    _git(['checkout', '-q', 'develop']);
  }

  void _writeStubs() {
    final realGit = _realGit;
    sandbox
      ..stub('git', '''
echo "\$*" >> "\$STUB_LOG_DIR/git.log"
exec '$realGit' "\$@"''')
      ..stub('dart', _dartStub);
  }
}

/// The `git` the process PATH finds, as an absolute path.
final String _realGit = () {
  final result = Process.runSync('sh', ['-c', 'command -v git']);
  final path = (result.stdout as String).trim();
  if (result.exitCode != 0 || path.isEmpty) {
    throw StateError('no git on the PATH');
  }
  return path;
}();

const _dartStub = r'''
echo "$PWD|$*" >> "$STUB_LOG_DIR/dart.log"
case "$1 $2" in
  'pub get')
    if [ "$STUB_DART_PUB" = fail ]; then
      echo 'stub: dart pub get failed' >&2
      exit 1
    fi
    ;;
  'build cli')
    out=
    while [ $# -gt 0 ]; do
      if [ "$1" = -o ]; then out=$2; fi
      shift
    done
    if [ "$STUB_DART_LOCK" = 1 ]; then
      lock=$(dirname "$out")/locked
      mkdir -p "$lock"
      echo locked > "$lock/file"
      chmod 555 "$lock"
    fi
    if [ "$STUB_DART_BUILD" = fail ]; then
      echo 'stub: dart build cli failed' >&2
      exit 1
    fi
    if [ "$STUB_DART_BUILD" = wait ]; then
      touch "$STUB_LOG_DIR/building"
      while [ ! -e "$STUB_LOG_DIR/release" ]; do sleep 0.1; done
    fi
    root=$(cd ../.. && pwd)
    mkdir -p "$out/bundle/lib" "$out/bundle/bin"
    echo stub > "$out/bundle/lib/libsqlite3.so"
    version=$(sed -n "s/^const String specstoneVersion = '\(.*\)';\r\{0,1\}$/\1/p" \
      "$root/packages/specstone_core/lib/src/version.dart")
    cp "$root/packages/specstone_core/lib/src/version.dart" \
      "$STUB_LOG_DIR/version.dart"
    marker=$(cat "$root/marker.txt")
    printf '#!/bin/sh\n# %s\nif [ "$1" = --version ]; then echo %s; fi\n' \
      "$marker" "$version" > "$out/bundle/bin/specstone"
    chmod 755 "$out/bundle/bin/specstone"
    ;;
  *)
    echo "dart stub: unexpected call: $*" >&2
    exit 2
    ;;
esac
''';
