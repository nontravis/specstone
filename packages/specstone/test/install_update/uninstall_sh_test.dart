@TestOn('!windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

void main() {
  const entry = r'export PATH="$HOME/.specstone/bin:$PATH"';
  const fishEntry = r'set -gx PATH "$HOME/.specstone/bin" $PATH';

  late ScriptSandbox sb;

  setUp(() async {
    sb = await createScriptSandbox();
  });

  String home(String relative) => '${sb.home.path}/$relative';

  File profile(String name, String content) => File(home(name))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  String read(String name) =>
      String.fromCharCodes(File(home(name)).readAsBytesSync());

  // Root ignores file modes, so the chmod test cannot make a profile
  // unwritable.
  final runsAsRoot =
      (Process.runSync('id', ['-u']).stdout as String).trim() == '0';

  group('uninstall.sh', () {
    test('bin, lib, and the entry '
        'go; no plugin command prints', () async {
      sb.installFake();
      profile('.zshrc', '$entry\n');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect((r.stdout as String).trimRight().split('\n'), [
        'Removed ${sb.home.path}/.specstone/bin',
        'Removed ${sb.home.path}/.specstone/lib',
        'Removed the PATH entry from ${sb.home.path}/.zshrc',
      ]);
      expect(Directory(home('.specstone/bin')).existsSync(), isFalse);
      expect(Directory(home('.specstone/lib')).existsSync(), isFalse);
      expect(read('.zshrc'), '');
    });

    test('packs, the update record, ~/.specstone, and a '
        'project .specstone stay', () async {
      sb.installFake();
      File(home('.specstone/update-check.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"checkedAt":"2026-11-15"}\n');
      File(home('.specstone/packs/mine/pack.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: mine\n');
      File(home('work/app/.specstone/docs/index.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# doc\n');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(read('.specstone/packs/mine/pack.yaml'), 'name: mine\n');
      expect(
        read('.specstone/update-check.json'),
        '{"checkedAt":"2026-11-15"}\n',
      );
      expect(Directory(home('.specstone')).existsSync(), isTrue);
      expect(read('work/app/.specstone/docs/index.md'), '# doc\n');
      expect(Directory(home('.specstone/bin')).existsSync(), isFalse);
    });

    test('a fish file holding only the entry is deleted', () async {
      sb.installFake();
      const fish = '.config/fish/conf.d/specstone.fish';
      profile(fish, '$fishEntry\n');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(File(home(fish)).existsSync(), isFalse);
      expect(
        r.stdout,
        contains('Removed the PATH entry from ${sb.home.path}/$fish\n'),
      );
    });

    test('a fish file with another line keeps that '
        'line', () async {
      const fish = '.config/fish/conf.d/specstone.fish';
      profile(fish, 'set -x A 1\n$fishEntry\n');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(read(fish), 'set -x A 1\n');
    });

    test('other profile lines stay byte for byte, and a '
        'missing final newline stays missing', () async {
      profile('.bashrc', 'a\r\n$entry\nb');
      profile('.profile', 'x\n$entry\n');
      profile('.bash_profile', '$entry\ny\n\n  z  \n');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(read('.bashrc'), 'a\r\nb');
      expect(read('.profile'), 'x\n');
      expect(read('.bash_profile'), 'y\n\n  z  \n');
    });

    test('an entry on the unterminated last line leaves '
        'the line before it terminated', () async {
      profile('.zshrc', 'a\n$entry');

      await sb.run('uninstall.sh');

      expect(read('.zshrc'), 'a\n');
    });

    test('a line that only contains the entry stays', () async {
      const near = '# $entry';
      profile('.zshrc', '$near\n$entry \n');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(read('.zshrc'), '$near\n$entry \n');
      expect(r.stdout, isNot(contains('Removed the PATH entry')));
    });

    test('every profile file the install can write is '
        'cleaned, ~/.bash_login included', () async {
      for (final name in [
        '.zshrc',
        '.zshenv',
        '.bashrc',
        '.bash_profile',
        '.bash_login',
        '.profile',
      ]) {
        profile(name, 'keep\n$entry\n');
      }

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      for (final name in [
        '.zshrc',
        '.zshenv',
        '.bashrc',
        '.bash_profile',
        '.bash_login',
        '.profile',
      ]) {
        expect(read(name), 'keep\n', reason: name);
        expect(
          r.stdout,
          contains('Removed the PATH entry from ${sb.home.path}/$name\n'),
        );
      }
    });

    test('a zsh install is undone in .zshrc, .zshenv, and .profile, '
        'in the order the install wrote them', () async {
      sb.installFake();
      for (final name in ['.zshrc', '.zshenv', '.profile']) {
        profile(name, 'keep\n$entry\n');
      }

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect((r.stdout as String).trimRight().split('\n'), [
        'Removed ${sb.home.path}/.specstone/bin',
        'Removed ${sb.home.path}/.specstone/lib',
        'Removed the PATH entry from ${sb.home.path}/.zshrc',
        'Removed the PATH entry from ${sb.home.path}/.zshenv',
        'Removed the PATH entry from ${sb.home.path}/.profile',
      ]);
    });

    test('with ZDOTDIR set the .zshenv there is cleaned and '
        '~/.zshenv is left alone', () async {
      final zdotdir = '${sb.root.path}/zdot';
      File('$zdotdir/.zshenv')
        ..createSync(recursive: true)
        ..writeAsStringSync('a=1\r\n$entry\nb');
      profile('.zshenv', '$entry\n');
      profile('.zshrc', '$entry\n');

      final r = await sb.run('uninstall.sh', extra: {'ZDOTDIR': zdotdir});

      expect(r.exitCode, 0);
      expect(
        String.fromCharCodes(File('$zdotdir/.zshenv').readAsBytesSync()),
        'a=1\r\nb',
      );
      expect(read('.zshenv'), '$entry\n');
      expect(read('.zshrc'), '');
      expect(
        r.stdout,
        contains('Removed the PATH entry from $zdotdir/.zshenv\n'),
      );
    });

    test('a symlinked profile keeps its link and the target '
        'keeps its mode', () async {
      final target = File(home('dotfiles/zshrc'))
        ..createSync(recursive: true)
        ..writeAsStringSync('keep\n$entry\n');
      Process.runSync('chmod', ['640', target.path]);
      Link(home('.zshrc')).createSync(target.path);

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(FileSystemEntity.isLinkSync(home('.zshrc')), isTrue);
      expect(Link(home('.zshrc')).targetSync(), target.path);
      expect(target.readAsStringSync(), 'keep\n');
      expect(target.statSync().mode & 0x1ff, 416); // 0640
    });

    test('nothing '
        'installed says so and prints no plugin command', () async {
      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(r.stdout, 'specstone: nothing to remove\n');
      expect(r.stderr, '');
      expect(sb.snapshot(), isEmpty);
    });

    test('claude on the PATH is never '
        'run', () async {
      sb.installFake();
      profile('.zshrc', '$entry\n');
      sb.stub('claude', r'echo "$@" >> "$STUB_LOG_DIR/claude.log"; exit 0');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(sb.logOf('claude'), isEmpty);
      expect(r.stdout, isNot(contains('plugin')));
    });

    test('a second run finds nothing left', () async {
      sb.installFake();
      profile('.zshrc', '$entry\n');
      await sb.run('uninstall.sh');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(r.stdout, 'specstone: nothing to remove\n');
    });

    test('an unwritable profile is named on stderr and the '
        'rest is removed', () async {
      sb.installFake();
      profile('.zshrc', '$entry\n');
      profile('.profile', '$entry\n');
      Process.runSync('chmod', ['444', home('.zshrc')]);

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: could not write ${sb.home.path}/.zshrc: '
        'remove the specstone line from it yourself\n',
      );
      expect(read('.zshrc'), '$entry\n');
      expect(read('.profile'), '');
      expect(Directory(home('.specstone/bin')).existsSync(), isFalse);
    }, skip: runsAsRoot ? 'root ignores file modes' : false);

    test('a write that fails midway leaves the profile '
        'byte for byte as it was', () async {
      const original = 'keep\n$entry\nmore';
      profile('.zshrc', original);
      sb.stub('cat', r'''
n="$STUB_LOG_DIR/cat.count"
if [ ! -e "$n" ]; then : > "$n"; printf 'xx'; exit 1; fi
exec /bin/cat "$@"''');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 1);
      expect(read('.zshrc'), original);
      expect(
        r.stderr,
        'specstone: could not write ${sb.home.path}/.zshrc: '
        'remove the specstone line from it yourself\n',
      );
    });

    test('when the restore fails too the old content is kept '
        'and its path is named', () async {
      const original = 'keep\n$entry\n';
      profile('.zshrc', original);
      sb.stub('cat', 'printf xx; exit 1');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 1);
      final match = RegExp(r'its old content is in (\S+)\n')
          .firstMatch(r.stderr as String);
      expect(match, isNotNull);
      expect(File(match!.group(1)!).readAsStringSync(), original);
    });

    test('two profiles whose writes and restores fail keep '
        'one backup each and name both', () async {
      const zsh = 'z\n$entry\n';
      const bash = 'b\n$entry\n';
      profile('.zshrc', zsh);
      profile('.bashrc', bash);
      sb.stub('cat', 'printf xx; exit 1');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 1);
      final paths = {
        for (final m in RegExp(
          r'could not write (\S+); its old content is in (\S+)\n',
        ).allMatches(r.stderr as String))
          m.group(1)!: m.group(2)!,
      };
      expect(paths.keys, [home('.zshrc'), home('.bashrc')]);
      expect(File(paths[home('.zshrc')]!).readAsStringSync(), zsh);
      expect(File(paths[home('.bashrc')]!).readAsStringSync(), bash);
    });

    test('a signal between truncating the profile and '
        'confirming it keeps the backup and names it', () async {
      const original = 'keep\n$entry\n';
      profile('.zshrc', original);
      sb.stub('cat', r'printf xx; kill -INT $PPID; sleep 1; exit 0');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, isNot(0));
      final match = RegExp(
        r'stopped while writing (\S+); its old content is in (\S+)\n',
      ).firstMatch(r.stderr as String);
      expect(match, isNotNull);
      expect(match!.group(1), home('.zshrc'));
      expect(File(match.group(2)!).readAsStringSync(), original);
    });

    test('a mktemp that succeeds but writes to stderr still '
        'edits the profile', () async {
      profile('.zshrc', 'keep\n$entry\n');
      sb.stub('mktemp', r'''
echo 'mktemp: noise' >&2
exec /usr/bin/mktemp "$@"''');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(read('.zshrc'), 'keep\n');
    });

    test('a closed stderr does not stop the run', () async {
      sb.installFake();
      profile('.zshrc', '$entry\n');
      File('${sb.stubs.path}/sh_no_stderr')
        ..writeAsStringSync('#!/bin/sh\nexec /bin/sh "\$@" 2>&-\n')
        ..createSync();
      Process.runSync('chmod', ['+x', '${sb.stubs.path}/sh_no_stderr']);

      final r = await sb.run(
        'uninstall.sh',
        shell: '${sb.stubs.path}/sh_no_stderr',
      );

      expect(r.exitCode, 0);
      expect(read('.zshrc'), '');
      expect(Directory(home('.specstone/bin')).existsSync(), isFalse);
    });

    test('an unreadable profile is named on stderr', () async {
      profile('.zshrc', '$entry\n');
      Process.runSync('chmod', ['000', home('.zshrc')]);
      addTearDown(() => Process.runSync('chmod', ['644', home('.zshrc')]));

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: could not read ${sb.home.path}/.zshrc: '
        'remove the specstone line from it yourself\n',
      );
    }, skip: runsAsRoot ? 'root ignores file modes' : false);

    test('a failed delete of bin is named, the rest goes on, '
        'and the run exits 1', () async {
      sb.installFake();
      profile('.zshrc', '$entry\n');
      sb.stub('rm', r'''
for a in "$@"; do
  case "$a" in */.specstone/bin) echo 'rm: denied' >&2; exit 1 ;; esac
done
exec /bin/rm "$@"''');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: could not remove ${sb.home.path}/.specstone/bin: '
        'rm: denied\n',
      );
      expect(
        (r.stderr as String).split('\n').where((l) => l.startsWith('rm:')),
        isEmpty,
      );
      expect(Directory(home('.specstone/bin')).existsSync(), isTrue);
      expect(Directory(home('.specstone/lib')).existsSync(), isFalse);
      expect(read('.zshrc'), '');
      expect((r.stdout as String).trimRight().split('\n'), [
        'Removed ${sb.home.path}/.specstone/lib',
        'Removed the PATH entry from ${sb.home.path}/.zshrc',
      ]);
    });

    test('USERPROFILE stands in when HOME is unset', () async {
      sb.installFake();

      final r = await sb.run(
        'uninstall.sh',
        extra: {'HOME': '', 'USERPROFILE': sb.home.path},
      );

      expect(r.exitCode, 0);
      expect(Directory(home('.specstone/bin')).existsSync(), isFalse);
    });

    test('with neither HOME nor USERPROFILE set it exits 1 '
        'and touches nothing', () async {
      final r = await sb.run(
        'uninstall.sh',
        extra: {'HOME': '', 'USERPROFILE': ''},
      );

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: no home folder: HOME and USERPROFILE are unset\n',
      );
      expect(r.stdout, '');
      expect(sb.snapshot(), isEmpty);
    });

    group('PATH search', () {
      // Each name is planted in the run folder and in a relative `planted`
      // folder; a planted program only records that it ran.
      const plantedNames = ['mktemp', 'rm', 'grep', 'tail', 'awk', 'cmp'];

      void plantPrograms() {
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

      List<String> plantedThatRan() => [
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
        test('$label on PATH never starts a program from there; the removal '
            'still runs', () async {
          sb.installFake();
          profile('.zshrc', '$entry\n');
          plantPrograms();

          final r = await sb.run(
            'uninstall.sh',
            extra: {'PATH': pathOf(sb.stubs.path)},
          );

          expect(plantedThatRan(), isEmpty);
          expect(r.exitCode, 0, reason: '${r.stderr}');
          expect(Directory(home('.specstone/bin')).existsSync(), isFalse);
          expect(read('.zshrc'), '');
        });
      }

      test(
        'a PATH of relative entries only searches no relative folder',
        () async {
          plantPrograms();

          await sb.run('uninstall.sh', extra: {'PATH': '.:planted:'});

          expect(plantedThatRan(), isEmpty);
        },
      );
    });
  });
}
