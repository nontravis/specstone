@TestOn('!windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/version_cases.dart';
import '../helpers/release_repo.dart';

const _check =
    'install_update/version_match/release_new_version/check_before_release';
const _bump =
    'install_update/version_match/release_new_version/bump_and_push_tag';
const _land =
    'install_update/version_match/release_new_version/merge_after_publish';
const _rerun =
    'install_update/version_match/release_new_version/'
    'rerun_from_release_branch';
const fetchLine =
    'fetch origin; check origin/main and local develop before moving any ref';
const fastForwardLine =
    'fast-forward main to v0.2.0; fast-forward develop to origin/develop; '
    'merge release/0.2.0 into develop';
const preFetchLine = 'fetch origin; check local develop before moving any ref';
const preFastForwardLine =
    'fast-forward develop to origin/develop; '
    'merge release/0.2.0-beta.1 into develop';
const prePushLine =
    'push develop alone; main stays where it is; '
    'delete release/0.2.0-beta.1';
const List<String> preLandingLines = [
  preFetchLine,
  preFastForwardLine,
  prePushLine,
];
const preReleased =
    'Released v0.2.0-beta.1: '
    'https://github.com/nontravis/specstone/releases/tag/v0.2.0-beta.1; '
    'develop pushed';

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

  test('$_check E09: a pre-release --dry-run prints the first-run steps and '
      'the three develop-only landing lines', () async {
    final r = await repo.release(['0.2.0-beta.1', '--dry-run']);

    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(
      r.stdout,
      [
        'create release/0.2.0-beta.1 from develop',
        'set 0.2.0-beta.1 in the five version spots',
        're-read the five spots; run dart pub get --enforce-lockfile',
        'commit "chore: release 0.2.0-beta.1"; tag v0.2.0-beta.1 on it',
        'push tag v0.2.0-beta.1',
        'wait for the release.yaml run of v0.2.0-beta.1',
        ...preLandingLines,
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
      'give a version of the form MAJOR.MINOR.PATCH[-<pre-release>] above '
      'it\n',
    );
    expect(await repo.state(), before);
  });

  // L5: no argv can carry NUL, the OS cuts the argument there, so the
  // in-process parse alone refuses a NUL entry (Task 2's tests).
  test('$_check E01: every refused version refuses naming the form and the '
      'current version', () async {
    for (final bad in refusedVersions.where((v) => !v.contains('\u0000'))) {
      final r = await repo.release([bad]);

      final label = jsonEncode(bad);
      expect(r.exitCode, 1, reason: label);
      expect(
        r.stderr,
        contains('MAJOR.MINOR.PATCH[-<pre-release>]'),
        reason: label,
      );
      expect(r.stderr, contains('current version is 0.1.0'), reason: label);
      expect(await repo.state(), before, reason: label);
    }
  });

  test('$_check E07: a pre-release above the current version passes '
      '--dry-run and changes nothing', () async {
    final r = await repo.release(['0.2.0-beta.1', '--dry-run']);

    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(await repo.state(), before);
  });

  test('$_check E08: the next version of a pre-release is above it in the '
      'Version order', () async {
    final pre = await createReleaseRepo(version: '0.2.0-beta.1');
    final preBefore = await pre.state();

    for (final next in ['0.2.0-beta.2', '0.2.0-rc.1', '0.2.0']) {
      final r = await pre.release([next, '--dry-run']);

      expect(r.exitCode, 0, reason: '$next: ${r.stderr}');
    }
    for (final below in ['0.2.0-beta.1', '0.2.0-alpha.1', '0.1.1']) {
      final r = await pre.release([below]);

      expect(r.exitCode, 1, reason: below);
      expect(r.stderr, contains('current version 0.2.0-beta.1'), reason: below);
    }
    expect(await pre.state(), preBefore);
  });

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

  const resolveBeta =
      'Resolve it, then run dart run tool/release.dart 0.2.0-beta.1 again '
      'from release/0.2.0-beta.1';

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
        'api repos/{owner}/{repo}/actions/runs?head_sha=$tagged&event=push';
    expect(repo.ghCalls().skip(1), [
      runList,
      'run watch 123456789 --exit-status',
      'release view v0.2.0 --json url --jq .url',
    ]);
    expect(await repo.git(['branch', '--show-current']), 'develop');
  });

  test('$_bump E01, INV-1: a pre-release tags a commit that changes the four '
      'files and leaves the root pubspec alone', () async {
    final r = await repo.release(['0.2.0-beta.1']);

    expect(r.exitCode, 0, reason: '${r.stderr}');
    final tagged = (await repo.originRefs())['refs/tags/v0.2.0-beta.1']!;
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
    expect(
      await repo.git([
        'diff',
        '--name-only',
        '$tagged~1',
        tagged,
        '--',
        'pubspec.yaml',
      ]),
      isEmpty,
    );
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
dependencies:
  specstone_core:
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
    // The watch output streams to the terminal ahead of the tool's own line.
    expect(r.stderr, startsWith('release.yaml failed\n'));
    expect(
      r.stderr,
      endsWith(
        'release: the release.yaml run of v0.2.0 failed: '
        'https://github.com/nontravis/specstone/actions/runs/123456789; '
        'main and develop are untouched. Fix on release/0.2.0, then run '
        'dart run tool/release.dart 0.2.0 from that branch\n',
      ),
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

  test('release_new_version S11, $_land E07: a pre-release lands develop '
      'alone and never writes main', () async {
    final main = await sha('main');
    final originMain = (await repo.originRefs())['refs/heads/main'];

    final r = await repo.release(['0.2.0-beta.1']);

    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect((r.stdout as String).trimRight().split('\n').last, preReleased);
    expect(await sha('main'), main);
    final refs = await repo.originRefs();
    expect(refs['refs/heads/main'], originMain);
    final tagged = refs['refs/tags/v0.2.0-beta.1']!;
    expect(refs['refs/heads/develop'], await sha('develop'));
    // Throws when the tag is not an ancestor.
    await repo.git([
      'merge-base',
      '--is-ancestor',
      tagged,
      refs['refs/heads/develop']!,
    ]);
    expect(refs.keys.where((k) => k.contains('release/')), isEmpty);
    expect(await repo.git(['branch', '--list', 'release/*']), isEmpty);
    expect(repo.ghCalls().skip(1), [
      'api repos/{owner}/{repo}/actions/runs?head_sha=$tagged&event=push',
      'run watch 123456789 --exit-status',
      'release view v0.2.0-beta.1 --json url --jq .url',
    ]);
    expect(await repo.git(['branch', '--show-current']), 'develop');
  });

  test('$_land E07: an origin/main that moved during the wait stops a '
      'pre-release nothing', () async {
    final main = await sha('main');

    final r = await repo.release(
      ['0.2.0-beta.1'],
      gh: {'GH_STUB_ON_WATCH': repo.pushFromOtherCloneCommand('main')},
    );

    expect(r.exitCode, 0, reason: '${r.stderr}');
    final refs = await repo.originRefs();
    final otherMain = await repo.git(['rev-parse', 'origin/main']);
    expect(refs['refs/heads/main'], otherMain);
    expect(otherMain, isNot(main));
    expect(await sha('main'), main);
    expect(refs.keys.where((k) => k.contains('release/')), isEmpty);
    await repo.git([
      'merge-base',
      '--is-ancestor',
      refs['refs/tags/v0.2.0-beta.1']!,
      refs['refs/heads/develop']!,
    ]);
  });

  test('$_land E08: a rejected push of develop resets local develop and '
      'keeps the release branch', () async {
    await rejectPushes('refs/heads/develop');
    final main = await sha('main');
    final develop = await sha('develop');
    final refs = await repo.originRefs();

    final r = await repo.release(['0.2.0-beta.1']);

    expect(r.exitCode, 1);
    expect(r.stderr, contains('git push origin develop'));
    expect(stderrLines(r).last, resolveBeta);
    final after = await repo.originRefs();
    expect(after['refs/heads/main'], refs['refs/heads/main']);
    expect(after['refs/heads/develop'], refs['refs/heads/develop']);
    expect(after, contains('refs/tags/v0.2.0-beta.1'));
    expect(await sha('main'), main);
    expect(await sha('develop'), develop);
    expect(
      await repo.git(['branch', '--list', 'release/0.2.0-beta.1']),
      isNotEmpty,
    );
    expect(await repo.git(['status', '--porcelain']), isEmpty);
  });

  test('$_land E09: a full release from a develop holding a pre-release '
      'moves main and develop in the atomic push', () async {
    final pre = await createReleaseRepo(version: '0.2.0-beta.1');

    final r = await pre.release(['0.2.0']);

    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(
      (r.stdout as String).trimRight().split('\n').last,
      'Released v0.2.0: '
      'https://github.com/nontravis/specstone/releases/tag/v0.2.0; '
      'main and develop pushed',
    );
    final refs = await pre.originRefs();
    final tagged = refs['refs/tags/v0.2.0']!;
    expect(refs['refs/heads/main'], tagged);
    await pre.git([
      'merge-base',
      '--is-ancestor',
      tagged,
      refs['refs/heads/develop']!,
    ]);
    expect(refs.keys.where((k) => k.contains('release/')), isEmpty);
  });

  test('$_land E05: local develop ahead of origin/develop refuses a '
      'pre-release too', () async {
    final main = await sha('main');
    final refs = await repo.originRefs();

    final r = await repo.release(
      ['0.2.0-beta.1'],
      gh: {'GH_STUB_ON_WATCH': localDevelopCommit()},
    );

    expect(r.exitCode, 1);
    final develop = await sha('develop');
    expect(
      r.stderr,
      contains(
        'release: local develop holds commits origin/develop lacks:\n'
        '  ${develop.substring(0, 7)} local-only\n',
      ),
    );
    expect(stderrLines(r).where((l) => l.startsWith('git ')), isEmpty);
    expect(stderrLines(r).last, resolveBeta);
    expect(await sha('main'), main);
    final after = await repo.originRefs();
    expect(after['refs/heads/main'], refs['refs/heads/main']);
    expect(after['refs/heads/develop'], refs['refs/heads/develop']);
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

    test('$_check: a pre-release specstoneVersion literal is the current '
        'version', () async {
      repo = await createReleaseRepo(
        files: {
          'packages/specstone_core/lib/src/version.dart':
              "const String specstoneVersion = '0.1.0-beta';\n",
        },
      );
      before = await repo.state();

      final r = await repo.release(['0.2.0', '--dry-run']);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(await repo.state(), before);
    });

    test('$_check: a specstoneVersion literal outside the form is no '
        'version', () async {
      repo = await createReleaseRepo(
        files: {
          'packages/specstone_core/lib/src/version.dart':
              "const String specstoneVersion = '0.1.0-beta.01';\n",
        },
      );
      before = await repo.state();

      final r = await repo.release(['0.2.0']);

      await expectRefusal(r, ['holds no specstoneVersion constant']);
    });

    test('$_check: a specstoneVersion literal with a NUL after the version is '
        'no version', () async {
      repo = await createReleaseRepo(
        files: {
          'packages/specstone_core/lib/src/version.dart':
              "const String specstoneVersion = '0.1.0\u0000';\n",
        },
      );
      before = await repo.state();

      final r = await repo.release(['0.2.0']);

      await expectRefusal(r, ['holds no specstoneVersion constant']);
    });

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
            (c) => c.startsWith('api repos/{owner}/{repo}/actions/runs'),
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

    for (final view in ['broken', 'cancelled', 'garbage']) {
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

  group('run again from the release branch', () {
    late String tagBefore;

    setUp(() async {
      final first = await repo.release(
        ['0.2.0'],
        gh: {'GH_STUB_RUN': 'failure'},
      );
      expect(first.exitCode, 1);
      tagBefore = (await repo.originRefs())['refs/tags/v0.2.0']!;
    });

    test('f09/us04/fr04, f09/us04/s4: the tag moves to the fix and the '
        'release lands', () async {
      await repo.commitFile('fix.txt', 'fixed\n', 'fix: the release');
      final fix = await sha('HEAD');

      final r = await repo.release(['0.2.0']);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      final refs = await repo.originRefs();
      expect(refs['refs/tags/v0.2.0'], fix);
      expect(refs['refs/heads/main'], fix);
      expect(refs.keys.where((k) => k.contains('release/')), isEmpty);
      expect(
        repo.ghCalls(),
        containsAllInOrder([
          'auth status',
          'release view v0.2.0 --json url --jq .url',
          'api repos/{owner}/{repo}/actions/runs?head_sha=$fix&event=push',
        ]),
      );
    });

    test('f09/us04/fr04/e01, f09/us04/fr03/e06, INV-5: a run again with the '
        'Release published only lands', () async {
      final firstCalls = repo.ghCalls().length;

      final r = await repo.release(
        ['0.2.0'],
        gh: {'GH_STUB_RELEASE': 'present'},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      final calls = repo.ghCalls().skip(firstCalls);
      expect(calls.where((c) => c.startsWith('run watch')), isEmpty);
      expect(
        calls.where((c) => c.contains('--workflow release.yaml')),
        isEmpty,
      );
      final refs = await repo.originRefs();
      expect(refs['refs/tags/v0.2.0'], tagBefore);
      expect(refs['refs/heads/main'], tagBefore);
      expect(refs.keys.where((k) => k.contains('release/')), isEmpty);
      expect(await repo.git(['branch', '--list', 'release/0.2.0']), isEmpty);
    });

    test('f09/us04/fr04: a run of the tag still in progress is awaited, and '
        'the tag stays', () async {
      await repo.commitFile('fix.txt', 'fixed\n', 'fix: the release');
      final firstCalls = repo.ghCalls().length;

      final r = await repo.release(
        ['0.2.0'],
        gh: {'GH_STUB_RUN_STATE': 'in_progress'},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        repo.ghCalls().skip(firstCalls).where((c) => c.startsWith('run watch')),
        isNotEmpty,
      );
      final refs = await repo.originRefs();
      expect(refs['refs/tags/v0.2.0'], tagBefore);
      expect(refs['refs/heads/main'], tagBefore);
      expect(
        r.stdout,
        contains(
          'v0.2.0 at $tagBefore is still being released; commits made on '
          'release/0.2.0 since then ship with the next version.\n',
        ),
      );
    });

    test('f09/us04/fr04: a run in progress on the tag at HEAD is awaited '
        'with no note about later commits', () async {
      final r = await repo.release(
        ['0.2.0'],
        gh: {'GH_STUB_RUN_STATE': 'in_progress'},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, isNot(contains('still being released')));
      expect((await repo.originRefs())['refs/heads/main'], tagBefore);
    });

    test('f09/us04/fr04: a local tag unlike the one on origin refuses before '
        'any ref moves', () async {
      await repo.commitFile('fix.txt', 'fixed\n', 'fix: the release');
      await repo.git(['tag', '-f', 'v0.2.0', 'HEAD']);
      final local = await sha('HEAD');
      final mid = await repo.state();

      final r = await repo.release(
        ['0.2.0'],
        gh: {'GH_STUB_RUN_STATE': 'in_progress'},
      );

      expect(r.exitCode, 1);
      expect(r.stderr, contains(local));
      expect(r.stderr, contains(tagBefore));
      expect(await repo.state(), mid);
    });

    test('f09/us04/fr04: --dry-run with a run in progress prints the wait '
        'and the landing', () async {
      final mid = await repo.state();

      final r = await repo.release(
        ['0.2.0', '--dry-run'],
        gh: {'GH_STUB_RUN_STATE': 'in_progress'},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        r.stdout,
        [
          'wait for the release.yaml run of v0.2.0',
          fetchLine,
          fastForwardLine,
          'push main and develop in one atomic push; delete release/0.2.0',
        ].map((l) => '$l\n').join(),
      );
      expect(await repo.state(), mid);
    });

    test('f09/us04/fr04: a tag already at HEAD whose run failed refuses '
        'early', () async {
      final mid = await repo.state();

      final r = await repo.release(
        ['0.2.0'],
        gh: {'GH_STUB_RUN_STATE': 'completed', 'GH_STUB_RUN': 'failure'},
      );

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        contains(
          'release: v0.2.0 already points at HEAD and its run failed; '
          'commit a fix or re-run the workflow',
        ),
      );
      expect(await repo.state(), mid);
    });

    test('f09/us04/fr04: a refused push of the release branch says how to run '
        'again once', () async {
      await repo.commitFile('fix.txt', 'fixed\n', 'fix: the release');
      await rejectPushes('refs/heads/release/*');
      final mid = await repo.state();

      final r = await repo.release(['0.2.0']);

      expect(r.exitCode, 1);
      expect(r.stderr, contains('main and develop are untouched\n'));
      expect(
        stderrLines(r).where((l) => l.startsWith('Resolve it, then')),
        hasLength(1),
      );
      expect(r.stderr, isNot(contains('untouched. run')));
      expect(await repo.state(), mid);
    });

    test('f09/us04/fr04/e05: the fixed tag failing again leaves main and '
        'develop untouched', () async {
      await repo.commitFile('fix.txt', 'fixed\n', 'fix: the release');
      final fix = await sha('HEAD');
      final refs = await repo.originRefs();

      final r = await repo.release(['0.2.0'], gh: {'GH_STUB_RUN': 'failure'});

      expect(r.exitCode, 1);
      expect(r.stderr, contains('the release.yaml run of v0.2.0 failed'));
      final after = await repo.originRefs();
      expect(after['refs/tags/v0.2.0'], fix);
      expect(after['refs/heads/main'], refs['refs/heads/main']);
      expect(after['refs/heads/develop'], refs['refs/heads/develop']);
    });

    test('f09/us04/fr03/e05: local develop ahead of origin/develop moves no '
        'ref and pushes nothing', () async {
      await repo.git(['switch', 'develop']);
      await repo.commitFile('local.txt', 'x\n', 'local: not pushed');
      final localSha = await repo.git(['rev-parse', '--short', 'HEAD']);
      await repo.git(['switch', 'release/0.2.0']);
      final mid = await repo.state();

      final r = await repo.release(
        ['0.2.0'],
        gh: {'GH_STUB_RELEASE': 'present'},
      );

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        contains('local develop holds commits origin/develop lacks:'),
      );
      expect(r.stderr, contains('  $localSha local: not pushed'));
      expect(stderrLines(r).where((l) => l.startsWith('git ')), isEmpty);
      expect(stderrLines(r).last, resolveLine);
      expect(await repo.state(), mid);
    });

    test(
      'f09/us04/fr04/e02: spots holding another version refuse naming it',
      () async {
        await repo.commitFile(
          'plugin/.claude-plugin/plugin.json',
          '{\n  "name": "specstone",\n  "version": "0.2.1"\n}\n',
          'chore: wrong version',
        );
        final mid = await repo.state();

        final r = await repo.release(['0.2.0']);

        expect(r.exitCode, 1);
        expect(r.stderr, contains('0.2.1'));
        expect(await repo.state(), mid);
      },
    );

    test('f09/us04/fr04/e03: another version than the branch refuses naming '
        'the branch version', () async {
      final mid = await repo.state();

      final r = await repo.release(['0.3.0']);

      expect(r.exitCode, 1);
      expect(r.stderr, contains('0.2.0'));
      expect(r.stderr, contains('pass 0.2.0 to release it again'));
      expect(r.stderr, contains('check out develop to release 0.3.0'));
      expect(await repo.state(), mid);
    });

    test('f09/us04/fr04: an unclean tree refuses', () async {
      File('${repo.work.path}/stray.txt').writeAsStringSync('x\n');
      final mid = await repo.state();

      final r = await repo.release(['0.2.0']);

      expect(r.exitCode, 1);
      expect(r.stderr, startsWith('release: the working tree is'));
      expect(await repo.state(), mid);
    });

    test('f09/us04/fr04: gh not logged in refuses', () async {
      final mid = await repo.state();

      final r = await repo.release(['0.2.0'], gh: {'GH_STUB_AUTH': 'none'});

      expect(r.exitCode, 1);
      expect(r.stderr, contains('gh is not logged in'));
      expect(await repo.state(), mid);
    });

    test('f09/us04/fr04: a gh that fails reading the Release does not move '
        'the tag', () async {
      final mid = await repo.state();

      final r = await repo.release(
        ['0.2.0'],
        gh: {'GH_STUB_RELEASE': 'broken'},
      );

      expect(r.exitCode, 1);
      expect(r.stderr, contains('gh failed (reading the Release v0.2.0)'));
      expect(await repo.state(), mid);
    });

    test('f09/us04/fr04/e04: develop moved since the first run is no '
        'refusal', () async {
      final other = await repo.pushFromOtherClone('develop');
      await repo.commitFile('fix.txt', 'fixed\n', 'fix: the release');
      final fix = await sha('HEAD');

      final r = await repo.release(['0.2.0']);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      await repo.git(['fetch', 'origin']);
      expect(
        await repo.git([
          'merge-base',
          '--is-ancestor',
          other,
          'origin/develop',
        ]),
        isEmpty,
      );
      expect(
        await repo.git(['merge-base', '--is-ancestor', fix, 'origin/develop']),
        isEmpty,
      );
    });

    test('f09/us04/fr04: --dry-run prints the run-again steps and changes '
        'nothing', () async {
      final mid = await repo.state();

      final r = await repo.release(['0.2.0', '--dry-run']);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        r.stdout,
        [
          'push release/0.2.0',
          'move tag v0.2.0 to the head of release/0.2.0; push it',
          'wait for the release.yaml run of v0.2.0',
          fetchLine,
          fastForwardLine,
          'push main and develop in one atomic push; delete release/0.2.0',
        ].map((l) => '$l\n').join(),
      );
      expect(await repo.state(), mid);
    });

    test('f09/us04/fr04: --dry-run with the Release published prints the '
        'landing only', () async {
      final mid = await repo.state();

      final r = await repo.release(
        ['0.2.0', '--dry-run'],
        gh: {'GH_STUB_RELEASE': 'present'},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        r.stdout,
        [
          fetchLine,
          fastForwardLine,
          'push main and develop in one atomic push; delete release/0.2.0',
        ].map((l) => '$l\n').join(),
      );
      expect(await repo.state(), mid);
    });
  });

  group('$_rerun: a pre-release', () {
    setUp(() async {
      final first = await repo.release(
        ['0.2.0-beta.1'],
        gh: {'GH_STUB_RUN': 'failure'},
      );
      expect(first.exitCode, 1);
    });

    test('$_rerun: a run again with the Release published lands develop '
        'alone', () async {
      final main = await sha('main');
      final originMain = (await repo.originRefs())['refs/heads/main'];
      final tagged = (await repo.originRefs())['refs/tags/v0.2.0-beta.1']!;

      final r = await repo.release(
        ['0.2.0-beta.1'],
        gh: {'GH_STUB_RELEASE': 'present'},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((r.stdout as String).trimRight().split('\n').last, preReleased);
      expect(await sha('main'), main);
      final refs = await repo.originRefs();
      expect(refs['refs/heads/main'], originMain);
      expect(refs['refs/tags/v0.2.0-beta.1'], tagged);
      await repo.git([
        'merge-base',
        '--is-ancestor',
        tagged,
        refs['refs/heads/develop']!,
      ]);
      expect(refs.keys.where((k) => k.contains('release/')), isEmpty);
      expect(await repo.git(['branch', '--list', 'release/*']), isEmpty);
    });

    test('$_rerun: --dry-run with the Release published prints the three '
        'develop-only landing lines', () async {
      final mid = await repo.state();

      final r = await repo.release(
        ['0.2.0-beta.1', '--dry-run'],
        gh: {'GH_STUB_RELEASE': 'present'},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(r.stdout, preLandingLines.map((l) => '$l\n').join());
      expect(await repo.state(), mid);
    });

    test('$_rerun: --dry-run without the Release prints the tag move, the '
        'wait, and the develop-only landing', () async {
      final mid = await repo.state();

      final r = await repo.release(['0.2.0-beta.1', '--dry-run']);

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        r.stdout,
        [
          'push release/0.2.0-beta.1',
          'move tag v0.2.0-beta.1 to the head of release/0.2.0-beta.1; push it',
          'wait for the release.yaml run of v0.2.0-beta.1',
          ...preLandingLines,
        ].map((l) => '$l\n').join(),
      );
      expect(await repo.state(), mid);
    });
  });
}
