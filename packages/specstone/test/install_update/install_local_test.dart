@TestOn('!windows')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/git_repo.dart' show commitAll, git;
import '../helpers/install_local_repo.dart';

const _fr =
    'install_update/machine_install/install_local_build/'
    'build_and_place_branch';
const _story = 'install_update/machine_install/install_local_build';
const _unchangedText = 'the install is unchanged';

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

  String installDir() => '${repo.sandbox.home.path}/.specstone';

  // The names directly under the install folder.
  List<String> installEntries() => [
    for (final entry in Directory(installDir()).listSync())
      entry.path.substring(installDir().length + 1),
  ];

  // A refusal changes nothing: the install, the worktree list, and the temp
  // folder are as they were, and no build step ran.
  void expectNothingChanged() {
    expect(repo.sandbox.snapshot(), before);
    expect(repo.worktrees(), hasLength(1));
    expect(repo.sandbox.logOf('dart'), isEmpty);
    expect(repo.tmpIsEmpty, isTrue);
  }

  // A failed or interrupted build leaves the install, the worktree list, and
  // the temp folder as they were, and no aside copy beside the install.
  void expectBuildLeftNothing() {
    expect(repo.sandbox.snapshot(), before);
    expect(installEntries(), unorderedEquals(['bin', 'lib']));
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

  // Makes the first `git worktree remove` fail, and the second one too under
  // `STUB_GIT_REMOVE_AGAIN=fail`; every other `git` call goes to the logging
  // stub.
  void failWorktreeRemove() {
    final stubs = repo.sandbox.stubs.path;
    File('$stubs/git').renameSync('$stubs/git_original');
    repo.sandbox.stub('git', r'''
if [ "$1 $2" = 'worktree remove' ]; then
  if [ ! -e "$STUB_LOG_DIR/first_remove" ]; then
    touch "$STUB_LOG_DIR/first_remove"
    echo 'stub: git worktree remove failed' >&2
    exit 1
  fi
  if [ "$STUB_GIT_REMOVE_AGAIN" = fail ]; then
    echo 'stub: second git worktree remove failed' >&2
    exit 1
  fi
fi
exec "$(dirname "$0")/git_original" "$@"''');
  }

  // Runs the tool and kills it after 30 s, so a tool that never exits fails
  // the test instead of hanging it.
  Future<({int exitCode, String stdout, String stderr})> runBounded({
    Map<String, String> env = const {},
  }) async {
    final process = await repo.start(tool, env: env);
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    final output = StringBuffer();
    final errors = StringBuffer();
    final done = Future.wait([
      process.stdout.transform(utf8.decoder).forEach(output.write),
      process.stderr.transform(utf8.decoder).forEach(errors.write),
    ]);
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () => fail('the tool did not exit within 30 s'),
    );
    await done;
    return (exitCode: exitCode, stdout: '$output', stderr: '$errors');
  }

  // Sends [signal] to the tool once a stub has created `<logs>/<marker>` and
  // waits for `<logs>/release`, lets that stub go once the tool says it saw the
  // signal (unless [releases] is false), and returns how the tool ended.
  Future<({int exitCode, String stdout, String stderr})> interruptAt(
    String marker,
    Map<String, String> env, {
    ProcessSignal signal = ProcessSignal.sigint,
    bool releases = true,
  }) async {
    final release = File('${repo.sandbox.logs.path}/release');
    final process = await repo.start(tool, env: env);
    // Frees the stub's wait loop and the tool whichever way the test ends.
    addTearDown(() {
      if (!release.existsSync()) release.createSync();
      process.kill(ProcessSignal.sigkill);
    });
    final output = StringBuffer();
    final errors = StringBuffer();
    final done = Future.wait([
      process.stdout.transform(utf8.decoder).forEach(output.write),
      process.stderr.transform(utf8.decoder).forEach(errors.write),
    ]);

    await waitFor(File('${repo.sandbox.logs.path}/$marker').existsSync);
    expect(repo.tmpIsEmpty, isFalse);
    expect(repo.worktrees(), hasLength(2));
    process.kill(signal);
    await waitFor(() => '$errors'.contains('interrupted; cleaning up'));
    if (releases) release.createSync();

    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
    );
    await done;
    return (exitCode: exitCode, stdout: '$output', stderr: '$errors');
  }

  // Sends SIGINT to the tool while its build waits; the build stub ignores
  // the signal the tool passes on when [stubIgnoresSignals] is true.
  Future<({int exitCode, String stdout, String stderr})> interruptDuringBuild({
    bool stubIgnoresSignals = false,
  }) => interruptAt('building', {
    'STUB_DART_BUILD': 'wait',
    if (stubIgnoresSignals) 'STUB_DART_IGNORE': 'signals',
  });

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

  test('$_fr E01: a range or a negated ref is refused by name, not taken as a '
      'commit', () async {
    for (final ref in ['develop..HEAD', '^develop']) {
      final result = await repo.run(tool, args: ['--branch', ref]);

      expect(result.exitCode, 1, reason: ref);
      expect(result.stderr, contains('branch not found: $ref'), reason: ref);
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
    final temp = '$tmp/${worktree![1]}';
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

  test('$_story S3, $_fr E03: a dirty checkout on develop is equal across a '
      'run of another branch', () async {
    final bundleBinary = keepBundleBinary();
    File('${repo.work.path}/marker.txt').writeAsStringSync('changed\n');
    File('${repo.work.path}/staged.txt').writeAsStringSync('staged\n');
    git(repo.work, ['add', 'staged.txt']);
    File('${repo.work.path}/untracked.txt').writeAsStringSync('new\n');
    final stateBefore = await repo.checkoutState();

    final result = await repo.run(tool, args: ['--branch', 'feature/example']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(await repo.checkoutState(), stateBefore);
    expect(
      bundleBinary.readAsLinesSync()[1],
      '# ${repo.sha('feature/example')} feature',
    );
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

  test('$_fr statement: Ctrl-C during a build that ignores it leaves no '
      'worktree and the same snapshot()', () async {
    final result = await interruptDuringBuild(stubIgnoresSignals: true);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('interrupted; the install is unchanged'));
    expect(repo.sandbox.logOf('dart'), hasLength(2));
    expectBuildLeftNothing();
  });

  test('$_fr statement: Ctrl-C passes to the build step; the step failure it '
      'causes is printed beside the interrupt', () async {
    // A shell waiting on `sleep` lets SIGINT pass unless it traps it.
    repo.sandbox.stub('dart', r'''
if [ "$1" = build ]; then
  trap 'echo "stub: dart build cli stopped" >&2; exit 130' INT
  touch "$STUB_LOG_DIR/building"
  while [ ! -e "$STUB_LOG_DIR/release" ]; do sleep 0.1; done
fi''');

    final result = await interruptDuringBuild();

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('interrupted; the install is unchanged'));
    expect(result.stderr, contains('dart build cli failed'));
    expect(result.stderr, contains('stub: dart build cli stopped'));
    expectBuildLeftNothing();
  });

  for (final (name, signal) in [
    ('SIGTERM', ProcessSignal.sigterm),
    ('SIGHUP', ProcessSignal.sighup),
  ]) {
    test('$_fr statement: $name during the build stops the build step, '
        'removes the worktree, and keeps the install', () async {
      final result = await interruptAt(
        'building',
        {'STUB_DART_BUILD': 'wait'},
        signal: signal,
        releases: false,
      );

      expect(result.exitCode, 1);
      expect(result.stderr, contains('interrupted; the install is unchanged'));
      expect(result.stderr, contains('dart build cli failed'));
      expectBuildLeftNothing();
    });
  }

  test('$_fr statement: SIGTERM during a build that ignores it ends after the '
      'step, with no install', () async {
    final result = await interruptAt('building', {
      'STUB_DART_BUILD': 'wait',
      'STUB_DART_IGNORE': 'signals',
    }, signal: ProcessSignal.sigterm);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('interrupted; the install is unchanged'));
    expectBuildLeftNothing();
  });

  test('$_fr statement: SIGHUP with stderr closed still removes the worktree '
      'and exits 1', () async {
    final release = File('${repo.sandbox.logs.path}/release');
    final process = await repo.start(tool, env: {'STUB_DART_BUILD': 'wait'});
    addTearDown(() {
      if (!release.existsSync()) release.createSync();
      process.kill(ProcessSignal.sigkill);
    });
    final output = process.stdout.drain<void>();
    final errors = process.stderr.listen((_) {});
    await waitFor(File('${repo.sandbox.logs.path}/building').existsSync);

    // Nobody reads the tool's stderr any more, as after a closed terminal.
    await errors.cancel();
    process.kill(ProcessSignal.sighup);

    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
    );
    await output;
    expect(exitCode, 1);
    expectBuildLeftNothing();
  });

  test('$_fr statement: a worktree that will not go is reported, removed by a '
      'second removal once its folder is gone, and the tool exits', () async {
    failWorktreeRemove();

    final result = await runBounded();

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('git worktree remove'));
    expect(result.stderr, contains('stub: git worktree remove failed'));
    expect(
      repo.sandbox.logOf('git'),
      anyElement(startsWith('worktree remove --force ')),
    );
    expect(
      repo.sandbox.logOf('git'),
      isNot(anyElement(startsWith('worktree prune'))),
    );
    expect(repo.worktrees(), hasLength(1));
    expect(repo.tmpIsEmpty, isTrue);
  });

  test(
    '$_fr statement: a failing second removal joins the first failure',
    () async {
      failWorktreeRemove();

      final result = await runBounded(env: {'STUB_GIT_REMOVE_AGAIN': 'fail'});

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('stub: git worktree remove failed'));
      expect(
        result.stderr,
        contains('stub: second git worktree remove failed'),
      );
      expect(repo.tmpIsEmpty, isTrue);
    },
  );

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

  String installLine(String ref, String shortCommit) =>
      'installed specstone 0.9.0 ($ref @ $shortCommit) in ${installDir()}/bin\n';

  // The second line of the placed binary: the stub's `# <commit> <marker>`.
  String placedMark() =>
      File('${installDir()}/bin/specstone').readAsLinesSync()[1];

  File buildTxt() => File('${installDir()}/lib/build.txt');

  Map<String, String> binEntries(Map<String, String> snapshot) => {
    for (final MapEntry(:key, :value) in snapshot.entries)
      if (key.startsWith('.specstone/bin/')) key: value,
  };

  // Makes `cp` or `mv` fail when its arguments name [aside]; any other call
  // goes to the real tool.
  void failOn(String tool, String aside) => repo.sandbox.stub(
    tool,
    'case "\$*" in\n'
    '  *$aside*) echo "stub: $tool failed" >&2; exit 1 ;;\n'
    'esac\n'
    'exec /bin/$tool "\$@"',
  );

  test('$_story S1: no ref installs develop and prints one line', () async {
    Directory(installDir()).deleteSync(recursive: true);
    final started = DateTime.now().toUtc();

    final result = await repo.run(tool);

    final finished = DateTime.now().toUtc();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, installLine('develop', repo.shortSha('develop')));
    expect(result.stderr, isEmpty);
    final version = await Process.run('${installDir()}/bin/specstone', [
      '--version',
    ]);
    expect(version.stdout, '0.9.0\n');
    expect(placedMark(), '# ${repo.sha('develop')} develop');
    final record = buildTxt().readAsLinesSync();
    expect(record, hasLength(3));
    expect(record[0], 'ref: develop');
    expect(record[1], 'commit: ${repo.sha('develop')}');
    expect(record[2], startsWith('built: '));
    final built = DateTime.parse(record[2].substring('built: '.length));
    expect(built.isUtc, isTrue);
    expect(built.isAfter(started.subtract(const Duration(seconds: 1))), isTrue);
    expect(built.isBefore(finished.add(const Duration(seconds: 1))), isTrue);
    expect(File('${installDir()}/lib/libsqlite3.so').existsSync(), isTrue);
    expect(installEntries(), unorderedEquals(['bin', 'lib']));
  });

  test('$_story S2: --branch feature/example installs that branch', () async {
    final result = await repo.run(tool, args: ['--branch', 'feature/example']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout,
      installLine('feature/example', repo.shortSha('feature/example')),
    );
    expect(placedMark(), '# ${repo.sha('feature/example')} feature');
    expect(buildTxt().readAsLinesSync().first, 'ref: feature/example');
  });

  test('$_fr input_output: a tag or a full commit installs and the line names '
      'it as given', () async {
    git(repo.work, ['tag', 'v0.9.0', 'feature/example']);
    git(repo.work, ['tag', '-a', 'v1.0.0', '-m', 'annotated', 'develop']);

    final tagged = await repo.run(tool, args: ['--branch', 'v0.9.0']);

    expect(tagged.exitCode, 0, reason: '${tagged.stderr}');
    expect(
      tagged.stdout,
      installLine('v0.9.0', repo.shortSha('feature/example')),
    );
    expect(placedMark(), '# ${repo.sha('feature/example')} feature');

    final annotated = await repo.run(tool, args: ['--branch', 'v1.0.0']);

    expect(annotated.exitCode, 0, reason: '${annotated.stderr}');
    expect(annotated.stdout, installLine('v1.0.0', repo.shortSha('develop')));
    expect(placedMark(), '# ${repo.sha('develop')} develop');
    expect(buildTxt().readAsLinesSync().first, 'ref: v1.0.0');

    final commit = repo.sha('develop');
    final full = await repo.run(tool, args: ['--branch', commit]);

    expect(full.exitCode, 0, reason: '${full.stderr}');
    expect(full.stdout, installLine(commit, repo.shortSha('develop')));
    expect(placedMark(), '# $commit develop');
    expect(buildTxt().readAsLinesSync().first, 'ref: $commit');
  });

  for (final folder in ['lib', 'bin']) {
    test('$_fr E05: a $folder copy that fails keeps snapshot()', () async {
      failOn('cp', '.$folder.new');

      final result = await repo.run(tool);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('${installDir()}/$folder'));
      expect(result.stderr, contains('stub: cp failed'));
      expect(repo.sandbox.snapshot(), before);
      expect(installEntries(), unorderedEquals(['bin', 'lib']));
      expect(repo.worktrees(), hasLength(1));
      expect(repo.tmpIsEmpty, isTrue);
    });
  }

  test('$_fr E06: a failed lib move leaves the old bin', () async {
    failOn('mv', '.lib.new');

    final result = await repo.run(tool);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('${installDir()}/lib'));
    expect(result.stderr, contains('stub: mv failed'));
    expect(binEntries(before), isNotEmpty);
    expect(binEntries(repo.sandbox.snapshot()), binEntries(before));
    expect(installEntries(), unorderedEquals(['bin']));
  });

  test('$_fr E06: a failed bin move is named', () async {
    failOn('mv', '.bin.new');

    final result = await repo.run(tool);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('${installDir()}/bin'));
    expect(result.stderr, contains('stub: mv failed'));
    expect(installEntries(), unorderedEquals(['lib']));
  });

  test('$_fr E07: packs stay', () async {
    File('${installDir()}/packs/mine.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('mine');
    final packed = repo.sandbox.snapshot();

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final after = repo.sandbox.snapshot();
    expect(after['.specstone/packs/mine.md'], 'mine');
    final changed = {
      ...packed.keys,
      ...after.keys,
    }.where((key) => packed[key] != after[key]);
    expect(changed, isNotEmpty);
    expect(
      changed,
      everyElement(
        anyOf(startsWith('.specstone/lib/'), startsWith('.specstone/bin/')),
      ),
    );
  });

  test('$_fr E08: installFake at 0.9.0 is replaced by the build', () async {
    repo.sandbox.installFake(version: '0.9.0');

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(placedMark(), '# ${repo.sha('develop')} develop');
    expect(buildTxt().existsSync(), isTrue);
    expect(File('${installDir()}/lib/libold.so').existsSync(), isFalse);
  });

  test('$_fr input_output: a stale .lib.new and .bin.new from a killed run '
      'are not nested', () async {
    File('${installDir()}/.lib.new/stale.so')
      ..createSync(recursive: true)
      ..writeAsStringSync('stale');
    File('${installDir()}/.bin.new').writeAsStringSync('stale');

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(placedMark(), '# ${repo.sha('develop')} develop');
    expect(File('${installDir()}/lib/stale.so').existsSync(), isFalse);
    expect(Directory('${installDir()}/lib/lib').existsSync(), isFalse);
    expect(Directory('${installDir()}/bin/bin').existsSync(), isFalse);
    expect(installEntries(), unorderedEquals(['bin', 'lib']));
  });

  test('$_fr input_output: a stale .bin.new folder is not nested', () async {
    File('${installDir()}/.bin.new/stale')
      ..createSync(recursive: true)
      ..writeAsStringSync('stale');

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(placedMark(), '# ${repo.sha('develop')} develop');
    expect(Directory('${installDir()}/bin/bin').existsSync(), isFalse);
    expect(File('${installDir()}/bin/stale').existsSync(), isFalse);
    expect(installEntries(), unorderedEquals(['bin', 'lib']));
  });

  test('$_story S2, $_fr E14: the placed shim is executable and holds the '
      'marker of the branch', () async {
    final result = await repo.run(tool, args: ['--branch', 'feature/example']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final shim = File('${installDir()}/bin/stn');
    expect(shim.existsSync(), isTrue);
    expect(shim.readAsLinesSync()[1], '# shim feature');
    // The three execute bits of the mode, as the committed shim has them.
    expect(shim.statSync().mode & 0x49, 0x49);
  });

  test('$_story S1, $_fr E14: no ref places the develop shim', () async {
    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final shim = File('${installDir()}/bin/stn');
    expect(shim.existsSync(), isTrue);
    expect(shim.readAsLinesSync()[1], '# shim develop');
  });

  test('$_story S3, $_fr E14: the placed shim is the committed one, not an '
      'uncommitted edit', () async {
    File('${repo.work.path}/$shimPath')
        .writeAsStringSync('#!/bin/sh\n# shim dirty\n');
    final stateBefore = await repo.checkoutState();

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(await repo.checkoutState(), stateBefore);
    expect(
      File('${installDir()}/bin/stn').readAsLinesSync()[1],
      '# shim develop',
    );
  });

  test(
    '$_fr E14: a commit holding shim/windows places only stn in bin',
    () async {
      final shimDir = '${repo.work.path}/packages/specstone/shim/windows';
      Directory(shimDir).createSync(recursive: true);
      File('$shimDir/stn.c').writeAsStringSync('/* placeholder */\n');
      File('$shimDir/build.ps1').writeAsStringSync('# placeholder\n');
      File('$shimDir/stn.exe').writeAsStringSync('placeholder\n');
      commitAll(repo.work, 'add the Windows shim sources');

      final result = await repo.run(tool);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final bin = '${installDir()}/bin';
      final stn = File('$bin/stn');
      expect(stn.existsSync(), isTrue);
      expect(stn.statSync().mode & 0x49, 0x49);
      final names = [
        for (final entry in Directory(bin).listSync())
          entry.path.substring(bin.length + 1),
      ];
      expect(names, unorderedEquals(['specstone', 'stn']));
    },
  );

  test('$_fr E05: a shim copy that fails keeps snapshot()', () async {
    failOn('cp', '.bin.new/stn');

    final result = await repo.run(tool);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('stub: cp failed'));
    expect(repo.sandbox.snapshot(), before);
    expect(installEntries(), unorderedEquals(['bin', 'lib']));
    expect(repo.worktrees(), hasLength(1));
    expect(repo.tmpIsEmpty, isTrue);
  });

  test('Owner ruling 2026-11-13: a commit with no shim is refused, nothing is '
      'placed, and no worktree remains', () async {
    git(repo.work, ['checkout', '-q', '-b', 'old']);
    git(repo.work, ['rm', '-q', shimPath]);
    commitAll(repo.work, 'before the shim');
    git(repo.work, ['checkout', '-q', 'develop']);

    final result = await repo.run(tool, args: ['--branch', 'old']);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('old'));
    expect(result.stderr, contains(shimPath));
    expect(result.stderr, contains(_unchangedText));
    expectNothingChanged();
  });

  test('$_fr E10: build.txt goes with lib/ under install.sh at 0.9.1 and '
      'uninstall.sh, and stays under install.sh at 0.9.0', () async {
    final sandbox = repo.sandbox;
    final archiveEnv = {'SPECSTONE_ARCHIVE_DIR': sandbox.archives.path};
    expect((await repo.run(tool)).exitCode, 0);
    expect(buildTxt().existsSync(), isTrue);

    await sandbox.writeArchive('linux-x64', version: '0.9.1');
    final upgraded = await sandbox.run('install.sh', extra: archiveEnv);

    expect(upgraded.exitCode, 0, reason: '${upgraded.stderr}');
    expect(buildTxt().existsSync(), isFalse);

    expect((await repo.run(tool)).exitCode, 0);
    await sandbox.writeArchive('linux-x64', version: '0.9.0');
    final same = await sandbox.run('install.sh', extra: archiveEnv);

    expect(same.exitCode, 0, reason: '${same.stderr}');
    expect(buildTxt().existsSync(), isTrue);
    expect(placedMark(), '# ${repo.sha('develop')} develop');

    final removed = await sandbox.run('uninstall.sh');

    expect(removed.exitCode, 0, reason: '${removed.stderr}');
    expect(Directory('${installDir()}/lib').existsSync(), isFalse);
  });

  for (final (label, env, unset) in [
    ('HOME unset', <String, String>{}, ['HOME']),
    ('HOME and USERPROFILE empty', {'HOME': '', 'USERPROFILE': ''}, <String>[]),
    ('HOME is not an absolute path', {'HOME': 'rel/home'}, <String>[]),
  ]) {
    test(
      '$_fr design R6: no home exits 1 before any worktree, $label',
      () async {
        final result = await repo.run(tool, env: env, unset: unset);

        expect(result.exitCode, 1);
        expect(result.stderr, contains('HOME'));
        expect(repo.sandbox.logOf('dart'), isEmpty);
        expect(
          repo.sandbox.logOf('git'),
          isNot(anyElement(startsWith('worktree'))),
        );
        expect(repo.sandbox.snapshot(), before);
        expect(repo.worktrees(), hasLength(1));
        expect(repo.tmpIsEmpty, isTrue);
      },
    );
  }

  test(
    '$_fr input_output: with HOME unset, USERPROFILE names the home',
    () async {
      final result = await repo.run(
        tool,
        env: {'USERPROFILE': repo.sandbox.home.path},
        unset: ['HOME'],
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('in ${installDir()}/bin\n'));
      expect(buildTxt().existsSync(), isTrue);
    },
  );

  test('$_fr statement: Ctrl-C to the tool between the moves lets them end '
      'and the install completes', () async {
    repo.sandbox.stub('mv', r'''
touch "$STUB_LOG_DIR/moving"
while [ ! -e "$STUB_LOG_DIR/release" ]; do sleep 0.1; done
exec /bin/mv "$@"''');

    final result = await interruptAt('moving', const {});

    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, installLine('develop', repo.shortSha('develop')));
    expect(result.stderr, isNot(contains('unchanged')));
    expect(placedMark(), '# ${repo.sha('develop')} develop');
    expect(repo.worktrees(), hasLength(1));
    expect(repo.tmpIsEmpty, isTrue);
  });

  test('$_fr statement: a worktree that will not go after a good build says '
      'the install is in place', () async {
    failWorktreeRemove();

    final result = await runBounded();

    expect(result.exitCode, 1);
    expect(result.stdout, installLine('develop', repo.shortSha('develop')));
    expect(result.stderr, contains('the install is in place, but'));
    expect(result.stderr, contains('stub: git worktree remove failed'));
    expect(placedMark(), '# ${repo.sha('develop')} develop');
    expect(buildTxt().existsSync(), isTrue);
  });

  test('$_fr statement: a temp folder that is already gone is reported and '
      'the failing step stays the first refusal', () async {
    final stubs = repo.sandbox.stubs.path;
    File('$stubs/git').renameSync('$stubs/git_original');
    // A removal that also deletes the temp folder, so the tool's own delete of
    // it fails without any file permission trick.
    repo.sandbox.stub('git', r'''
if [ "$1 $2" = 'worktree remove' ]; then
  "$(dirname "$0")/git_original" "$@" || exit $?
  rm -rf "$(dirname "$4")"
  exit 0
fi
exec "$(dirname "$0")/git_original" "$@"''');

    final result = await runBounded(env: {'STUB_DART_BUILD': 'fail'});

    expect(result.exitCode, 1);
    expect(result.stderr, contains('dart build cli failed'));
    expect(result.stderr, contains('could not remove'));
    expect(repo.worktrees(), hasLength(1));
    expect(repo.tmpIsEmpty, isTrue);
  });

  test('$_fr E04: a temp folder that cannot be made is refused, not a crash, '
      'and nothing changes', () async {
    final missing = '${repo.sandbox.root.path}/no such tmp';

    final result = await runBounded(env: {'TMPDIR': missing});

    expect(result.exitCode, 1);
    expect(result.stderr, startsWith('install_local: '));
    expect(result.stderr, contains(_unchangedText));
    expect(result.stderr, isNot(contains('#0')));
    expect(result.stdout, isEmpty);
    expect(repo.sandbox.snapshot(), before);
    expect(repo.worktrees(), hasLength(1));
    expect(repo.sandbox.logOf('dart'), isEmpty);
  });

  test('$_fr E05: a .specstone that is a file fails the placement and '
      'nothing changes', () async {
    Directory(installDir()).deleteSync(recursive: true);
    File(installDir()).writeAsStringSync('not a folder');
    final untouched = repo.sandbox.snapshot();

    final result = await repo.run(tool);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('could not place ${installDir()}'));
    expect(result.stderr, contains(_unchangedText));
    expect(repo.sandbox.snapshot(), untouched);
    expect(repo.worktrees(), hasLength(1));
    expect(repo.tmpIsEmpty, isTrue);
  });

  test('$_fr E04: a missing dart is refused naming the step and nothing '
      'changes', () async {
    File('${repo.sandbox.stubs.path}/dart').deleteSync();

    final result = await repo.run(tool);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('dart pub get failed'));
    expectNothingChanged();
  });

  test(
    '$_fr input_output: a home and a temp folder with a space install',
    () async {
      final root = repo.sandbox.root.path;
      final spacedTmp = await Directory('$root/my tmp').create();
      final spacedHome = '$root/my home';

      final result = await repo.run(
        tool,
        env: {'HOME': spacedHome, 'TMPDIR': spacedTmp.path},
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('in $spacedHome/.specstone/bin\n'));
      expect(
        File('$spacedHome/.specstone/bin/specstone').readAsLinesSync()[1],
        '# ${repo.sha('develop')} develop',
      );
      expect(File('$spacedHome/.specstone/lib/build.txt').existsSync(), isTrue);
      expect(spacedTmp.listSync(), isEmpty);
      expect(repo.worktrees(), hasLength(1));
    },
  );

  test('$_fr statement: a closed stdout after the placement still ends with '
      'exit 0 and a removed worktree', () async {
    repo.sandbox.stub('mv', r'''
touch "$STUB_LOG_DIR/moving"
while [ ! -e "$STUB_LOG_DIR/release" ]; do sleep 0.1; done
exec /bin/mv "$@"''');
    final release = File('${repo.sandbox.logs.path}/release');
    final process = await repo.start(tool);
    addTearDown(() {
      if (!release.existsSync()) release.createSync();
      process.kill(ProcessSignal.sigkill);
    });
    final errors = process.stderr.drain<void>();
    final output = process.stdout.listen((_) {});
    await waitFor(File('${repo.sandbox.logs.path}/moving').existsSync);

    // Nobody reads the install line any more, as after a closed terminal.
    await output.cancel();
    release.createSync();

    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
    );
    await errors;
    expect(exitCode, 0);
    expect(placedMark(), '# ${repo.sha('develop')} develop');
    expect(repo.worktrees(), hasLength(1));
    expect(repo.tmpIsEmpty, isTrue);
  });

  test('$_fr E03: a relative TMPDIR is refused before any worktree and the '
      'checkout stays as it was', () async {
    Directory('${repo.work.path}/rel/tmp').createSync(recursive: true);
    final stateBefore = await repo.checkoutState();

    final result = await runBounded(env: {'TMPDIR': 'rel/tmp'});

    expect(result.exitCode, 1);
    expect(result.stderr, contains('not an absolute path'));
    expect(result.stderr, contains(_unchangedText));
    expect(await repo.checkoutState(), stateBefore);
    expect(Directory('${repo.work.path}/rel/tmp').listSync(), isEmpty);
    expect(repo.sandbox.snapshot(), before);
    expect(repo.worktrees(), hasLength(1));
    expect(repo.sandbox.logOf('dart'), isEmpty);
  });
}
