@TestOn('!windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

void main() {
  const asset = 'specstone-linux-x64.tar.gz';
  const supported =
      'supported: macOS arm64, macOS x64, Linux x64, Windows x64\n';

  Future<ScriptSandbox> sandboxWith({
    String target = 'linux-x64',
    bool damaged = false,
    bool withSumsLine = true,
  }) async {
    final sandbox = await createScriptSandbox();
    await sandbox.writeArchive(
      target,
      damaged: damaged,
      withSumsLine: withSumsLine,
    );
    return sandbox;
  }

  Map<String, String> archiveEnv(ScriptSandbox sandbox) => {
    'SPECSTONE_ARCHIVE_DIR': sandbox.archives.path,
  };

  String installedVersion(ScriptSandbox sandbox) {
    final result = Process.runSync(
      '${sandbox.home.path}/.specstone/bin/specstone',
      ['--version'],
    );
    return (result.stdout as String).trim();
  }

  void stubCurlFailing(ScriptSandbox sandbox) {
    sandbox.stub('curl', r'echo "$@" >> "$STUB_LOG_DIR/curl.log"; exit 22');
  }

  group('install.sh', () {
    test('f09/us01/fr01/e01, f09/us01/s5: Linux aarch64 refuses before any '
        'download, exit 1', () async {
      final sb = await createScriptSandbox();
      sb.stub('curl', r'echo "$@" >> "$STUB_LOG_DIR/curl.log"; exit 0');

      final r = await sb.run('install.sh', extra: {'STUB_UNAME_M': 'aarch64'});

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: unsupported machine Linux aarch64; $supported',
      );
      expect(sb.snapshot(), isEmpty);
      expect(sb.logOf('curl'), isEmpty);
    });

    test('f09/us01/fr01/e04: Git Bash on Windows refuses naming the four '
        'targets', () async {
      final sb = await createScriptSandbox();
      sb.stub('curl', r'echo "$@" >> "$STUB_LOG_DIR/curl.log"; exit 0');

      final r = await sb.run(
        'install.sh',
        extra: {'STUB_UNAME_S': 'MINGW64_NT-10.0-19045'},
      );

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: unsupported machine MINGW64_NT-10.0-19045 x86_64; '
        '$supported',
      );
      expect(sb.snapshot(), isEmpty);
      expect(sb.logOf('curl'), isEmpty);
    });

    test('f09/us01/fr01/e05: a version argument is ignored; the latest '
        'archive installs', () async {
      final sb = await sandboxWith();

      final r = await sb.run(
        'install.sh',
        args: ['0.1.0'],
        extra: archiveEnv(sb),
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(installedVersion(sb), '0.2.0');
    });

    for (final (os, machine, target) in [
      ('Darwin', 'arm64', 'macos-arm64'),
      ('Darwin', 'x86_64', 'macos-x64'),
      ('Linux', 'x86_64', 'linux-x64'),
    ]) {
      test('f09/us01/fr01: $os $machine reads the $target archive', () async {
        final sb = await sandboxWith(target: target);

        final r = await sb.run(
          'install.sh',
          extra: {
            ...archiveEnv(sb),
            'STUB_UNAME_S': os,
            'STUB_UNAME_M': machine,
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(installedVersion(sb), '0.2.0');
      });
    }

    test('f09/us01/fr02/e01: a failed download stops with the install '
        'unchanged, exit 1', () async {
      final sb = await createScriptSandbox();
      stubCurlFailing(sb);
      sb.installFake();
      final before = sb.snapshot();

      final r = await sb.run('install.sh');

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: download failed for $asset; the install is unchanged\n',
      );
      expect(sb.snapshot(), before);
      expect(
        sb.logOf('curl').join('\n'),
        contains(
          'https://github.com/nontravis/specstone/releases/latest/download/'
          '$asset',
        ),
      );
    });

    test('f09/us01/fr02/e03, f09/us01/s6: a damaged archive stops, the older '
        'CLI still runs', () async {
      final sb = await sandboxWith(damaged: true);
      sb.installFake();
      final before = sb.snapshot();

      final r = await sb.run('install.sh', extra: archiveEnv(sb));

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: checksum mismatch for $asset; the install is unchanged\n',
      );
      expect(sb.snapshot(), before);
      expect(installedVersion(sb), '0.1.0');
    });

    test(
      'f09/us01/fr02/e02: no SHA256SUMS line is a checksum failure',
      () async {
        final sb = await sandboxWith(withSumsLine: false);
        sb.installFake();
        final before = sb.snapshot();

        final r = await sb.run('install.sh', extra: archiveEnv(sb));

        expect(r.exitCode, 1);
        expect(
          r.stderr,
          'specstone: checksum mismatch for $asset; the install is unchanged\n',
        );
        expect(sb.snapshot(), before);
      },
    );

    test('f09/us01/fr02: the temp folder is gone after a failure and after '
        'a success', () async {
      for (final damaged in [true, false]) {
        final sb = await sandboxWith(damaged: damaged);
        sb.stub('mktemp', r'''
dir=$(/usr/bin/mktemp "$@") || exit 1
echo "$dir" >> "$STUB_LOG_DIR/mktemp.log"
echo "$dir"''');

        final r = await sb.run('install.sh', extra: archiveEnv(sb));

        expect(r.exitCode, damaged ? 1 : 0, reason: '${r.stderr}');
        final made = sb.logOf('mktemp');
        expect(made, hasLength(1));
        expect(made.single, startsWith('${sb.root.path}/tmp/specstone.'));
        expect(Directory(made.single).existsSync(), isFalse);
        expect(Directory('${sb.root.path}/tmp').listSync(), isEmpty);
      }
    });

    test('f09/us01/fr03, f09/us01/s4: an older CLI is replaced; packs stay; '
        'the install line prints', () async {
      final sb = await sandboxWith();
      sb.installFake();
      final packs = File('${sb.home.path}/.specstone/packs/p/pack.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: p\n');

      final r = await sb.run('install.sh', extra: archiveEnv(sb));

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        r.stdout,
        contains('specstone 0.2.0 installed in ${sb.home.path}/.specstone/bin'),
      );
      expect(packs.readAsStringSync(), 'name: p\n');
      final files = sb.snapshot().keys;
      expect(files, isNot(contains('.specstone/lib/libold.so')));
      expect(files, contains('.specstone/lib/libfake.so'));
      expect(installedVersion(sb), '0.2.0');
    });

    test('f09/us01/fr03/e03: the same version is left as it is', () async {
      final sb = await sandboxWith();
      sb.installFake(version: '0.2.0');
      final before = sb.snapshot();

      final r = await sb.run('install.sh', extra: archiveEnv(sb));

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        r.stdout,
        contains('specstone 0.2.0 is already the latest release'),
      );
      expect(r.stdout, isNot(contains('installed in')));
      expect(sb.snapshot(), before);
    });

    test('f09/us01/fr03/e04: an empty home gains .specstone with bin and lib '
        'only', () async {
      final sb = await sandboxWith();

      final r = await sb.run('install.sh', extra: archiveEnv(sb));

      expect(r.exitCode, 0, reason: '${r.stderr}');
      final top = Directory('${sb.home.path}/.specstone')
          .listSync()
          .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last);
      expect(top.toSet(), {'bin', 'lib'});
    });

    test("f09/us01/fr03: the running binary's file is never written", () async {
      final sb = await sandboxWith();
      sb.installFake();
      final keep = '${sb.root.path}/keep';
      final link = Process.runSync('ln', [
        '${sb.home.path}/.specstone/bin/specstone',
        keep,
      ]);
      expect(link.exitCode, 0);

      final r = await sb.run('install.sh', extra: archiveEnv(sb));

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(Process.runSync(keep, ['--version']).stdout, '0.1.0\n');
      expect(installedVersion(sb), '0.2.0');
    });

    test('f09/us01/fr02: a truncated script stream runs nothing', () async {
      final sb = await sandboxWith();
      sb.stub('curl', r'echo "$@" >> "$STUB_LOG_DIR/curl.log"; exit 0');
      final script = File('${repoRoot().path}/install.sh');
      final half = script.lengthSync() ~/ 2;

      final r = await Process.run(
        '/bin/sh',
        ['-c', 'head -c $half "${script.path}" | sh'],
        environment: sb.env(archiveEnv(sb)),
        includeParentEnvironment: false,
      );

      expect(sb.snapshot(), isEmpty);
      expect(sb.logOf('curl'), isEmpty);
      expect(r.stdout, isEmpty);
    });

    test('f09/us01/fr03 (controller F10): no HOME and no USERPROFILE refuses '
        'with exit 1', () async {
      final sb = await sandboxWith();

      final r = await sb.run(
        'install.sh',
        extra: {...archiveEnv(sb), 'HOME': '', 'USERPROFILE': ''},
      );

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: no home folder: HOME and USERPROFILE are unset\n',
      );
      expect(sb.snapshot(), isEmpty);
    });

    test('f09/us01/fr02: the curl path fetches the archive and SHA256SUMS, '
        'with timeouts', () async {
      final sb = await sandboxWith();
      sb.stub('curl', r'''
echo "$@" >> "$STUB_LOG_DIR/curl.log"
out=''; url=''
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift ;;
    http*) url=$1 ;;
  esac
  shift
done
cp "$ARCHIVES/${url##*/}" "$out"''');

      final r = await sb.run(
        'install.sh',
        extra: {'ARCHIVES': sb.archives.path},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(installedVersion(sb), '0.2.0');
      final log = sb.logOf('curl');
      expect(log, hasLength(2));
      expect(log.first, contains('--connect-timeout 30'));
      expect(log.first, contains('--speed-limit 1 --speed-time 60'));
      expect(log.last, endsWith('/latest/download/SHA256SUMS'));
    });

    test('f09/us01/fr02: shasum is used when sha256sum is absent', () async {
      final shasum = Process.runSync('/bin/sh', ['-c', 'command -v shasum']);
      if (shasum.exitCode != 0) {
        markTestSkipped('no shasum on this machine');
        return;
      }
      final sb = await sandboxWith();
      final tools = Directory('${sb.root.path}/tools')..createSync();
      for (final name in [
        'awk', 'cut', 'tr', 'tar', 'gzip', 'cp', 'rm', 'mv', 'mkdir', //
        'mktemp', 'perl', 'shasum', 'sh', 'cat', 'env', 'dirname', 'basename',
      ]) {
        final found = Process.runSync('/bin/sh', [
          '-c',
          'PATH=/usr/bin:/bin command -v $name',
        ]);
        if (found.exitCode == 0) {
          Link('${tools.path}/$name')
              .createSync((found.stdout as String).trim());
        }
      }

      final r = await sb.run(
        'install.sh',
        extra: {...archiveEnv(sb), 'PATH': '${sb.stubs.path}:${tools.path}'},
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(installedVersion(sb), '0.2.0');
    });

    test(
      'f09/us01/fr02: an upper-case hash in SHA256SUMS still matches',
      () async {
        final sb = await sandboxWith();
        final sums = File('${sb.archives.path}/SHA256SUMS');
        final lines = sums.readAsLinesSync().map((line) {
          final parts = line.split('  ');
          return '${parts.first.toUpperCase()}  ${parts.last}';
        });
        sums.writeAsStringSync('${lines.join('\n')}\n');

        final r = await sb.run('install.sh', extra: archiveEnv(sb));

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(installedVersion(sb), '0.2.0');
      },
    );

    test('f09/us01/fr02: a stream cut just before main runs nothing', () async {
      final sb = await sandboxWith();
      sb.stub('curl', r'echo "$@" >> "$STUB_LOG_DIR/curl.log"; exit 0');
      final script = File('${repoRoot().path}/install.sh');
      final text = script.readAsStringSync();
      final cut = text.lastIndexOf(r'main "$@"');
      expect(cut, greaterThan(0));
      final head = File('${sb.root.path}/cut.sh')
        ..writeAsStringSync(text.substring(0, cut));

      final r = await Process.run(
        '/bin/sh',
        ['-c', 'cat "${head.path}" | sh'],
        environment: sb.env(archiveEnv(sb)),
        includeParentEnvironment: false,
      );

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(sb.snapshot(), isEmpty);
      expect(sb.logOf('curl'), isEmpty);
      expect(r.stdout, isEmpty);
    });

    test(
      'f09/us01/fr03: a failed lib copy leaves the old install runnable',
      () async {
        final sb = await sandboxWith();
        sb
          ..installFake()
          ..stub('cp', r'''
case "$*" in
  *.lib.new*) exit 1 ;;
esac
exec /bin/cp "$@"''');
        final before = sb.snapshot();

        final r = await sb.run('install.sh', extra: archiveEnv(sb));

        expect(r.exitCode, isNot(0));
        expect(installedVersion(sb), '0.1.0');
        expect(sb.snapshot()['.specstone/lib/libold.so'], 'old');
        expect(before.keys, contains('.specstone/bin/specstone'));
      },
    );

    test('f09/us01/fr02: an unpack failure names the archive, install '
        'unchanged', () async {
      final sb = await sandboxWith();
      sb
        ..installFake()
        ..stub('tar', 'exit 1');
      final before = sb.snapshot();

      final r = await sb.run('install.sh', extra: archiveEnv(sb));

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: could not unpack $asset; the install is unchanged\n',
      );
      expect(sb.snapshot(), before);
    });

    test('f09/us01/fr02: a downloaded binary that does not run is named, '
        'install unchanged', () async {
      final sb = await createScriptSandbox();
      final bundle = Directory('${sb.root.path}/bundle')
        ..createSync(recursive: true);
      Directory('${bundle.path}/lib').createSync();
      final bin = File('${bundle.path}/bin/specstone')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\nexit 3\n');
      Process.runSync('chmod', ['+x', bin.path]);
      await sb.writeArchive('linux-x64', bundle: bundle);
      sb.installFake();
      final before = sb.snapshot();

      final r = await sb.run('install.sh', extra: archiveEnv(sb));

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: the downloaded specstone does not run (exit 3); if TMPDIR '
        'is mounted noexec, set TMPDIR to another folder; the install is '
        'unchanged\n',
      );
      expect(sb.snapshot(), before);
    });
  });
}
