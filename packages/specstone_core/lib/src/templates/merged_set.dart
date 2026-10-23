import 'dart:convert';

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

  /// Returns one JSON object per doc type: `id`, `pack` when a pack supplies
  /// the doc type, and the first line of `description`.
  List<Map<String, Object>> listJson() => [
    for (final docType in docTypes)
      {
        'id': docType.id,
        'pack': ?docType.pack,
        'description': ?_firstLine(docType.description),
      },
  ];

  /// Returns the doc type ids, one per line, each ending with a newline.
  String listText() =>
      [for (final docType in docTypes) '${docType.id}\n'].join();

  /// Returns the first line of [text], `''` for an empty text, or null.
  static String? _firstLine(String? text) => text == null
      ? null
      : const LineSplitter().convert(text).firstOrNull ?? '';

  /// Returns an unmodifiable [docTypes] copy sorted by id (INV-22).
  static List<MergedDocType> _sortedCopy(List<MergedDocType> docTypes) {
    final sorted = List<MergedDocType>.of(docTypes)
      ..sort((a, b) => compareCodePoints(a.id, b.id));
    return List.unmodifiable(sorted);
  }
}
