import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:test/test.dart';

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
    test('NFR-DI01: replaces the file and leaves no temp sibling', () {
      final file = File('${folder.path}/FEATURE.md')
        ..writeAsStringSync('old\n');

      writeFileAtomic(file, utf8.encode('new\n'));

      expect(file.readAsStringSync(), 'new\n');
      expect(tempNames(), isEmpty);
    });

    test('NFR-DI01: a rename failure throws, keeps the target folder and '
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
  });

  group('writeTempSibling', () {
    test('us01/fr07/e03, NFR-DI01: a write stopped before the rename leaves '
        'the target untouched', () {
      final file = File('${folder.path}/FEATURE.md')
        ..writeAsStringSync('old\n');

      final temp = writeTempSibling(file, utf8.encode('new\n'));

      expect(file.readAsStringSync(), 'old\n');
      expect(temp.readAsStringSync(), 'new\n');
    });

    test('names the temp .<name>.<pid>.specstone.tmp in the target folder', () {
      final file = File('${folder.path}/FEATURE.md');

      final temp = writeTempSibling(file, utf8.encode('x'));

      expect(temp.uri.pathSegments.last, '.FEATURE.md.$pid.specstone.tmp');
      expect(temp.parent.path, file.parent.path);
    });
  });
}
