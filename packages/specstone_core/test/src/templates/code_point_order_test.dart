import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:test/test.dart';

void main() {
  test('s03/inv22: code point order puts U+FF01 before U+1F600', () {
    expect(compareCodePoints('\u{FF01}', '\u{1F600}'), isNegative);
    expect('\u{FF01}'.compareTo('\u{1F600}'), isPositive);
  });

  test('s03/inv22: a shorter prefix sorts first', () {
    expect(compareCodePoints('a', 'ab'), isNegative);
  });

  test('s03/inv22: a later code point sorts after', () {
    expect(compareCodePoints('b', 'a'), isPositive);
  });

  test('s03/inv22: equal strings compare 0', () {
    expect(compareCodePoints('same', 'same'), 0);
  });
}
