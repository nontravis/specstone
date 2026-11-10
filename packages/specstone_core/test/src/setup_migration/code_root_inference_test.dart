import 'dart:io';

import 'package:specstone_core/src/setup_migration/code_root_inference.dart';
import 'package:test/test.dart';

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
}
