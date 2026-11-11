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

  // Root ignores file modes, so the chmod tests cannot make a profile
  // unwritable.
  final runsAsRoot =
      !Platform.isWindows &&
      (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
  const rootSkip = 'root ignores file modes';

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
      File('${sb.home.path}/.zshrc')
          .writeAsStringSync('export PATH="\$HOME/.specstone/bin:\$PATH"\n');
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

    test('f09/us01/fr03: no HOME and no USERPROFILE refuses '
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

    for (final folder in ['lib', 'bin']) {
      test('f09/us01/fr03: a failed $folder copy is named, leaves no staging '
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

    test('f09/us01/fr02: a downloaded binary that fails with a message '
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

    test('f09/us01/fr02: a temporary folder that cannot be made prints a '
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

      String added(ScriptSandbox sb, String file) =>
          'Added ~/.specstone/bin to the PATH in ${sb.home.path}/$file. '
          'Open a new terminal to use specstone.\n';

      test('f09/us01/fr04, f09/us01/s1: zsh gains one line in ~/.zshrc and '
          'the new-terminal note', () async {
        final sb = await sandboxWith();

        final r = await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(File('${sb.home.path}/.zshrc').readAsStringSync(), posixLine);
        expect(r.stdout, contains(added(sb, '.zshrc')));
        expect(sb.snapshot().keys, isNot(contains('.profile')));
      });

      test('f09/us01/fr04/e01: a second run keeps one line and prints no '
          'note', () async {
        final sb = await sandboxWith();
        await runWith(sb, {'SHELL': '/bin/zsh'});

        final r = await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(File('${sb.home.path}/.zshrc').readAsStringSync(), posixLine);
        expect(r.stdout, isNot(contains('Added')));
      });

      test('f09/us01/fr04: bash on macOS writes ~/.bashrc and '
          '~/.bash_profile', () async {
        final sb = await sandboxWith(target: 'macos-arm64');

        final r = await runWith(sb, {
          'SHELL': '/bin/bash',
          'STUB_UNAME_S': 'Darwin',
          'STUB_UNAME_M': 'arm64',
        });

        expect(r.exitCode, 0, reason: '${r.stderr}');
        for (final file in ['.bashrc', '.bash_profile']) {
          expect(File('${sb.home.path}/$file').readAsStringSync(), posixLine);
          expect(r.stdout, contains(added(sb, file)));
        }
      });

      test('f09/us01/fr04/e03: bash on Linux writes ~/.bashrc only', () async {
        final sb = await sandboxWith();

        final r = await runWith(sb, {'SHELL': '/usr/bin/bash'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(File('${sb.home.path}/.bashrc').readAsStringSync(), posixLine);
        expect(sb.snapshot().keys, isNot(contains('.bash_profile')));
      });

      test('f09/us01/fr04: fish writes ~/.config/fish/conf.d/specstone.fish '
          'and not ~/.profile', () async {
        final sb = await sandboxWith();

        final r = await runWith(sb, {'SHELL': '/usr/local/bin/fish'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          File('${sb.home.path}/.config/fish/conf.d/specstone.fish')
              .readAsStringSync(),
          fishLine,
        );
        expect(sb.snapshot().keys, isNot(contains('.profile')));
      });

      for (final shell in ['/bin/tcsh', 'nu']) {
        test('f09/us01/fr04: SHELL="$shell" writes ~/.profile', () async {
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

      test('f09/us01/fr04/e02: a missing file is created holding the '
          'line', () async {
        final sb = await sandboxWith();
        expect(File('${sb.home.path}/.zshrc').existsSync(), isFalse);

        await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(File('${sb.home.path}/.zshrc').readAsStringSync(), posixLine);
      });

      test('f09/us01/fr04: a last line with no newline stays its own '
          'line', () async {
        final sb = await sandboxWith();
        File('${sb.home.path}/.zshrc').writeAsStringSync('alias a=b');

        await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(
          File('${sb.home.path}/.zshrc').readAsStringSync(),
          'alias a=b\n$posixLine',
        );
      });

      test('f09/us01/fr04: other lines stay and a longer line naming the '
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
        'f09/us01/fr04: an unset SHELL writes ~/.profile',
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

      test('f09/us01/fr04: an unwritable profile warns, the other target is '
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
        expect(
          File('${sb.home.path}/.bash_profile').readAsStringSync(),
          posixLine,
        );
      }, skip: runsAsRoot ? rootSkip : null);

      test('f09/us01/fr04: an unreadable profile is not appended to', () async {
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
        test('f09/us01/fr04: macOS bash with only ${existing.join(", ")} '
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
          expect(sb.snapshot().keys, isNot(contains('.bash_profile')));
          final before = sb.snapshot();

          final again = await runWith(sb, env);

          expect(again.stdout, isNot(contains('Added')));
          expect(sb.snapshot(), before);
        });
      }

      test('f09/us01/fr04: a second run on macOS bash adds nothing to '
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

      test('f09/us01/fr03/e03: the same version still gets its PATH '
          'entry', () async {
        final sb = await sandboxWith();
        sb.installFake(version: '0.2.0');

        final r = await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, contains('is already the latest release'));
        expect(File('${sb.home.path}/.zshrc').readAsStringSync(), posixLine);
        expect(r.stdout, contains(added(sb, '.zshrc')));
      });
    });

    group('plugin step', () {
      const marketplaceJson =
          '[{"name": "specstone", "source": "github", "repo": '
          '"nontravis/specstone"}]';
      const userPluginJson =
          '[{"id": "specstone@specstone", "version": "0.2.0", '
          '"scope": "user"}]';
      const listMarketplaces = 'plugin marketplace list --json';
      const listPlugins = 'plugin list --json';
      const addMarketplace = 'plugin marketplace add nontravis/specstone';
      const installPlugin = 'plugin install specstone@specstone';

      Future<ScriptSandbox> sandboxWithClaude() async {
        final sb = await sandboxWith();
        sb.stub('claude', r'''
echo "$*" >> "$STUB_LOG_DIR/claude.log"
if [ "$*" = "${STUB_FAIL:-}" ]; then
  echo boom >&2
  echo more >&2
  exit 1
fi
case "$*" in
  'plugin marketplace list --json') echo "${STUB_MARKETPLACES:-[]}" ;;
  'plugin list --json') echo "${STUB_PLUGINS:-[]}" ;;
esac''');
        return sb;
      }

      Future<ProcessResult> runWith(
        ScriptSandbox sb, [
        Map<String, String> extra = const {},
      ]) => sb.run('install.sh', extra: {...archiveEnv(sb), ...extra});

      test('f09/us01/fr05, f09/us01/s1: claude adds the marketplace, then '
          'installs the plugin', () async {
        final sb = await sandboxWithClaude();

        final r = await runWith(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          addMarketplace,
          installPlugin,
        ]);
      });

      test('f09/us01/fr05/e01: an added marketplace skips the add', () async {
        final sb = await sandboxWithClaude();

        final r = await runWith(sb, {'STUB_MARKETPLACES': marketplaceJson});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          installPlugin,
        ]);
      });

      test(
        'f09/us01/fr05/e02: an installed plugin skips the install',
        () async {
          final sb = await sandboxWithClaude();

          final r = await runWith(sb, {
            'STUB_MARKETPLACES': marketplaceJson,
            'STUB_PLUGINS': userPluginJson,
          });

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
        },
      );

      test('f09/us01/fr05/e02: a pretty-printed list still counts the user '
          'entry', () async {
        final sb = await sandboxWithClaude();

        final r = await runWith(sb, {
          'STUB_MARKETPLACES': marketplaceJson,
          'STUB_PLUGINS':
              '[\n  {\n    "id" : "specstone@specstone",\n'
              '    "version": "0.2.0",\n    "scope"  :  "user"\n  }\n]',
        });

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
      });

      test('f09/us01/fr05/e02: a project- or local-scope specstone@specstone '
          'still installs at user scope', () async {
        final sb = await sandboxWithClaude();

        final r = await runWith(sb, {
          'STUB_MARKETPLACES': marketplaceJson,
          'STUB_PLUGINS':
              '[{"id": "specstone@specstone", "version": "0.2.0", '
              '"scope": "project"}, {"id": "specstone@specstone", '
              '"version": "0.2.0", "scope": "local"}]',
        });

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          installPlugin,
        ]);
      });

      test('f09/us01/fr05/e02: a user entry of another plugin does not '
          'count', () async {
        final sb = await sandboxWithClaude();

        final r = await runWith(sb, {
          'STUB_MARKETPLACES': marketplaceJson,
          'STUB_PLUGINS':
              '[{"id": "other@specstone", "version": "1.0.0", '
              '"scope": "user"}, {"id": "specstone@specstone", '
              '"version": "0.2.0", "scope": "project"}]',
        });

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          installPlugin,
        ]);
      });

      test('f09/us01/fr05: a marketplace named specstone-extra is not '
          'specstone', () async {
        final sb = await sandboxWithClaude();

        final r = await runWith(sb, {
          'STUB_MARKETPLACES':
              '[{"name": "specstone-extra", "source": "github", '
              '"repo": "someone/specstone-extra"}]',
        });

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(sb.logOf('claude'), contains(addMarketplace));
      });

      test('f09/us01/fr05/e03, f09/us01/s3: no claude prints both commands; '
          'the CLI stays; exit 0', () async {
        final sb = await sandboxWith();

        final r = await runWith(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stdout,
          contains(
            'To add the Specstone plugin to Claude Code, run:\n'
            '  claude plugin marketplace add nontravis/specstone\n'
            '  claude plugin install specstone@specstone\n',
          ),
        );
        expect(
          File('${sb.home.path}/.specstone/bin/specstone').existsSync(),
          isTrue,
        );
      });

      test('f09/us01/fr05/e04: a failing install names its first stderr '
          'line; exit 0', () async {
        final sb = await sandboxWithClaude();

        final r = await runWith(sb, {'STUB_FAIL': installPlugin});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stderr,
          contains(
            'specstone: claude $installPlugin failed: boom; run it by hand\n',
          ),
        );
        expect(r.stderr, isNot(contains('more')));
        expect(
          File('${sb.home.path}/.specstone/bin/specstone').existsSync(),
          isTrue,
        );
      });

      test('f09/us01/fr05: a command with empty stderr is named with its exit '
          'status', () async {
        final sb = await sandboxWithClaude();
        sb.stub('claude', r'''
echo "$*" >> "$STUB_LOG_DIR/claude.log"
case "$*" in
  'plugin install specstone@specstone') exit 7 ;;
esac
echo '[]'
''');

        final r = await runWith(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stderr,
          contains(
            'specstone: claude $installPlugin failed: exit 7; run it by '
            'hand\n',
          ),
        );
      });

      test('f09/us01/fr05: a failing marketplace add stops the plugin step; '
          'exit 0', () async {
        final sb = await sandboxWithClaude();

        final r = await runWith(sb, {'STUB_FAIL': addMarketplace});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stderr,
          contains(
            'specstone: claude $addMarketplace failed: boom; run it by hand\n',
          ),
        );
        expect(sb.logOf('claude'), isNot(contains(installPlugin)));
      });

      test(
        'f09/us01/fr05: a failing list names the list command; exit 0',
        () async {
          final sb = await sandboxWithClaude();

          final r = await runWith(sb, {'STUB_FAIL': listPlugins});

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            r.stderr,
            contains(
              'specstone: claude $listPlugins failed: boom; run it by hand\n',
            ),
          );
          expect(sb.logOf('claude'), [listMarketplaces, listPlugins]);
        },
      );

      test(
        'f09/us01/fr05: a failing marketplace list is named; exit 0',
        () async {
          final sb = await sandboxWithClaude();

          final r = await runWith(sb, {'STUB_FAIL': listMarketplaces});

          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(
            r.stderr,
            contains(
              'specstone: claude $listMarketplaces failed: boom; run it by '
              'hand\n',
            ),
          );
          expect(sb.logOf('claude'), [listMarketplaces]);
        },
      );

      test('f09/us01/fr05: add and install show claude stdout live and replay '
          'its stderr', () async {
        final sb = await sandboxWithClaude();
        sb.stub('claude', r'''
echo "$*" >> "$STUB_LOG_DIR/claude.log"
case "$*" in
  'plugin marketplace add'*) echo 'added-marketplace-output' ;;
  'plugin install'*) echo 'installed-plugin-output'; echo 'a-warning' >&2 ;;
  *) echo '[]' ;;
esac
''');

        final r = await runWith(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stdout, contains('added-marketplace-output\n'));
        expect(r.stdout, contains('installed-plugin-output\n'));
        expect(r.stderr, contains('a-warning\n'));
      });

      test('f09/us01/fr05: claude gets EOF on stdin, not the script', () async {
        final sb = await sandboxWithClaude();
        sb.stub('claude', r'''
echo "$*" >> "$STUB_LOG_DIR/claude.log"
rest=$(cat)
echo "stdin:[$rest]" >> "$STUB_LOG_DIR/claude.log"
echo '[]'
''');

        final r = await sb.run(
          'install.sh',
          extra: archiveEnv(sb),
          stdinText: 'swallowed\n',
        );

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          sb.logOf('claude').where((l) => l.startsWith('stdin:')),
          everyElement('stdin:[]'),
        );
        expect(sb.logOf('claude'), contains(installPlugin));
      });

      test('f09/us01/fr05: empty stderr falls back to the first non-blank '
          'stdout line', () async {
        final sb = await sandboxWithClaude();
        sb.stub('claude', r'''
echo "$*" >> "$STUB_LOG_DIR/claude.log"
case "$*" in
  'plugin list --json') printf '\n  \nnot logged in\nsecond\n'; exit 1 ;;
esac
echo '[]'
''');

        final r = await runWith(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stderr,
          contains(
            'specstone: claude $listPlugins failed: not logged in; run it by '
            'hand\n',
          ),
        );
      });

      test('f09/us01/fr05: a CRLF stderr line has no carriage return and '
          'blank lines are skipped', () async {
        final sb = await sandboxWithClaude();
        sb.stub('claude', r'''
echo "$*" >> "$STUB_LOG_DIR/claude.log"
case "$*" in
  'plugin install specstone@specstone') printf '\r\n\nboom\r\nmore\r\n' >&2; exit 1 ;;
esac
echo '[]'
''');

        final r = await runWith(sb);

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stderr,
          contains(
            'specstone: claude $installPlugin failed: boom; run it by hand\n',
          ),
        );
        expect(r.stderr, isNot(contains('\r')));
      });

      test('f09/us01/fr04, f09/us01/fr05: an unwritable profile still runs '
          'the plugin step; exit 0', () async {
        final sb = await sandboxWithClaude();
        final rc = File('${sb.home.path}/.zshrc')
          ..writeAsStringSync('# mine\n');
        Process.runSync('chmod', ['444', rc.path]);

        final r = await runWith(sb, {'SHELL': '/bin/zsh'});

        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(r.stderr, startsWith('specstone: could not write ${rc.path}'));
        expect(sb.logOf('claude'), [
          listMarketplaces,
          listPlugins,
          addMarketplace,
          installPlugin,
        ]);
      }, skip: runsAsRoot ? rootSkip : null);
    });

    group('PATH search (G8-R10)', () {
      // Each name is planted in the run folder and in a relative `planted`
      // folder; a planted program only records that it ran.
      const plantedNames = ['claude', 'uname', 'mktemp', 'tar', 'awk', 'cp'];

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

      void stubClaude(ScriptSandbox sb) {
        sb.stub('claude', r'''
echo "$*" >> "$STUB_LOG_DIR/claude.log"
case "$*" in
  'plugin marketplace list --json' | 'plugin list --json') echo '[]' ;;
esac''');
      }

      final pathsWithRelativeEntries = <String, String Function(String)>{
        'a dot': (stubs) => '.:$stubs:/usr/bin:/bin',
        'a leading empty entry': (stubs) => ':$stubs:/usr/bin:/bin',
        'a middle empty entry': (stubs) => '$stubs::/usr/bin:/bin',
        'a relative folder': (stubs) => 'planted:$stubs:/usr/bin:/bin',
      };

      for (final MapEntry(key: label, value: pathOf)
          in pathsWithRelativeEntries.entries) {
        test('$label on PATH never starts a program from there; the absolute '
            'claude runs', () async {
          final sb = await sandboxWith();
          stubClaude(sb);
          plantPrograms(sb);

          final r = await sb.run(
            'install.sh',
            extra: {...archiveEnv(sb), 'PATH': pathOf(sb.stubs.path)},
          );

          expect(plantedThatRan(sb), isEmpty);
          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(sb.logOf('claude'), [
            'plugin marketplace list --json',
            'plugin list --json',
            'plugin marketplace add nontravis/specstone',
            'plugin install specstone@specstone',
          ]);
        });
      }

      // The stubs and the real tools come first, so only the trailing empty
      // entry can reach a planted `claude`; with no stub it is the only one.
      test('a trailing empty entry on PATH finds no claude in the run '
          'folder; the manual commands print', () async {
        final sb = await sandboxWith();
        plantPrograms(sb);

        final r = await sb.run(
          'install.sh',
          extra: {...archiveEnv(sb), 'PATH': '${sb.stubs.path}:/usr/bin:/bin:'},
        );

        expect(plantedThatRan(sb), isEmpty);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(
          r.stdout,
          contains(
            'To add the Specstone plugin to Claude Code, run:\n'
            '  claude plugin marketplace add nontravis/specstone\n'
            '  claude plugin install specstone@specstone\n',
          ),
        );
      });

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
  });
}
