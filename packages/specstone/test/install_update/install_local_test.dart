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

  // Sends SIGINT to the tool once a stub has created `<logs>/<marker>` and
  // waits for `<logs>/release`, lets that stub go once the tool says it saw the
  // signal, and returns how the tool ended.
  Future<({int exitCode, String stdout, String stderr})> interruptAt(
    String marker,
    Map<String, String> env,
  ) async {
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
    process.kill(ProcessSignal.sigint);
    await waitFor(() => '$errors'.contains('interrupted; cleaning up'));
    release.createSync();

    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
    );
    await done;
    return (exitCode: exitCode, stdout: '$output', stderr: '$errors');
  }

  // Sends SIGINT to the tool while its build waits.
  Future<({int exitCode, String stdout, String stderr})>
  interruptDuringBuild() =>
      interruptAt('building', {'STUB_DART_BUILD': 'wait'});

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

  String installDir() => '${repo.sandbox.home.path}/.specstone';

  String installLine(String ref, String shortCommit) =>
      'installed specstone 0.9.0 ($ref @ $shortCommit) in ${installDir()}/bin\n';

  // The names directly under the install folder.
  List<String> installEntries() => [
    for (final entry in Directory(installDir()).listSync())
      entry.path.substring(installDir().length + 1),
  ];

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

    final tagged = await repo.run(tool, args: ['--branch', 'v0.9.0']);

    expect(tagged.exitCode, 0, reason: '${tagged.stderr}');
    expect(
      tagged.stdout,
      installLine('v0.9.0', repo.shortSha('feature/example')),
    );
    expect(placedMark(), '# ${repo.sha('feature/example')} feature');

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

  test(
    '$_fr input_output: a stale .lib.new from a killed run is not nested',
    () async {
      File('${installDir()}/.lib.new/stale.so')
        ..createSync(recursive: true)
        ..writeAsStringSync('stale');

      final result = await repo.run(tool);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File('${installDir()}/lib/stale.so').existsSync(), isFalse);
      expect(Directory('${installDir()}/lib/lib').existsSync(), isFalse);
      expect(installEntries(), unorderedEquals(['bin', 'lib']));
    },
  );

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

    final removed = await sandbox.run('uninstall.sh');

    expect(removed.exitCode, 0, reason: '${removed.stderr}');
    expect(Directory('${installDir()}/lib').existsSync(), isFalse);
  });

  for (final (label, env, unset) in [
    ('HOME unset', <String, String>{}, ['HOME']),
    ('HOME and USERPROFILE empty', {'HOME': '', 'USERPROFILE': ''}, <String>[]),
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
}
