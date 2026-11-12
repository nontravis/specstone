import 'dart:math';

import 'package:specstone_core/src/doc_model/needle_search.dart';
import 'package:test/test.dart';

Set<String> _byContains(Iterable<String> needles, String text) => {
  for (final needle in needles)
    if (text.contains(needle)) needle,
};

void main() {
  group('doc_model/needle_search', () {
    test('finds a needle that is a suffix of another, and one inside it', () {
      const needles = ['he', 'she', 'his', 'hers'];

      expect(needlesFoundIn(needles, 'ushers'), {'he', 'she', 'hers'});
    });

    test('finds a needle that ends where a longer one fails', () {
      expect(needlesFoundIn(['abcd', 'bce'], 'abce'), {'bce'});
    });

    test('lists a repeated needle once and a missing one never', () {
      expect(needlesFoundIn(['a', 'a', 'z'], 'banana'), {'a'});
    });

    test('holds the empty needle in any text, as contains does', () {
      expect(needlesFoundIn(['', 'x'], ''), {''});
      expect(needlesFoundIn(['', 'x'], 'y'), {''});
    });

    test('reads a surrogate pair and a NUL as plain code units', () {
      const text = 'a\u{1F600}b\u0000c';

      expect(needlesFoundIn(['\u{1F600}b', 'b\u0000c', 'c\u0000'], text), {
        '\u{1F600}b',
        'b\u0000c',
      });
    });

    test('stops once every needle is found and still reports them all', () {
      expect(needlesFoundIn(['one', 'two'], 'one two ${'x' * 1000}'), {
        'one',
        'two',
      });
    });

    test('agrees with contains on random needles and texts', () {
      final random = Random(7);
      String word(int max) => String.fromCharCodes([
        for (var i = 0, n = 1 + random.nextInt(max); i < n; i++)
          0x61 + random.nextInt(3),
      ]);
      for (var round = 0; round < 300; round++) {
        final needles = [for (var i = 0; i < 12; i++) word(5)];
        final text = word(60);

        expect(
          needlesFoundIn(needles, text),
          _byContains(needles, text),
          reason: '$needles in $text',
        );
      }
    });
  });
}
