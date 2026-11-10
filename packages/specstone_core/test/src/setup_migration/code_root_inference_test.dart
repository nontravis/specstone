import 'dart:io';

import 'package:specstone_core/src/setup_migration/code_root_inference.dart';
import 'package:test/test.dart';

import '../../helpers/relative_link.dart';
import '../../helpers/temp_tree.dart';

const _repositoryMark = '.git/HEAD';

/// Writes [files] under a canonical temp folder and returns that folder.
Future<Directory> _tree(Map<String, String> files) async =>
    Directory((await writeTree(files)).resolveSymbolicLinksSync());

Directory _at(Directory base, String relative) =>
    Directory('${base.path}/$relative');

CodeRootChoice _infer(
  Directory root, {
  Directory? link,
  List<String> implementsEntries = const [],
  List<String> coversEntries = const [],
}) => inferCodeRoot(
  root,
  linkFolder: link,
  implementsEntries: implementsEntries,
  coversEntries: coversEntries,
);

void main() {
  test('f06/us01/fr05/e11: a real docs folder in a repo whose code sits one '
      'folder up infers .. and counts the stale entry as cited', () async {
    final tree = await _tree({
      _repositoryMark: '',
      'proj/keep.txt': '',
      for (var i = 1; i <= 39; i++) 'lib/f$i.dart': '',
    });

    final choice = _infer(
      _at(tree, 'proj'),
      implementsEntries: [
        for (var i = 1; i <= 39; i++) 'lib/f$i.dart',
        'lib/gone.dart',
      ],
    );

    expect(choice, (value: '..', found: 39, cited: 40));
  });

  test('f06/us01/fr05/e11: a folder above the repository top is never a '
      'candidate', () async {
    final tree = await _tree({
      'repo/$_repositoryMark': '',
      'repo/proj/keep.txt': '',
      'repo/lib/a.dart': '',
      'lib/a.dart': '',
      'lib/b.dart': '',
    });

    final choice = _infer(
      _at(tree, 'repo/proj'),
      implementsEntries: ['lib/a.dart', 'lib/b.dart'],
    );

    expect(choice, (value: '..', found: 1, cited: 2));
  });

  test('f06/us01/fr05/e11: equal counts go to the deeper folder', () async {
    final tree = await _tree({
      'proj/keep.txt': '',
      'proj/code/lib/a.dart': '',
      'proj/code/lib/b.dart': '',
    });

    final choice = _infer(
      _at(tree, 'proj'),
      link: _at(tree, 'proj/code'),
      implementsEntries: ['lib/a.dart', 'code/lib/b.dart'],
    );

    expect(choice, (value: 'code', found: 1, cited: 2));
  });

  test('f06/us01/fr05/e11: at equal depth the root wins over the link '
      'folder', () async {
    final tree = await _tree({
      'proj/keep.txt': '',
      'proj/lib/a.dart': '',
      'other/lib/a.dart': '',
    });

    final choice = _infer(
      _at(tree, 'proj'),
      link: _at(tree, 'other'),
      implementsEntries: ['lib/a.dart'],
    );

    expect(choice, (value: '.', found: 1, cited: 1));
  });

  test('f06/us01/fr05/e11: at equal depth the link folder wins over a folder '
      'above the root', () async {
    final tree = await _tree({
      _repositoryMark: '',
      'x/y/r/keep.txt': '',
      'x/y/lib/a.dart': '',
      'z/l/lib/a.dart': '',
    });

    final choice = _infer(
      _at(tree, 'x/y/r'),
      link: _at(tree, 'z/l'),
      implementsEntries: ['lib/a.dart'],
    );

    expect(choice, (value: '../../../z/l', found: 1, cited: 1));
  });

  test('f06/us01/fr05/e11: at equal depth and rank the code point order of '
      'the paths decides', () async {
    final tree = await _tree({
      _repositoryMark: '',
      'r1/a/root/keep.txt': '',
      'r1/a/lib/x.dart': '',
      'l1/b/link/keep.txt': '',
      'l1/b/lib/x.dart': '',
    });

    final choice = _infer(
      _at(tree, 'r1/a/root'),
      link: _at(tree, 'l1/b/link'),
      implementsEntries: ['lib/x.dart'],
    );

    expect(choice, (value: '../../../l1/b', found: 1, cited: 1));
  });

  test('f06/us01/fr05/e11: two entries citing one path count twice', () async {
    final tree = await _tree({
      _repositoryMark: '',
      'proj/keep.txt': '',
      'lib/a.dart': '',
    });

    final choice = _infer(
      _at(tree, 'proj'),
      implementsEntries: ['lib/a.dart', 'lib/a.dart:A'],
      coversEntries: ['lib/a.dart'],
    );

    expect(choice, (value: '..', found: 3, cited: 3));
  });

  test('f06/us01/fr05/e11: an implements entry naming a folder does not '
      'count', () async {
    final tree = await _tree({
      _repositoryMark: '',
      'proj/keep.txt': '',
      'lib/a.dart': '',
    });

    final choice = _infer(
      _at(tree, 'proj'),
      implementsEntries: ['lib', 'lib/'],
    );

    expect(choice, (value: '.', found: 0, cited: 2));
  });

  test('f06/us01/fr05/e11: a covers entry naming a folder counts', () async {
    final tree = await _tree({
      _repositoryMark: '',
      'proj/keep.txt': '',
      'lib/a.dart': '',
    });

    final choice = _infer(_at(tree, 'proj'), coversEntries: ['lib']);

    expect(choice, (value: '..', found: 1, cited: 1));
  });

  test('f06/us01/fr05/e12: a winner outside the project root is written '
      'as a path with .. steps', () async {
    final tree = await _tree({
      _repositoryMark: '',
      'proj/keep.txt': '',
      'code/lib/a.dart': '',
    });

    final choice = _infer(
      _at(tree, 'proj'),
      link: _at(tree, 'code'),
      implementsEntries: ['lib/a.dart'],
    );

    expect(choice, (value: '../code', found: 1, cited: 1));
  });

  test('f06/us01/fr05/e12: no cited entry gives .', () async {
    final tree = await _tree({_repositoryMark: '', 'proj/keep.txt': ''});

    final choice = _infer(_at(tree, 'proj'));

    expect(choice, (value: '.', found: 0, cited: 0));
  });

  test('f06/us01/fr05/e12: the root as winner gives .', () async {
    final tree = await _tree({
      _repositoryMark: '',
      'proj/lib/a.dart': '',
      'lib/b.dart': '',
    });

    final choice = _infer(
      _at(tree, 'proj'),
      implementsEntries: ['lib/a.dart', 'lib/a.dart:A', 'lib/b.dart'],
    );

    expect(choice, (value: '.', found: 2, cited: 3));
  });

  test('f06/us01/fr05/e11: a root reached through a symlink gives the value '
      'of its canonical path', () async {
    final tree = await _tree({
      'real/repo/$_repositoryMark': '',
      'real/repo/docs/keep.txt': '',
      'real/repo/lib/b.dart': '',
      'real/lib/a.dart': '',
      'real/lib/b.dart': '',
    });
    if (!_linkOrSkip('${tree.path}/ln', 'real')) return;
    const entries = ['lib/a.dart', 'lib/b.dart'];

    final canonical = _infer(
      _at(tree, 'real/repo/docs'),
      implementsEntries: entries,
    );
    final viaLink = _infer(
      _at(tree, 'ln/repo/docs'),
      implementsEntries: entries,
    );

    expect(canonical, (value: '..', found: 1, cited: 2));
    expect(viaLink, canonical);
  });

  test('f06/us01/fr05/e11: a link folder reached through a symlink adds no '
      'folder above the repository top', () async {
    final tree = await _tree({
      'proj/keep.txt': '',
      'real/repo/$_repositoryMark': '',
      'real/repo/code/keep.txt': '',
      'real/lib/a.dart': '',
    });
    if (!_linkOrSkip('${tree.path}/ln', 'real')) return;

    final choice = _infer(
      _at(tree, 'proj'),
      link: _at(tree, 'ln/repo/code'),
      implementsEntries: ['lib/a.dart'],
    );

    expect(choice, (value: '.', found: 0, cited: 1));
  });

  test('f06/us01/fr05/e11: a candidate whose value the reader refuses is '
      'skipped, so the winner is a value that can be written', () async {
    final tree = await _tree({
      _repositoryMark: '',
      'proj/keep.txt': '',
      'lib/b.dart': '',
    });
    // writeTree reads its keys as URIs, which turn `\` into `/`.
    File('${tree.path}/co\\de/lib/a.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('');

    final choice = _infer(
      _at(tree, 'proj'),
      link: Directory('${tree.path}/co\\de'),
      implementsEntries: ['lib/a.dart', 'lib/b.dart'],
    );

    expect(choice, (value: '..', found: 1, cited: 2));
  }, skip: _windowsSkip);

  test('f06/us01/fr05/e11: entries every candidate resolves go to the '
      'deepest candidate', () async {
    final tree = await _tree({'proj/keep.txt': '', 'proj/code/keep.txt': ''});

    final choice = _infer(
      _at(tree, 'proj'),
      link: _at(tree, 'proj/code'),
      coversEntries: ['', '.'],
    );

    expect(choice, (value: 'code', found: 2, cited: 2));
  });

  test('f06/us01/fr05/e11: a link folder in no repository adds no folder '
      'above it', () async {
    final tree = await _tree({
      'a/proj/keep.txt': '',
      'b/code/keep.txt': '',
      'b/lib/x.dart': '',
    });

    final choice = _infer(
      _at(tree, 'a/proj'),
      link: _at(tree, 'b/code'),
      implementsEntries: ['lib/x.dart'],
    );

    expect(choice, (value: '.', found: 0, cited: 1));
  });

  test('f06/us01/fr05/e11: a link folder in another repository climbs to its '
      'own repository top and no further', () async {
    final tree = await _tree({
      'r1/$_repositoryMark': '',
      'r1/proj/keep.txt': '',
      'r2/$_repositoryMark': '',
      'r2/code/keep.txt': '',
      'r2/lib/x.dart': '',
      'lib/y.dart': '',
    });

    final choice = _infer(
      _at(tree, 'r1/proj'),
      link: _at(tree, 'r2/code'),
      implementsEntries: ['lib/x.dart', 'lib/y.dart'],
    );

    expect(choice, (value: '../../r2', found: 1, cited: 2));
  });

  test('f06/us01/fr05/e11: a repository top equal to the root adds no '
      'folder above it', () async {
    final tree = await _tree({
      'proj/$_repositoryMark': '',
      'proj/keep.txt': '',
      'lib/a.dart': '',
    });

    final choice = _infer(
      _at(tree, 'proj'),
      implementsEntries: ['lib/a.dart'],
      coversEntries: ['lib/a.dart'],
    );

    expect(choice, (value: '.', found: 0, cited: 2));
  });

  test('f06/us01/fr05/e11: an entry with Windows separators does not count '
      r'where \ is a name character', () async {
    final tree = await _tree({
      _repositoryMark: '',
      'proj/keep.txt': '',
      'lib/q.dart': '',
    });

    final choice = _infer(
      _at(tree, 'proj'),
      implementsEntries: [r'..\lib\q.dart'],
      coversEntries: [r'..\lib\q.dart'],
    );

    expect(choice, (value: '.', found: 0, cited: 2));
  }, skip: _windowsSkip);

  test('f06/us01/fr05/e11: an absolute entry counts as the path under the '
      'candidate, as check resolves it', () async {
    final tree = await _tree({_repositoryMark: '', 'proj/lib/q.dart': ''});

    final choice = _infer(
      _at(tree, 'proj'),
      implementsEntries: ['/lib/q.dart'],
      coversEntries: ['/lib/q.dart'],
    );

    expect(choice, (value: '.', found: 2, cited: 2));
  }, skip: _windowsSkip);

  test('f06/us01/fr05/e11: an entry that leaves the repository counts from '
      'the candidate that reaches it', () async {
    final tree = await _tree({
      'repo/$_repositoryMark': '',
      'repo/proj/keep.txt': '',
      'lib/c.dart': '',
    });

    final choice = _infer(
      _at(tree, 'repo/proj'),
      implementsEntries: ['../../lib/c.dart'],
      coversEntries: ['../../lib/c.dart'],
    );

    expect(choice, (value: '.', found: 2, cited: 2));
  });

  test('f06/us01/fr05/e11: an entry through a symlinked code folder counts, '
      'as check follows links', () async {
    final tree = await _tree({
      _repositoryMark: '',
      'proj/keep.txt': '',
      'real/a.dart': '',
    });
    if (!_linkOrSkip('${tree.path}/proj/src', '../real')) return;

    final choice = _infer(
      _at(tree, 'proj'),
      implementsEntries: ['src/a.dart'],
      coversEntries: ['src'],
    );

    expect(choice, (value: '.', found: 2, cited: 2));
  });
}

final Object _windowsSkip = Platform.isWindows
    ? r'POSIX path rules: \ is a name character and / roots a path'
    : false;

/// Links [linkPath] to [target]; marks the test skipped and returns false
/// where links need privileges.
bool _linkOrSkip(String linkPath, String target) {
  try {
    createRelativeLink(linkPath, target);
    return true;
  } on FileSystemException {
    markTestSkipped('symbolic links need privileges on this machine');
    return false;
  }
}
