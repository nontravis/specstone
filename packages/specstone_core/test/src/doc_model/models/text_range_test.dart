import 'package:specstone_core/src/doc_model/models/text_range.dart';
import 'package:test/test.dart';

void main() {
  group('TextRange', () {
    test('holds the start and end it is built with', () {
      const range = TextRange(start: 2, end: 5);

      expect(range.start, 2);
      expect(range.end, 5);
    });

    test('destructures by field name, as the range readers do', () {
      final TextRange(:start, :end) = const TextRange(start: 2, end: 5);

      expect(start, 2);
      expect(end, 5);
    });
  });
}
