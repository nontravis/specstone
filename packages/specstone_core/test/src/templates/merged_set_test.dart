import 'dart:convert';

import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

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

    test('f03/us01/fr01/e05: a doc type with extends lists the first line of '
        'its inherited description', () {
      final inherited = _docType(
        'story',
        pack: 'prd-core',
        description: 'First line.\nSecond line.',
      ).copyWith(extendsId: 'base');

      final json = MergedSet(docTypes: [inherited]).listJson();

      expect(json.single['description'], 'First line.');
    });
  });
}
