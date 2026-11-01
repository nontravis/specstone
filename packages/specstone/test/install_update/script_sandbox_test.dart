@Tags(['ps1'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

void main() {
  final windows = Platform.isWindows;
  final target = windows ? 'windows-x64' : 'linux-x64';
  final asset = 'specstone-$target.${windows ? 'zip' : 'tar.gz'}';
  final binaryName = windows ? 'specstone.exe' : 'specstone';
  const posixOnly = 'POSIX shell, uname, or chmod behavior';

  // Unpacks [archive] into a new folder under the sandbox.
  Future<Directory> unpack(ScriptSandbox sandbox, File archive) async {
    final folder = Directory('${sandbox.root.path}/unpacked')..createSync();
    final expand =
        r"$ProgressPreference = 'SilentlyContinue'; "
        'Expand-Archive -LiteralPath "${archive.path}" '
        '-DestinationPath "${folder.path}"';
    final result = windows
        ? await Process.run('powershell', ['-NoProfile', '-Command', expand])
        : await Process.run('tar', ['-xzf', archive.path, '-C', folder.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return folder;
  }

  Future<String> listing(File archive) async {
    final entries =
        'Add-Type -AssemblyName System.IO.Compression.FileSystem; '
        '[IO.Compression.ZipFile]::OpenRead("${archive.path}").Entries | '
        r'ForEach-Object { $_.FullName }';
    final result = windows
        ? await Process.run('powershell', ['-NoProfile', '-Command', entries])
        : await Process.run('tar', ['-tzf', archive.path]);
    return (result.stdout as String).replaceAll(r'\', '/');
  }

  String sumsLineFor(ScriptSandbox sandbox, String name) {
    final lines = File('${sandbox.archives.path}/SHA256SUMS').readAsLinesSync();
    return lines.firstWhere(
      (line) => line.endsWith('  $name'),
      orElse: () => '',
    );
  }

  String sha256Of(File file) =>
      sha256.convert(file.readAsBytesSync()).toString();

  test(
    'writeArchive writes the asset and a SHA256SUMS line of its bytes',
    () async {
      final sandbox = await createScriptSandbox();

      final archive = await sandbox.writeArchive(target);

      expect(
        archive.path,
        '${sandbox.archives.path}${Platform.pathSeparator}$asset',
      );
      expect(sumsLineFor(sandbox, asset), '${sha256Of(archive)}  $asset');
    },
  );

  test('writeArchive holds bin, lib, LICENSE and THIRD_PARTY_NOTICES, and the '
      'fake binary prints the version', () async {
    final sandbox = await createScriptSandbox();
    final archive = await sandbox.writeArchive(target, version: '0.3.1');

    final unpacked = await unpack(sandbox, archive);
    final binary = File('${unpacked.path}/bin/$binaryName');
    final run = await Process.run(binary.path, const ['--version']);

    expect(File('${unpacked.path}/lib/libfake.so').existsSync(), isTrue);
    expect(File('${unpacked.path}/LICENSE').existsSync(), isTrue);
    expect(File('${unpacked.path}/THIRD_PARTY_NOTICES').existsSync(), isTrue);
    expect((run.stdout as String).trim(), '0.3.1');
  });

  test(
    'writeArchive with a bundle packs that folder instead of the fake',
    () async {
      final sandbox = await createScriptSandbox();
      final bundle = Directory('${sandbox.root.path}/bundle')
        ..createSync(recursive: true);
      Directory('${bundle.path}/bin').createSync();
      File('${bundle.path}/bin/specstone').writeAsStringSync('real');
      final archive = await sandbox.writeArchive(target, bundle: bundle);

      final entries = await listing(archive);

      expect(entries, contains('bin/specstone'));
      expect(entries, isNot(contains('libfake.so')));
    },
  );

  test('writeArchive damaged writes the hash of other bytes', () async {
    final sandbox = await createScriptSandbox();

    final archive = await sandbox.writeArchive(target, damaged: true);

    final line = sumsLineFor(sandbox, asset);
    expect(line, endsWith('  $asset'));
    expect(line, isNot('${sha256Of(archive)}  $asset'));
  });

  test(
    'writeArchive withSumsLine false leaves no line for the asset',
    () async {
      final sandbox = await createScriptSandbox();

      await sandbox.writeArchive(target, withSumsLine: false);

      expect(sumsLineFor(sandbox, asset), isEmpty);
      expect(
        File('${sandbox.archives.path}/SHA256SUMS').readAsLinesSync(),
        isNotEmpty,
      );
    },
  );

  test('a stub runs through run and its log reads back', () async {
    final sandbox = await createScriptSandbox();
    sandbox.stub(
      'probe',
      windows
          ? r'>> "%STUB_LOG_DIR%\probe.log" echo %*'
          : r'echo "$*" >> "$STUB_LOG_DIR/probe.log"',
    );
    final script = File('${sandbox.root.path}/call.${windows ? 'ps1' : 'sh'}')
      ..writeAsStringSync('probe one two\nprobe three\n');

    final result = await sandbox.run(script.path);

    expect(result.exitCode, 0);
    expect(sandbox.logOf('probe'), ['one two', 'three']);
    expect(sandbox.logOf('absent'), isEmpty);
  });

  test('run passes args and stdin to the script and keeps the parent '
      'environment out', () async {
    final sandbox = await createScriptSandbox();
    final script = File('${sandbox.root.path}/echo.${windows ? 'ps1' : 'sh'}')
      ..writeAsStringSync(
        windows
            ? r'''
$line = [Console]::In.ReadLine()
$probe = if ($env:SANDBOX_PROBE) { $env:SANDBOX_PROBE } else { 'unset' }
$extra = if ($env:EXTRA) { $env:EXTRA } else { 'none' }
"$($args[0]) $line $probe $extra"
'''
            : r'read line; echo "$1 $line '
                  r'${SANDBOX_PROBE:-unset} ${EXTRA:-none}"'
                  '\n',
      );

    final result = await sandbox.run(
      script.path,
      args: ['arg'],
      extra: {'EXTRA': 'yes'},
      stdinText: 'typed\n',
    );

    expect((result.stdout as String).trim(), 'arg typed unset yes');
  });

  test(
    'the uname stub answers from STUB_UNAME_S and STUB_UNAME_M',
    skip: windows ? posixOnly : null,
    () async {
      final sandbox = await createScriptSandbox();
      final script = File('${sandbox.root.path}/uname.sh')
        ..writeAsStringSync('uname -s\nuname -m\n');

      final fallback = await sandbox.run(script.path);
      final mac = await sandbox.run(
        script.path,
        extra: {'STUB_UNAME_S': 'Darwin', 'STUB_UNAME_M': 'arm64'},
      );

      expect(const LineSplitter().convert(fallback.stdout as String), [
        'Linux',
        'x86_64',
      ]);
      expect(const LineSplitter().convert(mac.stdout as String), [
        'Darwin',
        'arm64',
      ]);
    },
  );

  test(
    'env builds the sandbox environment and an empty extra removes a key',
    () async {
      final sandbox = await createScriptSandbox();

      final env = sandbox.env({'SHELL': '', 'FOO': 'bar'});

      expect(env.containsKey('SHELL'), isFalse);
      expect(env['FOO'], 'bar');
      expect(env['HOME'], sandbox.home.path);
      expect(env['STUB_LOG_DIR'], sandbox.logs.path);
      if (windows) {
        expect(env['USERPROFILE'], sandbox.home.path);
        expect(env['TEMP'], '${sandbox.root.path}\\tmp');
        expect(env['PATH'], startsWith('${sandbox.stubs.path};'));
        expect(env['PROCESSOR_ARCHITECTURE'], 'AMD64');
      } else {
        expect(env['TMPDIR'], '${sandbox.root.path}/tmp');
        expect(env['PATH'], startsWith('${sandbox.stubs.path}:'));
        expect(sandbox.env()['SHELL'], '/bin/zsh');
      }
    },
  );

  test('installFake and snapshot describe the home folder', () async {
    final sandbox = await createScriptSandbox();
    expect(sandbox.snapshot(), isEmpty);

    sandbox.installFake(version: '0.1.5');
    final before = sandbox.snapshot();

    expect(
      before.keys,
      unorderedEquals([
        '.specstone/bin/$binaryName',
        '.specstone/lib/libold.so',
      ]),
    );
    final version = Process.runSync(
      '${sandbox.home.path}/.specstone/bin/$binaryName',
      const ['--version'],
    );
    expect((version.stdout as String).trim(), '0.1.5');
    File('${sandbox.home.path}/.specstone/lib/libold.so')
        .writeAsStringSync('changed');
    expect(sandbox.snapshot(), isNot(before));
  });

  test(
    'writeArchive keeps the other target SUMS line and replaces its own',
    () async {
      final sandbox = await createScriptSandbox();

      final other = windows ? 'linux-x64' : 'macos-arm64';
      final linux = await sandbox.writeArchive(target);
      final mac = await sandbox.writeArchive(other);
      await sandbox.writeArchive(target, version: '0.9.0');

      final lines = File('${sandbox.archives.path}/SHA256SUMS')
          .readAsLinesSync();
      expect(lines, hasLength(2));
      expect(lines, contains('${sha256Of(mac)}  specstone-$other.tar.gz'));
      expect(lines, contains('${sha256Of(linux)}  $asset'));
    },
  );

  test(
    'run with shell /bin/bash runs a bash-only construct',
    skip: windows ? posixOnly : null,
    () async {
      final sandbox = await createScriptSandbox();
      final script = File('${sandbox.root.path}/bashism.sh')
        ..writeAsStringSync('[[ a == a ]] && echo bash-ok\n');

      final result = await sandbox.run(script.path, shell: '/bin/bash');

      expect(result.exitCode, 0);
      expect((result.stdout as String).trim(), 'bash-ok');
    },
  );

  test(
    'run survives a script that never reads stdin',
    skip: windows ? posixOnly : null,
    () async {
      final sandbox = await createScriptSandbox();
      final script = File('${sandbox.root.path}/noread.sh')
        ..writeAsStringSync('exit 3\n');

      final result = await sandbox.run(script.path, stdinText: 'x' * 1000000);

      expect(result.exitCode, 3);
    },
  );

  test(
    'run decodes malformed output bytes without throwing',
    skip: windows ? posixOnly : null,
    () async {
      final sandbox = await createScriptSandbox();
      final script = File('${sandbox.root.path}/bad.sh')
        ..writeAsStringSync("printf '\\377ok'\n");

      final result = await sandbox.run(script.path);

      expect(result.stdout as String, endsWith('ok'));
    },
  );

  test(
    'run joins a relative script to the repo root without a double slash',
    skip: windows ? posixOnly : null,
    () async {
      final sandbox = await createScriptSandbox();

      final result = await sandbox.run('missing.sh');

      expect(repoRoot().path, isNot(endsWith('/')));
      expect(result.stderr as String, isNot(contains('//')));
    },
  );

  test('repoRoot is the code repo root', () {
    expect(File('${repoRoot().path}/pubspec.yaml').existsSync(), isTrue);
    expect(
      Directory('${repoRoot().path}/packages/specstone').existsSync(),
      isTrue,
    );
  });
}
