import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:specstone/src/command_runner.dart';
import 'package:specstone/src/commands/upgrade_command.dart';
import 'package:test/test.dart';

import '../../helpers/script_sandbox.dart';
import '../../helpers/temp_tree.dart';

/// Joins its arguments with `/`, which every platform's `dart:io` accepts.
String _join(String first, [String? b, String? c, String? d]) =>
    [first, ?b, ?c, ?d].join('/');

const _story = 'install_update/machine_install/upgrade_cli_and_plugin';
const _keep = '$_story/keep_newer_prerelease';
const _rerun = '$_story/rerun_install_script';
const _refuse = '$_story/refuse_other_install';

/// The installed binary the upgrade runs with `folder`: it logs a line of
/// arguments, working folder, and own path to `FOLDER_LOG`, writes a line to
/// each output, and exits `FOLDER_EXIT`. `FOLDER_BYTES` makes its stderr
/// carry a byte no UTF-8 text holds.
const _folderStubSource = r'''
import 'dart:io';

void main(List<String> args) {
  final env = Platform.environment;
  File(env['FOLDER_LOG']!).writeAsStringSync(
    '${args.join(' ')}|${Directory.current.path}|'
    '${Platform.resolvedExecutable}\n',
    mode: FileMode.append,
  );
  stdout.writeln('folder-out');
  if (env['FOLDER_BYTES'] != null) {
    stderr.add([0x62, 0xff, 0x0a]);
  } else {
    stderr.writeln('stale line');
  }
  exit(int.parse(env['FOLDER_EXIT'] ?? '0'));
}
''';

