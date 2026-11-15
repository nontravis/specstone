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
}
