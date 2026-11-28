@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/shipped_pins.dart';
import '../helpers/package_root.dart';
import '../helpers/temp_tree.dart';

const _exitWithin = Duration(seconds: 2);

void main() {
  late String binary;

  setUpAll(() async {
    final out = await Directory.systemTemp.createTemp('specstone_notice_');
    addTearDown(() => out.delete(recursive: true));
    // Built like the CLI: `dart run` relinks the sqlite3 hook library, which
    // Windows cannot replace while the test process holds it.
    final build = await Process.run(Platform.resolvedExecutable, [
      'build',
      'cli',
      '-t',
      'test/helpers/notice_main.dart',
      '-o',
      out.path,
    ], workingDirectory: packageRoot().path);
    expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
    final name = Platform.isWindows ? 'notice_main.exe' : 'notice_main';
    binary = out.uri.resolve('bundle/bin/$name').toFilePath();
  });

  // Runs `folder` in a project with the notice on and returns how long the
  // process took to end once its stdout closed, and its exit status.
  Future<({Duration afterOutput, int status, String out})> run(
    String url, {
    Map<String, String> environment = const {},
  }) async {
    final home = await writeTree({'.specstone/bin/specstone': ''});
    final project = await writeTree({
      '.specstone/config.yaml': shippedPinsConfig(),
    });
    final process = await Process.start(
      binary,
      [url, home.path, 'folder'],
      workingDirectory: project.path,
      environment: environment,
    );
    final stderrDone = process.stderr.drain<void>();
    final out = await process.stdout.transform(utf8.decoder).join();
    final clock = Stopwatch()..start();
    final status = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await stderrDone;
    return (afterOutput: clock.elapsed, status: status, out: out);
  }

  test('a release site that accepts and never answers does not hold the '
      'process after its output', () async {
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(silent.close);
    silent.listen((socket) => socket.listen(null, onError: (Object _) {}));

    final result = await run('http://127.0.0.1:${silent.port}/');

    expect(result.status, 0);
    expect(result.afterOutput, lessThan(_exitWithin));
  });

  test('a release host that does not resolve does not hold the process after '
      'its output', () async {
    final result = await run('http://specstone-no-such-host.invalid/');

    expect(result.status, 0);
    expect(result.afterOutput, lessThan(_exitWithin));
  });

  test('the process ends with the command status whatever still holds the '
      'event loop', () async {
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(silent.close);
    silent.listen((socket) => socket.listen(null, onError: (Object _) {}));

    final result = await run(
      'http://127.0.0.1:${silent.port}/',
      environment: {'HANG': '1'},
    );

    expect(result.status, 0);
    expect(result.afterOutput, lessThan(_exitWithin));
  });
}
