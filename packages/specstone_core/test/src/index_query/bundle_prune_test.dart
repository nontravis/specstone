import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/index_query/bundle_prune.dart';
import 'package:test/test.dart';

const _bound = Duration(hours: 24);

void main() {
  late Directory root;
  late Directory bundles;
  // Whole seconds: a file system may round a stored time down.
  final now = DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('bundle_prune_');
    bundles = Directory('${root.path}/bundles')..createSync();
  });

  tearDown(() {
    // A test may leave a folder read-only.
    _makeWritable(root);
    root.deleteSync(recursive: true);
  });

  File file(String relative, DateTime modified) {
    final made = File('${bundles.path}/$relative')
      ..createSync(recursive: true)
      ..setLastModifiedSync(modified);
    return made;
  }

  void prune({Set<String> keep = const {}}) =>
      pruneBundles(bundles, keep: keep, now: now);

  test('prune deletes a file older than the bound', () {
    final old = file(
      'a.txt',
      now.subtract(_bound + const Duration(seconds: 1)),
    );

    prune();

    expect(old.existsSync(), isFalse);
  });

  test('prune keeps a newer file', () {
    final fresh = file('a.txt', now.subtract(const Duration(hours: 1)));

    prune();

    expect(fresh.existsSync(), isTrue);
  });

  test('prune keeps a file at the bound', () {
    final edge = file('a.txt', now.subtract(_bound));

    prune();

    expect(edge.existsSync(), isTrue);
  });

  test('prune keeps the files the run writes', () {
    final written = file('a.txt', now.subtract(const Duration(days: 9)));
    final other = file('b.txt', now.subtract(const Duration(days: 9)));

    prune(keep: {canonicalPath(written.path)});

    expect(written.existsSync(), isTrue);
    expect(other.existsSync(), isFalse);
  });

  test('prune reaches a subfolder and keeps the folder', () {
    final nested = file('sub/a.txt', now.subtract(const Duration(days: 3)));

    prune();

    expect(nested.existsSync(), isFalse);
    expect(Directory('${bundles.path}/sub').existsSync(), isTrue);
  });

  test('prune never follows a link', () {
    final outside = File('${root.path}/outside.txt')
      ..writeAsStringSync('keep me')
      ..setLastModifiedSync(now.subtract(const Duration(days: 9)));
    final outsideFolder = Directory('${root.path}/outside')..createSync();
    final inner = File('${outsideFolder.path}/inner.txt')
      ..writeAsStringSync('keep me too')
      ..setLastModifiedSync(now.subtract(const Duration(days: 9)));
    try {
      Link('${bundles.path}/file_link').createSync(outside.path);
      Link('${bundles.path}/folder_link').createSync(outsideFolder.path);
    } on FileSystemException {
      if (Platform.isWindows) {
        markTestSkipped('creating a link needs a privilege on Windows');
        return;
      }
      rethrow;
    }

    prune();

    expect(outside.existsSync(), isTrue);
    expect(inner.existsSync(), isTrue);
    expect(Link('${bundles.path}/file_link').existsSync(), isTrue);
  });

  test('prune does nothing when the bundles folder is missing', () {
    bundles.deleteSync();

    expect(prune, returnsNormally);
  });

  test('prune skips a file it cannot delete', () {
    final locked = file('locked/a.txt', now.subtract(const Duration(days: 9)));
    final other = file('b.txt', now.subtract(const Duration(days: 9)));
    Process.runSync('chmod', ['555', locked.parent.path]);

    expect(prune, returnsNormally);

    expect(locked.existsSync(), isTrue);
    expect(other.existsSync(), isFalse);
  }, skip: Platform.isWindows ? 'a read-only folder is a POSIX rule' : null);

  test('prune skips a subfolder it cannot list and goes on', () {
    final hidden = file('sub/a.txt', now.subtract(const Duration(days: 9)));
    final other = file('b.txt', now.subtract(const Duration(days: 9)));
    final nested = file('ok/c.txt', now.subtract(const Duration(days: 9)));
    Process.runSync('chmod', ['000', hidden.parent.path]);

    expect(prune, returnsNormally);

    expect(other.existsSync(), isFalse);
    expect(nested.existsSync(), isFalse);
  }, skip: Platform.isWindows ? 'a mode-000 folder is a POSIX rule' : null);
}

void _makeWritable(Directory folder) {
  if (Platform.isWindows || !folder.existsSync()) return;
  Process.runSync('chmod', ['-R', 'u+rwx', folder.path]);
}
