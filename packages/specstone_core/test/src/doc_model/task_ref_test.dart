import 'package:specstone_core/src/doc_model/task_ref.dart';
import 'package:test/test.dart';

void main() {
  group('TaskRef.parse', () {
    test('reads an entry with no colon as a whole-doc ref', () {
      final ref = TaskRef.parse('T-12');

      expect(ref, isNotNull);
      expect(ref!.item, isNull);
      expect(ref.task, 'T-12');
      expect(ref.isWholeDoc, isTrue);
    });

    test('reads item and task around the colon', () {
      final ref = TaskRef.parse('INV-04:T-12');

      expect(ref, isNotNull);
      expect(ref!.item, 'INV-04');
      expect(ref.task, 'T-12');
      expect(ref.isWholeDoc, isFalse);
    });

    test('splits at the last colon when the item holds a colon', () {
      final ref = TaskRef.parse('set --batch: all:T-12');

      expect(ref, isNotNull);
      expect(ref!.item, 'set --batch: all');
      expect(ref.task, 'T-12');
    });

    test('returns null for an empty entry', () {
      expect(TaskRef.parse(''), isNull);
    });

    test('returns null when the task is empty', () {
      expect(TaskRef.parse('INV-04:'), isNull);
      expect(TaskRef.parse(':'), isNull);
    });

    test('returns null when the item is empty', () {
      expect(TaskRef.parse(':T-12'), isNull);
    });
  });
}
