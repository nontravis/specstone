@TestOn('!windows')
@Timeout(Duration(minutes: 2))
library;

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

  // The second line of the placed binary: the stub's `# <marker>`.
  String placedMark() =>
      File('${installDir()}/bin/specstone').readAsLinesSync()[1];

  File buildTxt() => File('${installDir()}/lib/build.txt');

  Map<String, String> binEntries(Map<String, String> snapshot) => {
    for (final MapEntry(:key, :value) in snapshot.entries)
      if (key.startsWith('.specstone/bin/')) key: value,
  };

  // A refusal changes nothing: the install is as it was, no worktree is made,
  // no build step ran, and no temp folder exists.
  void expectNothingChanged({String? reason}) {
    expect(repo.sandbox.snapshot(), before, reason: reason);
    expect(repo.worktrees(), hasLength(1), reason: reason);
    expect(repo.sandbox.logOf('dart'), isEmpty, reason: reason);
    expect(repo.tmpIsEmpty, isTrue, reason: reason);
  }

  // A failed build leaves the install as it was with no aside copy beside it,
  // makes no worktree, and deletes its temp folder.
  void expectBuildLeftNothing({String? reason}) {
    expect(repo.sandbox.snapshot(), before, reason: reason);
    expect(installEntries(), unorderedEquals(['bin', 'lib']), reason: reason);
    expect(repo.worktrees(), hasLength(1), reason: reason);
    expect(repo.tmpIsEmpty, isTrue, reason: reason);
  }

  Future<void> waitFor(bool Function() isDone) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!isDone()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out after 30 s');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

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

  // Makes `cp` or `mv` fail when its arguments name [aside]; any other call
  // goes to the real tool.
  void failOn(String tool, String aside) => repo.sandbox.stub(
    tool,
    'case "\$*" in\n'
    '  *$aside*) echo "stub: $tool failed" >&2; exit 1 ;;\n'
    'esac\n'
    'exec /bin/$tool "\$@"',
  );

  test('an unresolvable ref is refused by name', () async {
    for (final ref in [
      'nope',
      '-x',
      '--upload-pack=x',
      'develop..HEAD',
      '^develop',
    ]) {
      final gitCalls = repo.sandbox.logOf('git').length;

      final result = await repo.run(tool, args: ['--branch', ref]);

      expect(result.exitCode, 1, reason: ref);
      expect(result.stderr, contains('branch not found: $ref'), reason: ref);
      if (ref.startsWith('-')) {
        expect(repo.sandbox.logOf('git'), hasLength(gitCalls), reason: ref);
      }
      expectNothingChanged(reason: ref);
    }
  });

  test('a bad argument list prints usage before git', () async {
    for (final args in [
      ['--force'],
      ['--branch'],
      ['develop'],
      ['--branch', 'develop', 'extra'],
    ]) {
      final result = await repo.run(tool, args: args);

      expect(result.exitCode, 1, reason: '$args');
      expect(result.stderr, contains('usage:'), reason: '$args');
      expect(repo.sandbox.logOf('git'), isEmpty, reason: '$args');
      expectNothingChanged(reason: '$args');
    }
  });

  test('the build runs in a git archive export in the temp folder', () async {
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
    expect(placedMark(), '# develop');
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

  test('the checkout and its git data stay across a run', () async {
    File('${repo.work.path}/marker.txt').writeAsStringSync('changed\n');
    File('${repo.work.path}/$_versionFile')
        .writeAsStringSync("const String specstoneVersion = '9.9.9';\n");
    File('${repo.work.path}/staged.txt').writeAsStringSync('staged\n');
    git(repo.work, ['add', _versionFile, 'staged.txt']);
    File('${repo.work.path}/untracked.txt').writeAsStringSync('new\n');
    final stateBefore = await repo.checkoutState();

    for (final (ref, mark) in [
      ('develop', '# develop'),
      ('feature/example', '# feature'),
    ]) {
      final result = await repo.run(tool, args: ['--branch', ref]);

      expect(result.exitCode, 0, reason: '$ref ${result.stderr}');
      expect(
        result.stdout,
        installLine('0.10.0-dev.1', ref, repo.shortSha(ref)),
        reason: ref,
      );
      expect(await repo.checkoutState(), stateBefore, reason: ref);
      expect(repo.worktrees(), hasLength(1), reason: ref);
      expect(
        Directory('${repo.work.path}/.git/worktrees').existsSync(),
        isFalse,
        reason: ref,
      );
      expect(placedMark(), mark, reason: ref);
    }
  });

  test('a failing build step is named and the install stays', () async {
    for (final (step, mode, calls) in [
      ('pub get', 'STUB_DART_PUB', 1),
      ('build cli', 'STUB_DART_BUILD', 2),
    ]) {
      final dartCalls = repo.sandbox.logOf('dart').length;

      final result = await repo.run(tool, env: {mode: 'fail'});

      expect(result.exitCode, isNot(0), reason: step);
      expect(result.stderr, contains('dart $step'), reason: step);
      expect(result.stderr, contains('stub: dart $step failed'), reason: step);
      expect(
        repo.sandbox.logOf('dart'),
        hasLength(dartCalls + calls),
        reason: step,
      );
      expectBuildLeftNothing(reason: step);
    }
  });

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
    // The interrupt ends the run with no cleanup: its temp folder stays.
    expect(repo.tmpIsEmpty, isFalse);
  });

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

  test('a branch, tag, or commit installs and is named as given', () async {
    git(repo.work, ['tag', 'v0.9.1', 'feature/example']);
    git(repo.work, ['tag', '-a', 'v0.9.2', '-m', 'annotated', 'develop']);
    final develop = repo.sha('develop');

    for (final (ref, tipOf) in [
      ('feature/example', 'feature/example'),
      ('v0.9.1', 'feature/example'),
      ('v0.9.2', 'develop'),
      (develop, 'develop'),
    ]) {
      final result = await repo.run(tool, args: ['--branch', ref]);

      expect(result.exitCode, 0, reason: '$ref ${result.stderr}');
      expect(
        result.stdout,
        installLine('0.10.0-dev.1', ref, repo.shortSha(tipOf)),
        reason: ref,
      );
      expect(buildTxt().readAsLinesSync().first, 'ref: $ref', reason: ref);
    }
  });

  test('the line tag itself builds as 0.10.0-dev.0', () async {
    await expectVersion('0.10.0-dev.0', ref: 'v0.9.0');
  });

  test(
    'a later release, a merge, and a new line move the dev Version',
    () async {
      git(repo.work, ['tag', 'v0.9.1', 'develop']);
      await expectVersion('0.10.0-dev.1');

      mergeIntoDevelop('second');
      await expectVersion('0.10.0-dev.2');

      git(repo.work, ['tag', 'v0.10.0-beta.1', 'develop']);
      await expectVersion('0.11.0-dev.0');
    },
  );

  test('a minor of any length moves up by one', () async {
    for (final (minor, next) in [
      ('9223372036854775807', '9223372036854775808'),
      ('9223372036854775808', '9223372036854775809'),
      ('99999999999999999999', '100000000000000000000'),
    ]) {
      git(repo.work, ['tag', 'v0.$minor.0', 'develop']);

      await expectVersion('0.$next.0-dev.0');
    }
  });

  test('tags outside the Version form or the commit are skipped', () async {
    for (final name in ['vnext', 'v1.2', 'release-2.0.0']) {
      git(repo.work, ['tag', name, 'develop']);
    }
    git(repo.work, ['tag', 'v9.9.9', 'feature/example']);

    await expectVersion('0.10.0-dev.1');
  });

  test('no merged tag is refused before any temp folder', () async {
    git(repo.work, ['tag', '-d', 'v0.9.0']);

    final result = await repo.run(tool);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('v<Version>'));
    expect(result.stderr, contains(repo.shortSha('develop')));
    expect(result.stderr, contains(_unchangedText));
    expectNothingChanged();
  });

  test('a commit with no specstoneVersion line is refused', () async {
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

  test('a failing copy aside keeps the old install', () async {
    for (final (aside, folder) in [
      ('.lib.new', 'lib'),
      ('.bin.new', 'bin'),
      ('.bin.new/stn', 'bin'),
    ]) {
      failOn('cp', aside);

      final result = await repo.run(tool);

      expect(result.exitCode, isNot(0), reason: aside);
      expect(result.stderr, contains('${installDir()}/$folder'), reason: aside);
      expect(result.stderr, contains('stub: cp failed'), reason: aside);
      expectBuildLeftNothing(reason: aside);
    }
  });

  test('a failing move into place is named', () async {
    for (final (aside, folder, remaining) in [
      ('.lib.new', 'lib', 'bin'),
      ('.bin.new', 'bin', 'lib'),
    ]) {
      Directory(installDir()).deleteSync(recursive: true);
      repo.sandbox.installFake();
      before = repo.sandbox.snapshot();
      failOn('mv', aside);

      final result = await repo.run(tool);

      expect(result.exitCode, isNot(0), reason: aside);
      expect(result.stderr, contains('${installDir()}/$folder'), reason: aside);
      expect(result.stderr, contains('stub: mv failed'), reason: aside);
      expect(installEntries(), [remaining], reason: aside);
      expect(repo.tmpIsEmpty, isTrue, reason: aside);
      if (remaining == 'bin') {
        expect(binEntries(before), isNotEmpty);
        expect(binEntries(repo.sandbox.snapshot()), binEntries(before));
      }
    }
  });

  test('packs stay when the build replaces lib and bin', () async {
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

  test('an install at the same version is replaced', () async {
    repo.sandbox.installFake(version: '0.10.0-dev.1');

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(placedMark(), '# develop');
    expect(buildTxt().existsSync(), isTrue);
    expect(File('${installDir()}/lib/libold.so').existsSync(), isFalse);
  });

  test('stale asides from a killed run are cleared', () async {
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

  test('the placed shim is the executable one of the ref', () async {
    for (final (ref, marker) in [
      ('develop', 'develop'),
      ('feature/example', 'feature'),
    ]) {
      final result = await repo.run(tool, args: ['--branch', ref]);

      expect(result.exitCode, 0, reason: '$ref ${result.stderr}');
      final shim = File('${installDir()}/bin/stn');
      expect(shim.readAsLinesSync()[1], '# shim $marker', reason: ref);
      // The three execute bits of the mode, as the committed shim has them.
      expect(shim.statSync().mode & 0x49, 0x49, reason: ref);
    }
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

  test('a commit with no shim is refused, nothing changed', () async {
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

  test('install.sh and uninstall.sh drop the local build.txt', () async {
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

  test('a relative TMPDIR is refused and the checkout stays', () async {
    Directory('${repo.work.path}/rel/tmp').createSync(recursive: true);
    final stateBefore = await repo.checkoutState();

    final result = await repo.run(tool, env: {'TMPDIR': 'rel/tmp'});

    expect(result.exitCode, 1);
    expect(result.stderr, contains('not an absolute path'));
    expect(result.stderr, contains(_unchangedText));
    expect(await repo.checkoutState(), stateBefore);
    expect(Directory('${repo.work.path}/rel/tmp').listSync(), isEmpty);
    expect(repo.sandbox.snapshot(), before);
    expect(repo.worktrees(), hasLength(1));
    expect(repo.sandbox.logOf('dart'), isEmpty);
  });

  test('a failed move into place asks for a new install run', () async {
    for (final aside in ['.lib.new', '.bin.new']) {
      Directory(installDir()).deleteSync(recursive: true);
      repo.sandbox.installFake();
      failOn('mv', aside);

      final result = await repo.run(tool);

      expect(result.exitCode, isNot(0), reason: aside);
      expect(
        result.stderr,
        contains('stub: mv failed; run install_local again'),
        reason: aside,
      );
    }
  });

  test('a relative TMPDIR refusal names TMPDIR', () async {
    final result = await repo.run(tool, env: {'TMPDIR': 'rel/tmp'});

    expect(result.exitCode, 1);
    expect(result.stderr, contains('TMPDIR'));
  });

  test('a refusal for no usable HOME says no home folder resolves', () async {
    for (final env in [
      {'HOME': ''},
      {'HOME': 'rel/home'},
    ]) {
      final result = await repo.run(tool, env: env);

      expect(result.exitCode, 1, reason: '$env');
      expect(result.stderr, contains('no home folder'), reason: '$env');
    }
  });

  test('a refusal before the temp folder runs no git call after it', () async {
    final commit = repo.sha('develop');
    const verify = 'rev-parse --verify --quiet develop^{commit}';
    final shim = 'cat-file -e $commit:$shimPath';
    final tags = 'tag --no-column --merged $commit';
    final count =
        'rev-list --first-parent --merges --count refs/tags/v0.9.0..$commit';
    final short = 'rev-parse --short $commit';
    git(repo.work, ['checkout', '-q', '-b', 'old']);
    git(repo.work, ['rm', '-q', shimPath]);
    commitAll(repo.work, 'before the shim');
    git(repo.work, ['checkout', '-q', 'develop']);
    final oldCommit = repo.sha('old');

    for (final (label, args, env, calls) in [
      (
        'no such commit',
        ['--branch', 'nope'],
        <String, String>{},
        ['rev-parse --verify --quiet nope^{commit}'],
      ),
      (
        'no shim',
        ['--branch', 'old'],
        <String, String>{},
        [
          'rev-parse --verify --quiet old^{commit}',
          'cat-file -e $oldCommit:$shimPath',
        ],
      ),
      ('no home', <String>[], {'HOME': ''}, [verify, shim, tags, count]),
      (
        'relative TMPDIR',
        <String>[],
        {'TMPDIR': 'rel/tmp'},
        [verify, shim, tags, count, short],
      ),
    ]) {
      File('${repo.sandbox.logs.path}/git.log').writeAsStringSync('');

      final result = await repo.run(tool, args: args, env: env);

      expect(result.exitCode, 1, reason: label);
      expect(repo.sandbox.logOf('git'), calls, reason: label);
    }
  });

  test('a refusal for no merged tag runs no git call after it', () async {
    final commit = repo.sha('develop');
    git(repo.work, ['tag', '-d', 'v0.9.0']);

    final result = await repo.run(tool);

    expect(result.exitCode, isNot(0));
    expect(repo.sandbox.logOf('git'), [
      'rev-parse --verify --quiet develop^{commit}',
      'cat-file -e $commit:$shimPath',
      'tag --no-column --merged $commit',
      'rev-parse --short $commit',
    ]);
  });

  test('a temp folder delete failure names the folder and the error', () async {
    final result = await repo.run(tool, env: {'STUB_DART_LOCK': '1'});

    final leftover = Directory('${repo.sandbox.root.path}/tmp')
        .listSync()
        .single;
    addTearDown(() {
      if (!leftover.existsSync()) return;
      Process.runSync('chmod', ['755', '${leftover.path}/locked']);
      Directory(leftover.path).deleteSync(recursive: true);
    });
    final folder = leftover.resolveSymbolicLinksSync();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stderr,
      matches(
        RegExp(
          '^install_local: could not remove ${RegExp.escape(folder)}: '
          r'\S.*$',
          multiLine: true,
        ),
      ),
    );
  });

  test(
    'a signal during the copy aside keeps the asides and the install',
    () async {
      repo.sandbox.stub('cp', r'''
case "$*" in
  *.bin.new/stn*)
    touch "$STUB_LOG_DIR/copying"
    while [ -d "$STUB_LOG_DIR" ] && [ ! -e "$STUB_LOG_DIR/release" ]
    do sleep 0.1; done
    exit 1 ;;
esac
exec /bin/cp "$@"''');
      final release = File('${repo.sandbox.logs.path}/release');
      final process = await repo.start(tool);
      addTearDown(() {
        if (!release.existsSync()) release.createSync();
        process.kill(ProcessSignal.sigkill);
      });
      final output = process.stdout.drain<void>();
      final errors = process.stderr.drain<void>();
      await waitFor(File('${repo.sandbox.logs.path}/copying').existsSync);

      process.kill(ProcessSignal.sigint);

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 30),
        onTimeout: () => fail('the tool did not exit within 30 s'),
      );
      await Future.wait([output, errors]);
      expect(exitCode, isNot(0));
      expect(
        installEntries(),
        unorderedEquals(['bin', 'lib', '.lib.new', '.bin.new']),
      );
      final installed = {
        for (final MapEntry(:key, :value) in repo.sandbox.snapshot().entries)
          if (key.startsWith('.specstone/lib/') ||
              key.startsWith('.specstone/bin/'))
            key: value,
      };
      expect(installed, before);
    },
  );

  // A teardown ends a waiting build stub by a release file or by deleting
  // the sandbox; either way the stub must exit and write no build output.
  for (final (trigger, end) in <(String, void Function(Directory))>[
    ('a release file', (logs) => File('${logs.path}/release').createSync()),
    ('a deleted logs folder', (logs) => logs.deleteSync(recursive: true)),
  ]) {
    test('a waiting build stub exits, writing nothing, on $trigger', () async {
      final logs = repo.sandbox.logs;
      final out = Directory('${logs.path}/out');
      final stub = await Process.start(
        '${repo.sandbox.stubs.path}/dart',
        ['build', 'cli', '-o', out.path],
        workingDirectory: repo.work.path,
        environment: repo.sandbox.env({'STUB_DART_BUILD': 'wait'}),
        includeParentEnvironment: false,
      );
      addTearDown(() => stub.kill(ProcessSignal.sigkill));
      final output = stub.stdout.drain<void>();
      final errors = stub.stderr.drain<void>();
      await waitFor(File('${logs.path}/building').existsSync);

      end(logs);

      final exitCode = await stub.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('the stub did not exit within 5 s'),
      );
      await Future.wait([output, errors]);
      expect(exitCode, 1);
      expect(out.existsSync(), isFalse);
    });
  }

  Future<void> expectSignalEndsBuildAtOnce(ProcessSignal signal) async {
    final release = File('${repo.sandbox.logs.path}/release');
    final process = await repo.start(tool, env: {'STUB_DART_BUILD': 'wait'});
    addTearDown(() {
      if (!release.existsSync()) release.createSync();
      process.kill(ProcessSignal.sigkill);
    });
    final output = process.stdout.drain<void>();
    final errors = process.stderr.drain<void>();
    await waitFor(File('${repo.sandbox.logs.path}/building').existsSync);

    process.kill(signal);

    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () => fail('the tool did not exit within 30 s'),
    );
    await Future.wait([output, errors]);
    expect(exitCode, isNot(0), reason: '$signal');
    expect(repo.sandbox.snapshot(), before, reason: '$signal');
    expect(repo.tmpIsEmpty, isFalse, reason: '$signal');
  }

  test('SIGTERM ends the build at once and keeps the temp folder', () async {
    await expectSignalEndsBuildAtOnce(ProcessSignal.sigterm);
  });

  test('SIGHUP ends the build at once and keeps the temp folder', () async {
    await expectSignalEndsBuildAtOnce(ProcessSignal.sighup);
  });

  test('the shim check runs before the dev Version is computed', () async {
    git(repo.work, ['checkout', '-q', '--orphan', 'bare']);
    git(repo.work, ['rm', '-rfq', '.']);
    File('${repo.work.path}/bare.txt').writeAsStringSync('bare\n');
    commitAll(repo.work, 'a commit with no shim and no tag');
    git(repo.work, ['checkout', '-q', 'develop']);

    final result = await repo.run(tool, args: ['--branch', 'bare']);

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains(shimPath));
    expect(result.stderr, isNot(contains('v<Version>')));
    expect(repo.sandbox.logOf('git'), isNot(anyElement(startsWith('tag'))));
    expectNothingChanged();
  });

  test('a folder or a link at the shim path passes the shim check', () async {
    git(repo.work, ['checkout', '-q', '-b', 'shim-folder']);
    git(repo.work, ['rm', '-q', shimPath]);
    File('${repo.work.path}/$shimPath/inner.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('inner\n');
    commitAll(repo.work, 'a folder at the shim path');
    git(repo.work, ['checkout', '-q', '-b', 'shim-link', 'develop']);
    git(repo.work, ['rm', '-q', shimPath]);
    Link('${repo.work.path}/$shimPath').createSync('../../../marker.txt');
    commitAll(repo.work, 'a link at the shim path');
    git(repo.work, ['checkout', '-q', 'develop']);

    for (final ref in ['shim-folder', 'shim-link']) {
      final result = await repo.run(tool, args: ['--branch', ref]);

      expect(result.stderr, isNot(contains('holds no $shimPath')), reason: ref);
      expect(repo.sandbox.logOf('dart'), isNotEmpty, reason: ref);
      if (ref == 'shim-folder') {
        expect(result.exitCode, isNot(0), reason: ref);
        expect(result.stderr, contains('${installDir()}/bin'), reason: ref);
        expectBuildLeftNothing(reason: ref);
      } else {
        expect(result.exitCode, 0, reason: '$ref ${result.stderr}');
      }
    }
  });

  test('another stn on the PATH does not stop the local install', () async {
    repo.sandbox.stub('stn', 'echo another');

    final result = await repo.run(tool);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stderr, isEmpty);
    expect(
      result.stdout,
      installLine('0.10.0-dev.1', 'develop', repo.shortSha('develop')),
    );
    expect(
      File('${installDir()}/bin/stn').readAsLinesSync()[1],
      '# shim develop',
    );
  });
}
