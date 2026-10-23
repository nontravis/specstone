import 'dart:io';

import 'package:specstone_core/src/rendering/doc_reader.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';

const _zeta = '''
id: zeta
description: A second doc type on the same paths.
path: prds/features/f{nn}_rendering/FEATURE.md
''';

const _feature = 'prds/features/f05_rendering/FEATURE.md';
const _notes = 'prds/features/f05_rendering/notes.md';

Future<DocRead> _read(
  String docPath,
  String content, {
  Map<String, String> extra = const {},
  List<int>? bytes,
}) async {
  final root = await fixtureProject({'docs/$docPath': content});
  final project = DocsProject.open(
    templates: TemplateResolver(shippedFiles: fixturePackFiles(extra: extra)),
    workingDirectory: root,
    homeDirectory: null,
  );
  final target = project.resolveTarget(
    'docs/$docPath',
    workingDirectory: root,
    defaultsToDocsRoot: false,
  );
  final file = target.entity as File;
  if (bytes != null) file.writeAsBytesSync(bytes);
  return readDoc(project, DocFile(file, target.docPath));
}

void main() {
  test('f05/us01/fr02, s03/inv12: a matched UTF-8 doc is readable, parsed from '
      'its LF text', () async {
    final read = await _read(_feature, '# T\r\n\r\n## Feature name\r\nx\r\n');

    expect(read, isA<ReadableDoc>());
    final doc = read as ReadableDoc;
    expect(doc.path, 'docs/$_feature');
    expect(doc.lineEnding, LineEnding.crlf);
    expect(doc.docType.id, 'feature');
    expect(doc.text, '# T\r\n\r\n## Feature name\r\nx\r\n');
    expect(doc.doc.title, 'T');
    expect(doc.doc.sections.single.body, 'x\n');
  });

  test('f05/us01/fr02/e02, s03/inv12: a path no doc type matches is '
      'unmatched, with the skip warning', () async {
    final read = await _read(_notes, 'text');

    expect(read, isA<UnmatchedDoc>());
    expect(
      (read as UnmatchedDoc).warning,
      'docs/$_notes: no doc type matches this path; skipped',
    );
  });

  test('f05/us01/fr02/e03, s03/inv6: a path two doc types match is '
      'ambiguous, with their ids', () async {
    final read = await _read(_feature, '# T\n', extra: {'zeta.yaml': _zeta});

    expect(read, isA<AmbiguousDoc>());
    expect((read as AmbiguousDoc).docTypeIds, ['feature', 'zeta']);
  });

  test('Plan decision 8: a doc that is not UTF-8 is not UTF-8 text, with '
      'the skip warning', () async {
    final read = await _read(_feature, '', bytes: [0xFF, 0xFE]);

    expect(read, isA<NotUtf8Doc>());
    expect(
      (read as NotUtf8Doc).warning,
      'docs/$_feature: not UTF-8 text; skipped',
    );
  });

  test('a doc type is matched before the bytes are decoded', () async {
    final read = await _read(_notes, '', bytes: [0xFF, 0xFE]);

    expect(read, isA<UnmatchedDoc>());
  });
}
