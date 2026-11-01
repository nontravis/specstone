import 'dart:async';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/upgrade_command.dart';
import 'package:test/test.dart';

import '../../helpers/script_sandbox.dart';
import '../../helpers/temp_tree.dart';

/// Joins its arguments with `/`, which every platform's `dart:io` accepts.
String _join(String first, [String? b, String? c, String? d]) =>
    [first, ?b, ?c, ?d].join('/');

void main() {
  late HttpServer server;
  late Uri base;
  late int requests;
  late List<String> paths;
  late Future<void> Function(HttpRequest) handle;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    requests = 0;
    paths = [];
    handle = (request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    };
    out = StringBuffer();
    err = StringBuffer();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}/');
    server.listen((request) {
      requests++;
      paths.add(request.uri.path);
      unawaited(handle(request));
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
    expect(requests, 1);
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
    expect(requests, 1);
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
    expect(requests, 1);
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

  // A Windows run starts PowerShell and cmd, about 25 s on a busy CI runner,
  // which the default 30 s timeout cuts off.
  group('the install run', timeout: const Timeout(Duration(minutes: 2)), () {
    final windows = Platform.isWindows;
    const updateCommand = 'claude plugin update specstone@specstone';
    const restartLine = 'Restart Claude Code to load the new CLI and plugin.';
    late Directory root;
    late SpecstoneCommandRunner runner;
    late Uri scriptUrl;

    String fileIn(String folder, String name) => _join(root.path, folder, name);

    // Prepares a sandbox whose served script exits [scriptExit] and whose
    // `claude` stub exits [claudeExit]; [withClaude] false leaves it out.
    Future<void> prepare({
      int scriptExit = 0,
      int claudeExit = 0,
      bool withClaude = true,
      bool asWindows = false,
    }) async {
      final sandbox = await createScriptSandbox();
      root = sandbox.root;
      final exe = await makeExecutable(
        Directory(_join(sandbox.home.path, '.specstone', 'bin')),
      );
      final ran = fileIn('logs', 'ran');
      final claudeLog = fileIn('logs', 'claude.log');
      final script = asWindows || windows
          ? "Set-Content -Path '$ran' -Value \$PSCommandPath\n"
                'exit $scriptExit\n'
          : "printf '%s\\n' \"\$0\" > '$ran'\nexit $scriptExit\n";
      scriptUrl = base.resolve(
        asWindows || windows ? 'install.ps1' : 'install.sh',
      );
      handle = (request) async {
        request.response.write(script);
        await request.response.close();
      };
      if (withClaude) {
        if (windows) {
          await File(fileIn('stubs', 'claude.cmd')).writeAsString(
            '@echo off\r\n'
            'echo %*>> "$claudeLog"\r\n'
            'echo claude-out\r\n'
            'if "%CLAUDE_EXIT%"=="0" exit /b 0\r\n'
            'echo boom: offline 1>&2\r\n'
            'echo second line 1>&2\r\n'
            'exit /b %CLAUDE_EXIT%\r\n',
          );
        } else {
          final stub = File(fileIn('stubs', 'claude'));
          await stub.writeAsString(
            '#!/bin/sh\n'
            'echo "\$*" >> \'$claudeLog\'\n'
            'echo claude-out\n'
            'if [ "\$CLAUDE_EXIT" != 0 ]; then\n'
            "  printf '\\n  boom: offline \\r\\nsecond line\\n' >&2\n"
            '  exit "\$CLAUDE_EXIT"\n'
            'fi\n',
          );
          await Process.run('chmod', ['+x', stub.path]);
        }
      }
      final env = sandbox.env({'CLAUDE_EXIT': '$claudeExit'});
      runner = runnerFor(exe.path, env, windows: asWindows || windows);
    }

    List<String> claudeLog() =>
        File(fileIn('logs', 'claude.log'))
            .readAsLinesSync()
            .map((line) => line.trim())
            .toList();

    test('f09/us02/fr02, f09/us02/fr03, f09/us02/s1: the script runs from a '
        'temp file, then the plugin updates; restart is the last line; '
        'exit 0', () async {
      await prepare();

      expect(await runner.run(['upgrade']), 0);
      final ran = File(fileIn('logs', 'ran')).readAsStringSync().trim();
      expect(ran, endsWith(windows ? 'install.ps1' : 'install.sh'));
      expect(File(ran).existsSync(), isFalse);
      expect(claudeLog(), [updateCommand.substring('claude '.length)]);
      expect(out.toString(), contains('claude-out'));
      expect(out.toString().trimRight().split('\n').last, restartLine);
      expect(paths, [scriptUrl.path]);
    });

    test('f09/us02/fr02/e01, f09/us02/fr03/e01, f09/us02/s2: upgrade does '
        'not read the script output; an exit 0 leads to the plugin '
        'update', () async {
      await prepare();

      expect(await runner.run(['upgrade']), 0);
      expect(claudeLog(), hasLength(1));
      expect(out.toString().trimRight().split('\n').last, restartLine);
    });

    test(
      'f09/us02/fr02/e02, f09/us02/s5: no server refuses '
      'install_script_failed, exit 69, naming the URL; nothing ran',
      () async {
        await prepare();
        await server.close(force: true);

        expect(await runner.run(['upgrade']), 69);
        expect(err.toString(), contains('$scriptUrl'));
        expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
        expect(File(fileIn('logs', 'claude.log')).existsSync(), isFalse);
      },
    );

    test('f09/us02/fr02: a non-2xx reply refuses, exit 69, naming the '
        'status', () async {
      await prepare();
      handle = (request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      expect(await runner.run(['upgrade']), 69);
      expect(
        err.toString(),
        'specstone upgrade could not fetch $scriptUrl: HTTP 404\n',
      );
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
    });

    test('f09/us02/fr02: a reply cut short runs nothing, exit 69', () async {
      await prepare();
      handle = (request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 200 OK\r\nContent-Length: 4096\r\n\r\n0123456789',
        );
        await socket.flush();
        socket.destroy();
      };

      expect(await runner.run(['upgrade']), 69);
      expect(err.toString(), contains('could not fetch $scriptUrl'));
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
      expect(File(fileIn('logs', 'claude.log')).existsSync(), isFalse);
    });

    test('f09/us02/fr02/e03: a script exit 1 refuses, exit 69; no plugin '
        'step', () async {
      await prepare(scriptExit: 1);

      expect(await runner.run(['upgrade']), 69);
      expect(
        err.toString(),
        'specstone upgrade: $scriptUrl exited 1; '
        'the install is as the script left it\n',
      );
      expect(File(fileIn('logs', 'claude.log')).existsSync(), isFalse);
      expect(out.toString(), isNot(contains(restartLine)));
      final ran = File(fileIn('logs', 'ran')).readAsStringSync().trim();
      expect(File(ran).existsSync(), isFalse);
    });

    test('f09/us02/fr02/e04: a shell that cannot start refuses, exit 69, '
        'the install unchanged', () async {
      // Windows mode on a POSIX host: `powershell` is not on the PATH.
      await prepare(asWindows: true);

      expect(await runner.run(['upgrade']), 69);
      expect(
        err.toString(),
        allOf(
          startsWith(
            'specstone upgrade: could not start powershell for '
            '$scriptUrl: ',
          ),
          endsWith('; the install is unchanged\n'),
        ),
      );
      expect(File(fileIn('logs', 'claude.log')).existsSync(), isFalse);
    }, testOn: '!windows');

    test('f09/us02/fr03/e02, f09/us02/s3: no claude prints the update '
        'command, then restart; exit 0', () async {
      await prepare(withClaude: false);

      expect(await runner.run(['upgrade']), 0);
      final lines = out.toString().trimRight().split('\n');
      expect(lines, contains('To update the Specstone plugin, run:'));
      expect(lines, contains(updateCommand));
      expect(lines.last, restartLine);
    });

    test('f09/us02/fr03/e03: a failing plugin update names its first stderr '
        'line; exit 0', () async {
      await prepare(claudeExit: 1);

      expect(await runner.run(['upgrade']), 0);
      expect(
        err.toString(),
        'specstone: $updateCommand failed: boom: offline; run it by hand\n',
      );
      expect(out.toString().trimRight().split('\n').last, restartLine);
    });

    test('f09/us02/fr03/e03: a non-UTF-8 byte from claude does not crash; '
        'exit 0 with the result line', () async {
      await prepare();
      await File(fileIn('stubs', 'claude')).writeAsString(
        '#!/bin/sh\n'
        "printf 'bad \\377 byte\\n'\n",
      );

      expect(await runner.run(['upgrade']), 0);
      expect(out.toString(), contains('bad'));
      expect(out.toString().trimRight().split('\n').last, restartLine);
    }, testOn: '!windows');

    // Runs [body] with every timer 100 times shorter, so a 60 s idle timeout
    // fires in 600 ms.
    Future<T> fast<T>(Future<T> Function() body) => runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) =>
            parent.createTimer(zone, duration ~/ 100, callback),
      ),
    );

    test('f09/us02/fr02: a server that never answers refuses, exit 69, '
        'naming the URL; nothing ran', () async {
      await prepare();
      handle = (request) async {};

      expect(await fast(() => runner.run(['upgrade'])), 69);
      expect(
        err.toString(),
        'specstone upgrade could not fetch $scriptUrl: no data for 60 s\n',
      );
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
    });

    test('f09/us02/fr02: a body that stalls after one byte refuses, exit 69; '
        'nothing ran', () async {
      await prepare();
      handle = (request) async {
        request.response.bufferOutput = false;
        request.response.add([65]);
        await request.response.flush();
      };

      expect(await fast(() => runner.run(['upgrade'])), 69);
      expect(
        err.toString(),
        'specstone upgrade could not fetch $scriptUrl: no data for 60 s\n',
      );
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
    });

    test(
      'f09/us02/fr02: an error reply that stalls refuses, exit 69',
      () async {
        await prepare();
        handle = (request) async {
          request.response.statusCode = HttpStatus.badGateway;
          request.response.bufferOutput = false;
          request.response.add([65]);
          await request.response.flush();
        };

        expect(await fast(() => runner.run(['upgrade'])), 69);
        expect(err.toString(), contains('could not fetch $scriptUrl'));
      },
    );

    test('f09/us02/fr02: a temp folder that cannot be created refuses, '
        'exit 69, before any request', () async {
      await prepare();
      final missing = Directory(_join(root.path, 'no', 'such', 'tmp'));

      final status = await IOOverrides.runZoned(
        () => runner.run(['upgrade']),
        getSystemTempDirectory: () => missing,
      );

      expect(status, 69);
      expect(
        err.toString(),
        allOf(
          startsWith('specstone upgrade: could not create a temp folder: '),
          endsWith('; the install is unchanged\n'),
        ),
      );
      expect(requests, 0);
    });

    test('f09/us02/fr02/e05, nfr-pr01: only upgrade_command.dart opens a '
        'network client', () {
      final client = RegExp(
        r'\b(HttpClient|HttpServer|RawSocket|SecureSocket|WebSocket|Socket)'
        r'\s*[.(]',
      );
      final hits = <String>[];
      for (final (shown, folder) in [
        ('packages/specstone/lib', Directory('lib')),
        ('packages/specstone_core/lib', Directory('../specstone_core/lib')),
      ]) {
        final root = folder.absolute.path.replaceAll(r'\', '/');
        for (final file in folder.listSync(recursive: true)) {
          if (file is! File || !file.path.endsWith('.dart')) continue;
          if (!client.hasMatch(file.readAsStringSync())) continue;
          final inside = file.absolute.path.replaceAll(r'\', '/');
          hits.add('$shown${inside.substring(root.length)}');
        }
      }

      expect(hits, [
        'packages/specstone/lib/src/commands/upgrade_command.dart',
      ]);
    });
  });

  group('findOnPath', () {
    late Directory root;

    File touch(String folder, String name) =>
        File(_join(root.path, folder, name))..createSync(recursive: true);

    setUp(() async => root = await writeTree({}));

    test('f09/us02/fr03: claude.exe wins over claude.cmd in one folder', () {
      touch('a', 'claude.cmd');
      final exe = touch('a', 'claude.exe');

      expect(
        findOnPath('claude', {'PATH': _join(root.path, 'a')}, windows: true),
        exe.path,
      );
    });

    test('f09/us02/fr03: an earlier folder wins, ";" separates, and an empty '
        'entry is skipped', () {
      touch('b', 'claude.exe');
      final first = touch('a', 'claude.cmd');

      expect(
        findOnPath('claude', {
          'PATH': ';${_join(root.path, 'a')};${_join(root.path, 'b')}',
        }, windows: true),
        first.path,
      );
    });

    test(
      'f09/us02/fr03: the Path key matches without case on Windows only',
      () {
        final exe = touch('a', 'claude.exe');
        final env = {'Path': _join(root.path, 'a')};

        expect(findOnPath('claude', env, windows: true), exe.path);
        expect(findOnPath('claude', env, windows: false), isNull);
      },
    );

    test('f09/us02/fr03: nothing found returns null', () {
      expect(
        findOnPath('claude', {'PATH': _join(root.path, 'a')}, windows: true),
        isNull,
      );
      expect(findOnPath('claude', {}, windows: false), isNull);
    });
  }, testOn: '!windows');
}
