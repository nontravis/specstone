import 'package:specstone_core/src/templates/code_link_entry.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
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

    test('reads the fingerprint after a prefix entry', () {
      const entry = CodeLinkEntry('lib/src/toast/ 9a1c03be55d2');

      expect(entry.pointer, 'lib/src/toast/');
      expect(entry.fingerprint, '9a1c03be55d2');
    });

    test('reads a prefix entry with no fingerprint as its pointer', () {
      const entry = CodeLinkEntry('lib/src/toast/');

      expect(entry.pointer, 'lib/src/toast/');
      expect(entry.fingerprint, isNull);
    });

    test('keeps the whole text as the pointer for an upper-case token', () {
      const text = 'lib/src/toast/ 5D1E0C4B7A92';
      const entry = CodeLinkEntry(text);

      expect(entry.pointer, text);
      expect(entry.fingerprint, isNull);
    });

    test('keeps the whole text as the pointer for a short token', () {
      const text = 'lib/src/toast/ 5d1e0c4b7a9';
      const entry = CodeLinkEntry(text);

      expect(entry.pointer, text);
      expect(entry.fingerprint, isNull);
    });

    test('keeps the whole text as the pointer for a long token', () {
      const text = 'lib/src/toast/ 5d1e0c4b7a921';
      const entry = CodeLinkEntry(text);

      expect(entry.pointer, text);
      expect(entry.fingerprint, isNull);
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

    test('keeps a text that is only a fingerprint-shaped token', () {
      const entry = CodeLinkEntry(_fingerprint);

      expect(entry.pointer, _fingerprint);
      expect(entry.fingerprint, isNull);
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
      expect(
        isCodeLinkField(_field(FieldType.outputRef, PointerKind.exact)),
        isFalse,
      );
    });

    test('is false for an output_ref field with item_test', () {
      expect(
        isCodeLinkField(_field(FieldType.outputRef, PointerKind.itemTest)),
        isFalse,
      );
    });

    test('is false for a field of another type', () {
      expect(isCodeLinkField(_field(FieldType.string)), isFalse);
    });
  });
}
