import 'package:specstone_core/src/index_query/models/cited_by.dart';
import 'package:test/test.dart';

CitedBy citedBy(String name, String docType, String? byItem, String line) =>
    CitedBy(name: name, docType: docType, byItem: byItem, line: line);

void main() {
  group('CitedBy', () {
    test(
      'equals another CitedBy with the same name, doc type, item, and line',
      () {
        expect(citedBy('a', 'fr', 'E01', 'x'), citedBy('a', 'fr', 'E01', 'x'));
        expect(
          citedBy('a', 'fr', 'E01', 'x'),
          isNot(citedBy('b', 'fr', 'E01', 'x')),
        );
        expect(
          citedBy('a', 'fr', 'E01', 'x'),
          isNot(citedBy('a', 'topic', 'E01', 'x')),
        );
        expect(
          citedBy('a', 'fr', 'E01', 'x'),
          isNot(citedBy('a', 'fr', null, 'x')),
        );
        expect(
          citedBy('a', 'fr', 'E01', 'x'),
          isNot(citedBy('a', 'fr', 'E01', 'y')),
        );
        expect(
          citedBy('a', 'fr', 'E01', 'x').hashCode,
          citedBy('a', 'fr', 'E01', 'x').hashCode,
        );
      },
    );
  });
}
