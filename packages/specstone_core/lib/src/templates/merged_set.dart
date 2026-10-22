import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// The merged doc types of one resolve, sorted by id in code point order.
final class MergedSet {
  new({required this.docTypes}) {
    docTypes.sort((a, b) => compareCodePoints(a.id, b.id));
  }

  /// The merged doc types, sorted by id.
  final List<MergedDocType> docTypes;

  /// Returns the doc type [id], or null when the set holds none.
  MergedDocType? lookup(String id) {
    for (final docType in docTypes) {
      if (docType.id == id) return docType;
    }
    return null;
  }
}
