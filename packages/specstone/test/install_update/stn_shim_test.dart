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

  test('stn runs the specstone beside it, '
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

  test("the exit status is the specstone run's, 3 here", () async {
    final sb = await createShimSandbox();

    final r = await sb.runStn(
      ['check'],
      path: '${sb.bin.path}:$systemEntries',
      extra: {'FAKE_EXIT': '3'},
    );

    expect(r.exitCode, 3);
  });

  test('arguments with spaces and quotes arrive as typed', () async {
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
  });

  test('another stn earlier on the PATH never runs', () async {
    final sb = await createShimSandbox();
    final other = dir('${sb.root.path}/tools');
    sb.otherStn(other.path, exit: 7);

    final r = await sb.runStn(
      ['check'],
      path: '${other.path}:${sb.bin.path}:$systemEntries',
      extra: {'FAKE_EXIT': '3'},
    );

    expect(r.exitCode, 3);
    expect(sb.logOf('specstone').sublist(0, 2), ['argv', 'check']);
    expect(sb.logOf('other'), isEmpty);
  });

  test('a link to stn in another folder runs the specstone beside the link, '
      'and a link folder without one fails in sh', () async {
    final sb = await createShimSandbox();
    final withSpecstone = dir('${sb.root.path}/linked');
    final without = dir('${sb.root.path}/bare');
    for (final folder in [withSpecstone, without]) {
      Process.runSync('ln', ['-s', '${sb.bin.path}/stn', '${folder.path}/stn']);
    }
    final recorder = File('${withSpecstone.path}/specstone')
      ..writeAsStringSync(
        '#!/bin/sh\nprintf "ran\\n" >> "\$STUB_LOG_DIR/linked.log"\n',
      );
    Process.runSync('chmod', ['755', recorder.path]);
    final environment = {
      'HOME': sb.home.path,
      'PATH': '${sb.bin.path}:$systemEntries',
      'STUB_LOG_DIR': sb.logs.path,
    };

    final reached = await Process.run(
      '/bin/sh',
      ['${withSpecstone.path}/stn', 'check'],
      environment: environment,
      includeParentEnvironment: false,
    );
    final missing = await Process.run(
      '/bin/sh',
      ['${without.path}/stn', 'check'],
      environment: environment,
      includeParentEnvironment: false,
    );

    expect(reached.exitCode, 0);
    expect(sb.logOf('linked'), ['ran']);
    expect(sb.logOf('specstone'), isEmpty);
    expect(missing.exitCode, 127);
    expect(missing.stderr, contains('specstone'));
    expect(sb.logOf('linked'), ['ran']);
    expect(sb.logOf('specstone'), isEmpty);
  });

  test('stdin piped into stn reaches the target', () async {
    final sb = await createShimSandbox();

    final r = await sb.runStn(
      ['get'],
      path: '${sb.bin.path}:$systemEntries',
      stdinText: 'piped bytes\n',
    );

    expect(r.exitCode, 0);
    expect(sb.logOf('specstone').sublist(0, 4), [
      'argv',
      'get',
      'stdin',
      'piped bytes',
    ]);
  });
}
