import 'package:specstone_core/src/doc_model/doc_splice.dart'
    show isFingerprint;
import 'package:specstone_core/src/index_query/code_root_files.dart'
    show isEmptyCodeEntry, normalCodeEntry;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

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
    return isFingerprint(text.substring(space + 1)) ? space : null;
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

/// Returns the `covers`-like fields of [type]: each `output_ref` field whose
/// pointer is `prefix`, in field order; none for an untyped doc.
///
/// The one field selection the code rules and the migrate stamp read.
List<MergedField> coversFieldsOf(MergedDocType? type) => [
  for (final field in type?.fields ?? const <MergedField>[])
    if (isCodeLinkField(field) && field.pointer == PointerKind.prefix) field,
];

/// Whether [field]'s entries resolve from the project root, which belongs to
/// no code target, in place of a code root.
bool readsFromProjectRoot(MergedField field) =>
    field.root == PointerRoot.project;

/// Returns the path [entry] names, in `normalCodeEntry`'s form; null when it
/// is empty, so it names no path of its own.
///
/// The one reader of a `covers` entry as a path: coverage and `context --code`
/// take it, so an empty entry reaches nothing in either.
String? reachablePathOf(String entry) {
  final pointer = CodeLinkEntry(entry).pointer;
  return isEmptyCodeEntry(pointer) ? null : normalCodeEntry(pointer);
}

/// Whether [entry] equals [path] or names a folder that holds it.
///
/// Both are `/`-separated paths in one normal form, from the same root, and
/// match by whole segment: `skills/rev` does not reach `skills/review/a.md`.
/// [entry] is a [reachablePathOf] result, never empty.
bool entryReaches(String entry, String path) =>
    path == entry || path.startsWith('$entry/');
