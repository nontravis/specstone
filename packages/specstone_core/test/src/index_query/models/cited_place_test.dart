import 'package:specstone_core/src/index_query/models/cited_place.dart';
import 'package:test/test.dart';

CitedPlace place(String docPath, CitedKind kind, String? key) =>
    CitedPlace(docPath: docPath, kind: kind, key: key);

void main() {
  group('CitedPlace', () {
    test('equals another CitedPlace with the same doc path, kind, and key', () {
      expect(
        place('a.md', CitedKind.item, 'E01'),
        place('a.md', CitedKind.item, 'E01'),
      );
      expect(
        place('a.md', CitedKind.item, 'E01'),
        isNot(place('b.md', CitedKind.item, 'E01')),
      );
      expect(
        place('a.md', CitedKind.item, 'E01'),
        isNot(place('a.md', CitedKind.section, 'E01')),
      );
      expect(
        place('a.md', CitedKind.item, 'E01'),
        isNot(place('a.md', CitedKind.item, 'E02')),
      );
      expect(
        place('a.md', CitedKind.item, 'E01').hashCode,
        place('a.md', CitedKind.item, 'E01').hashCode,
      );
    });

    test('a doc place with no key equals its twin and no section place', () {
      expect(
        place('a.md', CitedKind.doc, null),
        place('a.md', CitedKind.doc, null),
      );
      expect(
        place('a.md', CitedKind.doc, null),
        isNot(place('a.md', CitedKind.section, null)),
      );
    });

    test('a map and a set find a place by an equal one', () {
      expect(
        {place('a.md', CitedKind.item, 'E01'): 1}[place(
          'a.md',
          CitedKind.item,
          'E01',
        )],
        1,
      );
      expect({
        place('a.md', CitedKind.item, 'E01'),
        place('a.md', CitedKind.item, 'E01'),
      }, hasLength(1));
    });
  });
}
