import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_splice.dart' show baseHashOf;
import 'package:specstone_core/src/document_writing/audited_copy_store.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

const _docPath = 'prds/features/f01/FEATURE.md';
const _otherPath = 'prds/features/f02/FEATURE.md';

File _copyOf(Directory root, String docPath, String text) =>
    File('${root.path}/.specstone/audited/$docPath/${baseHashOf(text)}.md');

void main() {
  test(
    'saves a draft text under its path and base hash and finds it again',
    () async {
      final root = await writeTree({'.specstone/config.yaml': ''});
      const text = '---\ndraft: true\n---\n\n# Signup\n\nBody.\n';
      final store = AuditedCopyStore(root)..save(_docPath, text);

      expect(_copyOf(root, _docPath, text).readAsStringSync(), text);
      expect(store.find(_docPath, baseHashOf(text)), text);
      expect(
        File('${root.path}/.specstone/audited/.gitignore').readAsStringSync(),
        '*\n',
      );
    },
  );

  test('finds no copy for a hash it never saved', () async {
    final root = await writeTree({'.specstone/config.yaml': ''});
    final store = AuditedCopyStore(root)..save(_docPath, '# One\n');

    expect(store.find(_docPath, baseHashOf('# Two\n')), isNull);
    expect(store.find(_otherPath, baseHashOf('# One\n')), isNull);
    expect(store.find(_docPath, 'not a hash'), isNull);
    expect(store.find('../outside.md', baseHashOf('# One\n')), isNull);
  });

  test('prune drops the copies of a doc gone from disk', () async {
    final root = await writeTree({
      '.specstone/config.yaml': '',
      'docs/$_docPath': '# One\n',
    });
    AuditedCopyStore(root)
      ..save(_docPath, '# One\n')
      ..save(_docPath, '# One again\n')
      ..save(_otherPath, '# Two\n')
      ..prune((docPath) => File('${root.path}/docs/$docPath').existsSync());

    expect(_copyOf(root, _docPath, '# One\n').existsSync(), isTrue);
    expect(_copyOf(root, _docPath, '# One again\n').existsSync(), isTrue);
    expect(_copyOf(root, _otherPath, '# Two\n').existsSync(), isFalse);
    expect(
      Directory('${root.path}/.specstone/audited/prds/features/f02')
          .existsSync(),
      isFalse,
    );
  });
}
