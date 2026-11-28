@Tags(['integration'])
library;

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

  test('code input: a code root '
      'lists its files as paths from the code root, sorted by code point', () {
    ['lib/b.dart', 'lib/a/z.dart', 'lib/a-b.dart'].forEach(touch);
    expect(filesUnderCodeRoot(root, 'lib/'), [
      'lib/a-b.dart',
      'lib/a/z.dart',
      'lib/b.dart',
    ]);
  });

  test('code input: a name starting '
      'with a dot is skipped, a folder with it and all below', () {
    touch('lib/a.dart');
    touch('lib/.hidden.dart');
    touch('lib/.cache/b.dart');
    expect(filesUnderCodeRoot(root, 'lib'), ['lib/a.dart']);
  });

  test('code input: a link is '
      'skipped and not followed', () {
    touch('lib/a.dart');
    touch('other/b.dart');
    Link('${root.path}/lib/to_other').createSync('${root.path}/other');
    Link('${root.path}/lib/to_file').createSync('${root.path}/other/b.dart');
    expect(filesUnderCodeRoot(root, 'lib'), ['lib/a.dart']);
  }, skip: Platform.isWindows ? 'links need a privilege on Windows' : false);

  test('code input: a missing root '
      'yields none and reports nothing', () {
    final unlistable = <String>[];
    expect(
      filesUnderCodeRoot(root, 'nope/', onUnlistable: unlistable.add),
      isEmpty,
    );
    expect(unlistable, isEmpty);
  });

  test('code input: a file entry '
      'lists that file', () {
    touch('lib/a.dart');
    touch('lib/b.dart');
    expect(filesUnderCodeRoot(root, 'lib/a.dart'), ['lib/a.dart']);
    expect(codeRootFiles(root, ['lib/a.dart', 'lib/']), [
      'lib/a.dart',
      'lib/b.dart',
    ]);
  });

  test('code input: a folder that '
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

  test('code input: codeRootFiles '
      'lists every entry, a file under two entries once, all sorted', () {
    ['lib/b.dart', 'lib/a.dart', 'test/t.dart'].forEach(touch);
    expect(codeRootFiles(root, ['test/', 'lib/', 'lib/']), [
      'lib/a.dart',
      'lib/b.dart',
      'test/t.dart',
    ]);
  });

  // D9
  test('a mention scan code root that matches its folder by letter case '
      'alone lists nothing, on every OS', () {
    touch('lib/a.dart');
    expect(
      mentionScanFiles(root, {
        'LIB/',
      }, docsRoot: Directory('${root.path}/docs')),
      isEmpty,
    );
  });

  // D9
  test('a mention scan code root written in NFC lists the files of its NFD '
      'folder by the disk spelling', () {
    touch('cafe\u{301}/menu.dart');
    expect(
      mentionScanFiles(root, {
        'caf\u{E9}/',
      }, docsRoot: Directory('${root.path}/docs')),
      ['cafe\u{301}/menu.dart'],
    );
  });

  test('code input: dot '
      'segments of an entry are dropped, so every path is in one form', () {
    touch('lib/a.dart');
    touch('top.dart');
    expect(filesUnderCodeRoot(root, './lib/'), ['lib/a.dart']);
    expect(filesUnderCodeRoot(root, './'), ['lib/a.dart', 'top.dart']);
    expect(filesUnderCodeRoot(root, '.'), ['lib/a.dart', 'top.dart']);
    expect(filesUnderCodeRoot(root, 'lib/./a.dart'), ['lib/a.dart']);
  });

  test(
    'with the . root form a nested '
    'code root of another target is left out, a folder of it and all below',
    () {
      [
        'lib/a.dart',
        'web/lib/b.dart',
        'web/c.dart',
        'webx/d.dart',
      ].forEach(touch);
      expect(filesUnderCodeRoot(root, '.', skipFolders: ['web']), [
        'lib/a.dart',
        'webx/d.dart',
      ]);
      expect(filesUnderCodeRoot(root, 'web/', skipFolders: ['web']), isEmpty);
      expect(
        filesUnderCodeRoot(root, 'web/c.dart', skipFolders: ['web']),
        isEmpty,
      );
      expect(filesUnderCodeRoot(root, 'web/', skipFolders: ['web/lib']), [
        'web/c.dart',
      ]);
    },
  );

  // D14
  test('filesUnderCodeRoot prunes an ignored folder and skips an ignored '
      'file, tracked or not', () {
    [
      'lib/a.dart',
      'lib/b.g.dart',
      'lib/tracked.g.dart',
      'lib/gen/c.dart',
      'lib/gen/kept.dart',
    ].forEach(touch);
    File('${root.path}/.gitignore')
        .writeAsStringSync('*.g.dart\ngen/\n!lib/gen/kept.dart\n');
    for (final args in [
      ['init', '-q'],
      ['add', '-f', 'lib/tracked.g.dart'],
    ]) {
      expect(
        Process.runSync('git', args, workingDirectory: root.path).exitCode,
        0,
      );
    }

    expect(filesUnderCodeRoot(root, 'lib'), ['lib/a.dart']);
    expect(filesUnderCodeRoot(root, 'lib/gen/'), isEmpty);
    expect(filesUnderCodeRoot(root, 'lib/tracked.g.dart'), [
      'lib/tracked.g.dart',
    ], reason: 'an entry naming one file reads it');
    expect(codeRootFiles(root, ['lib/', 'lib/b.g.dart']), [
      'lib/a.dart',
      'lib/b.g.dart',
    ]);
  });

  // D14
  test('a folder holding a .git entry starts its own work tree, so the outer '
      'rules stop there', () {
    [
      'a.dart',
      'c.outer',
      'inner/top.dart',
      'inner/lib/a.dart',
      'inner/lib/b.outer',
      'inner/lib/skip.dart',
    ].forEach(touch);
    File('${root.path}/.gitignore').writeAsStringSync('/inner/\n*.outer\n');
    Directory('${root.path}/.git').createSync();
    Directory('${root.path}/inner/.git').createSync();
    File('${root.path}/inner/.gitignore').writeAsStringSync('skip.dart\n');

    expect(filesUnderCodeRoot(root, '.'), [
      'a.dart',
      'inner/lib/a.dart',
      'inner/lib/b.outer',
      'inner/top.dart',
    ]);
    expect(filesUnderCodeRoot(root, 'inner/'), [
      'inner/lib/a.dart',
      'inner/lib/b.outer',
      'inner/top.dart',
    ]);
    expect(filesUnderCodeRoot(root, 'inner/lib/'), [
      'inner/lib/a.dart',
      'inner/lib/b.outer',
    ]);
  });

  group('bounds', () {
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
      // D9: a `..` is refused, not folded.
      expect(filesUnderCodeRoot(codeRoot, 'lib/../lib/'), isEmpty);
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

  group('normal form', () {
    // D9: a `..` is kept, never folded into the segment before it.
    test('a code or covers entry drops . and the final /, and keeps each '
        '..', () {
      expect(normalCodeEntry('./lib/'), 'lib');
      expect(normalCodeEntry('lib/./src//'), 'lib/src');
      expect(normalCodeEntry('lib/../docs/'), 'lib/../docs');
      expect(normalCodeEntry('../x/../y'), '../x/../y');
      expect(normalCodeEntry('./'), '');
      expect(isOutsideCodeEntry('lib/../docs/'), isTrue);
      expect(isOutsideCodeEntry('lib/nope/../a.dart'), isTrue);
      expect(isOutsideCodeEntry('../y'), isTrue);
      expect(isOutsideCodeEntry('lib/a.dart'), isFalse);
    });

    test('a code file in the docs folder, by a docs/ entry, has no '
        'project path', () {
      touch('docs/x.md');
      touch('lib/a.dart');
      final docsRoot = Directory('${root.path}/docs');
      expect(filesUnderCodeRoot(root, 'lib/../docs/'), isEmpty);
      final files = filesUnderCodeRoot(root, 'docs/');
      expect(files, ['docs/x.md']);
      expect(
        ProjectPathReader(
          projectRoot: root,
          docsRoot: docsRoot,
        ).projectPathOf(files.single, root),
        isNull,
      );
      expect(
        ProjectPathReader(
          projectRoot: root,
          docsRoot: docsRoot,
        ).projectPathOf('lib/a.dart', root),
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
        ProjectPathReader(
          projectRoot: root,
          docsRoot: Directory('${root.path}/docs'),
        ).projectPathOf('Docs/x.md', root),
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
        ProjectPathReader(
          projectRoot: project,
          docsRoot: docsRoot,
        ).projectPathOf('lib/a.dart', root),
        '../lib/a.dart',
      );
      expect(
        ProjectPathReader(
          projectRoot: project,
          docsRoot: docsRoot,
        ).projectPathOf('specs/docs/x.md', root),
        isNull,
      );
    });
  });
}
