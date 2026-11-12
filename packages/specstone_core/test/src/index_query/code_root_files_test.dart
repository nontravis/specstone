import 'dart:io';

import 'package:specstone_core/src/index_query/code_root_files.dart';
import 'package:test/test.dart';

import '../../helpers/posix_modes.dart';

const _lister =
    'document_writing/rename_doc/rewrite_name_references code input:';

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

  group('$_lister bounds', () {
    late Directory codeRoot;

    setUp(() {
      codeRoot = Directory('${root.path}/code')..createSync();
      touch('code/lib/a.dart');
      touch('outside/b.dart');
    });

    test('an entry that leaves the code root lists nothing', () {
      expect(filesUnderCodeRoot(codeRoot, '../'), isEmpty);
      expect(filesUnderCodeRoot(codeRoot, 'lib/../../outside/'), isEmpty);
      expect(filesUnderCodeRoot(codeRoot, '../outside/b.dart'), isEmpty);
      expect(filesUnderCodeRoot(codeRoot, 'lib/../lib/'), ['lib/a.dart']);
    });

    test('an entry that is not a relative / path lists nothing', () {
      expect(filesUnderCodeRoot(codeRoot, '${root.path}/outside/'), isEmpty);
      expect(filesUnderCodeRoot(codeRoot, r'..\outside\'), isEmpty);
      expect(filesUnderCodeRoot(codeRoot, 'C:/x/'), isEmpty);
    });

    test('an entry that is a link, or passes one, lists nothing', () {
      Link('${codeRoot.path}/out').createSync('${root.path}/outside');
      Link('${codeRoot.path}/in').createSync('${codeRoot.path}/lib');
      Link('${codeRoot.path}/b.dart').createSync('${root.path}/outside/b.dart');
      expect(filesUnderCodeRoot(codeRoot, 'out/'), isEmpty);
      expect(filesUnderCodeRoot(codeRoot, 'out/b.dart'), isEmpty);
      expect(filesUnderCodeRoot(codeRoot, 'in/'), isEmpty);
      expect(filesUnderCodeRoot(codeRoot, 'b.dart'), isEmpty);
    }, skip: Platform.isWindows ? 'links need a privilege on Windows' : false);
  });

  group('$_lister normal form', () {
    test('a code or covers entry drops . and the final /, and applies ..', () {
      expect(normalCodeEntry('./lib/'), 'lib');
      expect(normalCodeEntry('lib/./src//'), 'lib/src');
      expect(normalCodeEntry('lib/../docs/'), 'docs');
      expect(normalCodeEntry('../x/../y'), '../y');
      expect(normalCodeEntry('./'), '');
    });

    test('a code file in the docs folder, by a lib/../docs entry, has no '
        'project path', () {
      touch('docs/x.md');
      touch('lib/a.dart');
      final docsRoot = Directory('${root.path}/docs');
      final files = filesUnderCodeRoot(root, 'lib/../docs/');
      expect(files, ['docs/x.md']);
      expect(
        projectPathOfCodeFile(
          files.single,
          projectRoot: root,
          docsRoot: docsRoot,
          codeRoot: root,
        ),
        isNull,
      );
      expect(
        projectPathOfCodeFile(
          'lib/a.dart',
          projectRoot: root,
          docsRoot: docsRoot,
          codeRoot: root,
        ),
        'lib/a.dart',
      );
    });

    test('a Docs/ entry on a case-insensitive volume names the docs '
        'folder', () {
      touch('docs/x.md');
      if (!Directory('${root.path}/DOCS').existsSync()) {
        markTestSkipped('the volume is case-sensitive');
        return;
      }
      expect(
        projectPathOfCodeFile(
          'Docs/x.md',
          projectRoot: root,
          docsRoot: Directory('${root.path}/docs'),
          codeRoot: root,
        ),
        isNull,
      );
    });

    test('a code file above the project, under code_root .., reads from the '
        'project with ..', () {
      touch('specs/docs/x.md');
      touch('lib/a.dart');
      final project = Directory('${root.path}/specs');
      final docsRoot = Directory('${project.path}/docs');
      expect(
        projectPathOfCodeFile(
          'lib/a.dart',
          projectRoot: project,
          docsRoot: docsRoot,
          codeRoot: root,
        ),
        '../lib/a.dart',
      );
      expect(
        projectPathOfCodeFile(
          'specs/docs/x.md',
          projectRoot: project,
          docsRoot: docsRoot,
          codeRoot: root,
        ),
        isNull,
      );
    });
  });
}
