@TestOn('!windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/release_repo.dart';

const fetchLine =
    'fetch origin; check origin/main and local develop before moving any ref';
const fastForwardLine =
    'fast-forward main to v0.2.0; fast-forward develop to origin/develop; '
    'merge release/0.2.0 into develop';

void main() {
  late ReleaseRepo repo;
  late String before;

  setUp(() async {
    repo = await createReleaseRepo();
    before = await repo.state();
  });

  Future<void> expectRefusal(
    ProcessResult result,
    List<String> stderrParts,
  ) async {
    expect(result.exitCode, 1);
    for (final part in stderrParts) {
      expect(result.stderr, contains(part));
    }
    expect(await repo.state(), before);
  }

  test('f09/us04/fr01, f09/us04/s3: --dry-run prints the steps and changes '
      'nothing', () async {
    final r = await repo.release(['0.2.0', '--dry-run']);

    expect(r.exitCode, 0);
    expect(
      r.stdout,
      [
        'create release/0.2.0 from develop',
        'set 0.2.0 in the five version spots',
        're-read the five spots; run dart pub get --enforce-lockfile',
        'commit "chore: release 0.2.0"; tag v0.2.0 on it',
        'push tag v0.2.0',
        'wait for the release.yaml run of v0.2.0',
        fetchLine,
        fastForwardLine,
        'push main and develop in one atomic push; delete release/0.2.0',
      ].map((l) => '$l\n').join(),
    );
    expect(await repo.state(), before);
  });

  test('f09/us04/fr01/e01, f09/us04/s5: a version not above the current one '
      'refuses', () async {
    final r = await repo.release(['0.1.0']);

    expect(r.exitCode, 1);
    expect(
      r.stderr,
      'release: 0.1.0 is not greater than the current version 0.1.0; '
      'give MAJOR.MINOR.PATCH above it\n',
    );
    expect(await repo.state(), before);
  });

  for (final bad in ['v0.2.0', '0.2']) {
    test('f09/us04/fr01/e01: $bad refuses naming the form and the current '
        'version', () async {
      final r = await repo.release([bad]);

      await expectRefusal(r, ['MAJOR.MINOR.PATCH', 'current version is 0.1.0']);
    });
  }

  test('f09/us04/fr01: versions compare field by field', () async {
    final other = await createReleaseRepo(
      version: '0.9.0',
      files: {
        'packages/specstone_core/lib/src/version.dart':
            "const String specstoneVersion = '0.9.0';\n",
      },
    );

    final r = await other.release(['0.10.0', '--dry-run']);

    expect(r.exitCode, 0, reason: '${r.stderr}');
  });

  test('f09/us04/fr01, f09/us04/s6: an unclean tree refuses', () async {
    await File('${repo.work.path}/stray.txt').writeAsString('x');
    before = await repo.state();

    final r = await repo.release(['0.2.0']);

    await expectRefusal(r, ['not clean']);
  });

  test('f09/us04/fr01/e02: develop ahead of origin/develop refuses', () async {
    await repo.commitFile('local.txt', 'x', 'local');
    before = await repo.state();

    final r = await repo.release(['0.2.0']);

    await expectRefusal(r, ['origin/develop']);
  });

  test('f09/us04/fr01/e02: develop behind origin/develop refuses; local '
      'develop does not move', () async {
    await repo.pushFromOtherClone('develop');
    before = await repo.state();
    final develop = await repo.git(['rev-parse', 'develop']);
    final originRefs = await repo.originRefs();

    final r = await repo.release(['0.2.0']);

    await expectRefusal(r, ['origin/develop']);
    expect(await repo.git(['rev-parse', 'develop']), develop);
    expect(await repo.originRefs(), originRefs);
  });

  for (final (ci, state) in [
    ('in_progress', 'in_progress'),
    ('failure', 'failure'),
  ]) {
    test('f09/us04/fr01/e03: a ci run $ci refuses naming its state', () async {
      final r = await repo.release(['0.2.0'], gh: {'GH_STUB_CI': ci});

      await expectRefusal(r, [state]);
    });
  }

  test(
    'f09/us04/fr01/e04: gh not logged in refuses naming gh auth login',
    () async {
      final r = await repo.release(['0.2.0'], gh: {'GH_STUB_AUTH': 'none'});

      await expectRefusal(r, ['gh auth login']);
    },
  );

  test('f09/us04/fr01/e05: another branch refuses naming develop', () async {
    await repo.git(['checkout', '-q', 'main']);
    before = await repo.state();

    final r = await repo.release(['0.2.0']);

    await expectRefusal(r, ['develop']);
  });

  test('f09/us04/fr01/e06: tag v0.2.0 on origin refuses', () async {
    await repo.git(['tag', 'v0.2.0']);
    await repo.git(['push', '-q', 'origin', 'v0.2.0']);
    await repo.git(['tag', '-d', 'v0.2.0']);
    before = await repo.state();

    final r = await repo.release(['0.2.0']);

    await expectRefusal(r, ['v0.2.0', 'origin']);
  });

  test('f09/us04/fr01: a local tag v0.2.0 refuses', () async {
    await repo.git(['tag', 'v0.2.0']);
    before = await repo.state();

    final r = await repo.release(['0.2.0']);

    await expectRefusal(r, ['v0.2.0', 'locally']);
  });

  test(
    'f09/us04/fr01: a missing, extra, or unknown argument prints the usage',
    () async {
      for (final args in [
        <String>[],
        ['0.2.0', '0.3.0'],
        ['0.2.0', '--force'],
        ['--dry-run'],
      ]) {
        final r = await repo.release(args);

        expect(r.exitCode, 1, reason: args.join(' '));
        expect(
          r.stderr,
          'release: usage: dart run tool/release.dart X.Y.Z [--dry-run]\n',
        );
      }
      expect(await repo.state(), before);
    },
  );

  test('f09/us04/fr01: the CI check reads the develop head', () async {
    final sha = await repo.git(['rev-parse', 'develop']);

    await repo.release(['0.2.0', '--dry-run']);

    expect(
      repo.ghCalls().first,
      'run list --workflow ci.yaml --commit $sha --limit 1 '
      '--json status,conclusion',
    );
  });
}
