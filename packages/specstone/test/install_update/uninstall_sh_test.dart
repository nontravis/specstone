@TestOn('!windows')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/script_sandbox.dart';

void main() {
  const entry = r'export PATH="$HOME/.specstone/bin:$PATH"';
  const fishEntry = r'set -gx PATH "$HOME/.specstone/bin" $PATH';
  const pluginLine = 'claude plugin uninstall specstone@specstone';

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
    test('f09/us03/fr01, f09/us03/fr02, f09/us03/s1: bin, lib, and the entry '
        'go; the plugin command is last', () async {
      sb.installFake();
      profile('.zshrc', '$entry\n');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect((r.stdout as String).trimRight().split('\n'), [
        'Removed ${sb.home.path}/.specstone/bin',
        'Removed ${sb.home.path}/.specstone/lib',
        'Removed the PATH entry from ${sb.home.path}/.zshrc',
        pluginLine,
      ]);
      expect(Directory(home('.specstone/bin')).existsSync(), isFalse);
      expect(Directory(home('.specstone/lib')).existsSync(), isFalse);
      expect(read('.zshrc'), '');
    });

    test('f09/us03/fr01/e01, e02, f09/us03/s3: packs, ~/.specstone, and a '
        'project .specstone stay', () async {
      sb.installFake();
      File(home('.specstone/packs/mine/pack.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: mine\n');
      File(home('work/app/.specstone/docs/index.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# doc\n');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(read('.specstone/packs/mine/pack.yaml'), 'name: mine\n');
      expect(Directory(home('.specstone')).existsSync(), isTrue);
      expect(read('work/app/.specstone/docs/index.md'), '# doc\n');
      expect(Directory(home('.specstone/bin')).existsSync(), isFalse);
    });

    test(
      'f09/us03/fr01/e03: a fish file holding only the entry is deleted',
      () async {
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
      },
    );

    test('f09/us03/fr01/e03: a fish file with another line keeps that '
        'line', () async {
      const fish = '.config/fish/conf.d/specstone.fish';
      profile(fish, 'set -x A 1\n$fishEntry\n');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(read(fish), 'set -x A 1\n');
    });

    test('f09/us03/fr01/e05: other profile lines stay byte for byte, and a '
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

    test('f09/us03/fr01/e05: an entry on the unterminated last line leaves '
        'the line before it terminated', () async {
      profile('.zshrc', 'a\n$entry');

      await sb.run('uninstall.sh');

      expect(read('.zshrc'), 'a\n');
    });

    test(
      'f09/us03/fr01/e05: a line that only contains the entry stays',
      () async {
        const near = '# $entry';
        profile('.zshrc', '$near\n$entry \n');

        final r = await sb.run('uninstall.sh');

        expect(r.exitCode, 0);
        expect(read('.zshrc'), '$near\n$entry \n');
        expect(r.stdout, isNot(contains('Removed the PATH entry')));
      },
    );

    test('f09/us03/fr01: every profile file the install can write is '
        'cleaned, ~/.bash_login included', () async {
      for (final name in [
        '.zshrc',
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

    test('f09/us03/fr01: a symlinked profile keeps its link and the target '
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

    test('f09/us03/fr01/e04, f09/us03/fr02/e02, f09/us03/s5: nothing '
        'installed says so and still names the plugin command', () async {
      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(r.stdout, 'specstone: nothing to remove\n$pluginLine\n');
      expect(r.stderr, '');
      expect(sb.snapshot(), isEmpty);
    });

    test('f09/us03/fr02/e01, f09/us03/s4: claude on the PATH is never '
        'run', () async {
      sb.installFake();
      profile('.zshrc', '$entry\n');
      sb.stub('claude', r'echo "$@" >> "$STUB_LOG_DIR/claude.log"; exit 0');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(sb.logOf('claude'), isEmpty);
      expect((r.stdout as String).trimRight().split('\n').last, pluginLine);
    });

    test('f09/us03/fr01: a second run finds nothing left', () async {
      sb.installFake();
      profile('.zshrc', '$entry\n');
      await sb.run('uninstall.sh');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 0);
      expect(r.stdout, 'specstone: nothing to remove\n$pluginLine\n');
    });

    test('f09/us03/fr01: an unwritable profile is named on stderr and the '
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
      expect((r.stdout as String).trimRight().split('\n').last, pluginLine);
    }, skip: runsAsRoot ? 'root ignores file modes' : false);

    test('f09/us03/fr01: a write that fails midway leaves the profile '
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
      expect((r.stdout as String).trimRight().split('\n').last, pluginLine);
    });

    test('f09/us03/fr01: when the restore fails too the old content is kept '
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
      expect((r.stdout as String).trimRight().split('\n').last, pluginLine);
    });

    test('f09/us03/fr01: an unreadable profile is named on stderr', () async {
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
      expect((r.stdout as String).trimRight().split('\n').last, pluginLine);
    }, skip: runsAsRoot ? 'root ignores file modes' : false);

    test('f09/us03/fr01: a failed delete of bin is named, the rest goes on, '
        'and the run exits 1', () async {
      sb.installFake();
      profile('.zshrc', '$entry\n');
      sb.stub('rm', r'''
for a in "$@"; do
  case "$a" in */.specstone/bin) exit 1 ;; esac
done
exec /bin/rm "$@"''');

      final r = await sb.run('uninstall.sh');

      expect(r.exitCode, 1);
      expect(
        r.stderr,
        'specstone: could not remove ${sb.home.path}/.specstone/bin\n',
      );
      expect(Directory(home('.specstone/bin')).existsSync(), isTrue);
      expect(Directory(home('.specstone/lib')).existsSync(), isFalse);
      expect(read('.zshrc'), '');
      expect((r.stdout as String).trimRight().split('\n'), [
        'Removed ${sb.home.path}/.specstone/lib',
        'Removed the PATH entry from ${sb.home.path}/.zshrc',
        pluginLine,
      ]);
    });

    test('f09/us03/fr01: USERPROFILE stands in when HOME is unset', () async {
      sb.installFake();

      final r = await sb.run(
        'uninstall.sh',
        extra: {'HOME': '', 'USERPROFILE': sb.home.path},
      );

      expect(r.exitCode, 0);
      expect(Directory(home('.specstone/bin')).existsSync(), isFalse);
    });

    test('f09/us03/fr01: with neither HOME nor USERPROFILE set it exits 1 '
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
  });
}
