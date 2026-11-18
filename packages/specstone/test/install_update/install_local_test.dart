@TestOn('!windows')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/git_repo.dart' show commitAll, git;
import '../helpers/install_local_repo.dart';

const _unchangedText = 'the install is unchanged';
const _versionFile = 'packages/specstone_core/lib/src/version.dart';

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

  String installLine(String version, String ref, String shortCommit) =>
      'installed specstone $version ($ref @ $shortCommit) '
      'in ${installDir()}/bin\n';

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

  // The dart stub saves the `version.dart` it builds from.
  File builtVersionFile() => File('${repo.sandbox.logs.path}/version.dart');

  Future<void> waitFor(bool Function() isDone) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!isDone()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out after 30 s');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
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

  test(
    'an unknown ref is refused by name before any temp folder exists',
    () async {
      final result = await repo.run(tool, args: ['--branch', 'nope']);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('nope'));
      expectNothingChanged();
    },
  );

  test('a dash-led ref is refused before git runs', () async {
    for (final ref in ['-x', '--upload-pack=x']) {
      final result = await repo.run(tool, args: ['--branch', ref]);

      expect(result.exitCode, isNot(0), reason: ref);
      expect(result.stderr, contains(ref), reason: ref);
      expect(repo.sandbox.logOf('git'), isEmpty, reason: ref);
      expectNothingChanged();
    }
  });

  test('a range or a negated ref is refused by name, not taken as a '
      'commit', () async {
    for (final ref in ['develop..HEAD', '^develop']) {
      final result = await repo.run(tool, args: ['--branch', ref]);

      expect(result.exitCode, 1, reason: ref);
      expect(result.stderr, contains('branch not found: $ref'), reason: ref);
      expectNothingChanged();
    }
  });

  test('an argument list the tool does not take exits 1 '
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

  test('a git failure other than a missing ref keeps its own error', () async {
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
  });

  test('checkoutState() is equal across a refused ref', () async {
    File('${repo.work.path}/marker.txt').writeAsStringSync('changed\n');
    File('${repo.work.path}/untracked.txt').writeAsStringSync('new\n');
    final stateBefore = await repo.checkoutState();

    final result = await repo.run(tool, args: ['--branch', 'nope']);

    expect(result.exitCode, isNot(0));
    expect(await repo.checkoutState(), stateBefore);
  });

  test('the build runs in a git archive export in the temp folder', () async {
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
    final export = RegExp('^${RegExp.escape(tmp)}/([^/]+)/export\$')
        .firstMatch(steps[0].dir);
    expect(export, isNotNull, reason: steps[0].dir);
    final temp = '$tmp/${export![1]}';
    expect(steps[0].args, 'pub get --enforce-lockfile');
    expect(steps[1].dir, '${steps[0].dir}/packages/specstone');
    expect(steps[1].args, 'build cli -t bin/specstone.dart -o $temp/build');
    final gitLog = repo.sandbox.logOf('git');
    expect(
      gitLog,
      contains('archive --format=tar -o $temp/export.tar $commit'),
    );
    expect(gitLog, isNot(anyElement(startsWith('worktree'))));
    expect(bundleBinary.readAsLinesSync()[1], '# develop');
    expect(repo.worktrees(), hasLength(1));
    expect(Directory('${repo.work.path}/.git/worktrees').existsSync(), isFalse);
    expect(repo.tmpIsEmpty, isTrue);
  });

  test('a temp folder that will not delete is named after the run', () async {
    for (final isGood in [true, false]) {
      final result = await repo.run(
        tool,
        env: {'STUB_DART_LOCK': '1', if (!isGood) 'STUB_DART_BUILD': 'fail'},
      );

      final leftover = Directory('${repo.sandbox.root.path}/tmp')
          .listSync()
          .single;
      final locked = '${leftover.path}/locked';
      void removeLeftover() {
        if (!leftover.existsSync()) return;
        Process.runSync('chmod', ['755', locked]);
        Directory(leftover.path).deleteSync(recursive: true);
      }

      addTearDown(removeLeftover);
      final stderr = result.stderr as String;
      expect(result.exitCode, isGood ? 0 : 1, reason: stderr);
      expect(stderr, contains('could not remove'));
      expect(stderr, contains(leftover.resolveSymbolicLinksSync()));
      if (isGood) {
        expect(
          result.stdout,
          installLine('0.10.0-dev.1', 'develop', repo.shortSha('develop')),
        );
      } else {
        expect(stderr, contains('dart build cli failed'));
        expect(
          stderr.indexOf('dart build cli failed'),
          lessThan(stderr.indexOf('could not remove')),
        );
      }
      removeLeftover();
    }
  });

  test('checkoutState() is equal across a run, and the '
      'bundle holds the committed marker.txt', () async {
    final bundleBinary = keepBundleBinary();
    File('${repo.work.path}/marker.txt').writeAsStringSync('changed\n');
    File('${repo.work.path}/$_versionFile')
        .writeAsStringSync("const String specstoneVersion = '9.9.9';\n");
    git(repo.work, ['add', _versionFile]);
    File('${repo.work.path}/untracked.txt').writeAsStringSync('new\n');
    final stateBefore = await repo.checkoutState();

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(await repo.checkoutState(), stateBefore);
    expect(bundleBinary.readAsLinesSync()[1], '# develop');
    final version = await Process.run(bundleBinary.path, ['--version']);
    expect((version.stdout as String).trim(), '0.10.0-dev.1');
  });

  test('a dirty checkout on develop is equal across a '
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
    expect(bundleBinary.readAsLinesSync()[1], '# feature');
  });

  for (final (step, mode) in [
    ('pub get', 'STUB_DART_PUB'),
    ('build cli', 'STUB_DART_BUILD'),
  ]) {
    test('a failing $step is named and snapshot() keeps every '
        'entry', () async {
      final result = await repo.run(tool, env: {mode: 'fail'});

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('dart $step'));
      expect(result.stderr, contains('stub: dart $step failed'));
      expect(repo.sandbox.logOf('dart'), hasLength(step == 'pub get' ? 1 : 2));
      expectBuildLeftNothing();
    });
  }

  test('an interrupt during the build leaves checkout and install', () async {
    File('${repo.work.path}/marker.txt').writeAsStringSync('changed\n');
    File('${repo.work.path}/untracked.txt').writeAsStringSync('new\n');
    final stateBefore = await repo.checkoutState();
    final release = File('${repo.sandbox.logs.path}/release');
    final process = await repo.start(tool, env: {'STUB_DART_BUILD': 'wait'});
    addTearDown(() {
      if (!release.existsSync()) release.createSync();
      process.kill(ProcessSignal.sigkill);
    });
    final output = process.stdout.drain<void>();
    final errors = process.stderr.drain<void>();
    await waitFor(File('${repo.sandbox.logs.path}/building').existsSync);

    process.kill(ProcessSignal.sigint);

    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () => fail('the tool did not exit within 30 s'),
    );
    await Future.wait([output, errors]);
    expect(exitCode, isNot(0));
    expect(release.existsSync(), isFalse);
    expect(repo.sandbox.snapshot(), before);
    expect(await repo.checkoutState(), stateBefore);
    expect(repo.worktrees(), hasLength(1));
    expect(Directory('${repo.work.path}/.git/worktrees').existsSync(), isFalse);
    expect(repo.tmpIsEmpty, isFalse);
  });

  // Merges a new branch into develop with a merge commit.
  void mergeIntoDevelop(String name) {
    git(repo.work, ['checkout', '-q', '-b', name]);
    File('${repo.work.path}/$name.txt').writeAsStringSync('$name\n');
    commitAll(repo.work, name);
    git(repo.work, ['checkout', '-q', 'develop']);
    git(repo.work, ['merge', '-q', '--no-ff', '-m', 'merge $name', name]);
  }

  // Runs the tool on [ref] and expects its install line to name [version].
  Future<void> expectVersion(String version, {String ref = 'develop'}) async {
    final result = await repo.run(tool, args: ['--branch', ref]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout,
      installLine(version, ref, repo.shortSha(ref)),
      reason: ref,
    );
  }

  // The second line of the placed binary: the stub's `# <marker>`.
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

  test('no ref installs develop as 0.10.0-dev.1', () async {
    Directory(installDir()).deleteSync(recursive: true);
    final started = DateTime.now().toUtc();

    final result = await repo.run(tool);

    final finished = DateTime.now().toUtc();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout,
      installLine('0.10.0-dev.1', 'develop', repo.shortSha('develop')),
    );
    expect(result.stderr, isEmpty);
    final version = await Process.run('${installDir()}/bin/specstone', [
      '--version',
    ]);
    expect(version.stdout, '0.10.0-dev.1\n');
    expect(placedMark(), '# develop');
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

  test('--branch feature/example installs that branch', () async {
    final result = await repo.run(tool, args: ['--branch', 'feature/example']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout,
      installLine(
        '0.10.0-dev.1',
        'feature/example',
        repo.shortSha('feature/example'),
      ),
    );
    expect(placedMark(), '# feature');
    expect(buildTxt().readAsLinesSync().first, 'ref: feature/example');
  });

  test('a tag or a full commit installs and the line names '
      'it as given', () async {
    git(repo.work, ['tag', 'v0.9.1', 'feature/example']);
    git(repo.work, ['tag', '-a', 'v0.9.2', '-m', 'annotated', 'develop']);

    final tagged = await repo.run(tool, args: ['--branch', 'v0.9.1']);

    expect(tagged.exitCode, 0, reason: '${tagged.stderr}');
    expect(
      tagged.stdout,
      installLine('0.10.0-dev.1', 'v0.9.1', repo.shortSha('feature/example')),
    );
    expect(placedMark(), '# feature');

    final annotated = await repo.run(tool, args: ['--branch', 'v0.9.2']);

    expect(annotated.exitCode, 0, reason: '${annotated.stderr}');
    expect(
      annotated.stdout,
      installLine('0.10.0-dev.1', 'v0.9.2', repo.shortSha('develop')),
    );
    expect(placedMark(), '# develop');
    expect(buildTxt().readAsLinesSync().first, 'ref: v0.9.2');

    final commit = repo.sha('develop');
    final full = await repo.run(tool, args: ['--branch', commit]);

    expect(full.exitCode, 0, reason: '${full.stderr}');
    expect(
      full.stdout,
      installLine('0.10.0-dev.1', commit, repo.shortSha('develop')),
    );
    expect(placedMark(), '# develop');
    expect(buildTxt().readAsLinesSync().first, 'ref: $commit');
  });

  test('the line tag itself builds as 0.10.0-dev.0', () async {
    await expectVersion('0.10.0-dev.0', ref: 'v0.9.0');
  });

  test('a later release, a merge, and a new pre-release line move the '
      'dev Version', () async {
    git(repo.work, ['tag', 'v0.9.1', 'develop']);
    await expectVersion('0.10.0-dev.1');

    mergeIntoDevelop('second');
    await expectVersion('0.10.0-dev.2');

    git(repo.work, ['tag', 'v0.10.0-beta.1', 'develop']);
    await expectVersion('0.11.0-dev.0');
  });

  test('a tag in no Version form, and a tag the commit does not reach, '
      'are skipped', () async {
    for (final name in ['vnext', 'v1.2', 'release-2.0.0']) {
      git(repo.work, ['tag', name, 'develop']);
    }
    git(repo.work, ['tag', 'v9.9.9', 'feature/example']);

    await expectVersion('0.10.0-dev.1');
  });

  test('a branch of a tag name does not shift the count, and an annotated '
      'line tag counts the same', () async {
    git(repo.work, ['branch', 'v0.9.0', 'develop']);
    // `refs/<name>` outranks `refs/tags/<name>` for a bare name.
    git(repo.work, ['update-ref', 'refs/v0.9.0', 'develop']);
    await expectVersion('0.10.0-dev.1');

    git(repo.work, [
      'tag',
      '-f',
      '-a',
      'v0.9.0',
      '-m',
      'annotated',
      git(repo.work, [
        'rev-list',
        '--max-parents=0',
        'develop',
      ]).stdout.toString().trim(),
    ]);
    await expectVersion('0.10.0-dev.1');
  });

  test('no tag merged into the commit is refused before any '
      'temp folder', () async {
    git(repo.work, ['tag', '-d', 'v0.9.0']);

    final result = await repo.run(tool);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('v<Version>'));
    expect(result.stderr, contains(repo.shortSha('develop')));
    expect(result.stderr, contains(_unchangedText));
    expect(
      repo.sandbox.logOf('git'),
      isNot(anyElement(startsWith('worktree'))),
    );
    expectNothingChanged();
  });

  test('a git that prints tags in columns still finds them', () async {
    git(repo.work, ['config', 'column.ui', 'always']);
    git(repo.work, ['tag', 'v0.9.1', 'develop']);

    await expectVersion('0.10.0-dev.1');
  });

  test('a version.dart that cannot be read is not called a missing '
      'line', () async {
    git(repo.work, ['checkout', '-q', '-b', 'binary']);
    File('${repo.work.path}/$_versionFile')
        .writeAsBytesSync([0xff, 0xfe, 0x0a]);
    commitAll(repo.work, 'not utf-8');
    git(repo.work, ['checkout', '-q', 'develop']);

    final result = await repo.run(tool, args: ['--branch', 'binary']);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('could not read $_versionFile'));
    expect(result.stderr, isNot(contains('no specstoneVersion line')));
    expect(result.stderr, contains(_unchangedText));
    expect(repo.sandbox.logOf('dart'), isEmpty);
    expectBuildLeftNothing();
  });

  test('a commit with no specstoneVersion line is refused naming the file '
      'before any build step', () async {
    git(repo.work, ['checkout', '-q', '-b', 'old-version']);
    File('${repo.work.path}/$_versionFile')
        .writeAsStringSync('// no version yet\n');
    commitAll(repo.work, 'drop the version line');
    git(repo.work, ['checkout', '-q', 'develop']);

    final result = await repo.run(tool, args: ['--branch', 'old-version']);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains(_versionFile));
    expect(result.stderr, contains(_unchangedText));
    expect(repo.sandbox.logOf('dart'), isEmpty);
    expectBuildLeftNothing();
  });

  test('a version.dart with CRLF line ends takes the dev Version', () async {
    // A global autocrlf would turn the committed CRLF back into LF.
    git(repo.work, ['config', 'core.autocrlf', 'false']);
    git(repo.work, ['checkout', '-q', '-b', 'crlf']);
    File('${repo.work.path}/$_versionFile')
        .writeAsStringSync("const String specstoneVersion = '0.9.0';\r\n");
    commitAll(repo.work, 'crlf');
    git(repo.work, ['checkout', '-q', 'develop']);

    await expectVersion('0.10.0-dev.1', ref: 'crlf');
    expect(
      builtVersionFile().readAsStringSync(),
      "const String specstoneVersion = '0.10.0-dev.1';\r\n",
    );
  });

  test('a version.dart with two specstoneVersion lines changes the '
      'first', () async {
    git(repo.work, ['checkout', '-q', '-b', 'twice']);
    File('${repo.work.path}/$_versionFile').writeAsStringSync(
      "const String specstoneVersion = '0.9.0';\n"
      "const String specstoneVersion = '0.8.0'; // second\n",
    );
    commitAll(repo.work, 'twice');
    git(repo.work, ['checkout', '-q', 'develop']);

    await expectVersion('0.10.0-dev.1', ref: 'twice');
    expect(
      builtVersionFile().readAsStringSync(),
      "const String specstoneVersion = '0.10.0-dev.1';\n"
      "const String specstoneVersion = '0.8.0'; // second\n",
    );
  });

  for (final folder in ['lib', 'bin']) {
    test('a $folder copy that fails keeps snapshot()', () async {
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

  test('a failed lib move leaves the old bin', () async {
    failOn('mv', '.lib.new');

    final result = await repo.run(tool);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('${installDir()}/lib'));
    expect(result.stderr, contains('stub: mv failed'));
    expect(binEntries(before), isNotEmpty);
    expect(binEntries(repo.sandbox.snapshot()), binEntries(before));
    expect(installEntries(), unorderedEquals(['bin']));
  });

  test('a failed bin move is named', () async {
    failOn('mv', '.bin.new');

    final result = await repo.run(tool);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('${installDir()}/bin'));
    expect(result.stderr, contains('stub: mv failed'));
    expect(installEntries(), unorderedEquals(['lib']));
  });

  test('packs stay', () async {
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

  test('installFake at 0.10.0-dev.1 is replaced by the build', () async {
    repo.sandbox.installFake(version: '0.10.0-dev.1');

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(placedMark(), '# develop');
    expect(buildTxt().existsSync(), isTrue);
    expect(File('${installDir()}/lib/libold.so').existsSync(), isFalse);
  });

  test('a stale .lib.new and .bin.new from a killed run '
      'are not nested', () async {
    File('${installDir()}/.lib.new/stale.so')
      ..createSync(recursive: true)
      ..writeAsStringSync('stale');
    File('${installDir()}/.bin.new').writeAsStringSync('stale');

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(placedMark(), '# develop');
    expect(File('${installDir()}/lib/stale.so').existsSync(), isFalse);
    expect(Directory('${installDir()}/lib/lib').existsSync(), isFalse);
    expect(Directory('${installDir()}/bin/bin').existsSync(), isFalse);
    expect(installEntries(), unorderedEquals(['bin', 'lib']));
  });

  test('a stale .bin.new folder is not nested', () async {
    File('${installDir()}/.bin.new/stale')
      ..createSync(recursive: true)
      ..writeAsStringSync('stale');

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(placedMark(), '# develop');
    expect(Directory('${installDir()}/bin/bin').existsSync(), isFalse);
    expect(File('${installDir()}/bin/stale').existsSync(), isFalse);
    expect(installEntries(), unorderedEquals(['bin', 'lib']));
  });

  test('the placed shim is executable and holds the '
      'marker of the branch', () async {
    final result = await repo.run(tool, args: ['--branch', 'feature/example']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final shim = File('${installDir()}/bin/stn');
    expect(shim.existsSync(), isTrue);
    expect(shim.readAsLinesSync()[1], '# shim feature');
    // The three execute bits of the mode, as the committed shim has them.
    expect(shim.statSync().mode & 0x49, 0x49);
  });

  test('no ref places the develop shim', () async {
    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final shim = File('${installDir()}/bin/stn');
    expect(shim.existsSync(), isTrue);
    expect(shim.readAsLinesSync()[1], '# shim develop');
  });

  test('the placed shim is the committed one, not an '
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

  test('a commit holding shim/windows places only stn in bin', () async {
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
  });

  test('a shim copy that fails keeps snapshot()', () async {
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
      'placed, and no temp folder remains', () async {
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

  test('build.txt goes with lib/ under install.sh at 0.9.1 and at 0.9.0, '
      'and under uninstall.sh', () async {
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
    expect(buildTxt().existsSync(), isFalse);

    final removed = await sandbox.run('uninstall.sh');

    expect(removed.exitCode, 0, reason: '${removed.stderr}');
    expect(Directory('${installDir()}/lib').existsSync(), isFalse);
  });

  test('no usable HOME exits 1 before any temp folder', () async {
    final cases = [
      ('HOME unset', <String, String>{}, ['HOME']),
      ('HOME empty', {'HOME': ''}, <String>[]),
      ('HOME relative', {'HOME': 'rel/home'}, <String>[]),
      (
        'HOME unset with USERPROFILE set',
        {'USERPROFILE': repo.sandbox.home.path},
        ['HOME'],
      ),
    ];
    for (final (label, env, unset) in cases) {
      final result = await repo.run(tool, env: env, unset: unset);

      expect(result.exitCode, 1, reason: label);
      expect(result.stderr, contains('HOME'), reason: label);
      expect(repo.sandbox.logOf('dart'), isEmpty, reason: label);
      expect(
        repo.sandbox.logOf('git'),
        isNot(anyElement(startsWith('archive'))),
        reason: label,
      );
      expect(repo.sandbox.snapshot(), before, reason: label);
      expect(repo.tmpIsEmpty, isTrue, reason: label);
    }
  });

  test('a temp folder that cannot be made is refused, not a crash, '
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

  test('a .specstone that is a file fails the placement and '
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

  test('a missing dart is refused naming the step and nothing '
      'changes', () async {
    File('${repo.sandbox.stubs.path}/dart').deleteSync();

    final result = await repo.run(tool);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('dart pub get failed'));
    expectNothingChanged();
  });

  test('a home and a temp folder with a space install', () async {
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
      '# develop',
    );
    expect(File('$spacedHome/.specstone/lib/build.txt').existsSync(), isTrue);
    expect(spacedTmp.listSync(), isEmpty);
    expect(repo.worktrees(), hasLength(1));
  });

  test('a relative TMPDIR is refused before any temp folder and the '
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
