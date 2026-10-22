import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The merged doc types of one resolve, sorted by id in code point order.
final class MergedSet {
  new({required List<MergedDocType> docTypes})
    : docTypes = _sortedCopy(docTypes);

  /// The merged doc types, sorted by id; the caller's list is untouched.
  final List<MergedDocType> docTypes;

  /// Returns the doc type [id], or null when the set holds none.
  MergedDocType? lookup(String id) {
    for (final docType in docTypes) {
      if (docType.id == id) return docType;
    }
    return null;
  }

  /// Returns an unmodifiable [docTypes] copy sorted by id (INV-22).
  static List<MergedDocType> _sortedCopy(List<MergedDocType> docTypes) {
    final sorted = List<MergedDocType>.of(docTypes)
      ..sort((a, b) => compareCodePoints(a.id, b.id));
    return List.unmodifiable(sorted);
  }
}
