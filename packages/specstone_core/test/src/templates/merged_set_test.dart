import 'dart:convert';
import 'dart:typed_data';

import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/temp_tree.dart';

MergedDocType _docType(String id, {String? pack, String? description}) =>
    MergedDocType(
      id: id,
      pack: pack,
      description: description,
      fields: const [],
      sections: const [],
      lint: const MergedLint(),
      files: const [],
    );

void main() {
  group('MergedSet', () {
    test('sorts doc types by id and freezes the list', () {
      final given = [_docType('b'), _docType('a'), _docType('c')];

      final merged = MergedSet(docTypes: given);

      expect(merged.docTypes.map((docType) => docType.id), ['a', 'b', 'c']);
      expect(given.map((docType) => docType.id), ['b', 'a', 'c']);
      expect(() => merged.docTypes.add(_docType('d')), throwsUnsupportedError);
    });

    test('finds a doc type by id and misses an unknown id', () {
      final merged = MergedSet(docTypes: [_docType('feature')]);

      expect(merged.lookup('feature')!.id, 'feature');
      expect(merged.lookup('runbook'), isNull);
    });

    test('f03/us01/s2, f03/us01/fr01: listText prints one id per line', () {
      final merged = MergedSet(
        docTypes: [_docType('runbook'), _docType('feature')],
      );

      expect(merged.listText(), 'feature\nrunbook\n');
      expect(MergedSet(docTypes: const []).listText(), '');
    });

    test('f03/us01/s8, f03/us01/fr01: listJson matches the s02 example', () {
      final merged = MergedSet(
        docTypes: [
          _docType(
            'runbook',
            description: 'An operations runbook for one service.',
          ),
          _docType(
            'feature',
            pack: 'prd-core',
            description: 'A feature groups the stories that serve one goal.',
          ),
        ],
      );

      final json = merged.listJson();

      expect(json, [
        {
          'id': 'feature',
          'pack': 'prd-core',
          'description': 'A feature groups the stories that serve one goal.',
        },
        {
          'id': 'runbook',
          'description': 'An operations runbook for one service.',
        },
      ]);
      expect(
        jsonEncode(json),
        '[{"id":"feature","pack":"prd-core","description":"A feature groups '
        'the stories that serve one goal."},{"id":"runbook","description":"An '
        'operations runbook for one service."}]',
      );
    });

    test('lists the first line of a description that spans lines', () {
      final inherited = _docType(
        'story',
        pack: 'prd-core',
        description: 'First line.\nSecond line.',
      ).copyWith(extendsId: 'base');

      final json = MergedSet(docTypes: [inherited]).listJson();

      expect(json.single['description'], 'First line.');
    });

    test('f03/us01/fr01/e05: a doc type with extends and no description of '
        'its own lists the first line of the target description', () async {
      final project = await writeTree({
        '.specstone/config.yaml': 'packs:\n  prd-core: 1.1.0\n',
        '.specstone/templates/a.yaml': '''
id: a
description: |
  First line of a.
  Second line of a.
path: a/{slug}.md
''',
        '.specstone/templates/b.yaml': '''
id: b
extends: a
path: b/{slug}.md
''',
      });
      final home = await writeTree({});
      final resolver = TemplateResolver(
        shippedFiles: {
          'prd-core/pack.yaml': Uint8List.fromList(
            utf8.encode('name: prd-core\nversion: 1.1.0\n'),
          ),
        },
      );

      final json = resolver
          .resolve(workingDirectory: project, homeDirectory: home)
          .listJson();

      expect(json, [
        {'id': 'a', 'description': 'First line of a.'},
        {'id': 'b', 'description': 'First line of a.'},
      ]);
    });

    test('f03/us01/fr01: an empty description lists as an empty string', () {
      final json = MergedSet(docTypes: [_docType('a', description: '')])
          .listJson();

      expect(json, [
        {'id': 'a', 'description': ''},
      ]);
    });
  });
}
