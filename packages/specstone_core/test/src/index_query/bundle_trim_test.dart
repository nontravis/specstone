import 'package:specstone_core/src/index_query/bundle_trim.dart';
import 'package:test/test.dart';

void main() {
  group('SectionLine', () {
    test('shiftedBy moves the section lower by the given lines', () {
      final shifted = const SectionLine(key: 'goals', line: 3).shiftedBy(1);
      expect(shifted.key, 'goals');
      expect(shifted.line, 4);
    });
    test('equals another SectionLine with the same key and line', () {
      expect(
        const SectionLine(key: 'goals', line: 3),
        const SectionLine(key: 'goals', line: 3),
      );
      expect(
        const SectionLine(key: 'goals', line: 3),
        isNot(const SectionLine(key: 'goals', line: 4)),
      );
    });
  });
}
