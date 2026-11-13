@TestOn('!windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/shim_sandbox.dart';

void main() {
  // Every PATH a case passes holds /bin and /usr/bin: the recorders the shim
  // runs are /bin/sh scripts that call `cat`.
  const systemEntries = '/bin:/usr/bin';

  Directory dir(String path) => Directory(path)..createSync(recursive: true);

  test('run_cli_or_yield S1: no other stn runs the specstone beside it, '
      'passing argv, stdin, PATH, and no guard, exit 0', () async {
    final sb = await createShimSandbox();
    final path = '${sb.bin.path}:$systemEntries';

    final r = await sb.runStn(
      ['check', 'docs/prds'],
      path: path,
      stdinText: 'hello\n',
    );

    expect(r.exitCode, 0);
    expect(sb.logOf('specstone'), [
      'argv',
      'check',
      'docs/prds',
      'stdin',
      'hello',
      'path',
      path,
      'guard',
      'unset',
    ]);
    expect(sb.logOf('other'), isEmpty);
  });

  test(
    "run_cli_or_yield S1: the exit status is the specstone run's, 3 here",
    () async {
      final sb = await createShimSandbox();

      final r = await sb.runStn(
        ['check'],
        path: '${sb.bin.path}:$systemEntries',
        extra: {'FAKE_EXIT': '3'},
      );

      expect(r.exitCode, 3);
    },
  );

  test(
    'run_cli_or_yield S1: arguments with spaces and quotes arrive as typed',
    () async {
      final sb = await createShimSandbox();

      final r = await sb.runStn([
        'a b',
        '"q"',
        "it's",
      ], path: '${sb.bin.path}:$systemEntries');

      expect(r.exitCode, 0);
      expect(sb.logOf('specstone'), [
        'argv',
        'a b',
        '"q"',
        "it's",
        'stdin',
        '',
        'path',
        '${sb.bin.path}:$systemEntries',
        'guard',
        'unset',
      ]);
    },
  );

  test('run_cli_or_yield S3: another stn on a later entry runs with the '
      'unchanged PATH and the guard set; the specstone does not run; the '
      "exit status is that stn's", () async {
    final sb = await createShimSandbox();
    final other = dir('${sb.root.path}/tools');
    sb.otherStn(other.path, exit: 7);
    final path = '${sb.bin.path}:${other.path}:$systemEntries';

    final r = await sb.runStn(['check'], path: path);

    expect(r.exitCode, 7);
    expect(sb.logOf('other'), [
      'argv',
      'check',
      'stdin',
      '',
      'path',
      path,
      'guard',
      '1',
    ]);
    expect(sb.logOf('specstone'), isEmpty);
  });

  test('run_cli_or_yield E01: the guard set runs the specstone beside it '
      'even with another stn on the PATH', () async {
    final sb = await createShimSandbox();
    final other = dir('${sb.root.path}/tools');
    sb.otherStn(other.path);
    final path = '${other.path}:${sb.bin.path}:$systemEntries';

    final r = await sb.runStn(
      ['check'],
      path: path,
      extra: {'SPECSTONE_STN_GUARD': '1'},
    );

    expect(r.exitCode, 0);
    expect(sb.logOf('specstone').sublist(0, 2), ['argv', 'check']);
    expect(sb.logOf('other'), isEmpty);
  });

  test('run_cli_or_yield E02: relative, dot, empty, and tilde entries are '
      'skipped even when each holds a stn', () async {
    final sb = await createShimSandbox();
    final relative = dir('${sb.root.path}/rel tools');
    sb.otherStn(relative.path);
    // A stn in the current folder for the empty and dot entries.
    sb.otherStn(sb.root.path);
    // Link the other stn under the sandbox root as a stn found by `~` would
    // be found only if `~` were expanded, which the walk never does.
    Process.runSync('ln', [
      '-s',
      '${relative.path}/stn',
      'tilde-stn',
    ], workingDirectory: sb.root.path);

    final r = await sb.runStn([
      'check',
    ], path: '${relative.path}/nested:rel:.::~:${sb.bin.path}:$systemEntries');

    expect(r.exitCode, 0);
    expect(sb.logOf('other'), isEmpty);
    expect(sb.logOf('specstone').sublist(0, 2), ['argv', 'check']);
  });

  test('run_cli_or_yield E08: the install folder on the PATH with a trailing '
      'slash or through a folder symlink is skipped, so a later stn runs and '
      'no loop forms', () async {
    final sb = await createShimSandbox();
    final other = dir('${sb.root.path}/tools');
    sb.otherStn(other.path, exit: 7);
    final linked = '${sb.root.path}/linked';
    Process.runSync('ln', ['-s', sb.bin.path, linked]);

    final withSlash = await sb.runStn([
      'check',
    ], path: '${sb.bin.path}/:${other.path}:$systemEntries');
    final throughLink = await sb.runStn([
      'check',
    ], path: '$linked:${other.path}:$systemEntries');

    expect(withSlash.exitCode, 7);
    expect(throughLink.exitCode, 7);
    // Both runs handed off to the other stn; neither looped into the shim
    // again, or the specstone log would hold two runs and the exits 0.
    expect(sb.logOf('other').where((line) => line == 'argv').length, 2);
    expect(sb.logOf('specstone'), isEmpty);
  });

  test('run_cli_or_yield E09: a folder and a non-executable file named stn '
      'are skipped; a symlink to an executable stn counts', () async {
    final sb = await createShimSandbox();
    final withDir = dir('${sb.root.path}/one/stn');
    final withPlain = dir('${sb.root.path}/two');
    File('${withPlain.path}/stn').writeAsStringSync('#!/bin/sh\nexit 5\n');
    final real = dir('${sb.root.path}/real');
    sb.otherStn(real.path, exit: 9);
    final linked = dir('${sb.root.path}/linked');
    Process.runSync('ln', ['-s', '${real.path}/stn', '${linked.path}/stn']);

    final skipped = await sb.runStn([
      'check',
    ], path: '${withDir.path}:${withPlain.path}:${sb.bin.path}:$systemEntries');
    final viaLink = await sb.runStn([
      'check',
    ], path: '${linked.path}:${sb.bin.path}:$systemEntries');

    expect(skipped.exitCode, 0);
    expect(sb.logOf('specstone').sublist(0, 2), ['argv', 'check']);
    expect(viaLink.exitCode, 9);
    expect(sb.logOf('other').sublist(0, 2), ['argv', 'check']);
    expect(viaLink.exitCode, isNot(0));
  });

  test('run_cli_or_yield E11 analogue: two runs in a row from one parent '
      'environment both hand off; the parent never holds the guard', () async {
    final sb = await createShimSandbox();
    final other = dir('${sb.root.path}/tools');
    sb.otherStn(other.path, exit: 4);
    final path = '${sb.bin.path}:${other.path}:$systemEntries';
    expect(Platform.environment[stnGuardVariable], isNull);

    final first = await sb.runStn(['one'], path: path);
    final second = await sb.runStn(['two'], path: path);

    expect(first.exitCode, 4);
    expect(second.exitCode, 4);
    expect(sb.logOf('other').where((line) => line == 'argv').length, 2);
    expect(sb.logOf('specstone'), isEmpty);
    expect(Platform.environment[stnGuardVariable], isNull);
  });

  test('review focus 1, 3: a spaced PATH entry holds one entry; no argument '
      'reaches the target as none', () async {
    final sb = await createShimSandbox();
    final other = dir('${sb.root.path}/space tools');
    sb.otherStn(other.path, exit: 2);

    final r = await sb.runStn([], path: '${other.path}:$systemEntries');

    expect(r.exitCode, 2);
    expect(sb.logOf('other'), [
      'argv',
      'stdin',
      '',
      'path',
      '${other.path}:$systemEntries',
      'guard',
      '1',
    ]);
  });

  test('review focus 4: stdin piped into stn reaches the target', () async {
    final sb = await createShimSandbox();
    final other = dir('${sb.root.path}/tools');
    sb.otherStn(other.path);

    final r = await sb.runStn(
      ['get'],
      path: '${other.path}:$systemEntries',
      stdinText: 'piped bytes\n',
    );

    expect(r.exitCode, 0);
    expect(sb.logOf('other').sublist(0, 4), [
      'argv',
      'get',
      'stdin',
      'piped bytes',
    ]);
  });

  test(
    'review focus 5: a missing absolute entry is skipped with empty stderr',
    () async {
      final sb = await createShimSandbox();
      final missing = '${sb.root.path}/no such folder';

      final r = await sb.runStn([
        'check',
      ], path: '$missing:${sb.bin.path}:$systemEntries');

      expect(r.exitCode, 0);
      expect(r.stderr, isEmpty);
      expect(sb.logOf('specstone').sublist(0, 2), ['argv', 'check']);
    },
  );
}
