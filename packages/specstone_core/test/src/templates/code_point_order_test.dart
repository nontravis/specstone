import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:test/test.dart';

void main() {
  test('code point order puts U+FF01 before U+1F600', () {
    expect(compareCodePoints('\u{FF01}', '\u{1F600}'), isNegative);
    expect('\u{FF01}'.compareTo('\u{1F600}'), isPositive);
  });

  test('equal strings compare 0', () {
    expect(compareCodePoints('same', 'same'), 0);
  });

  group('the order matches a compare of runes', () {
    int runesOrder(String a, String b) {
      final (aRunes, bRunes) = (a.runes.toList(), b.runes.toList());
      for (var i = 0; i < aRunes.length && i < bRunes.length; i++) {
        if (aRunes[i] != bRunes[i]) return aRunes[i].compareTo(bRunes[i]);
      }
      return aRunes.length.compareTo(bRunes.length);
    }

    for (final (a, b) in [
      ('x\u{1F600}', 'x\u{E000}'),
      ('x\u{1F600}', 'x\u{FFFF}'),
      ('\u{1F600}', '\u{1F601}'),
      ('a\uD83D', 'a'),
      ('a\uDE00', 'a\u{1F600}'),
      ('a\uD83D', 'a\u{1F600}'),
      ('ab', 'a'),
      ('', 'a'),
      ('docs/b.md', 'docs/a.md'),
    ]) {
      test('${a.runes} against ${b.runes}', () {
        expect(compareCodePoints(a, b), runesOrder(a, b));
        expect(compareCodePoints(b, a), runesOrder(b, a));
      });
    }
  });
}
