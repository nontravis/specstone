import 'dart:io';

import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:test/test.dart';

String _join(List<String> parts) => parts.join(Platform.pathSeparator);

void main() {
  final project = Directory(_join([Directory.systemTemp.path, 'proj']));
  final docs = Directory(_join([project.path, 'docs']));

  File fileOf(String docPath) =>
      fileOfDocPath(docPath, docsRoot: docs, projectRoot: project);

  String? docPathOf(String path) =>
      docPathOfPath(path, docsRoot: docs, projectRoot: project);

  test('a records DocPath resolves under the project root', () {
    expect(
      fileOf('.specstone/records/f01_x/IMPLEMENTATION.md').path,
      _join([
        project.path,
        '.specstone',
        'records',
        'f01_x',
        'IMPLEMENTATION.md',
      ]),
    );
  });

  test('any other DocPath resolves under the docs root', () {
    expect(
      fileOf('prds/features/f01_x/FEATURE.md').path,
      _join([docs.path, 'prds', 'features', 'f01_x', 'FEATURE.md']),
    );
    expect(
      fileOf('.specstone/other/x.md').path,
      _join([docs.path, '.specstone', 'other', 'x.md']),
    );
  });

  test('only the records folder counts as a records DocPath', () {
    expect(
      isRecordsDocPath('.specstone/records/f01_x/IMPLEMENTATION.md'),
      isTrue,
    );
    expect(isRecordsDocPath('.specstone/records'), isFalse);
    expect(isRecordsDocPath('.specstone/index.md'), isFalse);
    expect(isRecordsDocPath('prds/.specstone/records/x.md'), isFalse);
  });

  test('a path inverts to its DocPath in either root', () {
    expect(
      docPathOf(_join([docs.path, 'prds', 'PROJECT.md'])),
      'prds/PROJECT.md',
    );
    expect(
      docPathOf(
        _join([
          project.path,
          '.specstone',
          'records',
          'f01_x',
          'IMPLEMENTATION.md',
        ]),
      ),
      '.specstone/records/f01_x/IMPLEMENTATION.md',
    );
    expect(docPathOf(docs.path), '');
    expect(
      docPathOf(_join([project.path, '.specstone', 'records'])),
      '.specstone/records',
    );
  });

  test('a path in neither root has no DocPath', () {
    expect(
      docPathOf(_join([project.path, '.specstone', 'index.sqlite'])),
      isNull,
    );
    expect(docPathOf(_join([project.path, 'lib', 'a.dart'])), isNull);
    expect(
      docPathOf(_join([project.path, '.specstone', 'records_old', 'a.md'])),
      isNull,
    );
  });

  group('recordsRootOf', () {
    final skipLinks = Platform.isWindows
        ? 'links need privileges on Windows'
        : null;

    Directory tree() {
      final root = Directory.systemTemp.createTempSync('specstone_records_');
      addTearDown(() => root.deleteSync(recursive: true));
      return root;
    }

    test('gives the records folder of a project that holds one', () {
      final root = tree();
      Directory(_join([root.path, '.specstone', 'records']))
          .createSync(recursive: true);
      expect(
        recordsRootOf(root)?.path,
        _join([root.path, '.specstone', 'records']),
      );
    });

    test('gives null when the project holds none', () {
      expect(recordsRootOf(tree()), isNull);
    });

    test('gives null for a linked records folder', skip: skipLinks, () {
      final root = tree();
      final outside = Directory(_join([root.path, 'outside']))..createSync();
      Directory(_join([root.path, '.specstone'])).createSync();
      Link(_join([root.path, '.specstone', 'records']))
          .createSync(outside.path);
      expect(recordsRootOf(root), isNull);
    });

    test('gives null for a linked .specstone folder', skip: skipLinks, () {
      final root = tree();
      final outside = Directory(_join([root.path, 'outside']));
      Directory(_join([outside.path, 'records'])).createSync(recursive: true);
      Link(_join([root.path, '.specstone'])).createSync(outside.path);
      expect(recordsRootOf(root), isNull);
    });
  });
}
