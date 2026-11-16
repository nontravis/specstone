import 'package:specstone_core/src/setup_migration/models/label_conversion.dart';
import 'package:test/test.dart';

KeptLabel kept(int line, String label) => KeptLabel(line: line, label: label);

void main() {
  group('KeptLabel', () {
    test('equals another KeptLabel with the same line and label', () {
      expect(kept(1, 'FR-07'), kept(1, 'FR-07'));
      expect(kept(1, 'FR-07'), isNot(kept(2, 'FR-07')));
      expect(kept(1, 'FR-07'), isNot(kept(1, 'FR-08')));
      expect(kept(1, 'FR-07').hashCode, kept(1, 'FR-07').hashCode);
    });
  });
}
