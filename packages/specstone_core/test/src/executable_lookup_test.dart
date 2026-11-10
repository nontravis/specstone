import 'dart:io';

import 'package:specstone_core/src/executable_lookup.dart';
import 'package:test/test.dart';

import '../helpers/temp_tree.dart';

final String _sep = Platform.pathSeparator;

/// Returns a lookup whose is-file check accepts exactly [files].
bool Function(String) _only(Set<String> files) => files.contains;

void main() {
  group('findExecutable: POSIX', () {
    test('an absolute entry holding the program is found', () {
      final found = findExecutable(
        'git',
        {'PATH': '/usr/bin'},
        isWindows: false,
        isFile: _only({'/usr/bin${_sep}git'}),
      );

      expect(found, '/usr/bin${_sep}git');
    });

    test('an earlier absolute entry wins', () {
      final found = findExecutable(
        'git',
        {'PATH': '/opt/bin:/usr/bin'},
        isWindows: false,
        isFile: _only({'/opt/bin${_sep}git', '/usr/bin${_sep}git'}),
      );

      expect(found, '/opt/bin${_sep}git');
    });

    test('an empty, ".", and relative entry is skipped even holding it', () {
      final found = findExecutable(
        'git',
        {'PATH': ':.:bin:./bin:../bin:/usr/bin'},
        isWindows: false,
        isFile: (path) => path.startsWith('/usr/bin') || !path.startsWith('/'),
      );

      expect(found, '/usr/bin${_sep}git');
    });

    test('a PATH of skipped entries only finds nothing', () {
      expect(
        findExecutable(
          'git',
          {'PATH': ':.:bin'},
          isWindows: false,
          isFile: (_) => true,
        ),
        isNull,
      );
    });

    test('the current folder is never a candidate', () {
      final asked = <String>[];

      findExecutable(
        'git',
        {'PATH': '/usr/bin'},
        isWindows: false,
        isFile: (path) {
          asked.add(path);
          return false;
        },
      );

      expect(asked, ['/usr/bin${_sep}git']);
    });

    test('a missing PATH finds nothing', () {
      expect(
        findExecutable('git', {}, isWindows: false, isFile: (_) => true),
        isNull,
      );
    });

    test('the key is PATH with its case on POSIX', () {
      expect(
        findExecutable(
          'git',
          {'Path': '/usr/bin'},
          isWindows: false,
          isFile: (_) => true,
        ),
        isNull,
      );
    });
  });

  group('findExecutable: Windows', () {
    test('the name gets .exe and ";" separates entries', () {
      final found = findExecutable(
        'git',
        {'PATH': r'C:\one;C:\two'},
        isWindows: true,
        isFile: _only({'C:\\two${_sep}git.exe'}),
      );

      expect(found, 'C:\\two${_sep}git.exe');
    });

    test('the PATH key matches without case', () {
      final found = findExecutable(
        'git',
        {'Path': r'C:\Git\cmd'},
        isWindows: true,
        isFile: _only({'C:\\Git\\cmd${_sep}git.exe'}),
      );

      expect(found, 'C:\\Git\\cmd${_sep}git.exe');
    });

    test('an empty, ".", relative, and drive-relative entry is skipped', () {
      final found = findExecutable(
        'git',
        {'PATH': r';.;bin;..\bin;C:bin;D:\ok'},
        isWindows: true,
        isFile: (_) => true,
      );

      expect(found, 'D:\\ok${_sep}git.exe');
    });

    test('a UNC entry is absolute', () {
      final found = findExecutable(
        'git',
        {'PATH': r'\\server\share'},
        isWindows: true,
        isFile: (_) => true,
      );

      expect(found, '\\\\server\\share${_sep}git.exe');
    });

    test('the extensions are tried in order inside one folder', () {
      final found = findExecutable(
        'claude',
        {'PATH': r'C:\a'},
        isWindows: true,
        windowsExtensions: const ['.exe', '.cmd'],
        isFile: _only({'C:\\a${_sep}claude.cmd'}),
      );

      expect(found, 'C:\\a${_sep}claude.cmd');
    });

    test('.exe wins over .cmd in one folder', () {
      final found = findExecutable(
        'claude',
        {'PATH': r'C:\a'},
        isWindows: true,
        windowsExtensions: const ['.exe', '.cmd'],
        isFile: _only({'C:\\a${_sep}claude.cmd', 'C:\\a${_sep}claude.exe'}),
      );

      expect(found, 'C:\\a${_sep}claude.exe');
    });

    test('no hit gives null', () {
      expect(
        findExecutable(
          'git',
          {'PATH': r'C:\a'},
          isWindows: true,
          isFile: (_) => false,
        ),
        isNull,
      );
    });
  });

  group('findExecutable: the file system', () {
    late Directory folder;

    setUp(() async => folder = await writeTree({'git': '#!/bin/sh\n'}));

    test('a file without an execute bit is skipped on POSIX', () {
      expect(
        findExecutable('git', {'PATH': folder.path}, isWindows: false),
        isNull,
      );
    }, testOn: '!windows');

    test('a file with an execute bit is found on POSIX', () {
      expect(
        Process.runSync('chmod', ['755', '${folder.path}/git']).exitCode,
        0,
      );

      expect(
        findExecutable('git', {'PATH': folder.path}, isWindows: false),
        '${folder.path}${_sep}git',
      );
    }, testOn: '!windows');

    test('a folder named like the program is skipped', () async {
      final other = await writeTree({'git/inner': ''});

      expect(
        findExecutable('git', {'PATH': other.path}, isWindows: false),
        isNull,
      );
    }, testOn: '!windows');
  });
}
