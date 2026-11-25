import 'package:specstone_core/src/index_query/models/cited_by.dart';
import 'package:test/test.dart';

CitedBy citedBy(
  String name,
  String docType,
  String? byItem,
  String bySection, {
  String docPath = 'a.md',
}) => CitedBy(
  docPath: docPath,
  name: name,
  docType: docType,
  byItem: byItem,
  bySection: bySection,
);

void main() {
  group('CitedBy', () {
    test('equals a CitedBy with the same path, name, type, item, section', () {
      expect(
        citedBy('a', 'fr', 'E01', 'statement'),
        citedBy('a', 'fr', 'E01', 'statement'),
      );
      expect(
        citedBy('a', 'fr', 'E01', 'statement'),
        isNot(citedBy('b', 'fr', 'E01', 'statement')),
      );
      expect(
        citedBy('a', 'fr', 'E01', 'statement'),
        isNot(citedBy('a', 'charter', 'E01', 'statement')),
      );
      expect(
        citedBy('a', 'fr', 'E01', 'statement'),
        isNot(citedBy('a', 'fr', null, 'statement')),
      );
      expect(
        citedBy('a', 'fr', 'E01', 'statement'),
        isNot(citedBy('a', 'fr', 'E01', 'edge_cases')),
      );
      expect(
        citedBy('a', 'fr', 'E01', 'statement'),
        isNot(citedBy('a', 'fr', 'E01', 'statement', docPath: 'b.md')),
      );
      expect(
        citedBy('a', 'fr', 'E01', 'statement').hashCode,
        citedBy('a', 'fr', 'E01', 'statement').hashCode,
      );
      expect(
        citedBy('a', 'fr', 'E01', 'statement').hashCode,
        isNot(citedBy('a', 'fr', 'E01', 'statement', docPath: 'b.md').hashCode),
      );
    });
  });
}
