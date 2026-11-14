import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

final _fingerprintToken = RegExp(r'^[0-9a-f]{12}$');

/// One entry of a code-link field: a pointer, then optionally a fingerprint.
///
/// Every reader of such a field splits an entry through this one rule.
extension type const CodeLinkEntry(String text) {
  /// The pointer: the text before the fingerprint, or all of it.
  String get pointer {
    final split = _fingerprintSplit;
    return split == null ? text : text.substring(0, split);
  }

  /// The code fingerprint after the last space; null when the entry has none.
  ///
  /// A last token that is not 12 lowercase hex characters belongs to the
  /// pointer.
  String? get fingerprint {
    final split = _fingerprintSplit;
    return split == null ? null : text.substring(split + 1);
  }

  int? get _fingerprintSplit {
    final space = text.lastIndexOf(' ');
    if (space < 0) return null;
    return _fingerprintToken.hasMatch(text.substring(space + 1)) ? space : null;
  }
}

/// Returns the entry text that records [fingerprint] after [pointer].
String codeLinkEntryOf(String pointer, String fingerprint) =>
    '$pointer $fingerprint';

/// Whether [field] holds code-link entries: an `output_ref` with a pointer
/// that is `item_exact` or `prefix`.
bool isCodeLinkField(MergedField field) =>
    field.type == FieldType.outputRef &&
    (field.pointer == PointerKind.itemExact ||
        field.pointer == PointerKind.prefix);
