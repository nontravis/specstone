import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/git_repo.dart' show commitAll, git;
import 'script_sandbox.dart';

/// Compiles `tool/install_local.dart` and returns the path of the exe.
///
/// The tool is copied into a new temp folder outside the workspace and
/// compiled there, where no build hook is involved (as
/// `ScriptSandbox.compileFakeCli` does). Call it from `setUpAll`: the folder is
/// deleted by `addTearDown` after the group.
Future<String> compileInstallLocal() async {
  final separator = Platform.pathSeparator;
  final scratch = await Directory.systemTemp.createTemp(
    'specstone_install_local_',
  );
  addTearDown(() => scratch.delete(recursive: true));
  final source = await File(
    '${repoRoot().path}${separator}tool${separator}install_local.dart',
  ).copy('${scratch.path}${separator}install_local.dart');
  final exe =
      '${scratch.path}${separator}install_local'
      '${Platform.isWindows ? '.exe' : ''}';
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    source.path,
    '-o',
    exe,
  ], workingDirectory: scratch.path);
  if (result.exitCode != 0) {
    throw StateError(
      'dart compile exe failed: ${result.stdout}\n${result.stderr}',
    );
  }
  return exe;
}

/// Creates a sandbox, a git checkout, and `dart` and `git` stubs; POSIX only.
///
/// The checkout is `<sandbox.root>/check out/`, on `develop`, with
/// `feature/example` one commit ahead; both are deleted by `addTearDown`.
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
/// `STUB_DART_IGNORE=signals` it ignores INT, TERM, and HUP.
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

  void _fillCheckout() {
    _git(['init', '-q', '-b', 'develop']);
    _write('fixture_version.txt', '0.9.0\n');
    _write('marker.txt', 'develop\n');
    _write('packages/specstone/bin/specstone.dart', 'void main() {}\n');
    commitAll(work, 'init');
    _git(['checkout', '-q', '-b', 'feature/example']);
    _write('marker.txt', 'feature\n');
    commitAll(work, 'feature');
    _git(['checkout', '-q', 'develop']);
  }

  void _writeStubs() {
    final realGit = _realGit;
    sandbox
      ..stub('git', '''
echo "\$*" >> "\$STUB_LOG_DIR/git.log"
exec '$realGit' "\$@"''')
      ..stub('dart', _dartStub.replaceAll('<real git>', realGit));
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
if [ "$STUB_DART_IGNORE" = signals ]; then trap '' INT TERM HUP; fi
case "$1 $2" in
  'pub get')
    if [ "$STUB_DART_PUB" = fail ]; then
      echo 'stub: dart pub get failed' >&2
      exit 1
    fi
    ;;
  'build cli')
    if [ "$STUB_DART_BUILD" = fail ]; then
      echo 'stub: dart build cli failed' >&2
      exit 1
    fi
    if [ "$STUB_DART_BUILD" = wait ]; then
      touch "$STUB_LOG_DIR/building"
      while [ ! -e "$STUB_LOG_DIR/release" ]; do sleep 0.1; done
    fi
    out=
    while [ $# -gt 0 ]; do
      if [ "$1" = -o ]; then out=$2; fi
      shift
    done
    root=$(cd ../.. && pwd)
    mkdir -p "$out/bundle/lib" "$out/bundle/bin"
    echo stub > "$out/bundle/lib/libsqlite3.so"
    version=$(cat "$root/fixture_version.txt")
    commit=$('<real git>' -C "$root" rev-parse HEAD)
    marker=$(cat "$root/marker.txt")
    printf '#!/bin/sh\n# %s %s\nif [ "$1" = --version ]; then echo %s; fi\n' \
      "$commit" "$marker" "$version" > "$out/bundle/bin/specstone"
    chmod 755 "$out/bundle/bin/specstone"
    ;;
  *)
    echo "dart stub: unexpected call: $*" >&2
    exit 2
    ;;
esac
''';
