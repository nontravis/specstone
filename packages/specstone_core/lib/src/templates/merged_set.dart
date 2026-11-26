import 'dart:convert';

import 'package:specstone_core/src/doc_model/path_pattern.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show headerKey;
import 'package:specstone_core/src/templates/code_point_order.dart';
import 'package:specstone_core/src/templates/feature_group_paths.dart';
import 'package:specstone_core/src/templates/leftover_home.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/models/feature_pattern.dart';
import 'package:specstone_core/src/templates/nested_paths.dart';
import 'package:specstone_core/src/templates/shared_merge.dart';

/// The merged doc types and feature patterns of one resolve, each sorted by id
/// in code point order, with the shared entries that reach them.
final class MergedSet {
  new({
    required List<MergedDocType> docTypes,
    List<FeaturePattern> featurePatterns = const [],
    this.shared = SharedSet.empty,
    Map<String, String> foldedDocTypes = const {},
    Set<String> droppedDocTypes = const {},
    Set<String> orphanedDocTypes = const {},
    List<LeftoverHome> leftoverHomes = const [],
  }) : docTypes = List.unmodifiable(
         withNestedPaths(
           withGroupLevels(withFeatureGroupPaths(_sortedCopy(docTypes))),
         ),
       ),
       featurePatterns = List.unmodifiable(
         List<FeaturePattern>.of(featurePatterns)
           ..sort((a, b) => compareCodePoints(a.id, b.id)),
       ),
       foldedDocTypes = Map.unmodifiable(foldedDocTypes),
       droppedDocTypes = Set.unmodifiable(droppedDocTypes),
       orphanedDocTypes = Set.unmodifiable(orphanedDocTypes),
       leftoverHomes = List.unmodifiable(leftoverHomes);

  /// The merged doc types, sorted by id; the caller's list is untouched.
  final List<MergedDocType> docTypes;

  /// The merged feature patterns, sorted by id; the caller's list is
  /// untouched.
  final List<FeaturePattern> featurePatterns;

  /// The merged shared lines and fields, before any doc type takes its own.
  final SharedSet shared;

  /// The id each loaded pack's `merge_doc` step drops, mapped to the id that
  /// takes its docs; empty when no loaded pack holds such a step.
  final Map<String, String> foldedDocTypes;

  /// The id each loaded pack's `drop_doc_type` step drops; empty when no
  /// loaded pack holds such a step.
  final Set<String> droppedDocTypes;

  /// The id of each project layer that overrides a doc type no loaded pack
  /// defines, writing neither `id` nor `extends`; the layer never loads.
  ///
  /// Such a layer outlives a pack that dropped its type: the step that
  /// dropped it may be gone from the pack, so no step names the id.
  final Set<String> orphanedDocTypes;

  /// The `leftover_homes` entries of every loaded pack, in pack order; empty
  /// when no loaded pack holds any.
  final List<LeftoverHome> leftoverHomes;

  /// Returns the leftover home that names the section [header] of a doc of
  /// [docTypeId], or null when no loaded pack's entry does.
  ///
  /// A header matches as the formatter matches section headers: letter case
  /// and whitespace aside. The entry of the upper pack wins over a lower one.
  LeftoverHome? leftoverForSection(String docTypeId, String header) {
    final key = headerKey(header);
    for (final entry in leftoverHomes.reversed) {
      if (entry.header case final entryHeader?
          when entry.docTypes.contains(docTypeId) &&
              headerKey(entryHeader) == key) {
        return entry;
      }
    }
    return null;
  }

  /// Returns the leftover home whose `path` pattern matches [docPath], or null
  /// when no loaded pack's entry does; the upper pack's entry wins.
  LeftoverHome? leftoverForPath(String docPath) {
    for (final entry in leftoverHomes.reversed) {
      if (entry.path case final path? when PathPattern(path).matches(docPath)) {
        return entry;
      }
    }
    return null;
  }

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
