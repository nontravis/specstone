import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:test/test.dart';

/// Opens the path for the duration, signalling `open` then `closed`.
Future<void> _holdOpen((String, Duration, SendPort) args) async {
  final (path, hold, port) = args;
  final handle = File(path).openSync();
  port.send('open');
  await Future<void>.delayed(hold);
  handle.closeSync();
  port.send('closed');
}

/// Runs [act] while another isolate holds [path] open for [hold].
///
/// Fails at once with the holder's error when the holder cannot open [path];
/// otherwise waits for the holder to close before it returns.
Future<void> _whileHeld(String path, Duration hold, void Function() act) async {
  final signal = ReceivePort();
  final opened = Completer<void>()..future.ignore();
  final closed = Completer<void>()..future.ignore();
  signal.listen((message) {
    if (message is List) {
      final failure = StateError('the holder isolate failed: ${message.first}');
      if (!opened.isCompleted) opened.completeError(failure);
      if (!closed.isCompleted) closed.completeError(failure);
    }
    if (message == 'open') opened.complete();
    if (message == 'closed') closed.complete();
  });
  final holder = await Isolate.spawn(_holdOpen, (
    path,
    hold,
    signal.sendPort,
  ), onError: signal.sendPort);
  try {
    await opened.future;
    act();
    await closed.future;
  } finally {
    signal.close();
    holder.kill();
  }
}

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

    test('f01/us01/fr04, s03/inv22, NFR-DI01, FM2: a replace outwaits a reader '
        'that holds the target open for 300 ms', () async {
      final file = File('${folder.path}/.gitignore')
        ..writeAsStringSync('old\n');

      await _whileHeld(
        file.path,
        const Duration(milliseconds: 300),
        () => writeFileAtomic(file, utf8.encode('new\n')),
      );

      expect(file.readAsStringSync(), 'new\n');
      expect(tempNames(), isEmpty);
    });

    test(
      'f01/us01/fr04, s03/inv22, NFR-DI01, FM2: a replace blocked for longer '
      'than 1 s throws after 1 s and leaves no temp sibling',
      () async {
        final file = File('${folder.path}/.gitignore')
          ..writeAsStringSync('old\n');
        final clock = Stopwatch();
        Object? thrown;

        await _whileHeld(file.path, const Duration(milliseconds: 1500), () {
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
    test(
      'f05/us01/fr07/e03, NFR-DI01: a write stopped before the rename leaves '
      'the target untouched',
      () {
        final file = File('${folder.path}/FEATURE.md')
          ..writeAsStringSync('old\n');

        final temp = writeTempSibling(file, utf8.encode('new\n'));

        expect(file.readAsStringSync(), 'old\n');
        expect(temp.readAsStringSync(), 'new\n');
      },
    );

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
