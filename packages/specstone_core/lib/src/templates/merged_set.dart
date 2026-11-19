import 'dart:convert';

import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/feature_pattern.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/nested_paths.dart';
import 'package:specstone_core/src/templates/shared_merge.dart';

/// The merged doc types and feature patterns of one resolve, each sorted by id
/// in code point order, with the shared entries that reach them.
final class MergedSet {
  new({
    required List<MergedDocType> docTypes,
    List<FeaturePattern> featurePatterns = const [],
    this.shared = SharedSet.empty,
  }) : docTypes = List.unmodifiable(withNestedPaths(_sortedCopy(docTypes))),
       featurePatterns = List.unmodifiable(
         List<FeaturePattern>.of(featurePatterns)
           ..sort((a, b) => compareCodePoints(a.id, b.id)),
       );

  /// The merged doc types, sorted by id; the caller's list is untouched.
  final List<MergedDocType> docTypes;

  /// The merged feature patterns, sorted by id; the caller's list is
  /// untouched.
  final List<FeaturePattern> featurePatterns;

  /// The merged shared lines and fields, before any doc type takes its own.
  final SharedSet shared;

  /// The doc type that writes `max_depth`, 0 included; null when none does.
  MergedDocType? get nestingType => nestingTypeOf(docTypes);

  /// The doc type holding a `record_status` field, found by that field alone;
  /// null when none does.
  MergedDocType? get recordDocType {
    for (final docType in docTypes) {
      if (docType.isRecordType) return docType;
    }
    return null;
  }

  /// Returns the doc type [id], or null when the set holds none.
  MergedDocType? lookup(String id) {
    for (final docType in docTypes) {
      if (docType.id == id) return docType;
    }
    return null;
  }

  /// Whether [type] has no parent and builds on a doc type that has one.
  bool isProjectSpecType(MergedDocType type) =>
      type.parent == null &&
      type.extendsChain.any((id) => lookup(id)?.parent != null);

  /// Returns the feature pattern [id], or null when the set holds none.
  FeaturePattern? featurePattern(String id) {
    for (final pattern in featurePatterns) {
      if (pattern.id == id) return pattern;
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

  /// Returns one JSON object per feature pattern: `id`, `pack` when a pack
  /// supplies it, and the first line of `description`.
  List<Map<String, Object>> featurePatternListJson() => [
    for (final pattern in featurePatterns)
      {
        'id': pattern.id,
        'pack': ?pattern.pack,
        'description': ?_firstLine(pattern.description),
      },
  ];

  /// Returns the feature pattern ids, one per line, each ending with a
  /// newline.
  String featurePatternListText() =>
      [for (final pattern in featurePatterns) '${pattern.id}\n'].join();

  /// Returns the first line of [text], `''` for an empty text, or null.
  static String? _firstLine(String? text) => text == null
      ? null
      : const LineSplitter().convert(text).firstOrNull ?? '';

  /// Returns a [docTypes] copy sorted by id.
  static List<MergedDocType> _sortedCopy(List<MergedDocType> docTypes) =>
      List<MergedDocType>.of(docTypes)
        ..sort((a, b) => compareCodePoints(a.id, b.id));
}
