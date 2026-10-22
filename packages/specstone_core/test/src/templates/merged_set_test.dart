import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:test/test.dart';

MergedDocType _docType(String id) => MergedDocType(
  id: id,
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
  });
}
