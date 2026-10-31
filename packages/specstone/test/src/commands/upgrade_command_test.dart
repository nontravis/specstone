import 'dart:async';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/upgrade_command.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

/// Joins its arguments with `/`, which every platform's `dart:io` accepts.
String _join(String first, [String? b, String? c, String? d]) =>
    [first, ?b, ?c, ?d].join('/');

void main() {
  late HttpServer server;
  late Uri base;
  late int requests;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    requests = 0;
    out = StringBuffer();
    err = StringBuffer();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}/');
    server.listen((request) {
      requests++;
      request.response.statusCode = HttpStatus.notFound;
      unawaited(request.response.close());
    });
  });

  tearDown(() => server.close(force: true));

  SpecstoneCommandRunner runnerFor(
    String executable,
    Map<String, String> env, {
    bool windows = false,
    Directory? workingDirectory,
  }) => SpecstoneCommandRunner(
    out: out,
    err: err,
    workingDirectory: workingDirectory,
    upgrade: UpgradeCommand(
      scriptBase: base,
      executable: executable,
      environment: env,
      windows: windows,
    ),
  );

  Future<File> makeExecutable(Directory folder) async {
    await folder.create(recursive: true);
    final file = File(_join(folder.path, 'specstone'));
    await file.writeAsString('');
    return file;
  }

  test('f09/us02/fr01/e02, f09/us02/s4: a binary outside ~/.specstone/bin '
      'refuses install_not_managed, exit 78, before any request', () async {
    final root = await writeTree({});
    final tools = Directory(_join(root.path, 'opt', 'tools'));
    final exe = await makeExecutable(tools);
    final runner = runnerFor(exe.path, {'HOME': _join(root.path, 'home')});

    expect(await runner.run(['upgrade']), 78);
    expect(
      err.toString(),
      'specstone upgrade updates only a CLI installed in ~/.specstone/bin; '
      'this one runs from ${tools.path}\n',
    );
    expect(requests, 0);
    expect(out.toString(), isEmpty);
  });

  test(
    'f09/us02/fr01/e01: the Dart VM of a checkout refuses, exit 78',
    () async {
      final root = await writeTree({});
      final runner = runnerFor(Platform.resolvedExecutable, {
        'HOME': _join(root.path, 'home'),
      });

      expect(await runner.run(['upgrade']), 78);
      expect(
        err.toString(),
        contains(File(Platform.resolvedExecutable).parent.path),
      );
      expect(requests, 0);
    },
  );

  test(
    'f09/us02/fr01/e03: no HOME and no USERPROFILE refuses, exit 78',
    () async {
      final root = await writeTree({});
      final tools = Directory(_join(root.path, 'opt', 'tools'));
      final exe = await makeExecutable(tools);
      final runner = runnerFor(exe.path, {});

      expect(await runner.run(['upgrade']), 78);
      expect(err.toString(), contains(tools.path));
      expect(err.toString(), contains('~/.specstone/bin'));
      expect(requests, 0);
    },
  );

  test('f09/us02/fr01/e04: an argument or an option is usage on err, '
      'exit 64', () async {
    final root = await writeTree({});
    final exe = await makeExecutable(Directory(_join(root.path, 'bin')));
    final runner = runnerFor(exe.path, {'HOME': root.path});

    expect(await runner.run(['upgrade', 'x']), usageExitCode);
    expect(err.toString(), contains('Usage:'));
    err.clear();
    expect(await runner.run(['upgrade', '--force']), usageExitCode);
    expect(err.toString(), contains('Usage:'));
    expect(requests, 0);
  });

  test('f09/us02/fr01: a binary in <home>/.specstone/bin passes the '
      'check', () async {
    final root = await writeTree({});
    final home = Directory(_join(root.path, 'home'));
    final exe = await makeExecutable(
      Directory(_join(home.path, '.specstone', 'bin')),
    );
    final runner = runnerFor(exe.path, {'HOME': home.path});

    expect(await runner.run(['upgrade']), isNot(78));
  });

  test('f09/us02/fr01: a home reached through a symlink passes', () async {
    final root = await writeTree({});
    final real = Directory(_join(root.path, 'real'));
    final exe = await makeExecutable(
      Directory(_join(real.path, '.specstone', 'bin')),
    );
    final link = Link(_join(root.path, 'link'))..createSync(real.path);
    final runner = runnerFor(exe.path, {'HOME': link.path});

    expect(await runner.run(['upgrade']), isNot(78));
  }, testOn: '!windows');

  test('f09/us02/fr01: Windows compares folders without case', () async {
    final root = await writeTree({});
    final home = Directory(_join(root.path, 'Home'));
    final exe = await makeExecutable(
      Directory(_join(home.path, '.specstone', 'bin')),
    );
    final runner = runnerFor(exe.path, {
      'USERPROFILE': home.path.toUpperCase(),
    }, windows: true);

    expect(await runner.run(['upgrade']), isNot(78));
  }, testOn: 'windows');

  test('f09/us02/fr01: upgrade loads no templates', () async {
    final root = await writeTree({'.specstone/config.yaml': 'pins: [\n'});
    final tools = Directory(_join(root.path, 'opt', 'tools'));
    final exe = await makeExecutable(tools);
    final runner = runnerFor(exe.path, {
      'HOME': _join(root.path, 'home'),
    }, workingDirectory: root);

    expect(await runner.run(['upgrade']), 78);
    expect(err.toString(), contains('~/.specstone/bin'));
  });
}
