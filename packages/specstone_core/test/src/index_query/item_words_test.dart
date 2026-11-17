import 'package:specstone_core/src/index_query/item_words.dart';
import 'package:test/test.dart';

void main() {
  group('definitionLinesOf', () {
    test('gives each definition as [label]: <destination> in source order, '
        'a repeated label taking its first destination', () {
      expect(
        definitionLinesOf(
          'Uses [a][x].\n\n[x]: <a.md>\n[Y  z]: b.md "t"\n[X]: c.md\n',
        ),
        '[x]: <a.md>\n[Y  z]: <b.md>\n[X]: <a.md>',
      );
    });

    test('gives nothing for a body with no definition', () {
      expect(definitionLinesOf('Text a]: b\n'), '');
    });
  });
}
