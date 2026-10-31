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

  Future<void> rejectPushes(String refPattern) async {
    final hook = File('${repo.origin.path}/hooks/pre-receive');
    await hook.writeAsString(
      '#!/bin/sh\n'
      'while read old new ref; do\n'
      '  case "\$ref" in\n'
      '    $refPattern) echo "push of \$ref refused" >&2; exit 1;;\n'
      '  esac\n'
      'done\n',
    );
    await Process.run('chmod', ['+x', hook.path]);
  }

  Future<String> sha(String ref) => repo.git(['rev-parse', ref]);

  List<String> stderrLines(ProcessResult r) =>
      (r.stderr as String).trimRight().split('\n');

  // Commits on local develop only, from inside `gh run watch`.
  String localDevelopCommit() =>
      "c=\$(git -C '${repo.work.path}' commit-tree -m local-only "
      "-p develop 'develop^{tree}') "
      "&& git -C '${repo.work.path}' update-ref refs/heads/develop \$c";

  const resolveLine =
      'Resolve it, then run dart run tool/release.dart 0.2.0 again from '
      'release/0.2.0';

  test('f09/us04/fr02, f09/us04/fr03, f09/us04/s1: the tag ships first; main '
      'and develop move after the Release', () async {
    final r = await repo.release(['0.2.0']);

    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(
      (r.stdout as String).trimRight().split('\n').last,
      'Released v0.2.0: '
      'https://github.com/nontravis/specstone/releases/tag/v0.2.0; '
      'main and develop pushed',
    );
    final refs = await repo.originRefs();
    final tagged = refs['refs/tags/v0.2.0']!;
    expect(
      await repo.git(['log', '-1', '--format=%s', tagged]),
      'chore: release 0.2.0',
    );
    expect(
      (await repo.git(['diff', '--name-only', '$tagged~1', tagged])).split('\n')
        ..sort(),
      [
        'packages/specstone/pubspec.yaml',
        'packages/specstone_core/lib/src/version.dart',
        'packages/specstone_core/pubspec.yaml',
        'plugin/.claude-plugin/plugin.json',
      ],
    );
    expect(refs['refs/heads/main'], tagged);
    // Throws when the tag is not an ancestor.
    await repo.git([
      'merge-base',
      '--is-ancestor',
      tagged,
      refs['refs/heads/develop']!,
    ]);
    expect(refs.keys.where((k) => k.contains('release/')), isEmpty);
    expect(await repo.git(['branch', '--list', 'release/*']), isEmpty);
    final runList =
        'run list --workflow release.yaml --commit $tagged --limit 1 '
        '--json databaseId,url';
    expect(repo.ghCalls().skip(1), [
      runList,
      'run watch 123456789 --exit-status',
      'release view v0.2.0 --json url --jq .url',
    ]);
    expect(await repo.git(['branch', '--show-current']), 'develop');
  });

  test('f09/us04/fr02/e01, f09/us04/s8: a spot left behind refuses before the '
      'commit and undoes the bump', () async {
    repo = await createReleaseRepo(
      files: {
        'plugin/.claude-plugin/plugin.json': '{\n  "name": "specstone"\n}\n',
      },
    );
    before = await repo.state();

    final r = await repo.release(['0.2.0']);

    await expectRefusal(r, ['plugin/.claude-plugin/plugin.json']);
    expect(await repo.git(['branch', '--show-current']), 'develop');
    expect(await repo.git(['branch', '--list', 'release/*']), isEmpty);
    expect(await repo.git(['tag', '--list']), isEmpty);
  });

  test('f09/us04/fr02/e02: a bump dart pub get rejects is undone the same '
      'way', () async {
    repo = await createReleaseRepo(
      files: {
        'pubspec.yaml': '''
name: fixture_workspace
publish_to: none
environment:
  sdk: ^3.13.5
workspace:
  - packages/specstone_core
  - packages/specstone
  - packages/other
''',
        'packages/other/pubspec.yaml': '''
name: other
environment:
  sdk: ^3.13.5
resolution: workspace
dependencies:
  specstone_core: ^0.1.0
''',
      },
    );
    before = await repo.state();

    final r = await repo.release(['0.2.0']);

    await expectRefusal(r, ['specstone_core']);
    expect(await repo.git(['branch', '--show-current']), 'develop');
    expect(await repo.git(['branch', '--list', 'release/*']), isEmpty);
  });

  test('f09/us04/fr02/e03: a rejected tag push keeps the branch and tag for a '
      'run again', () async {
    await rejectPushes('refs/tags/*');
    final refs = await repo.originRefs();

    final r = await repo.release(['0.2.0']);

    expect(r.exitCode, 1);
    expect(r.stderr, contains('git push origin v0.2.0'));
    expect(await repo.git(['branch', '--list', 'release/0.2.0']), isNotEmpty);
    expect(await repo.git(['tag', '--list', 'v0.2.0']), 'v0.2.0');
    expect(await repo.originRefs(), refs);
  });

  test('f09/us04/fr03/e01, f09/us04/s7: a failed release run leaves main and '
      'develop untouched', () async {
    final refs = await repo.originRefs();

    final r = await repo.release(['0.2.0'], gh: {'GH_STUB_RUN': 'failure'});

    expect(r.exitCode, 1);
    expect(
      r.stderr,
      'release: the release.yaml run of v0.2.0 failed: '
      'https://github.com/nontravis/specstone/actions/runs/123456789; '
      'main and develop are untouched. Fix on release/0.2.0, then run '
      'dart run tool/release.dart 0.2.0 from that branch\n',
    );
    final after = await repo.originRefs();
    expect(after['refs/heads/main'], refs['refs/heads/main']);
    expect(after['refs/heads/develop'], refs['refs/heads/develop']);
    expect(after, contains('refs/tags/v0.2.0'));
    expect(await repo.git(['branch', '--show-current']), 'release/0.2.0');
    expect(repo.ghCalls().where((c) => c.startsWith('release view')), isEmpty);
  });

  test('f09/us04/fr03/e04, f09/us04/s9: a develop moved during the wait is '
      'merged and pushed', () async {
    final r = await repo.release(
      ['0.2.0'],
      gh: {'GH_STUB_ON_WATCH': repo.pushFromOtherCloneCommand('develop')},
    );

    expect(r.exitCode, 0, reason: '${r.stderr}');
    final refs = await repo.originRefs();
    final other = await repo.git(['rev-parse', 'origin/develop~1']);
    await repo.git([
      'merge-base',
      '--is-ancestor',
      other,
      refs['refs/heads/develop']!,
    ]);
    await repo.git([
      'merge-base',
      '--is-ancestor',
      refs['refs/tags/v0.2.0']!,
      refs['refs/heads/develop']!,
    ]);
    expect(refs['refs/heads/main'], refs['refs/tags/v0.2.0']);
  });

  test('f09/us04/fr03/e02, f09/us04/s10: a main moved during the wait moves '
      'no ref and pushes nothing', () async {
    final main = await sha('main');
    final develop = await sha('develop');
    final refs = await repo.originRefs();

    final r = await repo.release(
      ['0.2.0'],
      gh: {'GH_STUB_ON_WATCH': repo.pushFromOtherCloneCommand('main')},
    );

    expect(r.exitCode, 1);
    final otherMain = (await repo.originRefs())['refs/heads/main']!;
    expect(otherMain, isNot(refs['refs/heads/main']));
    expect(r.stderr, contains(otherMain.substring(0, 7)));
    expect(r.stderr, contains('a second release reached main'));
    expect(stderrLines(r).where((l) => l.startsWith('git ')), isEmpty);
    expect(stderrLines(r).last, resolveLine);
    expect(await sha('main'), main);
    expect(await sha('develop'), develop);
    final after = await repo.originRefs();
    expect(after['refs/heads/develop'], refs['refs/heads/develop']);
    expect(after, contains('refs/tags/v0.2.0'));
    expect(await repo.git(['branch', '--list', 'release/0.2.0']), isNotEmpty);
  });

  test('f09/us04/fr03/e05: local develop ahead of origin/develop moves no ref '
      'and pushes nothing', () async {
    final main = await sha('main');
    final refs = await repo.originRefs();

    final r = await repo.release(
      ['0.2.0'],
      gh: {'GH_STUB_ON_WATCH': localDevelopCommit()},
    );

    expect(r.exitCode, 1);
    final develop = await sha('develop');
    expect(develop, isNot(refs['refs/heads/develop']));
    expect(
      r.stderr,
      contains(
        'release: local develop holds commits origin/develop lacks:\n'
        '  ${develop.substring(0, 7)} local-only\n',
      ),
    );
    expect(stderrLines(r).where((l) => l.startsWith('git ')), isEmpty);
    expect(stderrLines(r).last, resolveLine);
    expect(await sha('main'), main);
    final after = await repo.originRefs();
    expect(after['refs/heads/main'], refs['refs/heads/main']);
    expect(after['refs/heads/develop'], refs['refs/heads/develop']);
  });

  test('f09/us04/fr03/e03: a rejected atomic push leaves both sides as they '
      'were', () async {
    await rejectPushes('refs/heads/main');
    final main = await sha('main');
    final develop = await sha('develop');
    final refs = await repo.originRefs();

    final r = await repo.release(['0.2.0']);

    expect(r.exitCode, 1);
    expect(r.stderr, contains('git push --atomic origin main develop'));
    expect(stderrLines(r).last, resolveLine);
    final after = await repo.originRefs();
    expect(after['refs/heads/main'], refs['refs/heads/main']);
    expect(after['refs/heads/develop'], refs['refs/heads/develop']);
    expect(after, contains('refs/tags/v0.2.0'));
    expect(await sha('main'), main);
    expect(await sha('develop'), develop);
    expect(await repo.git(['branch', '--list', 'release/0.2.0']), isNotEmpty);
    expect(await repo.git(['status', '--porcelain']), isEmpty);
  });

  test('f09/us04/fr03: main moved and develop ahead at once reports the main '
      'check only', () async {
    final r = await repo.release(
      ['0.2.0'],
      gh: {
        'GH_STUB_ON_WATCH':
            '${repo.pushFromOtherCloneCommand('main')} && '
            '${localDevelopCommit()}',
      },
    );

    expect(r.exitCode, 1);
    expect(r.stderr, contains('a second release reached main'));
    expect(r.stderr, isNot(contains('develop holds commits')));
  });

  group('first-run checks', () {
    test('f09/us04/fr01: a modified tracked file keeps its porcelain status '
        'column', () async {
      await File('${repo.work.path}/plugin/.claude-plugin/plugin.json')
          .writeAsString('{"version": "0.1.0"}\n');
      before = await repo.state();

      final r = await repo.release(['0.2.0']);

      await expectRefusal(r, ['\n M plugin/.claude-plugin/plugin.json']);
    });

    test('f09/us04/fr01: an empty ci run list refuses', () async {
      final r = await repo.release(['0.2.0'], gh: {'GH_STUB_CI': 'empty'});

      await expectRefusal(r, ['ci run']);
    });

    test('f09/us04/fr01: gh output that is not JSON refuses', () async {
      final r = await repo.release(['0.2.0'], gh: {'GH_STUB_CI': 'garbage'});

      await expectRefusal(r, ['no JSON']);
    });

    test('f09/us04/fr01: gh missing from PATH refuses naming gh', () async {
      final bin = Directory('${repo.root.path}/only_git')..createSync();
      final which = await Process.run('which', ['git']);
      Link('${bin.path}/git').createSync((which.stdout as String).trim());

      final r = await repo.release(['0.2.0'], gh: {'PATH': bin.path});

      await expectRefusal(r, ['gh is not available']);
    });

    test('f09/us04/fr01: a gh failure other than not logged in quotes its '
        'first stderr line and does not name gh auth login', () async {
      final r = await repo.release(['0.2.0'], gh: {'GH_STUB_AUTH': 'broken'});

      await expectRefusal(r, ['gh: network down']);
      expect(r.stderr, isNot(contains('gh auth login')));
    });

    test('f09/us04/fr01: checks run in the order of the contract', () async {
      // Each case holds two failures; the earlier check in the contract wins.
      await File('${repo.work.path}/stray.txt').writeAsString('x');
      before = await repo.state();
      var r = await repo.release(['v1'], gh: {'GH_STUB_CI': 'failure'});
      await expectRefusal(r, ['not clean']);

      await File('${repo.work.path}/stray.txt').delete();
      before = await repo.state();
      r = await repo.release(['v1'], gh: {'GH_STUB_CI': 'failure'});
      await expectRefusal(r, ['failure']);

      r = await repo.release(['v1']);
      await expectRefusal(r, ['MAJOR.MINOR.PATCH']);
    });

    test('f09/us04/fr01: a run from a subfolder finds the repo root', () async {
      final r = await Process.run(
        Platform.resolvedExecutable,
        ['run', '../../tool/release.dart', '0.2.0', '--dry-run'],
        workingDirectory: '${repo.work.path}/packages/specstone',
        environment: {
          'PATH':
              '${repo.root.path}/stubs:${Platform.environment['PATH'] ?? ''}',
        },
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
    });
  });

  group('hardening', () {
    test(
      'f09/us04/fr02: a missing spot file refuses before anything is cut',
      () async {
        await repo.git(['rm', '-q', 'plugin/.claude-plugin/plugin.json']);
        await repo.git(['commit', '-q', '-m', 'drop plugin.json']);
        await repo.git(['push', '-q', 'origin', 'develop']);
        before = await repo.state();

        final r = await repo.release(['0.2.0']);

        await expectRefusal(r, ['release: plugin/.claude-plugin/plugin.json']);
      },
    );

    test(
      'f09/us04/fr01: a suffixed specstoneVersion is not a version',
      () async {
        repo = await createReleaseRepo(
          files: {
            'packages/specstone_core/lib/src/version.dart':
                "const String specstoneVersion = '0.1.0-beta';\n",
          },
        );
        before = await repo.state();

        final r = await repo.release(['0.2.0']);

        await expectRefusal(r, ['holds no specstoneVersion constant']);
      },
    );

    test('f09/us04/fr01: origin/main holding commits develop lacks refuses '
        'naming them', () async {
      await repo.pushFromOtherClone('main');
      final other = (await repo.originRefs())['refs/heads/main']!;
      before = await repo.state();

      final r = await repo.release(['0.2.0']);

      await expectRefusal(r, [
        'origin/main holds commits develop lacks',
        '  ${other.substring(0, 7)} other',
      ]);
    });

    test(
      'f09/us04/fr02: a run that is not listed yet is polled again',
      () async {
        final r = await repo.release(['0.2.0'], gh: {'GH_STUB_RUN_LATE': '1'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          repo.ghCalls().where(
            (c) => c.startsWith('run list --workflow release'),
          ),
          hasLength(2),
        );
      },
    );

    test('f09/us04/fr02: the wait names the run it watches', () async {
      final r = await repo.release(['0.2.0']);

      expect(
        r.stdout,
        contains(
          'Waiting for the release.yaml run of v0.2.0: '
          'https://github.com/nontravis/specstone/actions/runs/123456789\n',
        ),
      );
    });

    for (final view in ['broken']) {
      test('f09/us04/fr03: a failed gh run watch whose run is not read as '
          'failed ($view) exits 1 and moves nothing', () async {
        final refs = await repo.originRefs();

        final r = await repo.release(
          ['0.2.0'],
          gh: {'GH_STUB_RUN': 'failure', 'GH_STUB_VIEW': view},
        );

        expect(r.exitCode, 1);
        expect(
          repo.ghCalls().last,
          'run view 123456789 --json status,conclusion',
        );
        expect(stderrLines(r).last, resolveLine);
        expect(r.stderr, isNot(contains('failed: https')));
        final after = await repo.originRefs();
        expect(after['refs/heads/main'], refs['refs/heads/main']);
        expect(after['refs/heads/develop'], refs['refs/heads/develop']);
      });
    }

    test('f09/us04/fr03: a failing gh run watch falls back to polling the run '
        'and lands once it succeeds', () async {
      final r = await repo.release(
        ['0.2.0'],
        gh: {
          'GH_STUB_RUN': 'failure',
          'GH_STUB_VIEW': 'later_success',
          'GH_STUB_RELEASE': 'present',
        },
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        repo.ghCalls().where((c) => c.startsWith('run view')),
        hasLength(2),
      );
      final refs = await repo.originRefs();
      expect(refs['refs/heads/main'], refs['refs/tags/v0.2.0']);
    });

    test('f09/us04/fr02: --dry-run refuses a missing spot too', () async {
      await repo.git(['rm', '-q', 'plugin/.claude-plugin/plugin.json']);
      await repo.git(['commit', '-q', '-m', 'drop plugin.json']);
      await repo.git(['push', '-q', 'origin', 'develop']);
      before = await repo.state();

      final r = await repo.release(['0.2.0', '--dry-run']);

      await expectRefusal(r, ['release: plugin/.claude-plugin/plugin.json']);
    });

    test('f09/us04/fr03: a failed branch cleanup after the landing exits 0 '
        'and says so', () async {
      final hook = File('${repo.origin.path}/hooks/pre-receive');
      await hook.writeAsString(
        '#!/bin/sh\n'
        'while read old new ref; do\n'
        '  case "\$new" in\n'
        '    *[!0]*) ;;\n'
        '    *) echo "delete of \$ref refused" >&2; exit 1;;\n'
        '  esac\n'
        'done\n',
      );
      await Process.run('chmod', ['+x', hook.path]);

      final r = await repo.release(
        ['0.2.0'],
        gh: {
          'GH_STUB_ON_WATCH':
              "git -C '${repo.work.path}' push -q origin release/0.2.0",
        },
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        (r.stdout as String).trimRight().split('\n').last,
        startsWith('Released v0.2.0: '),
      );
      expect(r.stderr, contains('release: could not delete release/0.2.0:'));
      final refs = await repo.originRefs();
      expect(refs['refs/heads/main'], refs['refs/tags/v0.2.0']);
    });
  });
}
