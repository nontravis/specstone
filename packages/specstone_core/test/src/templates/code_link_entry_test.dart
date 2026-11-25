import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

const _fingerprint = '5d1e0c4b7a92';

MergedField _field(FieldType type, [PointerKind? pointer]) =>
    MergedField(id: 'f', type: type, list: true, pointer: pointer);

void main() {
  group('CodeLinkEntry', () {
    test('reads the fingerprint after an item_exact line', () {
      const entry = CodeLinkEntry(
        'show_toast:lib/toast.dart:showToast $_fingerprint',
      );

      expect(entry.pointer, 'show_toast:lib/toast.dart:showToast');
      expect(entry.fingerprint, _fingerprint);
    });

    test('reads an item_exact line with no fingerprint as its pointer', () {
      const entry = CodeLinkEntry('show_toast:lib/toast.dart:showToast');

      expect(entry.pointer, 'show_toast:lib/toast.dart:showToast');
      expect(entry.fingerprint, isNull);
    });

    test('keeps the whole text as the pointer for an upper-case token', () {
      for (final (text, reason) in [
        ('lib/src/toast/ 5D1E0C4B7A92', 'upper-case token'),
        ('lib/src/toast/ 5d1e0c4b7a9', 'short token'),
        ('lib/src/toast/ 5d1e0c4b7a921', 'long token'),
      ]) {
        final entry = CodeLinkEntry(text);

        expect(entry.pointer, text, reason: reason);
        expect(entry.fingerprint, isNull, reason: reason);
      }
    });

    test('keeps a 12-hex segment with no space before it in the pointer', () {
      const text = 'lib/src/$_fingerprint';
      const entry = CodeLinkEntry(text);

      expect(entry.pointer, text);
      expect(entry.fingerprint, isNull);
    });

    test('keeps a folder named as 12 hex with a fingerprint after it', () {
      const entry = CodeLinkEntry('lib/$_fingerprint/ 9a1c03be55d2');

      expect(entry.pointer, 'lib/$_fingerprint/');
      expect(entry.fingerprint, '9a1c03be55d2');
    });
  });

  group('codeLinkEntryOf', () {
    test('joins pointer and fingerprint with one space', () {
      final text = codeLinkEntryOf('lib/src/toast/', _fingerprint);

      expect(text, 'lib/src/toast/ $_fingerprint');
      expect(CodeLinkEntry(text).pointer, 'lib/src/toast/');
      expect(CodeLinkEntry(text).fingerprint, _fingerprint);
    });
  });

  group('isCodeLinkField', () {
    test('is true for an output_ref field with item_exact', () {
      expect(
        isCodeLinkField(_field(FieldType.outputRef, PointerKind.itemExact)),
        isTrue,
      );
    });

    test('is true for an output_ref field with prefix', () {
      expect(
        isCodeLinkField(_field(FieldType.outputRef, PointerKind.prefix)),
        isTrue,
      );
    });

    test('is false for an output_ref field with exact', () {
      for (final pointer in [PointerKind.exact, PointerKind.itemTest]) {
        expect(
          isCodeLinkField(_field(FieldType.outputRef, pointer)),
          isFalse,
          reason: pointer.name,
        );
      }
    });

    test('is false for a field of another type', () {
      expect(isCodeLinkField(_field(FieldType.string)), isFalse);
    });
  });
}
