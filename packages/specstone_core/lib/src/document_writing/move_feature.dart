import 'dart:math';

import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/own_segment.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart'
    show nameWithType;
import 'package:specstone_core/src/templates/merged_doc_type.dart';

/// Returns the moves that put each of [features] last under [newParent], or
/// among the top features when null, in order: its folder, then each of its
/// spec and record folders that exists, its slug kept.
///
/// A feature already there, or under a moving ancestor, stays out.
/// Throws as [_checkParent] and [checkNoClash] do.
List<PathMove> planFeatureMoves(
  WriteSession session,
  List<IndexedDoc> features, {
  required IndexedDoc? newParent,
}) {
  final index = session.index;
  final leaving = [
    for (final feature in features)
      if (!_sitsUnder(index, feature, newParent)) feature,
  ];
  final leavingPaths = {for (final feature in leaving) feature.docPath};
  final moving = [
    for (final feature in leaving)
      if (!_hasAncestorIn(index, feature, leavingPaths)) feature,
  ];
  if (moving.isEmpty) return const [];
  final place = _Place.of(session, newParent);
  _checkParent(session, moving, newParent, place);
  return _landingMoves(session, moving, place);
}

/// Whether [feature] sits directly under [newParent], or among the top
/// features when it is null.
bool _sitsUnder(DocIndex index, IndexedDoc feature, IndexedDoc? newParent) {
  final parent = index.parentOf(feature);
  if (newParent == null) return parent?.docTypeId != featureType;
  return parent?.docPath == newParent.docPath;
}

/// Whether a doc above [feature] sits at one of [docPaths], so its move
/// carries [feature].
bool _hasAncestorIn(DocIndex index, IndexedDoc feature, Set<String> docPaths) =>
    index
        .chainOf(feature)
        .skip(1)
        .any((ancestor) => docPaths.contains(ancestor.docPath));

/// Where the moved features land: the values of the parent's placeholders
/// and the nesting depth each moved feature takes.
final class _Place {
  const new(this.docType, this.parentValues, this.depth);

  /// Returns the place under [newParent], or among the top features.
  factory of(WriteSession session, IndexedDoc? newParent) {
    final set = session.index.set;
    final docType =
        set.lookup(featureType) ??
        (throw StateError('the project has no $featureType doc type'));
    if (newParent == null) return _Place(docType, const [], 0);
    final shape = _shapeOf(session, docType, newParent);
    return _Place(docType, _valuesOf(shape, newParent), shape.depth + 1);
  }

  final MergedDocType docType;
  final List<String> parentValues;
  final int depth;
}

/// Throws [IndexFault] `argument_invalid` when [newParent] is one of [moving]
/// or under one, holds stories, or puts a feature of [moving] past the
/// nesting type's `max_depth`.
void _checkParent(
  WriteSession session,
  List<IndexedDoc> moving,
  IndexedDoc? newParent,
  _Place place,
) {
  final index = session.index;
  if (newParent != null) {
    for (final feature in moving) {
      final folder = _shapeOf(
        session,
        place.docType,
        feature,
      ).ownPathOf(feature.docPath);
      if (!newParent.docPath.startsWith(folder)) continue;
      throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '${feature.name} cannot move under itself or its own sub-feature',
      );
    }
    if (index.childrenOf(newParent).any((c) => c.docTypeId == storyType)) {
      throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '${nameWithType(newParent)} holds stories, so it takes no sub-feature',
      );
    }
  }
  final limit = index.set.nestingType?.maxDepth ?? 0;
  for (final feature in moving) {
    final deepest = place.depth + _levelsBelow(index, feature);
    if (deepest <= limit) continue;
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '${feature.name} would land at depth $deepest, past the '
      "${place.docType.id} template's max_depth $limit",
    );
  }
}

/// Returns how many levels of sub-features nest under [feature].
int _levelsBelow(DocIndex index, IndexedDoc feature) {
  var deepest = 0;
  for (final child in index.childrenOf(feature)) {
    if (child.docTypeId != featureType) continue;
    deepest = max(deepest, 1 + _levelsBelow(index, child));
  }
  return deepest;
}

/// Returns the moves of [moving] to [place], numbered from the highest
/// sibling there, each feature's folder before its spec and record folders.
///
/// Throws `WriteFault` `doc_exists` when two features carry one slug, naming
/// the first of them, or as [checkNoClash] does.
List<PathMove> _landingMoves(
  WriteSession session,
  List<IndexedDoc> moving,
  _Place place,
) {
  final set = session.index.set;
  final docType = place.docType;
  final landedShape =
      DocPathShape.of(docType, set, depth: place.depth) ??
      (throw StateError('${docType.id} has no path at depth ${place.depth}'));
  final siblings = siblingsOnDisk(
    session.project,
    landedShape,
    place.parentValues,
  );
  final highest = siblings.fold(0, (top, s) => max(top, s.number ?? 0));
  final firstOfSlug = <String, IndexedDoc>{};
  final moves = <PathMove>[];
  for (final (index, feature) in moving.indexed) {
    final shape = _shapeOf(session, docType, feature);
    final oldValues = _valuesOf(shape, feature);
    final slug =
        shape.matchOwn(feature.docPath.split('/')[shape.ownIndex])?.slug ??
        (throw StateError('${feature.docPath} carries no slug'));
    if (firstOfSlug[slug] case final first?) {
      throw existsFault(docType, first.docPath, first.docPath);
    }
    firstOfSlug[slug] = feature;
    final newValues = [
      ...place.parentValues,
      ...landedShape.ownValues(
        number: padNumber(highest + 1 + index),
        slug: slug,
      ),
    ];
    final newDocPath = landedShape.build(newValues);
    final featureMoves = [
      PathMove(
        from: shape.ownPathOf(feature.docPath),
        to: landedShape.ownPathOf(newDocPath),
      ),
      for (final move in specFolderMovesOf(
        set,
        docType,
        oldValues,
        newValues,
        depth: shape.depth,
        newDepth: landedShape.depth,
        targetNames: session.index.twinNames,
      ))
        if (isOnDisk(session, move.from)) move,
    ];
    checkNoClash(
      session,
      docType,
      landedShape,
      place.parentValues,
      siblings,
      slug: slug,
      newDocPath: newDocPath,
      moves: featureMoves,
    );
    moves.addAll(featureMoves);
  }
  return moves;
}

DocPathShape _shapeOf(
  WriteSession session,
  MergedDocType docType,
  IndexedDoc feature,
) =>
    DocPathShape.ofDoc(
      docType,
      session.index.set,
      feature.docPath,
      target: feature.target,
    ) ??
    (throw StateError('${feature.docPath} does not match its doc type'));

List<String> _valuesOf(DocPathShape shape, IndexedDoc feature) =>
    shape.valuesOf(feature.docPath) ??
    (throw StateError('${feature.docPath} does not match its doc type'));
