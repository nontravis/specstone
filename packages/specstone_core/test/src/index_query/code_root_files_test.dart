import 'dart:io';

import 'package:specstone_core/src/index_query/code_root_files.dart';
import 'package:test/test.dart';

import '../../helpers/posix_modes.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('specstone_code_root_');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  void touch(String path) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync('');

  test('document_writing/rename_doc/rewrite_name_references code input: a code root '
      'lists its files as paths from the code root, sorted by code point', () {
    ['lib/b.dart', 'lib/a/z.dart', 'lib/a-b.dart'].forEach(touch);
    expect(filesUnderCodeRoot(root, 'lib/'), [
      'lib/a-b.dart',
      'lib/a/z.dart',
      'lib/b.dart',
    ]);
  });

  test('document_writing/rename_doc/rewrite_name_references code input: a name starting '
      'with a dot is skipped, a folder with it and all below', () {
    touch('lib/a.dart');
    touch('lib/.hidden.dart');
    touch('lib/.cache/b.dart');
    expect(filesUnderCodeRoot(root, 'lib'), ['lib/a.dart']);
  });

  test(
    'document_writing/rename_doc/rewrite_name_references code input: a link is '
    'skipped and not followed',
    () {
      touch('lib/a.dart');
      touch('other/b.dart');
      Link('${root.path}/lib/to_other').createSync('${root.path}/other');
      Link('${root.path}/lib/to_file').createSync('${root.path}/other/b.dart');
      expect(filesUnderCodeRoot(root, 'lib'), ['lib/a.dart']);
    },
    skip: Platform.isWindows ? 'links need a privilege on Windows' : false,
  );

  test('document_writing/rename_doc/rewrite_name_references code input: a missing root '
      'yields none and reports nothing', () {
    final unlistable = <String>[];
    expect(
      filesUnderCodeRoot(root, 'nope/', onUnlistable: unlistable.add),
      isEmpty,
    );
    expect(unlistable, isEmpty);
  });

  test('document_writing/rename_doc/rewrite_name_references code input: a file entry '
      'lists that file', () {
    touch('lib/a.dart');
    touch('lib/b.dart');
    expect(filesUnderCodeRoot(root, 'lib/a.dart'), ['lib/a.dart']);
    expect(codeRootFiles(root, ['lib/a.dart', 'lib/']), [
      'lib/a.dart',
      'lib/b.dart',
    ]);
  });

  test('document_writing/rename_doc/rewrite_name_references code input: a folder that '
      'cannot be listed is reported and its files left out', () {
    touch('lib/a.dart');
    touch('lib/locked/b.dart');
    final locked = '${root.path}/lib/locked';
    Process.runSync('chmod', ['000', locked]);
    addTearDown(() => Process.runSync('chmod', ['755', locked]));
    final unlistable = <String>[];
    expect(filesUnderCodeRoot(root, 'lib', onUnlistable: unlistable.add), [
      'lib/a.dart',
    ]);
    expect(unlistable, ['lib/locked']);
  }, skip: unreadablePathSkipReason() ?? false);

  test('document_writing/rename_doc/rewrite_name_references code input: codeRootFiles '
      'lists every entry, a file under two entries once, all sorted', () {
    ['lib/b.dart', 'lib/a.dart', 'test/t.dart'].forEach(touch);
    expect(codeRootFiles(root, ['test/', 'lib/', 'lib/']), [
      'lib/a.dart',
      'lib/b.dart',
      'test/t.dart',
    ]);
  });

  test('document_writing/rename_doc/rewrite_name_references code input: dot '
      'segments of an entry are dropped, so every path is in one form', () {
    touch('lib/a.dart');
    touch('top.dart');
    expect(filesUnderCodeRoot(root, './lib/'), ['lib/a.dart']);
    expect(filesUnderCodeRoot(root, './'), ['lib/a.dart', 'top.dart']);
    expect(filesUnderCodeRoot(root, '.'), ['lib/a.dart', 'top.dart']);
    expect(filesUnderCodeRoot(root, 'lib/./a.dart'), ['lib/a.dart']);
  });
}
