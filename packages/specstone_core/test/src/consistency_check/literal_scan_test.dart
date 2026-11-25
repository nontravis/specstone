import 'dart:math';

import 'package:specstone_core/src/consistency_check/literal_scan.dart';
import 'package:test/test.dart';

Set<String> _containedIn(String text, Set<String> literals) => {
  for (final literal in literals)
    if (text.contains(literal)) literal,
};

void main() {
  group('LiteralScan.foundIn', () {
    for (final (name, text, literals) in [
      ('overlapping literals', 'abcd', {'abc', 'bcd', 'cd', 'x'}),
      ('a literal inside another', 'say hers', {'he', 'she', 'his', 'hers'}),
      ('a literal and its own prefix', 'aaab', {'a', 'aa', 'aab', 'aaaa'}),
      ('a repeat reached by fallback', 'xabxabc', {'abc', 'bc', 'xabc'}),
      ('the empty literal', 'abc', {'', 'z'}),
      ('code units past one byte', 'naïve 🙂 test', {'ïve', '🙂', 'é'}),
      ('an empty text', '', {'a', ''}),
    ]) {
      test('finds what String.contains finds: $name', () {
        expect(
          LiteralScan(literals).foundIn(text),
          _containedIn(text, literals),
        );
      });
    }

    test('one scan finds what String.contains finds in many random texts', () {
      final random = Random(7);
      String word(int length) => String.fromCharCodes([
        for (var i = 0; i < length; i++) 0x61 + random.nextInt(3),
      ]);
      for (var round = 0; round < 40; round++) {
        final literals = {
          for (var i = 0; i < 8; i++) word(1 + random.nextInt(5)),
        };
        final scan = LiteralScan(literals);
        for (var text = 0; text < 5; text++) {
          final words = word(random.nextInt(40));

          expect(
            scan.foundIn(words),
            _containedIn(words, literals),
            reason: 'text $words, literals $literals',
          );
        }
      }
    });
  });
}