/// The Version the tests run as unless one names another; a full release, so
/// no test depends on the Version the shipped binary carries.
const _fullRelease = '1.1.1';

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
    String runningVersion = _fullRelease,
  }) => SpecstoneCommandRunner(
    out: out,
    err: err,
    workingDirectory: workingDirectory,
    upgrade: UpgradeCommand(
      scriptBase: base,
      latestReleaseUrl: base.resolve('releases/latest'),
      runningVersion: runningVersion,
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

  test('$_refuse E02: a pre-release binary outside ~/.specstone/bin refuses '
      'install_not_managed, exit 78, before any request', () async {
    final root = await writeTree({});
    final tools = Directory(_join(root.path, 'opt', 'tools'));
    final exe = await makeExecutable(tools);
    final runner = runnerFor(exe.path, {
      'HOME': _join(root.path, 'home'),
    }, runningVersion: '1.2.0-beta.1');

    expect(await runner.run(['upgrade']), 78);
    expect(err.toString(), contains('this one runs from ${tools.path}'));
    expect(requests, 0);
    expect(out.toString(), isEmpty);
  });

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
    late Directory root;
    late SpecstoneCommandRunner runner;
    late Uri scriptUrl;
    late Uri releaseUrl;
    late Future<void> Function(HttpRequest) releaseHandle;
    late Directory stubBuild;
    late String folderStub;

    // The installed binary of every run: it logs its arguments, working
    // folder, and own path, prints a line on each output, and exits as
    // FOLDER_EXIT says. A compiled program, so one file serves every OS.
    setUpAll(() async {
      stubBuild = await Directory.systemTemp.createTemp('specstone_stub_');
      final source = File(_join(stubBuild.path, 'folder_stub.dart'))
        ..writeAsStringSync(_folderStubSource);
      folderStub = _join(stubBuild.path, windows ? 'stub.exe' : 'stub');
      final compiled = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'exe',
        source.path,
        '-o',
        folderStub,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
    });

    tearDownAll(() => stubBuild.delete(recursive: true));

    String fileIn(String folder, String name) => _join(root.path, folder, name);

    final installedName = windows ? 'specstone.exe' : 'specstone';

    // Prepares a sandbox whose served script exits [scriptExit] and whose
    // installed binary exits [folderExit]; [withInstalled] false leaves the
    // binary out. A `claude` stub logs any start, which no run may make.
    // The release path answers through `releaseHandle`, no reply at first.
    Future<void> prepare({
      int scriptExit = 0,
      int folderExit = 0,
      bool withInstalled = true,
      bool asWindows = false,
      String runningVersion = _fullRelease,
      Map<String, String> extraEnv = const {},
    }) async {
      final sandbox = await createScriptSandbox();
      root = sandbox.root;
      final bin = Directory(_join(sandbox.home.path, '.specstone', 'bin'));
      await bin.create(recursive: true);
      final exe = File(_join(bin.path, installedName));
      if (withInstalled) await File(folderStub).copy(exe.path);
      final ran = fileIn('logs', 'ran');
      final claudeLog = fileIn('logs', 'claude.log');
      // Imported by name, Set-Content's module loads at once; found by
      // command lookup, it costs a Windows PowerShell 5.1 with a cold module
      // analysis cache about 20 s.
      final script = asWindows || windows
          ? 'Import-Module -Name Microsoft.PowerShell.Management\n'
                "Set-Content -Path '$ran' -Value \$PSCommandPath\n"
                'exit $scriptExit\n'
          : "printf '%s\\n' \"\$0\" > '$ran'\nexit $scriptExit\n";
      scriptUrl = base.resolve(
        asWindows || windows ? 'install.ps1' : 'install.sh',
      );
      releaseUrl = base.resolve('releases/latest');
      releaseHandle = (request) async {};
      handle = (request) async {
        if (request.uri.path == releaseUrl.path) {
          await releaseHandle(request);
          return;
        }
        request.response.write(script);
        await request.response.close();
      };
      sandbox.stub(
        'claude',
        windows ? 'echo %*>> "$claudeLog"' : "echo \"\$*\" >> '$claudeLog'",
      );
      Directory(fileIn('project', '')).createSync();
      final env = sandbox.env({
        'FOLDER_LOG': fileIn('logs', 'folder.log'),
        'FOLDER_EXIT': '$folderExit',
        ...extraEnv,
      });
      runner = runnerFor(
        exe.path,
        env,
        windows: asWindows || windows,
        runningVersion: runningVersion,
        workingDirectory: Directory(fileIn('project', '')),
      );
    }

    // Answers the release path with the [body] bytes, [status], and [headers].
    void releaseSends(
      List<int> body, {
      int status = HttpStatus.ok,
      Map<String, String> headers = const {},
    }) {
      releaseHandle = (request) async {
        final response = request.response..statusCode = status;
        headers.forEach(response.headers.set);
        response.add(body);
        await response.close();
      };
    }

    // Answers the release path with the text [body] and [status].
    void releaseReplies(String body, {int status = HttpStatus.ok}) =>
        releaseSends(utf8.encode(body), status: status);

    // The recorded runs of the installed binary: arguments, working folder,
    // and the path it ran from, each `|` apart.
    List<List<String>> folderRuns() {
      final log = File(fileIn('logs', 'folder.log'));
      if (!log.existsSync()) return const [];
      return [for (final line in log.readAsLinesSync()) line.split('|')];
    }

    bool claudeStarted() => File(fileIn('logs', 'claude.log')).existsSync();

    String resolved(String path) => Directory(path).resolveSymbolicLinksSync();

    test('the script runs from a temp file, then the installed binary runs '
        'folder in the working folder; its stderr shows, its stdout does not; '
        'exit 0', () async {
      await prepare();

      expect(await runner.run(['upgrade']), 0);
      final ran = File(fileIn('logs', 'ran')).readAsStringSync().trim();
      expect(ran, endsWith(windows ? 'install.ps1' : 'install.sh'));
      expect(File(ran).existsSync(), isFalse);
      expect(paths, [scriptUrl.path]);
      final [run] = folderRuns();
      expect(run[0], 'folder');
      expect(resolved(run[1]), resolved(fileIn('project', '')));
      expect(run[2], endsWith(installedName));
      expect(err.toString(), 'stale line\n');
      expect(out.toString(), isEmpty);
      expect(claudeStarted(), isFalse);
    });

    test('a run outside a project shows nothing more; exit 0', () async {
      await prepare(folderExit: 66);

      expect(await runner.run(['upgrade']), 0);
      expect(folderRuns(), hasLength(1));
      expect(err.toString(), isEmpty);
      expect(out.toString(), isEmpty);
    });

    test(
      'a folder run that exits non-zero shows nothing more; exit 0',
      () async {
        await prepare(folderExit: 78);

        expect(await runner.run(['upgrade']), 0);
        expect(err.toString(), isEmpty);
        expect(out.toString(), isEmpty);
      },
    );

    test(
      'an installed binary that cannot start shows nothing more; exit 0',
      () async {
        await prepare(withInstalled: false);

        expect(await runner.run(['upgrade']), 0);
        expect(folderRuns(), isEmpty);
        expect(err.toString(), isEmpty);
        expect(out.toString(), isEmpty);
      },
    );

    test('a byte outside UTF-8 on stderr does not crash the upgrade', () async {
      await prepare(extraEnv: {'FOLDER_BYTES': '1'});

      expect(await runner.run(['upgrade']), 0);
      expect(err.toString(), 'b\u{fffd}\n');
    });

    // The script renames the running `specstone.exe`, as install.ps1 does, and
    // writes a new one; the run must start the new file.
    test('Windows starts the new exe while the old is renamed', () async {
      await prepare();
      final bin = _join(root.path, 'home', '.specstone', 'bin');
      handle = (request) async {
        request.response.write(
          'Import-Module -Name Microsoft.PowerShell.Management\n'
          "Rename-Item -Path '$bin\\specstone.exe' "
          "-NewName 'specstone.exe.old'\n"
          "Copy-Item -Path '$folderStub' -Destination '$bin\\specstone.exe'\n",
        );
        await request.response.close();
      };

      expect(await runner.run(['upgrade']), 0);
      expect(File('$bin\\specstone.exe.old').existsSync(), isTrue);
      final [run] = folderRuns();
      expect(run[2], endsWith('specstone.exe'));
      expect(err.toString(), 'stale line\n');
    }, testOn: 'windows');

    test(
      'f09/us02/fr02/e02, f09/us02/s5: no server refuses '
      'install_script_failed, exit 69, naming the URL; nothing ran',
      () async {
        await prepare();
        await server.close(force: true);

        expect(await runner.run(['upgrade']), 69);
        expect(err.toString(), contains('$scriptUrl'));
        expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
        expect(claudeStarted(), isFalse);
        expect(folderRuns(), isEmpty);
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
      expect(claudeStarted(), isFalse);
      expect(folderRuns(), isEmpty);
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
      expect(claudeStarted(), isFalse);
      expect(folderRuns(), isEmpty);
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
      expect(claudeStarted(), isFalse);
      expect(folderRuns(), isEmpty);
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
        expect(
          err.toString(),
          'specstone upgrade could not fetch $scriptUrl: HTTP 502\n',
        );
      },
    );

    test('f09/us02/fr02: an error reply with a bad gzip body still names the '
        'status, exit 69', () async {
      await prepare();
      handle = (request) async {
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..headers.set(HttpHeaders.contentEncodingHeader, 'gzip')
          ..add(utf8.encode('this is not gzip'));
        await request.response.close();
      };

      expect(await runner.run(['upgrade']), 69);
      expect(
        err.toString(),
        'specstone upgrade could not fetch $scriptUrl: HTTP 503\n',
      );
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
    });

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

    test(
      'a pre-release newer than the latest '
      'release is kept; one line, no script, then the folder run; exit 0',
      () async {
        await prepare(runningVersion: '1.2.0-beta.1');
        releaseReplies('{"tag_name": "v1.1.1"}');

        expect(await runner.run(['upgrade']), 0);
        expect(
          out.toString(),
          'specstone 1.2.0-beta.1 is newer than the latest release 1.1.1; '
          'nothing to upgrade\n',
        );
        expect(err.toString(), 'stale line\n');
        expect(paths, [releaseUrl.path]);
        expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
        expect(claudeStarted(), isFalse);
        expect(folderRuns(), hasLength(1));
      },
    );

    test('a latest release above the pre-release runs the script '
        'and then the folder run', () async {
      await prepare(runningVersion: '1.2.0-beta.1');
      releaseReplies('{"tag_name": "v1.2.0"}');

      expect(await runner.run(['upgrade']), 0);
      final ran = File(fileIn('logs', 'ran')).readAsStringSync().trim();
      expect(ran, endsWith(windows ? 'install.ps1' : 'install.sh'));
      expect(folderRuns(), hasLength(1));
      expect(claudeStarted(), isFalse);
      expect(paths, [releaseUrl.path, scriptUrl.path]);
    });

    test('$_keep E03: a binary with no pre-release part sends no release '
        'request', () async {
      await prepare(runningVersion: _fullRelease);
      releaseReplies('{"tag_name": "v1.0.0"}');

      expect(await runner.run(['upgrade']), 0);
      expect(paths, [scriptUrl.path]);
    });

    // Review Focus 4: every reply the request can get that names no release.
    final unreadable = <(String, int, String, String)>[
      (
        'a rate-limit reply',
        403,
        '{"message": "API rate limit exceeded"}',
        'HTTP 403',
      ),
      (
        'a body that is not JSON',
        200,
        '<html>no</html>',
        'the body is not JSON',
      ),
      (
        'a body of several JSON documents',
        200,
        '{"tag_name": "v1.1.1"} {}',
        'the body is not JSON',
      ),
      ('a JSON array', 200, '[{"tag_name": "v1.1.1"}]', 'no tag_name'),
      ('no tag_name', 200, '{"name": "1.1.1"}', 'no tag_name'),
      ('a tag_name that is no string', 200, '{"tag_name": 111}', 'no tag_name'),
      (
        'a tag_name without its v',
        200,
        '{"tag_name": "1.1.1"}',
        'tag_name 1.1.1 is not v<Version>',
      ),
      (
        'a tag_name of two fields',
        200,
        '{"tag_name": "v1.2"}',
        'tag_name v1.2 is not v<Version>',
      ),
      (
        'a tag_name with build metadata',
        200,
        '{"tag_name": "v1.2.0+build.5"}',
        'tag_name v1.2.0+build.5 is not v<Version>',
      ),
      (
        'a tag_name with a control character',
        200,
        r'{"tag_name": "v1.2\u001b[2J"}',
        'tag_name v1.2?[2J is not v<Version>',
      ),
      (
        'a tag_name with a bidi override',
        200,
        r'{"tag_name": "v1.2\u202e"}',
        'tag_name v1.2? is not v<Version>',
      ),
      (
        'a tag_name with a zero-width space and line and paragraph separators',
        200,
        r'{"tag_name": "v1.2\u200b\u2028\u2029"}',
        'tag_name v1.2??? is not v<Version>',
      ),
      (
        'a tag_name with a C1 control character',
        200,
        r'{"tag_name": "v1.2\u0085"}',
        'tag_name v1.2? is not v<Version>',
      ),
      (
        'a tag_name with a non-ASCII letter',
        200,
        r'{"tag_name": "v1.2\u00e9"}',
        'tag_name v1.2? is not v<Version>',
      ),
      (
        'a tag_name with a character outside the BMP',
        200,
        r'{"tag_name": "v1.2\ud83d\ude00"}',
        'tag_name v1.2? is not v<Version>',
      ),
      (
        'a tag_name of 200 characters',
        200,
        '{"tag_name": "v${'x' * 199}"}',
        'tag_name v${'x' * 60}... is not v<Version>',
      ),
      (
        'a tag_name of exactly 64 characters',
        200,
        '{"tag_name": "v${'x' * 63}"}',
        'tag_name v${'x' * 63} is not v<Version>',
      ),
      ('a 503 reply', 503, '{"tag_name": "v1.1.1"}', 'HTTP 503'),
      ('an empty 2xx body', 200, '', 'the body is not JSON'),
    ];
    for (final (label, status, body, failure) in unreadable) {
      test('$_keep E04: $label refuses install_script_failed, exit 69, '
          'naming the URL; nothing ran', () async {
        await prepare(runningVersion: '1.2.0-beta.1');
        releaseReplies(body, status: status);

        expect(await runner.run(['upgrade']), 69);
        expect(
          err.toString(),
          'specstone upgrade could not read the latest release from '
          '$releaseUrl: $failure\n',
        );
        expect(out.toString(), isEmpty);
        expect(paths, [releaseUrl.path]);
        expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
        expect(claudeStarted(), isFalse);
        expect(folderRuns(), isEmpty);
      });
    }

    test('$_keep E04: a 2xx body of invalid UTF-8 refuses, exit 69, naming '
        'the URL; nothing ran', () async {
      await prepare(runningVersion: '1.2.0-beta.1');
      releaseSends([0x7b, 0xff, 0x7d]);

      expect(await runner.run(['upgrade']), 69);
      expect(
        err.toString(),
        'specstone upgrade could not read the latest release from '
        '$releaseUrl: the body is not JSON\n',
      );
      expect(paths, [releaseUrl.path]);
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
    });

    for (final (label, status, location) in [
      ('a 302 to an ftp URL', 302, 'ftp://x'),
      ('a 301 with a malformed Location', 301, 'http://['),
    ]) {
      test('$_keep E04: $label is not followed; refuses, exit 69, nothing '
          'fetched or run', () async {
        await prepare(runningVersion: '1.2.0-beta.1');
        releaseSends(const [], status: status, headers: {'location': location});

        expect(await runner.run(['upgrade']), 69);
        expect(
          err.toString(),
          'specstone upgrade could not read the latest release from '
          '$releaseUrl: HTTP $status\n',
        );
        expect(paths, [releaseUrl.path]);
        expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
        expect(claudeStarted(), isFalse);
        expect(folderRuns(), isEmpty);
      });
    }

    test('$_rerun E02: a script URL that redirects is not followed; refuses, '
        'exit 69, nothing ran', () async {
      await prepare();
      handle = (request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set('location', '${base}elsewhere');
        await request.response.close();
      };

      expect(await runner.run(['upgrade']), 69);
      expect(
        err.toString(),
        'specstone upgrade could not fetch $scriptUrl: HTTP 302\n',
      );
      expect(paths, [scriptUrl.path]);
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
    });

    test('$_keep E04: a 2xx gzip reply with garbage refuses, exit 69, naming '
        'the URL; nothing ran', () async {
      await prepare(runningVersion: '1.2.0-beta.1');
      releaseSends(
        utf8.encode('not gzip data'),
        headers: {'content-encoding': 'gzip'},
      );

      expect(await runner.run(['upgrade']), 69);
      expect(
        err.toString(),
        'specstone upgrade could not read the latest release from '
        '$releaseUrl: Filter error, bad data\n',
      );
      expect(paths, [releaseUrl.path]);
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
      expect(claudeStarted(), isFalse);
      expect(folderRuns(), isEmpty);
    });

    test('$_rerun E02: a 2xx gzip script reply with garbage refuses, exit '
        '69, nothing ran', () async {
      await prepare();
      handle = (request) async {
        request.response.headers.set('content-encoding', 'gzip');
        request.response.write('not gzip data');
        await request.response.close();
      };

      expect(await runner.run(['upgrade']), 69);
      expect(
        err.toString(),
        'specstone upgrade could not fetch $scriptUrl: '
        'Filter error, bad data\n',
      );
      expect(paths, [scriptUrl.path]);
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
    });

    // The release reply padded with spaces to [length] bytes.
    List<int> paddedRelease(int length) {
      final json = utf8.encode('{"tag_name": "v1.1.1"}');
      return [...json, ...List.filled(length - json.length, 0x20)];
    }

    test('$_keep E04: a reply of 1 MiB plus one byte refuses, exit 69, '
        'naming the URL; nothing ran', () async {
      await prepare(runningVersion: '1.2.0-beta.1');
      releaseSends(paddedRelease(1024 * 1024 + 1));

      expect(await runner.run(['upgrade']), 69);
      expect(
        err.toString(),
        'specstone upgrade could not read the latest release from '
        '$releaseUrl: the reply is over 1 MiB\n',
      );
      expect(paths, [releaseUrl.path]);
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
    });

    test('$_keep S6: a reply of exactly 1 MiB is read', () async {
      await prepare(runningVersion: '1.2.0-beta.1');
      releaseSends(paddedRelease(1024 * 1024));

      expect(await runner.run(['upgrade']), 0);
      expect(out.toString(), contains('nothing to upgrade'));
      expect(paths, [releaseUrl.path]);
    });

    test('$_keep E01: 1.10.0-beta.1 over 1.9.0 is kept, the fields compared '
        'as numbers', () async {
      await prepare(runningVersion: '1.10.0-beta.1');
      releaseReplies('{"tag_name": "v1.9.0"}');

      expect(await runner.run(['upgrade']), 0);
      expect(
        out.toString(),
        startsWith(
          'specstone 1.10.0-beta.1 is newer than the latest release 1.9.0; ',
        ),
      );
      expect(paths, [releaseUrl.path]);
    });

    test(
      '$_keep E02: 1.1.1-beta.1 is below 1.1.1, so the script runs',
      () async {
        await prepare(runningVersion: '1.1.1-beta.1');
        releaseReplies('{"tag_name": "v1.1.1"}');

        expect(await runner.run(['upgrade']), 0);
        expect(paths, [releaseUrl.path, scriptUrl.path]);
        expect(folderRuns(), hasLength(1));
      },
    );

    test('$_keep E04: a server that never answers refuses, exit 69, naming '
        'the URL; nothing ran', () async {
      await prepare(runningVersion: '1.2.0-beta.1');

      expect(await fast(() => runner.run(['upgrade'])), 69);
      expect(
        err.toString(),
        'specstone upgrade could not read the latest release from '
        '$releaseUrl: no data for 60 s\n',
      );
      expect(paths, [releaseUrl.path]);
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
    });

    test('$_keep E04: no server refuses, exit 69, naming the URL', () async {
      await prepare(runningVersion: '1.2.0-beta.1');
      await server.close(force: true);

      expect(await runner.run(['upgrade']), 69);
      expect(
        err.toString(),
        startsWith(
          'specstone upgrade could not read the latest release from '
          '$releaseUrl: ',
        ),
      );
      expect(File(fileIn('logs', 'ran')).existsSync(), isFalse);
    });

    // The case-insensitive drop of `Specstone_Version` is checked only on a
    // Windows host, since only there does the script run through PowerShell.
    test('$_rerun E08: the script runs without an exported '
        'SPECSTONE_VERSION', () async {
      await prepare(
        extraEnv: {
          'SPECSTONE_VERSION': '1.2.0-beta.1',
          if (windows) 'Specstone_Version': '1.2.0-beta.1',
        },
      );
      final seen = fileIn('logs', 'seen');
      final script = windows
          ? 'Import-Module -Name Microsoft.PowerShell.Management\n'
                'if (Test-Path Env:SPECSTONE_VERSION) '
                "{ Set-Content -Path '$seen' -Value \$env:SPECSTONE_VERSION } "
                "else { Set-Content -Path '$seen' -Value unset }\n"
          : "printf '%s\\n' \"\${SPECSTONE_VERSION-unset}\" > '$seen'\n";
      handle = (request) async {
        request.response.write(script);
        await request.response.close();
      };

      expect(await runner.run(['upgrade']), 0);
      expect(File(seen).readAsStringSync().trim(), 'unset');
    });

    test('$_rerun E08: a POSIX environment keeps the variable of another '
        'case', () async {
      await prepare(
        extraEnv: {
          'SPECSTONE_VERSION': '1.2.0-beta.1',
          'Specstone_Version': 'kept',
        },
      );
      final seen = fileIn('logs', 'seen');
      final script =
          "printf '%s\\n' \"\${Specstone_Version-unset}\" > '$seen'\n";
      handle = (request) async {
        request.response.write(script);
        await request.response.close();
      };

      expect(await runner.run(['upgrade']), 0);
      expect(File(seen).readAsStringSync().trim(), 'kept');
    }, testOn: '!windows');

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
}
