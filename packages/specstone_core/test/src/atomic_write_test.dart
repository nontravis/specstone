@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:test/test.dart';

import '../helpers/hold_open.dart';

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('specstone_atomic_');
  });

  tearDown(() {
    folder.deleteSync(recursive: true);
  });

  List<String> tempNames() => folder
      .listSync()
      .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
      .where((name) => name.endsWith('.specstone.tmp'))
      .toList();

  group('writeFileAtomic', () {
    test('a rewrite keeps the permission bits of an existing file', () {
      final file = File('${folder.path}/run.sh')..writeAsStringSync('old\n');
      Process.runSync('chmod', ['755', file.path]);
      writeFileAtomic(file, utf8.encode('new\n'));
      expect(file.readAsStringSync(), 'new\n');
      expect(file.statSync().mode & 0xFFF, 493);
    }, skip: Platform.isWindows ? 'Windows has no permission bits' : false);

    test('replaces the file and leaves no temp sibling', () {
      final file = File('${folder.path}/FEATURE.md')
        ..writeAsStringSync('old\n');

      writeFileAtomic(file, utf8.encode('new\n'));

      expect(file.readAsStringSync(), 'new\n');
      expect(tempNames(), isEmpty);
    });

    test('a rename failure throws, keeps the target folder and '
        'leaves no temp sibling', () {
      final target = Directory('${folder.path}/FEATURE.md')..createSync();
      File('${target.path}/keep.txt').writeAsStringSync('kept');

      expect(
        () => writeFileAtomic(File(target.path), utf8.encode('new\n')),
        throwsA(isA<FileSystemException>()),
      );

      expect(target.existsSync(), isTrue);
      expect(File('${target.path}/keep.txt').readAsStringSync(), 'kept');
      expect(tempNames(), isEmpty);
    });

    test('creates no parent folder: a missing folder throws', () {
      final file = File('${folder.path}/missing/FEATURE.md');

      expect(
        () => writeFileAtomic(file, utf8.encode('new\n')),
        throwsA(isA<FileSystemException>()),
      );

      expect(Directory('${folder.path}/missing').existsSync(), isFalse);
    });

    test('a replace outwaits a reader '
        'that holds the target open for 300 ms', () async {
      final file = File('${folder.path}/.gitignore')
        ..writeAsStringSync('old\n');

      await whileHeld(
        file.path,
        const Duration(milliseconds: 300),
        () => writeFileAtomic(file, utf8.encode('new\n')),
      );

      expect(file.readAsStringSync(), 'new\n');
      expect(tempNames(), isEmpty);
    });

    test(
      'a replace blocked for longer '
      'than 1 s throws after 1 s and leaves no temp sibling',
      () async {
        final file = File('${folder.path}/.gitignore')
          ..writeAsStringSync('old\n');
        final clock = Stopwatch();
        Object? thrown;

        await whileHeld(file.path, const Duration(milliseconds: 1500), () {
          clock.start();
          try {
            writeFileAtomic(file, utf8.encode('new\n'));
          } on FileSystemException catch (e) {
            thrown = e;
          }
          clock.stop();
        });

        expect(thrown, isA<FileSystemException>());
        expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(1000));
        expect(file.readAsStringSync(), 'old\n');
        expect(tempNames(), isEmpty);
      },
      skip: Platform.isWindows
          ? false
          : 'only Windows refuses a replace of an open file',
    );
  });

  group('writeTempSibling', () {
    test('a write stopped before the rename leaves '
        'the target untouched', () {
      final file = File('${folder.path}/FEATURE.md')
        ..writeAsStringSync('old\n');

      final temp = writeTempSibling(file, utf8.encode('new\n'));

      expect(file.readAsStringSync(), 'old\n');
      expect(temp.readAsStringSync(), 'new\n');
    });

    test(
      'names the temp .<name>.<pid>.<hex>.specstone.tmp beside the target',
      () {
        final file = File('${folder.path}/FEATURE.md');

        final temp = writeTempSibling(file, utf8.encode('x'));

        expect(
          temp.uri.pathSegments.last,
          matches(
            RegExp(
              '^\\.FEATURE\\.md\\.$pid\\.[0-9a-f]{16}\\.specstone\\.tmp\$',
            ),
          ),
        );
        expect(temp.parent.path, file.parent.path);
      },
    );

    test('the temp of a private file holds its mode before the rename, so no '
        'other user reads the new text', () {
      final file = File('${folder.path}/secrets.yaml')
        ..writeAsStringSync('old\n');
      Process.runSync('chmod', ['600', file.path]);

      final temp = writeTempSibling(file, utf8.encode('new\n'));

      expect(temp.statSync().mode & 0xFFF, 384);
      expect(temp.readAsStringSync(), 'new\n');
    }, skip: Platform.isWindows ? 'Windows has no permission bits' : false);

    test('the temp of a read-only file takes its bytes and its mode', () {
      final file = File('${folder.path}/locked.md')..writeAsStringSync('old\n');
      Process.runSync('chmod', ['444', file.path]);

      final temp = writeTempSibling(file, utf8.encode('new\n'));

      expect(temp.statSync().mode & 0xFFF, 292);
      expect(temp.readAsStringSync(), 'new\n');
    }, skip: Platform.isWindows ? 'Windows has no permission bits' : false);

    test('a 250-byte ASCII target name writes, its temp name at most 255 '
        'bytes', () {
      final file = File('${folder.path}/${'a' * 250}');

      writeFileAtomic(file, utf8.encode('x'));

      expect(file.readAsStringSync(), 'x');
      final temp = writeTempSibling(file, utf8.encode('y'));
      final name = temp.uri.pathSegments.last;
      expect(utf8.encode(name).length, lessThanOrEqualTo(255));
      expect(
        name,
        matches(RegExp('^\\.a+\\.$pid\\.[0-9a-f]{16}\\.specstone\\.tmp\$')),
      );
    });

    test('a multibyte target name is cut on a code point boundary in its '
        'temp name', () {
      final file = File('${folder.path}/${'\u{1F600}' * 60}');

      final temp = writeTempSibling(file, utf8.encode('y'));

      final name = temp.uri.pathSegments.last;
      expect(utf8.decode(utf8.encode(name)), name);
      expect(utf8.encode(name).length, lessThanOrEqualTo(255));
      expect(name, endsWith('.specstone.tmp'));
    });

    test('two calls for one target write two temps', () {
      final file = File('${folder.path}/FEATURE.md');

      final first = writeTempSibling(file, utf8.encode('a'));
      final second = writeTempSibling(file, utf8.encode('b'));

      expect(second.path, isNot(first.path));
      expect(first.readAsStringSync(), 'a');
      expect(second.readAsStringSync(), 'b');
    });
  });

  group('isReadOnly', () {
    const skipWindows = 'file modes need chmod, which Windows lacks';

    test('a file without the owner write bit is read-only', () async {
      final file = File('${folder.path}/FEATURE.md')..writeAsStringSync('x');
      await Process.run('chmod', ['444', file.path]);

      expect(isReadOnly(file), isTrue);
    }, skip: Platform.isWindows ? skipWindows : false);

    test('a writable file is not read-only', () async {
      final file = File('${folder.path}/FEATURE.md')..writeAsStringSync('x');
      await Process.run('chmod', ['644', file.path]);

      expect(isReadOnly(file), isFalse);
    }, skip: Platform.isWindows ? skipWindows : false);

    test('a file that does not exist is not read-only', () {
      expect(isReadOnly(File('${folder.path}/missing.md')), isFalse);
    });
  });
}
