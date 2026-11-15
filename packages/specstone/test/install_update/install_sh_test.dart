@TestOn('!windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../specstone_core/test/helpers/version_cases.dart';
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

  // Gives every file a zsh install writes its PATH line, so a run adds none.
  void writeZshEntries(ScriptSandbox sandbox) {
    for (final name in ['.zshrc', '.zshenv', '.profile']) {
      File('${sandbox.home.path}/$name')
          .writeAsStringSync('export PATH="\$HOME/.specstone/bin:\$PATH"\n');
    }
  }

  String installedVersion(ScriptSandbox sandbox) {
    final result = Process.runSync(
      '${sandbox.home.path}/.specstone/bin/specstone',
      ['--version'],
    );
    return (result.stdout as String).trim();
  }

  // Root ignores file modes, so the chmod tests cannot make a profile
  // unwritable.
  final runsAsRoot =
      !Platform.isWindows &&
      (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
  const rootSkip = 'root ignores file modes';

  // The scripts show a value byte by byte: printable ASCII stays, every
  // other byte of its UTF-8 encoding becomes a question mark.
  String shownBytes(String text) => String.fromCharCodes(
    utf8.encode(text).map((byte) => byte >= 0x20 && byte <= 0x7e ? byte : 0x3f),
  );

  void stubCurlFailing(ScriptSandbox sandbox) {
    sandbox.stub('curl', r'echo "$@" >> "$STUB_LOG_DIR/curl.log"; exit 22');
  }

  group('install.sh', () {
    test('git keeps install.sh and uninstall.sh at LF', () async {
      final r = await Process.run('git', [
        'check-attr',
        'eol',
        '--',
        'install.sh',
        'uninstall.sh',
      ], workingDirectory: repoRoot().path);

      final lines = LineSplitter.split(r.stdout as String).toList();
      expect(lines, hasLength(2));
      expect(lines, everyElement(endsWith('eol: lf')));
    });

    test('Linux aarch64 refuses before any '
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

    test('Git Bash on Windows refuses naming the four '
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

    test('a version argument is ignored; the latest '
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

    group('install by version', () {
      const releases = 'https://github.com/nontravis/specstone/releases';
      const downloadFailed =
          'specstone: download failed for $asset; the install is unchanged\n';

      // Serves the archive folder by file name and logs every URL.
      void stubCurlServing(ScriptSandbox sandbox) {
        sandbox.stub('curl', r'''
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
      }

      // Logs the environment of every grep call, then runs the real grep;
      // STUB_GREP_STRIP_CR drops carriage returns from the form check's input,
      // as BSD grep does.
      void stubGrep(ScriptSandbox sandbox) {
        sandbox.stub('grep', r'''
echo "LC_ALL=${LC_ALL-unset} GREP_OPTIONS=${GREP_OPTIONS-unset} $*" >> "$STUB_LOG_DIR/grep.log"
if [ "$1" = -Eqx ] && [ -n "${STUB_GREP_STRIP_CR:-}" ]; then
  tr -d '\r' | /usr/bin/grep "$@"
else
  exec /usr/bin/grep "$@"
fi''');
      }

      Future<ScriptSandbox> sandboxServing(String version) async {
        final sb = await createScriptSandbox();
        await sb.writeArchive('linux-x64', version: version);
        stubCurlServing(sb);
        return sb;
      }

      test('the named version installs from its own release', () async {
        final sb = await sandboxServing('1.2.0-beta.1');

        final r = await sb.run(
          'install.sh',
          extra: {
            'ARCHIVES': sb.archives.path,
            'SPECSTONE_VERSION': '1.2.0-beta.1',
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        final log = sb.logOf('curl');
        expect(log, hasLength(2));
        expect(log.first, endsWith('$releases/download/v1.2.0-beta.1/$asset'));
        expect(
          log.last,
          endsWith('$releases/download/v1.2.0-beta.1/SHA256SUMS'),
        );
        expect(installedVersion(sb), '1.2.0-beta.1');
      });

      // The form check is shell code of its own, so every form runs through
      // it; one sandbox serves them all, since a refusal changes nothing and
      // an accepted form reaches the stubbed download and stops there.
      test('every refused form is '
          'refused before any download', () async {
        final sb = await createScriptSandbox();
        stubCurlServing(sb);
        sb.installFake();
        final before = sb.snapshot();

        for (final version in refusedVersions) {
          // A NUL cannot cross an environment, so only the core test sees it.
          if (version.isEmpty || version.contains('\u0000')) continue;
          final label = jsonEncode(version);

          final r = await sb.run(
            'install.sh',
            extra: {'SPECSTONE_VERSION': version},
          );

          expect(r.exitCode, 1, reason: label);
          expect(
            r.stderr,
            'specstone: ${shownBytes(version)} '
            'is not a version of the form '
            'MAJOR.MINOR.PATCH[-<pre-release>]; the install is unchanged\n',
            reason: label,
          );
          expect(sb.logOf('curl'), isEmpty, reason: label);
          expect(sb.snapshot(), before, reason: label);
        }
      });

      test('every accepted form passes the form check and fails as a '
          'download', () async {
        final sb = await createScriptSandbox();
        stubCurlFailing(sb);

        for (final (index, version) in acceptedVersions.indexed) {
          final label = jsonEncode(version);

          final r = await sb.run(
            'install.sh',
            extra: {'SPECSTONE_VERSION': version},
          );

          expect(r.exitCode, 1, reason: label);
          expect(r.stderr, downloadFailed, reason: label);
          final log = sb.logOf('curl');
          expect(log, hasLength(index + 1), reason: label);
          expect(
            log.last,
            endsWith('$releases/download/v$version/$asset'),
            reason: label,
          );
        }
      });

      test('a version no release carries fails as a failed '
          'download, the install unchanged', () async {
        final sb = await createScriptSandbox();
        stubCurlFailing(sb);
        sb.installFake();
        final before = sb.snapshot();

        final r = await sb.run(
          'install.sh',
          extra: {'SPECSTONE_VERSION': '9.9.9'},
        );

        expect(r.exitCode, 1);
        expect(r.stderr, downloadFailed);
        expect(sb.snapshot(), before);
      });

      test('an empty version fetches the latest release', () async {
        final sb = await sandboxServing('0.2.0');
        // The sandbox drops an empty variable, so a wrapper sets it empty.
        final wrapper = File('${sb.root.path}/empty_version.sh')
          ..writeAsStringSync(
            'SPECSTONE_VERSION=""\n'
            'export SPECSTONE_VERSION\n'
            'exec /bin/sh "${repoRoot().path}/install.sh"\n',
          );

        final r = await sb.run(
          wrapper.path,
          extra: {'ARCHIVES': sb.archives.path},
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          sb.logOf('curl').first,
          endsWith('$releases/latest/download/$asset'),
        );
        expect(installedVersion(sb), '0.2.0');
      });

      test('the version already installed is named and '
          'nothing is placed', () async {
        final sb = await sandboxServing('1.2.0-beta.1');
        sb.installFake(version: '1.2.0-beta.1');
        writeZshEntries(sb);
        final before = sb.snapshot();

        final r = await sb.run(
          'install.sh',
          extra: {
            'ARCHIVES': sb.archives.path,
            'SPECSTONE_VERSION': '1.2.0-beta.1',
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stdout,
          contains('specstone 1.2.0-beta.1 is already installed'),
        );
        expect(r.stdout, isNot(contains('installed in')));
        expect(r.stdout, isNot(contains('latest release')));
        expect(sb.snapshot(), before);
      });

      test('the form check runs grep with LC_ALL=C and an empty '
          'GREP_OPTIONS', () async {
        final sb = await createScriptSandbox();
        stubGrep(sb);
        stubCurlFailing(sb);

        await sb.run(
          'install.sh',
          extra: {'SPECSTONE_VERSION': '1.2.0', 'GREP_OPTIONS': '-v'},
        );

        final check = sb.logOf('grep').where((line) => line.contains('-Eqx'));
        expect(check, hasLength(1));
        expect(check.single, startsWith('LC_ALL=C GREP_OPTIONS= -Eqx '));
      });

      test('GREP_OPTIONS=-v neither lets a path through nor refuses '
          'a version', () async {
        final sb = await createScriptSandbox();
        stubCurlFailing(sb);
        const path = '1.2.0/../../../../evil/x/releases/download/v1';

        final refused = await sb.run(
          'install.sh',
          extra: {'SPECSTONE_VERSION': path, 'GREP_OPTIONS': '-v'},
        );
        final accepted = await sb.run(
          'install.sh',
          extra: {'SPECSTONE_VERSION': '1.2.0', 'GREP_OPTIONS': '-v'},
        );

        expect(
          refused.stderr,
          'specstone: $path is not a version of the form '
          'MAJOR.MINOR.PATCH[-<pre-release>]; the install is unchanged\n',
        );
        expect(accepted.stderr, downloadFailed);
        expect(sb.logOf('curl').single, endsWith('/v1.2.0/$asset'));
      });

      test('a carriage return is refused even when grep drops it', () async {
        final sb = await createScriptSandbox();
        stubGrep(sb);
        stubCurlFailing(sb);

        final r = await sb.run(
          'install.sh',
          extra: {'SPECSTONE_VERSION': '1.2.0\r', 'STUB_GREP_STRIP_CR': '1'},
        );

        expect(r.exitCode, 1);
        expect(r.stderr, startsWith('specstone: 1.2.0? is not a version'));
        expect(sb.logOf('curl'), isEmpty);
      });

      test('a named version replaces an older CLI', () async {
        final sb = await sandboxServing('1.2.0-beta.1');
        sb.installFake();

        final r = await sb.run(
          'install.sh',
          extra: {
            'ARCHIVES': sb.archives.path,
            'SPECSTONE_VERSION': '1.2.0-beta.1',
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stdout,
          contains(
            'specstone 1.2.0-beta.1 installed in ${sb.home.path}/.specstone/bin',
          ),
        );
        expect(installedVersion(sb), '1.2.0-beta.1');
      });
    });

    for (final (os, machine, target) in [
      ('Darwin', 'arm64', 'macos-arm64'),
      ('Darwin', 'x86_64', 'macos-x64'),
      ('Linux', 'x86_64', 'linux-x64'),
    ]) {
      test('$os $machine reads the $target archive', () async {
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

    test('a failed download stops with the install '
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

    test('a damaged archive stops, the older '
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

    test('no SHA256SUMS line is a checksum failure', () async {
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
    });

    test('the temp folder is gone after a failure and after '
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

    test('an older CLI is replaced; packs stay; '
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

    test('the same version is left as it is', () async {
      final sb = await sandboxWith();
      sb.installFake(version: '0.2.0');
      writeZshEntries(sb);
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

    test('an empty home gains .specstone with bin and lib '
        'only', () async {
      final sb = await sandboxWith();

      final r = await sb.run('install.sh', extra: archiveEnv(sb));

      expect(r.exitCode, 0, reason: '${r.stderr}');
      final top = Directory('${sb.home.path}/.specstone')
          .listSync()
          .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last);
      expect(top.toSet(), {'bin', 'lib'});
    });

    test("the running binary's file is never written", () async {
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

    test('a truncated script stream runs nothing', () async {
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

    test('no HOME and no USERPROFILE refuses '
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

    test('the curl path fetches the archive and SHA256SUMS, '
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

    test('shasum is used when sha256sum is absent', () async {
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

    test('an upper-case hash in SHA256SUMS still matches', () async {
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
    });

    test('a stream cut just before main runs nothing', () async {
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

    for (final folder in ['lib', 'bin']) {
      test('a failed $folder copy is named, leaves no staging '
          'and the old install runnable', () async {
        final sb = await sandboxWith();
        sb
          ..installFake()
          ..stub(
            'cp',
            r'case "$*" in'
                '\n'
                '  *.$folder.new*) exit 1 ;;\n'
                'esac\n'
                r'exec /bin/cp "$@"',
          );
        final before = sb.snapshot();

        final r = await sb.run('install.sh', extra: archiveEnv(sb));

        expect(r.exitCode, 1);
        expect(
          r.stderr,
          'specstone: could not place ${sb.home.path}/.specstone/$folder: '
          'run the install again\n',
        );
        expect(installedVersion(sb), '0.1.0');
        expect(sb.snapshot(), before);
        expect(
          Directory('${sb.home.path}/.specstone').listSync().map((e) => e.path),
          isNot(anyElement(contains('.new'))),
        );
      });
    }

    test('an unpack failure names the archive, install '
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

    test('a downloaded binary that does not run is named, '
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

    test('a downloaded binary that fails with a message '
        'names that first stderr line', () async {
      final sb = await createScriptSandbox();
      final bundle = Directory('${sb.root.path}/bundle')
        ..createSync(recursive: true);
      Directory('${bundle.path}/lib').createSync();
      final bin = File('${bundle.path}/bin/specstone')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/sh\n'
          "printf '\\nversion GLIBC_2.34 not found\\r\\nsecond\\n' >&2\n"
          'exit 1\n',
        );
      Process.runSync('chmod', ['+x', bin.path]);
      await sb.writeArchive('linux-x64', bundle: bundle);
      sb.installFake();
      final before = sb.snapshot();

      final r = await sb.run('install.sh', extra: archiveEnv(sb));

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: the downloaded specstone does not run (exit 1: version '
        'GLIBC_2.34 not found); if TMPDIR is mounted noexec, set TMPDIR to '
        'another folder; the install is unchanged\n',
      );
      expect(sb.snapshot(), before);
    });

    test('a temporary folder that cannot be made prints a '
        'specstone line, install unchanged', () async {
      final sb = await createScriptSandbox();
      sb.installFake();
      final before = sb.snapshot();
      final missing = '${sb.root.path}/no-such-folder';

      final r = await sb.run(
        'install.sh',
        extra: {...archiveEnv(sb), 'TMPDIR': missing},
      );

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: could not make a temporary folder in $missing; the '
        'install is unchanged\n',
      );
      expect(sb.snapshot(), before);
    });

    group('PATH entry', () {
      const posixLine = 'export PATH="\$HOME/.specstone/bin:\$PATH"\n';
      const fishLine = 'set -gx PATH "\$HOME/.specstone/bin" \$PATH\n';

      Future<ProcessResult> runWith(
        ScriptSandbox sb,
        Map<String, String> extra,
      ) => sb.run('install.sh', extra: {...archiveEnv(sb), ...extra});

      // The one note naming each file the run wrote, in the order written.
      String addedIn(List<String> paths) {
        final names = switch (paths) {
          [final one] => one,
          [final first, final second] => '$first and $second',
          _ => '${paths.take(paths.length - 1).join(', ')}, and ${paths.last}',
        };
        return 'Added ~/.specstone/bin to the PATH in $names. '
            'Open a new terminal to use specstone.\n';
      }

      String added(ScriptSandbox sb, String file) =>
          addedIn(['${sb.home.path}/$file']);

      test('zsh gains one line in ~/.zshrc, ~/.zshenv, and ~/.profile '
          'and the new-terminal note', () async {
        final sb = await sandboxWith();

        final r = await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        for (final file in ['.zshrc', '.zshenv', '.profile']) {
          expect(File('${sb.home.path}/$file').readAsStringSync(), posixLine);
        }
        expect(
          r.stdout,
          contains(
            addedIn([
              for (final file in ['.zshrc', '.zshenv', '.profile'])
                '${sb.home.path}/$file',
            ]),
          ),
        );
      });

      test('zsh with ZDOTDIR set writes .zshenv there and '
          'not in ~', () async {
        final sb = await sandboxWith();
        final zdotdir = '${sb.root.path}/zdot';

        final r = await runWith(sb, {'SHELL': '/bin/zsh', 'ZDOTDIR': zdotdir});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(File('$zdotdir/.zshenv').readAsStringSync(), posixLine);
        expect(sb.snapshot().keys, isNot(contains('.zshenv')));
        for (final file in ['.zshrc', '.profile']) {
          expect(File('${sb.home.path}/$file').readAsStringSync(), posixLine);
        }
        expect(
          r.stdout,
          contains(
            addedIn([
              '${sb.home.path}/.zshrc',
              '$zdotdir/.zshenv',
              '${sb.home.path}/.profile',
            ]),
          ),
        );
      });

      for (final zdotdir in [null, 'zdot']) {
        test('a second zsh run keeps one line in each file and prints no '
            'note${zdotdir == null ? '' : ' with ZDOTDIR'}', () async {
          final sb = await sandboxWith();
          final env = {
            'SHELL': '/bin/zsh',
            'ZDOTDIR': ?zdotdir == null ? null : '${sb.root.path}/$zdotdir',
          };
          await runWith(sb, env);
          final before = sb.snapshot();

          final r = await runWith(sb, env);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(r.stdout, isNot(contains('Added')));
          expect(sb.snapshot(), before);
          for (final file in ['.zshrc', '.profile']) {
            expect(File('${sb.home.path}/$file').readAsStringSync(), posixLine);
          }
        });
      }

      test('bash on macOS writes ~/.bashrc, ~/.bash_profile, and '
          '~/.profile', () async {
        final sb = await sandboxWith(target: 'macos-arm64');

        final r = await runWith(sb, {
          'SHELL': '/bin/bash',
          'STUB_UNAME_S': 'Darwin',
          'STUB_UNAME_M': 'arm64',
        });

        expect(r.exitCode, 0, reason: '${r.stderr}');
        for (final file in ['.bashrc', '.bash_profile', '.profile']) {
          expect(File('${sb.home.path}/$file').readAsStringSync(), posixLine);
        }
        expect(
          r.stdout,
          contains(
            addedIn([
              for (final file in ['.bashrc', '.bash_profile', '.profile'])
                '${sb.home.path}/$file',
            ]),
          ),
        );
      });

      test('bash on Linux writes ~/.bashrc and ~/.profile', () async {
        final sb = await sandboxWith();

        final r = await runWith(sb, {'SHELL': '/usr/bin/bash'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        for (final file in ['.bashrc', '.profile']) {
          expect(File('${sb.home.path}/$file').readAsStringSync(), posixLine);
        }
        expect(sb.snapshot().keys, isNot(contains('.bash_profile')));
      });

      test('fish writes ~/.config/fish/conf.d/specstone.fish '
          'and ~/.profile', () async {
        final sb = await sandboxWith();

        final r = await runWith(sb, {'SHELL': '/usr/local/bin/fish'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        const fishFile = '.config/fish/conf.d/specstone.fish';
        expect(File('${sb.home.path}/$fishFile').readAsStringSync(), fishLine);
        expect(File('${sb.home.path}/.profile').readAsStringSync(), posixLine);
        expect(
          r.stdout,
          contains(
            addedIn(['${sb.home.path}/$fishFile', '${sb.home.path}/.profile']),
          ),
        );
      });

      for (final shell in ['/bin/tcsh', 'nu']) {
        test('SHELL="$shell" writes ~/.profile', () async {
          final sb = await sandboxWith();

          final r = await runWith(sb, {'SHELL': shell});

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            File('${sb.home.path}/.profile').readAsStringSync(),
            posixLine,
          );
          expect(r.stdout, contains(added(sb, '.profile')));
        });
      }

      test('a missing file is created holding the '
          'line', () async {
        final sb = await sandboxWith();
        expect(File('${sb.home.path}/.zshrc').existsSync(), isFalse);

        await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(File('${sb.home.path}/.zshrc').readAsStringSync(), posixLine);
      });

      test('a last line with no newline stays its own '
          'line', () async {
        final sb = await sandboxWith();
        File('${sb.home.path}/.zshrc').writeAsStringSync('alias a=b');

        await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(
          File('${sb.home.path}/.zshrc').readAsStringSync(),
          'alias a=b\n$posixLine',
        );
      });

      test('other lines stay and a longer line naming the '
          'folder does not count as the entry', () async {
        final sb = await sandboxWith();
        const before =
            '# my profile\nexport PATH="\$HOME/.specstone/bin:\$PATH":/x\n';
        File('${sb.home.path}/.zshrc').writeAsStringSync(before);

        await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(
          File('${sb.home.path}/.zshrc').readAsStringSync(),
          '$before$posixLine',
        );
      });

      test(
        'an unset SHELL writes ~/.profile',
        () async {
          final sb = await sandboxWith();

          final r = await runWith(sb, {'SHELL': ''});

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            File('${sb.home.path}/.profile').readAsStringSync(),
            posixLine,
          );
        },
        // macOS /bin/sh is bash, which refills an unset SHELL.
        testOn: '!mac-os',
      );

      test('an unwritable profile warns, the other target is '
          'still written, exit 0', () async {
        final sb = await sandboxWith(target: 'macos-arm64');
        final rc = File('${sb.home.path}/.bashrc')
          ..writeAsStringSync('# mine\n');
        Process.runSync('chmod', ['444', rc.path]);

        final r = await runWith(sb, {
          'SHELL': '/bin/bash',
          'STUB_UNAME_S': 'Darwin',
          'STUB_UNAME_M': 'arm64',
        });

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stderr,
          'specstone: could not write ${rc.path}: add '
          '${posixLine.trim()} to it yourself\n',
        );
        expect(rc.readAsStringSync(), '# mine\n');
        for (final file in ['.bash_profile', '.profile']) {
          expect(File('${sb.home.path}/$file').readAsStringSync(), posixLine);
        }
      }, skip: runsAsRoot ? rootSkip : null);

      test('an unreadable profile is not appended to', () async {
        final sb = await sandboxWith();
        final rc = File('${sb.home.path}/.zshrc')
          ..writeAsStringSync('alias a=b');
        Process.runSync('chmod', ['000', rc.path]);
        addTearDown(() => Process.runSync('chmod', ['644', rc.path]));

        final r = await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stderr, startsWith('specstone: could not write ${rc.path}'));
        Process.runSync('chmod', ['644', rc.path]);
        expect(rc.readAsStringSync(), 'alias a=b');
      }, skip: runsAsRoot ? rootSkip : null);

      for (final (existing, expected) in [
        (['.profile'], '.profile'),
        (['.bash_login'], '.bash_login'),
        (['.bash_login', '.profile'], '.bash_login'),
      ]) {
        test('macOS bash with only ${existing.join(", ")} '
            'writes $expected and creates no ~/.bash_profile', () async {
          final sb = await sandboxWith(target: 'macos-arm64');
          for (final name in existing) {
            File('${sb.home.path}/$name').writeAsStringSync('# mine\n');
          }
          final env = {
            'SHELL': '/bin/bash',
            'STUB_UNAME_S': 'Darwin',
            'STUB_UNAME_M': 'arm64',
          };

          final r = await runWith(sb, env);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            File('${sb.home.path}/$expected').readAsStringSync(),
            '# mine\n$posixLine',
          );
          expect(
            File('${sb.home.path}/.profile')
                .readAsLinesSync()
                .where((line) => line == posixLine.trim()),
            hasLength(1),
          );
          expect(sb.snapshot().keys, isNot(contains('.bash_profile')));
          final before = sb.snapshot();

          final again = await runWith(sb, env);

          expect(again.stdout, isNot(contains('Added')));
          expect(sb.snapshot(), before);
        });
      }

      test('a second run on macOS bash adds nothing to '
          'either file', () async {
        final sb = await sandboxWith(target: 'macos-arm64');
        final env = {
          'SHELL': '/bin/bash',
          'STUB_UNAME_S': 'Darwin',
          'STUB_UNAME_M': 'arm64',
        };
        await runWith(sb, env);
        final before = sb.snapshot();

        final r = await runWith(sb, env);

        expect(r.stdout, isNot(contains('Added')));
        expect(sb.snapshot(), before);
      });

      test('the same version still gets its PATH '
          'entry', () async {
        final sb = await sandboxWith();
        sb.installFake(version: '0.2.0');

        final r = await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, contains('is already the latest release'));
        expect(File('${sb.home.path}/.zshrc').readAsStringSync(), posixLine);
        expect(
          r.stdout,
          contains(
            addedIn([
              for (final file in ['.zshrc', '.zshenv', '.profile'])
                '${sb.home.path}/$file',
            ]),
          ),
        );
      });
    });

    group('no plugin step', () {
      for (final (label, env) in [
        ('a plain install', <String, String>{}),
        ('an install by version', {'SPECSTONE_VERSION': '1.2.0-beta.1'}),
      ]) {
        test('$label runs no claude command and prints no plugin '
            'line', () async {
          final sb = await sandboxWith();
          sb.stub('claude', r'echo "$*" >> "$STUB_LOG_DIR/claude.log"');

          final r = await sb.run(
            'install.sh',
            extra: {...archiveEnv(sb), ...env},
          );

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('claude'), isEmpty);
          for (final word in ['Claude', 'plugin', 'marketplace']) {
            expect(r.stdout, isNot(contains(word)));
            expect(r.stderr, isNot(contains(word)));
          }
        });
      }
    });

    group('prerequisite warnings', () {
      const macGitCommand = 'xcode-select --install';
      const linuxGitCommand = 'sudo apt install git';
      const linuxFloorLine =
          'specstone: git 2.25 or later is missing; install it with '
          '$linuxGitCommand\n';

      Future<ProcessResult> runWith(
        ScriptSandbox sb, [
        Map<String, String> extra = const {},
      ]) => sb.run('install.sh', extra: {...archiveEnv(sb), ...extra});

      test('a Mac with git 2.39 warns about nothing', () async {
        final sb = await sandboxWith(target: 'macos-arm64');
        sb.stub('git', r'''
echo "$*" >> "$STUB_LOG_DIR/git.log"
case "$*" in
  --version) echo 'git version 2.39.0' ;;
esac''');

        final r = await runWith(sb, {
          'STUB_UNAME_S': 'Darwin',
          'STUB_UNAME_M': 'arm64',
        });

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, isNot(contains('specstone:')));
        expect(sb.logOf('git'), ['--version']);
      });

      test('Linux with git 2.20 warns naming the floor and the '
          'install command', () async {
        final sb = await sandboxWith();
        sb.stub('git', 'echo "git version 2.20.0"\n');

        final r = await runWith(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stdout,
          contains(
            'specstone: git 2.25 or later is missing; install it with '
            '$linuxGitCommand\n',
          ),
        );
        expect(r.stdout, isNot(contains('Claude Code')));
      });

      test('a missing git warns once; the install still ran and its exit '
          'status is kept', () async {
        final sb = await sandboxWith();
        sb.stub('git', 'exit 127\n');

        final r = await runWith(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, contains(linuxFloorLine));
        expect(installedVersion(sb), '0.2.0');
        expect(
          File('${sb.home.path}/.specstone/bin/specstone').existsSync(),
          isTrue,
        );
      });

      for (final (os, machine, command) in [
        ('Darwin', 'arm64', macGitCommand),
        ('Linux', 'x86_64', linuxGitCommand),
      ]) {
        test('no git on $os warns naming $command', () async {
          final sb = await sandboxWith(
            target: os == 'Darwin' ? 'macos-arm64' : 'linux-x64',
          );
          // /usr/bin stays on the sandbox PATH and holds the machine's own
          // git; the stub answers as a shell does for a command not found.
          sb.stub('git', 'exit 127\n');

          final r = await runWith(sb, {
            'STUB_UNAME_S': os,
            'STUB_UNAME_M': machine,
          });

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            r.stdout,
            contains(
              'specstone: git 2.25 or later is missing; install it with '
              '$command\n',
            ),
          );
        });
      }

      for (final (version, warns) in [
        ('git version 2.25.0', false),
        ('git version 2.24.1', true),
        ('git version 2.24.1.320', true),
        ('git version 2.39.3 (Apple Git-146)', false),
        ('git version 3.0.0', false),
        ('git version 1.9.5', true),
      ]) {
        test('$version counts as ${warns ? "below" : "at or above"} '
            'the floor', () async {
          final sb = await sandboxWith();
          sb.stub('git', 'echo "$version"\n');

          final r = await runWith(sb);

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            (r.stdout as String).contains('git 2.25 or later is missing'),
            warns,
          );
        });
      }

      test('a git that cannot report a version counts as missing and '
          'keeps the exit status', () async {
        final sb = await sandboxWith();
        sb.stub('git', 'exit 129\n');

        final r = await runWith(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stdout,
          contains(
            'specstone: git 2.25 or later is missing; install it with '
            '$linuxGitCommand\n',
          ),
        );
      });
    });

    group('PATH search', () {
      // Each name is planted in the run folder and in a relative `planted`
      // folder; a planted program only records that it ran.
      const plantedNames = ['git', 'uname', 'mktemp', 'tar', 'awk', 'cp'];

      void plantPrograms(ScriptSandbox sb) {
        for (final folder in ['.', 'planted']) {
          for (final name in plantedNames) {
            final file = File('${sb.root.path}/$folder/$name')
              ..createSync(recursive: true)
              ..writeAsStringSync(
                '#!/bin/sh\n: > "\$STUB_LOG_DIR/planted-$name.ran"\n',
              );
            Process.runSync('chmod', ['755', file.path]);
          }
        }
      }

      List<String> plantedThatRan(ScriptSandbox sb) => [
        for (final name in plantedNames)
          if (File('${sb.logs.path}/planted-$name.ran').existsSync()) name,
      ];

      final pathsWithRelativeEntries = <String, String Function(String)>{
        'a dot': (stubs) => '.:$stubs:/usr/bin:/bin',
        'a leading empty entry': (stubs) => ':$stubs:/usr/bin:/bin',
        'a middle empty entry': (stubs) => '$stubs::/usr/bin:/bin',
        'a relative folder': (stubs) => 'planted:$stubs:/usr/bin:/bin',
      };

      for (final MapEntry(key: label, value: pathOf)
          in pathsWithRelativeEntries.entries) {
        test('$label on PATH never starts a program from there; the install '
            'runs', () async {
          final sb = await sandboxWith();
          plantPrograms(sb);

          final r = await sb.run(
            'install.sh',
            extra: {...archiveEnv(sb), 'PATH': pathOf(sb.stubs.path)},
          );

          expect(plantedThatRan(sb), isEmpty);
          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(installedVersion(sb), '0.2.0');
        });
      }

      test(
        'a PATH of relative entries only searches no relative folder',
        () async {
          final sb = await sandboxWith();
          plantPrograms(sb);

          await sb.run(
            'install.sh',
            extra: {...archiveEnv(sb), 'PATH': '.:planted:'},
          );

          expect(plantedThatRan(sb), isEmpty);
        },
      );
    });

    group('name another stn at install', () {
      String notice(String path) =>
          'specstone: another stn is at $path; '
          'type specstone to run the CLI\n';

      // Writes another tool's recording `stn` in [folder] and returns the
      // entry's path.
      String otherStn(String folder, {int exit = 0}) {
        final file = File('$folder/stn')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            '#!/bin/sh\n'
            r'printf "%s\n" "$*" >> "$STUB_LOG_DIR/other.log"'
            '\n'
            'exit $exit\n',
          );
        Process.runSync('chmod', ['755', file.path]);
        return folder;
      }

      test('another stn on a later absolute entry prints one '
          'notice line; bin/stn is installed and executable; exit 0', () async {
        final sb = await sandboxWith();
        final tools = Directory('${sb.root.path}/space tools')..createSync();
        otherStn(tools.path, exit: 7);

        final r = await sb.run(
          'install.sh',
          extra: {
            ...archiveEnv(sb),
            'PATH': [
              '${sb.home.path}/.specstone/bin',
              tools.path,
              sb.stubs.path,
              '/usr/bin:/bin',
            ].join(':'),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, contains(notice('${tools.path}/stn')));
        final occurrences = 'another stn'.allMatches(r.stdout as String).length;
        expect(occurrences, 1);
        final shim = File('${sb.home.path}/.specstone/bin/stn');
        expect(shim.existsSync(), isTrue);
        // The run keeps the runner's PATH out, so the shim beside the fake
        // specstone is the program that runs, not a stn on this machine.
        final run = Process.runSync(
          shim.path,
          ['--version'],
          environment: const {'PATH': '/usr/bin:/bin'},
          includeParentEnvironment: false,
        );
        expect(run.exitCode, 0, reason: '${run.stderr}');
        expect(sb.logOf('other'), isEmpty);
      });

      test('two other stn name the earlier entry only', () async {
        final sb = await sandboxWith();
        final first = otherStn('${sb.root.path}/first');
        final second = otherStn('${sb.root.path}/second');

        final r = await sb.run(
          'install.sh',
          extra: {
            ...archiveEnv(sb),
            'PATH': [
              '${sb.home.path}/.specstone/bin',
              first,
              second,
              sb.stubs.path,
              '/usr/bin:/bin',
            ].join(':'),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, contains(notice('$first/stn')));
        expect(r.stdout, isNot(contains('$second/stn')));
      });

      test('no other stn prints no notice', () async {
        final sb = await sandboxWith();

        final r = await sb.run(
          'install.sh',
          extra: {
            ...archiveEnv(sb),
            'PATH': [
              '${sb.home.path}/.specstone/bin',
              sb.stubs.path,
              '/usr/bin:/bin',
            ].join(':'),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, isNot(contains('another stn')));
      });

      test('a stn on a relative entry only prints no notice', () async {
        final sb = await sandboxWith();
        otherStn('${sb.root.path}/rel');

        final r = await sb.run(
          'install.sh',
          extra: {
            ...archiveEnv(sb),
            'PATH': ['rel:.::', sb.stubs.path, '/usr/bin:/bin'].join(':'),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, isNot(contains('another stn')));
      });

      test('the install folder with a trailing slash or through a '
          'symlink prints no notice', () async {
        final sb = await sandboxWith();
        final linked = '${sb.root.path}/linked';
        Process.runSync('ln', ['-s', '${sb.home.path}/.specstone/bin', linked]);

        for (final entry in ['${sb.home.path}/.specstone/bin/', linked]) {
          final r = await sb.run(
            'install.sh',
            extra: {
              ...archiveEnv(sb),
              'PATH': [entry, sb.stubs.path, '/usr/bin:/bin'].join(':'),
            },
          );

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(r.stdout, isNot(contains('another stn')), reason: entry);
        }
      });

      test('a folder named stn prints no notice', () async {
        final sb = await sandboxWith();
        Directory('${sb.root.path}/tools/stn').createSync(recursive: true);

        final r = await sb.run(
          'install.sh',
          extra: {
            ...archiveEnv(sb),
            'PATH': [
              '${sb.home.path}/.specstone/bin',
              '${sb.root.path}/tools',
              sb.stubs.path,
              '/usr/bin:/bin',
            ].join(':'),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, isNot(contains('another stn')));
      });

      test('a non-executable file named stn prints no notice', () async {
        final sb = await sandboxWith();
        File('${sb.root.path}/tools/stn')
          ..createSync(recursive: true)
          ..writeAsStringSync('#!/bin/sh\nexit 5\n');

        final r = await sb.run(
          'install.sh',
          extra: {
            ...archiveEnv(sb),
            'PATH': [
              '${sb.home.path}/.specstone/bin',
              '${sb.root.path}/tools',
              sb.stubs.path,
              '/usr/bin:/bin',
            ].join(':'),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, isNot(contains('another stn')));
      });

      test('a missing absolute entry is skipped with nothing '
          'on stderr', () async {
        final sb = await sandboxWith();
        final missing = '${sb.root.path}/no such folder';

        final r = await sb.run(
          'install.sh',
          extra: {
            ...archiveEnv(sb),
            'PATH': [
              '${sb.home.path}/.specstone/bin',
              missing,
              sb.stubs.path,
              '/usr/bin:/bin',
            ].join(':'),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stderr, isEmpty, reason: '${r.stderr}');
        expect(r.stdout, isNot(contains('another stn')));
      });

      test('api install step 5: a run at the installed Version prints the '
          'notice too', () async {
        final sb = await sandboxWith();
        sb.installFake(version: '0.2.0');
        final tools = Directory('${sb.root.path}/tools')..createSync();
        otherStn(tools.path);

        final r = await sb.run(
          'install.sh',
          extra: {
            ...archiveEnv(sb),
            'PATH': [
              '${sb.home.path}/.specstone/bin',
              tools.path,
              sb.stubs.path,
              '/usr/bin:/bin',
            ].join(':'),
          },
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, contains('is already the latest release'));
        expect(r.stdout, contains(notice('${tools.path}/stn')));
      });
    });
  });
}
