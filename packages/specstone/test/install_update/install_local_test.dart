@TestOn('!windows')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/git_repo.dart' show git;
import '../helpers/install_local_repo.dart';

const _fr =
    'install_update/machine_install/install_local_build/'
    'build_and_place_branch';
const _story = 'install_update/machine_install/install_local_build';

void main() {
  late String tool;
  late InstallLocalRepo repo;
  late Map<String, String> before;

  setUpAll(() async => tool = await compileInstallLocal());

  setUp(() async {
    repo = await createInstallLocalRepo();
    repo.sandbox.installFake();
    before = repo.sandbox.snapshot();
  });

  // A refusal changes nothing: the install, the worktree list, and the temp
  // folder are as they were, and no build step ran.
  void expectNothingChanged() {
    expect(repo.sandbox.snapshot(), before);
    expect(repo.worktrees(), hasLength(1));
    expect(repo.sandbox.logOf('dart'), isEmpty);
    expect(repo.tmpIsEmpty, isTrue);
  }

  // A failed or interrupted build leaves the install, the worktree list, and
  // the temp folder as they were.
  void expectBuildLeftNothing() {
    expect(repo.sandbox.snapshot(), before);
    expect(repo.worktrees(), hasLength(1));
    expect(repo.tmpIsEmpty, isTrue);
  }

  // The tool deletes the bundle with its temp folder, so the stub copies the
  // binary it builds to the logs folder, where a test reads it.
  File keepBundleBinary() {
    final stubs = repo.sandbox.stubs.path;
    File('$stubs/dart').renameSync('$stubs/dart_original');
    repo.sandbox.stub('dart', r'''
"$(dirname "$0")/dart_original" "$@" || exit $?
if [ "$1 $2" = 'build cli' ]; then
  while [ $# -gt 0 ]; do
    if [ "$1" = -o ]; then out=$2; fi
    shift
  done
  cp "$out/bundle/bin/specstone" "$STUB_LOG_DIR/bundle_specstone"
fi''');
    return File('${repo.sandbox.logs.path}/bundle_specstone');
  }

  Future<void> waitFor(bool Function() isDone) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!isDone()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out after 30 s');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  // Makes `git worktree remove` fail, and `git worktree prune` fail under
  // `STUB_GIT_PRUNE=fail`; every other `git` call goes to the logging stub.
  void failWorktreeRemove() {
    final stubs = repo.sandbox.stubs.path;
    File('$stubs/git').renameSync('$stubs/git_original');
    repo.sandbox.stub('git', r'''
case "$1 $2" in
  'worktree remove')
    echo 'stub: git worktree remove failed' >&2
    exit 1
    ;;
  'worktree prune')
    if [ "$STUB_GIT_PRUNE" = fail ]; then
      echo 'stub: git worktree prune failed' >&2
      exit 1
    fi
    ;;
esac
exec "$(dirname "$0")/git_original" "$@"''');
  }

  // Runs the tool and kills it after 30 s, so a tool that never exits fails
  // the test instead of hanging it.
  Future<({int exitCode, String stderr})> runBounded({
    Map<String, String> env = const {},
  }) async {
    final process = await repo.start(tool, env: env);
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    final errors = StringBuffer();
    final done = Future.wait([
      process.stdout.drain<void>(),
      process.stderr.transform(utf8.decoder).forEach(errors.write),
    ]);
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () => fail('the tool did not exit within 30 s'),
    );
    await done;
    return (exitCode: exitCode, stderr: '$errors');
  }

  // Sends SIGINT to the tool while its build waits, lets the build end once
  // the tool says it saw the signal, and returns how the tool ended.
  Future<({int exitCode, String stderr})> interruptDuringBuild() async {
    final release = File('${repo.sandbox.logs.path}/release');
    final process = await repo.start(tool, env: {'STUB_DART_BUILD': 'wait'});
    // Frees the stub's wait loop and the tool whichever way the test ends.
    addTearDown(() {
      if (!release.existsSync()) release.createSync();
      process.kill(ProcessSignal.sigkill);
    });
    final errors = StringBuffer();
    final done = Future.wait([
      process.stdout.drain<void>(),
      process.stderr.transform(utf8.decoder).forEach(errors.write),
    ]);

    await waitFor(File('${repo.sandbox.logs.path}/building').existsSync);
    expect(repo.tmpIsEmpty, isFalse);
    expect(repo.worktrees(), hasLength(2));
    process.kill(ProcessSignal.sigint);
    await waitFor(() => '$errors'.contains('interrupted; cleaning up'));
    release.createSync();

    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
    );
    await done;
    return (exitCode: exitCode, stderr: '$errors');
  }

  test(
    '$_fr E01: an unknown ref is refused by name before any worktree exists',
    () async {
      final result = await repo.run(tool, args: ['--branch', 'nope']);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('nope'));
      expectNothingChanged();
    },
  );

  test('$_fr E01: a dash-led ref is refused before git runs', () async {
    for (final ref in ['-x', '--upload-pack=x']) {
      final result = await repo.run(tool, args: ['--branch', ref]);

      expect(result.exitCode, isNot(0), reason: ref);
      expect(result.stderr, contains(ref), reason: ref);
      expect(repo.sandbox.logOf('git'), isEmpty, reason: ref);
      expectNothingChanged();
    }
  });

  test('$_fr design R6: an argument list the tool does not take exits 1 '
      'before any git call', () async {
    for (final args in [
      ['--force'],
      ['--branch'],
      ['develop'],
      ['--branch', 'develop', 'extra'],
    ]) {
      final result = await repo.run(tool, args: args);

      expect(result.exitCode, 1, reason: '$args');
      expect(repo.sandbox.logOf('git'), isEmpty, reason: '$args');
      expectNothingChanged();
    }
  });

  test(
    '$_fr E01: a git failure other than a missing ref keeps its own error',
    () async {
      final plain = await Directory('${repo.sandbox.root.path}/plain').create();

      final result = await Process.run(
        tool,
        const [],
        workingDirectory: plain.path,
        environment: repo.sandbox.env(),
        includeParentEnvironment: false,
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('not a git repository'));
      expect(result.stderr, isNot(contains('branch not found')));
      expectNothingChanged();
    },
  );

  test('$_story S5: checkoutState() is equal across a refused ref', () async {
    File('${repo.work.path}/marker.txt').writeAsStringSync('changed\n');
    File('${repo.work.path}/untracked.txt').writeAsStringSync('new\n');
    final stateBefore = await repo.checkoutState();

    final result = await repo.run(tool, args: ['--branch', 'nope']);

    expect(result.exitCode, isNot(0));
    expect(await repo.checkoutState(), stateBefore);
  });

  test("$_fr statement: both build steps run in a temp worktree on the ref's "
      'commit, which then goes', () async {
    final bundleBinary = keepBundleBinary();
    final commit = repo.sha('develop');
    final tmp = Directory('${repo.sandbox.root.path}/tmp')
        .resolveSymbolicLinksSync();

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final steps = [
      for (final line in repo.sandbox.logOf('dart'))
        (
          dir: line.substring(0, line.indexOf('|')),
          args: line.substring(line.indexOf('|') + 1),
        ),
    ];
    expect(steps, hasLength(2));
    final worktree = RegExp('^${RegExp.escape(tmp)}/([^/]+)/worktree\$')
        .firstMatch(steps[0].dir);
    expect(worktree, isNotNull, reason: steps[0].dir);
    final temp = '${repo.sandbox.root.path}/tmp/${worktree![1]}';
    expect(steps[0].args, 'pub get --enforce-lockfile');
    expect(steps[1].dir, '${steps[0].dir}/packages/specstone');
    expect(steps[1].args, 'build cli -t bin/specstone.dart -o $temp/build');
    expect(
      repo.sandbox.logOf('git'),
      containsAllInOrder([
        'worktree add --detach $temp/worktree $commit',
        'worktree remove --force $temp/worktree',
      ]),
    );
    expect(bundleBinary.readAsLinesSync()[1], '# $commit develop');
    expect(repo.worktrees(), hasLength(1));
    expect(repo.tmpIsEmpty, isTrue);
  });

  test('$_story S3, $_fr E03: checkoutState() is equal across a run, and the '
      'bundle holds the committed marker.txt', () async {
    final bundleBinary = keepBundleBinary();
    File('${repo.work.path}/marker.txt').writeAsStringSync('changed\n');
    File('${repo.work.path}/fixture_version.txt').writeAsStringSync('9.9.9\n');
    git(repo.work, ['add', 'fixture_version.txt']);
    File('${repo.work.path}/untracked.txt').writeAsStringSync('new\n');
    final stateBefore = await repo.checkoutState();

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(await repo.checkoutState(), stateBefore);
    expect(
      bundleBinary.readAsLinesSync()[1],
      '# ${repo.sha('develop')} develop',
    );
    final version = await Process.run(bundleBinary.path, ['--version']);
    expect((version.stdout as String).trim(), '0.9.0');
  });

  for (final (step, mode) in [
    ('pub get', 'STUB_DART_PUB'),
    ('build cli', 'STUB_DART_BUILD'),
  ]) {
    test('$_fr E04: a failing $step is named and snapshot() keeps every '
        'entry', () async {
      final result = await repo.run(tool, env: {mode: 'fail'});

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('dart $step'));
      expect(result.stderr, contains('stub: dart $step failed'));
      expect(repo.sandbox.logOf('dart'), hasLength(step == 'pub get' ? 1 : 2));
      expectBuildLeftNothing();
    });
  }

  test('$_fr statement: Ctrl-C during the build leaves no worktree and the '
      'same snapshot()', () async {
    final result = await interruptDuringBuild();

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('interrupted; the install is unchanged'));
    expectBuildLeftNothing();
  });

  test('$_fr statement: Ctrl-C that also fails the build step is reported as '
      'an interrupt', () async {
    // The real child gets the same Ctrl-C and dies: the step fails.
    repo.sandbox.stub('dart', r'''
if [ "$1" = build ]; then
  touch "$STUB_LOG_DIR/building"
  while [ ! -e "$STUB_LOG_DIR/release" ]; do sleep 0.1; done
  echo 'stub: dart build cli killed' >&2
  exit 130
fi''');

    final result = await interruptDuringBuild();

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('interrupted; the install is unchanged'));
    expect(result.stderr, isNot(contains('dart build cli failed')));
    expectBuildLeftNothing();
  });

  test('$_fr statement: a worktree that will not go is reported and the tool '
      'exits', () async {
    failWorktreeRemove();

    final result = await runBounded();

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('git worktree remove'));
    expect(result.stderr, contains('stub: git worktree remove failed'));
    expect(repo.worktrees(), hasLength(1));
    expect(repo.tmpIsEmpty, isTrue);
  });

  test('$_fr statement: a failing prune joins the removal failure', () async {
    failWorktreeRemove();

    final result = await runBounded(env: {'STUB_GIT_PRUNE': 'fail'});

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('stub: git worktree remove failed'));
    expect(result.stderr, contains('stub: git worktree prune failed'));
    expect(repo.tmpIsEmpty, isTrue);
  });

  test('$_fr E04: a failing build step stays the reported refusal when the '
      'worktree will not go either', () async {
    failWorktreeRemove();

    final result = await runBounded(env: {'STUB_DART_BUILD': 'fail'});

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('dart build cli failed'));
    expect(result.stderr, contains('stub: dart build cli failed'));
    expect(result.stderr, contains('stub: git worktree remove failed'));
    expect(repo.worktrees(), hasLength(1));
    expect(repo.tmpIsEmpty, isTrue);
  });
}
