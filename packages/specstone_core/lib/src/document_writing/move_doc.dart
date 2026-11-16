import 'dart:io';
import 'dart:math';

import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/document_writing/item_mentions.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/own_segment.dart';
import 'package:specstone_core/src/document_writing/rewrite_item_refs.dart';
import 'package:specstone_core/src/document_writing/rewrite_labels.dart'
    show rewriteMovedFrTraces;
import 'package:specstone_core/src/document_writing/rewrite_records.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart';
import 'package:specstone_core/src/document_writing/stale_mentions.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/override_chain.dart'
    show nfTypeId;
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

final _wholeNumber = RegExp(r'^[0-9]+$');

/// Returns the place [value] names; `0` parses, the range check refuses it.
///
/// Throws [IndexFault] `argument_missing` for null and `argument_invalid`
/// for anything but ASCII digits.
int parsePlace(String? value) {
  if (value == null) {
    throw missingArgument(
      'reorder',
      'a place',
      'specstone reorder user_story:login/reset_password --to 1',
    );
  }
  final place = _wholeNumber.hasMatch(value) ? int.tryParse(value) : null;
  return place ??
      (throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '--to takes a whole number, got $value',
      ));
}

/// Moves the doc [address] names to [place] among its siblings.
///
/// Every sibling is numbered from 01 with no gap, so a reorder also closes
/// the gaps a delete left. Each renamed segment moves, with the spec folders
/// of a feature right after it, and the links to them follow. A doc that
/// already holds [place] with no gap changes nothing. No draft mark is
/// written. A code file or an agent file is never written; each path mention
/// in one that the reorder stops resolving is listed in the answer.
///
/// [codeTarget] keeps the doc's name to that code target's docs and the shared
/// docs. Every entry of a record names its item relative to its feature, so a
/// reorder changes none.
///
/// Throws [WriteFault] `doc_type_not_movable` for a doc type that numbers no
/// doc and `position_out_of_range` for a place outside 1 to the sibling
/// count; an `IndexFault` for a bad address or [place], or `doc_not_found`
/// when the doc is gone from disk; `index_busy` when another call holds the
/// lock; `RenderFault` `output_not_writable` for roots the Owner has not
/// recorded, naming the journal, before any rewrite is planned.
ReadAnswer answerReorder(
  WriteSession session,
  String address, {
  required String? place,
  String? codeTarget,
  bool dryRun = false,
}) {
  final wanted = parsePlace(place);
  final target = session.target(address, codeTarget: codeTarget);
  final docType =
      session.index.typeOf(target) ??
      (throw StateError('${target.docPath} has no doc type'));
  final shape = DocPathShape.ofDoc(
    docType,
    session.index.set,
    target.docPath,
    target: target.target,
  );
  if (shape == null || !shape.numbered) {
    throw WriteFault(
      WriteFaultCode.docTypeNotMovable,
      '${docType.id} docs carry no number, so reorder cannot move them',
    );
  }
  return session.locked(() {
    final moves = _movesFor(
      session,
      address,
      target,
      docType,
      shape,
      wanted: wanted,
    );
    if (moves.isEmpty) {
      return _answerFor(session, moves, const [], dryRun: dryRun);
    }
    session.journalTarget.requireTrusted();
    final rewrites = planRewrites(session, moves);
    final mentions = staleMentions(session, moves, namesChange: false);
    if (!dryRun) {
      MoveJournal([..._stageSteps(session, moves), ...rewrites])
          .run(session.journalTarget);
    }
    return _answerFor(
      session,
      moves,
      rewrites,
      mentions: mentions,
      dryRun: dryRun,
    );
  });
}

/// Renames the doc [address] names to the slug [slug], keeping its number.
///
/// The own segment moves, with the spec folders of a feature, and the links
/// to them and the `doc_ref` values that name a renamed doc follow. The `# `
/// title is never touched and no draft mark is written. The slug a doc
/// already carries changes nothing. A code file or an agent file is never
/// written; each Name or path mention in one that the rename stops resolving
/// is listed in the answer.
///
/// [codeTarget] keeps the doc's name to that code target's docs and the shared
/// docs. The entry of a renamed story or FR, in each target's record, takes
/// the new name.
///
/// Throws [WriteFault] `doc_type_not_movable` for a doc type that carries no
/// slug, a spec doc included, and `doc_exists` when a sibling carries
/// [slug] or a path on disk is where the renamed segment would land; an
/// `IndexFault` for a missing or bad [slug] or a bad address, or
/// `doc_not_found` when the doc is gone from disk; `index_busy` when another
/// call holds the lock; `RenderFault` `output_not_writable` for roots the
/// Owner has not recorded, naming the journal, before any rewrite is planned.
ReadAnswer answerRename(
  WriteSession session,
  String address, {
  required String? slug,
  String? codeTarget,
  bool dryRun = false,
}) {
  if (slug == null) {
    throw missingArgument(
      'rename',
      'a slug',
      'specstone rename user_story:login/reset_password --to recover_account',
    );
  }
  checkSlug(slug);
  final target = session.target(address, codeTarget: codeTarget);
  final docType =
      session.index.typeOf(target) ??
      (throw StateError('${target.docPath} has no doc type'));
  final shape = DocPathShape.ofDoc(
    docType,
    session.index.set,
    target.docPath,
    target: target.target,
  );
  if (shape == null || !shape.slugged) {
    throw _noSlugFault(session, address, target, docType, shape);
  }
  return session.locked(() {
    final moves = _renameMoves(session, target, docType, shape, slug);
    if (moves.isEmpty) {
      return _answerFor(session, moves, const [], dryRun: dryRun);
    }
    session.journalTarget.requireTrusted();
    final renamed = renamedNamesOf(session, moves);
    final records = planRecordRewrites(session, renamed);
    final rewrites = planRewrites(
      session,
      moves,
      renamed: renamed,
      docEdits: records.edits,
    );
    final mentions = staleMentions(session, moves, namesChange: true);
    if (!dryRun) {
      MoveJournal([
        for (final move in moves)
          MoveStep(_stepPath(session, move.from), _stepPath(session, move.to)),
        ...rewrites,
      ]).run(session.journalTarget);
    }
    return _answerFor(
      session,
      moves,
      rewrites,
      mentions: mentions,
      dryRun: dryRun,
    );
  });
}

/// Moves the docs or items [addresses] name under [under], rewriting every
/// reference in one pass.
///
/// The flags are judged before any address resolves; only an item target
/// takes [codeTarget], and only a feature takes [top].
///
/// Throws [WriteFault], [IndexFault], and the faults of [answerItemMove].
ReadAnswer answerMove(
  WriteSession session,
  List<String> addresses, {
  required String? under,
  bool top = false,
  String? codeTarget,
  bool dryRun = false,
}) {
  if (addresses.isEmpty) {
    throw missingArgument(
      'move',
      'a target',
      'specstone move user_story:login/reset_password --under account',
    );
  }
  final items = [for (final a in addresses) isItemAddress(session.index, a)];
  _checkFlags(under: under, top: top, areItems: items.every((item) => item));
  if (items.any((isItem) => isItem)) {
    return _answerItemMove(
      session,
      addresses,
      isItem: items,
      under: under,
      top: top,
      codeTarget: codeTarget,
      dryRun: dryRun,
    );
  }
  final targets = _distinct([for (final a in addresses) session.target(a)]);
  final docType = _movableTypeOf(session, targets);
  if (top && docType.id != featureType) throw _topFault();
  if (codeTarget != null) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'move takes --target only with item targets',
    );
  }
  if (docType.id == nfTypeId || docType.id == featureType) {
    throw StateError('the ${docType.id} move is not wired yet');
  }
  final parentTypeId =
      docType.parent ?? (throw StateError('${docType.id} has no parent type'));
  final newParent = session.parentTarget(
    under ?? (throw StateError('${docType.id} move reached with no --under')),
    parentTypeId,
  );
  final moving = [
    for (final target in targets)
      if (session.index.parentOf(target)?.docPath != newParent.docPath) target,
  ];
  if (moving.isEmpty) {
    return _answerFor(session, const [], const [], dryRun: dryRun);
  }
  if (docType.id == storyType) {
    _checkTakesStory(session, newParent, parentTypeId);
  }
  // Refuse before the lock; the numbers are taken again inside it, since a
  // concurrent `new` can claim one in between.
  _landingMoves(session, moving, docType, newParent);
  return session.locked(() {
    final moves = _landingMoves(session, moving, docType, newParent);
    session.journalTarget.requireTrusted();
    final renamed = renamedNamesOf(session, moves);
    final records = planRecordRewrites(session, renamed);
    final rewrites = planRewrites(
      session,
      moves,
      renamed: renamed,
      docEdits: {
        ...records.edits,
        if (docType.id == frType) ..._movedFrEdits(session, moving, newParent),
      },
    );
    final mentions = staleMentions(session, moves, namesChange: true);
    if (!dryRun) {
      MoveJournal([
        for (final move in moves)
          MoveStep(_stepPath(session, move.from), _stepPath(session, move.to)),
        ...rewrites,
        ...records.creates,
      ]).run(session.journalTarget);
    }
    return _answerFor(
      session,
      moves,
      rewrites,
      created: records.creates,
      mentions: mentions,
      dryRun: dryRun,
    );
  });
}

/// Throws [IndexFault] `argument_conflict` for both [under] and [top], and
/// `argument_missing` for neither, naming item targets' own form when
/// [areItems].
void _checkFlags({
  required String? under,
  required bool top,
  required bool areItems,
}) {
  if (under != null && top) {
    throw IndexFault(
      IndexFaultCode.argumentConflict,
      'move takes --under or --top, not both',
    );
  }
  if (under != null || top) return;
  throw IndexFault(
    IndexFaultCode.argumentMissing,
    areItems
        ? 'move needs --under <doc address> for item targets'
        : 'move needs --under <doc address> or --top',
  );
}

/// Returns the fault for `--top` beside a target that is no feature.
IndexFault _topFault() => IndexFault(
  IndexFaultCode.argumentInvalid,
  'move takes --top only with feature targets',
);

/// Moves the items [addresses] name once every target resolves, [isItem]
/// marking each address that is an item.
///
/// Throws [WriteFault] `doc_type_not_movable` for a doc target of another type,
/// [IndexFault] `argument_invalid` for a doc target at all or [top], and the
/// faults of [answerItemMove].
ReadAnswer _answerItemMove(
  WriteSession session,
  List<String> addresses, {
  required List<bool> isItem,
  required String? under,
  required bool top,
  required String? codeTarget,
  required bool dryRun,
}) {
  final docs = <IndexedDoc>[];
  for (var i = 0; i < addresses.length; i++) {
    if (!isItem[i]) {
      docs.add(session.target(addresses[i]));
      continue;
    }
    final docPart = session.index.splitAddress(addresses[i]).docPart;
    session.target(docPart, codeTarget: codeTarget);
  }
  _requireMovable(session, docs);
  if (docs.isNotEmpty) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'move takes item targets or doc targets, not both',
    );
  }
  if (top) throw _topFault();
  return answerItemMove(
    session,
    addresses,
    under: under ?? (throw StateError('an item move reached with no --under')),
    codeTarget: codeTarget,
    dryRun: dryRun,
  );
}

/// Moves the items [addresses] name to the end of their section of the doc
/// [under] names, marking each source doc and that doc draft.
///
/// An item lands with its nested items and `Overrides:` line; its ID changes
/// only to the next free number, and every reference to it follows. A bare ID
/// the move leaves unresolved prints as a `mentions` line. [dryRun] writes
/// nothing, not even a journal.
///
/// Throws the faults of [planItemMove] and `RenderFault` `output_not_writable`.
ReadAnswer answerItemMove(
  WriteSession session,
  List<String> addresses, {
  required String under,
  String? codeTarget,
  bool dryRun = false,
}) {
  final landings = planItemMove(
    session,
    addresses,
    under: under,
    codeTarget: codeTarget,
  );
  if (landings.isEmpty) {
    return _answerFor(
      session,
      const [],
      const [],
      landings: const [],
      dryRun: dryRun,
    );
  }
  return session.locked(() {
    session.journalTarget.requireTrusted();
    final refs = planItemRefs(session, landings);
    final rewrites = planRewrites(session, const [], docEdits: refs.edits);
    final mentions = itemMentions(session, landings, refs: refs);
    if (!dryRun) MoveJournal(rewrites).run(session.journalTarget);
    return _answerFor(
      session,
      const [],
      rewrites,
      mentions: mentions,
      landings: landings,
      dryRun: dryRun,
    );
  });
}

/// Returns, by DocPath before the move, the edit that sets each of [moving]
/// FRs' own scenario traces for its move into [newParent].
Map<String, TextEdit> _movedFrEdits(
  WriteSession session,
  List<IndexedDoc> moving,
  IndexedDoc newParent,
) => {
  for (final fr in moving)
    if (session.index.parentOf(fr) case final source?)
      fr.docPath: (lfText) => rewriteMovedFrTraces(
        lfText,
        sourceStory: source.name,
        isTargetStory: (storyName) =>
            _namesStory(session, storyName, newParent),
      ),
};

/// Whether [storyName], in any name form, names [story] alone.
bool _namesStory(WriteSession session, String storyName, IndexedDoc story) {
  try {
    final named = session.index.resolve('$storyType:$storyName');
    return named.length == 1 && named.single.docPath == story.docPath;
  } on IndexFault {
    return false;
  }
}

/// Returns the one doc type [targets] carry, a story, an FR, an nf, or a
/// feature.
///
/// Throws [WriteFault] `doc_type_not_movable` for the first target of any
/// other type, then [IndexFault] `argument_invalid` naming the first two
/// types that differ.
MergedDocType _movableTypeOf(WriteSession session, List<IndexedDoc> targets) {
  final types = _requireMovable(session, targets);
  for (final type in types) {
    if (type.id == types.first.id) continue;
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      'move takes one doc type per call, not ${types.first.id} and ${type.id}',
    );
  }
  return types.first;
}

/// Returns the doc type of each of [targets].
///
/// Throws [WriteFault] `doc_type_not_movable` for the first target whose type
/// `move` takes none of.
List<MergedDocType> _requireMovable(
  WriteSession session,
  List<IndexedDoc> targets,
) {
  const movable = {storyType, frType, nfTypeId, featureType};
  final types = [
    for (final target in targets)
      session.index.typeOf(target) ??
          (throw StateError('${target.docPath} has no doc type')),
  ];
  for (final type in types) {
    if (movable.contains(type.id)) continue;
    throw WriteFault(
      WriteFaultCode.docTypeNotMovable,
      '${type.id} docs cannot move; move takes a $storyType, an $frType, an '
      '$nfTypeId, or a $featureType',
    );
  }
  return types;
}

/// Returns [targets] without a doc named twice, first mention first.
List<IndexedDoc> _distinct(List<IndexedDoc> targets) {
  final seen = <String>{};
  return [
    for (final target in targets)
      if (seen.add(target.docPath)) target,
  ];
}

/// Throws [IndexFault] `argument_invalid` when [parent] holds a doc of the
/// nesting type, since a feature holds stories or features.
void _checkTakesStory(
  WriteSession session,
  IndexedDoc parent,
  String parentTypeId,
) {
  final nestingId = session.index.set.nestingType?.id;
  final holdsSubFeature = session.index
      .childrenOf(parent)
      .any((child) => child.docTypeId == nestingId);
  if (!holdsSubFeature) return;
  throw IndexFault(
    IndexFaultCode.argumentInvalid,
    '${nameWithType(parent)} holds sub-${parentTypeId}s, so it takes no story',
  );
}

/// Returns the moves that put [targets] last among the children of
/// [newParent], in order, each slug kept.
///
/// Throws [WriteFault] `doc_exists` when two targets carry one slug, naming
/// the first of them, or as [_checkNoClash] does.
List<PathMove> _landingMoves(
  WriteSession session,
  List<IndexedDoc> targets,
  MergedDocType docType,
  IndexedDoc newParent,
) {
  final set = session.index.set;
  final parentType =
      set.lookup(newParent.docTypeId!) ??
      (throw StateError('${newParent.docPath} has no doc type'));
  final parentShape =
      DocPathShape.ofDoc(
        parentType,
        set,
        newParent.docPath,
        target: newParent.target,
      ) ??
      (throw StateError('${newParent.docPath} does not match its doc type'));
  final parentValues =
      parentShape.valuesOf(newParent.docPath) ??
      (throw StateError('${newParent.docPath} does not match its doc type'));
  final landedShape =
      DocPathShape.of(docType, set, depth: parentShape.depth) ??
      (throw StateError(
        '${docType.id} has no path at depth ${parentShape.depth}',
      ));
  final siblings = siblingsOnDisk(session.project, landedShape, parentValues);
  final highest = siblings.fold(0, (top, s) => max(top, s.number ?? 0));
  final firstOfSlug = <String, IndexedDoc>{};
  final moves = <PathMove>[];
  for (final target in targets) {
    final shape =
        DocPathShape.ofDoc(
          docType,
          set,
          target.docPath,
          target: target.target,
        ) ??
        (throw StateError('${target.docPath} does not match its doc type'));
    final slug =
        shape.matchOwn(target.docPath.split('/')[shape.ownIndex])?.slug ??
        (throw StateError('${target.docPath} carries no slug'));
    final first = firstOfSlug[slug];
    if (first != null) {
      throw _existsFault(docType, first.docPath, first.docPath);
    }
    firstOfSlug[slug] = target;
    final newDocPath = landedShape.build([
      ...parentValues,
      ...landedShape.ownValues(
        number: padNumber(highest + 1 + moves.length),
        slug: slug,
      ),
    ]);
    final move = (
      from: shape.ownPathOf(target.docPath),
      to: landedShape.ownPathOf(newDocPath),
    );
    _checkNoClash(
      session,
      docType,
      landedShape,
      parentValues,
      siblings,
      slug: slug,
      newDocPath: newDocPath,
      moves: [move],
    );
    moves.add(move);
  }
  return moves;
}

/// Returns the fault for a doc type that [shape] gives no slug to: a spec
/// doc names its parent, any other type says it carries no slug.
WriteFault _noSlugFault(
  WriteSession session,
  String address,
  IndexedDoc target,
  MergedDocType docType,
  DocPathShape? shape,
) {
  final parentType = docType.parent;
  if (parentType != null && shape != null && isSpecDocShape(shape)) {
    final parentDocType = session.index.set.lookup(parentType);
    final parentShape = parentDocType == null
        ? null
        : DocPathShape.of(parentDocType, session.index.set, depth: shape.depth);
    final values = shape.valuesOf(target.docPath);
    if (parentDocType != null && parentShape != null && values != null) {
      final parentName = docNameOf(
        parentShape.build(values.take(shape.parentCount).toList()),
        parentDocType,
      );
      return WriteFault(
        WriteFaultCode.docTypeNotMovable,
        '$address takes its name from its $parentType; '
        'rename $parentType:$parentName instead',
      );
    }
  }
  return WriteFault(
    WriteFaultCode.docTypeNotMovable,
    '${docType.id} docs carry no slug, so rename cannot rename them',
  );
}

/// Returns the moves that give [target] the slug [slug]: its own segment,
/// then the spec folders of a feature that exist; empty for the slug it
/// carries.
List<PathMove> _renameMoves(
  WriteSession session,
  IndexedDoc target,
  MergedDocType docType,
  DocPathShape shape,
  String slug,
) {
  final set = session.index.set;
  final oldValues =
      shape.valuesOf(target.docPath) ??
      (throw StateError('${target.docPath} does not match its doc type'));
  final parentValues = oldValues.take(shape.parentCount).toList();
  final siblings = siblingsOnDisk(session.project, shape, parentValues);
  final own = _ownEntry(
    siblings,
    target.docPath.split('/')[shape.ownIndex],
    target,
  );
  if (own.slug == slug) return const [];
  final number = own.number;
  final newDocPath = shape.build([
    ...parentValues,
    ...shape.ownValues(
      number: number == null ? null : padNumber(number),
      slug: slug,
    ),
  ]);
  final newValues =
      shape.valuesOf(newDocPath) ??
      (throw StateError('$newDocPath does not match its doc type'));
  final moves = [
    (from: shape.ownPathOf(target.docPath), to: shape.ownPathOf(newDocPath)),
  ];
  for (final move in specFolderMovesOf(
    set,
    docType,
    oldValues,
    newValues,
    depth: shape.depth,
    targetNames: session.index.twinNames,
  )) {
    if (_folderExists(session, move.from)) moves.add(move);
  }
  _checkNoClash(
    session,
    docType,
    shape,
    parentValues,
    siblings,
    slug: slug,
    newDocPath: newDocPath,
    moves: moves,
  );
  return moves;
}

/// Throws [WriteFault] `doc_exists` when a sibling doc of [docType] carries
/// [slug], or a path on disk is where one of [moves] lands; the fault
/// names [newDocPath].
void _checkNoClash(
  WriteSession session,
  MergedDocType docType,
  DocPathShape shape,
  List<String> parentValues,
  List<SiblingEntry> siblings, {
  required String slug,
  required String newDocPath,
  required List<PathMove> moves,
}) {
  for (final sibling in siblings) {
    if (sibling.slug != slug) continue;
    final docPath = [
      '${shape.containerOf(parentValues)}${sibling.name}',
      ...shape.segments.skip(shape.ownIndex + 1),
    ].join('/');
    if (session.fileOf(docPath).existsSync()) {
      throw _existsFault(docType, docPath, docPath);
    }
  }
  for (final move in moves) {
    final landing = session.fileOf(_withoutClosingSlash(move.to)).path;
    if (FileSystemEntity.typeSync(landing) == FileSystemEntityType.notFound) {
      continue;
    }
    throw _existsFault(docType, newDocPath, move.to);
  }
}

String _withoutClosingSlash(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;

WriteFault _existsFault(MergedDocType docType, String named, String file) =>
    WriteFault(
      WriteFaultCode.docExists,
      'a ${docType.id} named ${docNameOf(named, docType)} exists',
      file: file,
    );

/// Returns the entry of [siblings] named [ownName].
///
/// Throws [IndexFault] `doc_not_found` when [target] is indexed but its
/// segment is gone from disk.
SiblingEntry _ownEntry(
  List<SiblingEntry> siblings,
  String ownName,
  IndexedDoc target,
) {
  for (final sibling in siblings) {
    if (sibling.name == ownName) return sibling;
  }
  throw IndexFault(
    IndexFaultCode.docNotFound,
    'no ${target.docTypeId} doc carries the name ${target.name}',
  );
}

/// Returns the moves that put [target] at [wanted] and number every sibling
/// from 1: each renamed own segment, then the spec folders that follow it.
List<PathMove> _movesFor(
  WriteSession session,
  String address,
  IndexedDoc target,
  MergedDocType docType,
  DocPathShape shape, {
  required int wanted,
}) {
  final set = session.index.set;
  final targetValues =
      shape.valuesOf(target.docPath) ??
      (throw StateError('${target.docPath} does not match its doc type'));
  final parentValues = targetValues.take(shape.parentCount).toList();
  final siblings = siblingsOnDisk(session.project, shape, parentValues);
  if (wanted < 1 || wanted > siblings.length) {
    throw WriteFault(
      WriteFaultCode.positionOutOfRange,
      '$address cannot move to place $wanted: the places run from 1 to '
      '${siblings.length}',
    );
  }
  final ownName = target.docPath.split('/')[shape.ownIndex];
  final ordered = [
    for (final sibling in siblings)
      if (sibling.name != ownName) sibling,
  ]..insert(wanted - 1, _ownEntry(siblings, ownName, target));

  String siblingDocPath(String name) =>
      (target.docPath.split('/')..[shape.ownIndex] = name).join('/');

  final moves = <PathMove>[];
  for (final (index, sibling) in ordered.indexed) {
    final oldPath = siblingDocPath(sibling.name);
    final oldValues = shape.valuesOf(oldPath)!;
    final newValues = [
      ...parentValues,
      ...shape.ownValues(number: padNumber(index + 1), slug: sibling.slug),
    ];
    final from = shape.ownPathOf(oldPath);
    final to = shape.ownPathOf(shape.build(newValues));
    if (from == to) continue;
    moves.add((from: from, to: to));
    for (final move in specFolderMovesOf(
      set,
      docType,
      oldValues,
      newValues,
      depth: shape.depth,
      targetNames: session.index.twinNames,
    )) {
      if (_folderExists(session, move.from)) moves.add(move);
    }
  }
  return moves;
}

bool _folderExists(WriteSession session, String folder) =>
    Directory(session.fileOf(folder.substring(0, folder.length - 1)).path)
        .existsSync();

/// Returns every move twice, as a [MoveStep]: each path to its stage slot,
/// then each stage slot to its target, so no move lands on a path another
/// has not yet left.
List<MoveStep> _stageSteps(WriteSession session, List<PathMove> moves) => [
  for (final (i, move) in moves.indexed)
    MoveStep(_stepPath(session, move.from), '${MoveJournal.stagePath}/$i'),
  for (final (i, move) in moves.indexed)
    MoveStep('${MoveJournal.stagePath}/$i', _stepPath(session, move.to)),
];

/// Returns [docPath] as a [MoveStep] takes it: a project path with no
/// closing `/`.
String _stepPath(WriteSession session, String docPath) {
  final path = session.projectPathOf(docPath);
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

/// Returns the reply to a move: one line per move, or per item of [landings]
/// and per new number, then the written docs and the mentions.
///
/// A null [landings] is a doc move; an item move, even one that lands nothing,
/// also holds `renumbered` in `--json`.
ReadAnswer _answerFor(
  WriteSession session,
  List<PathMove> moves,
  List<WriteStep> rewrites, {
  List<CreateStep> created = const [],
  List<StaleMention> mentions = const [],
  List<ItemLanding>? landings,
  bool dryRun = false,
}) {
  // A record the move creates is a file it writes, listed with the rewrites.
  final written = [
    for (final step in rewrites) step.path,
    for (final step in created) step.path,
  ]..sort();
  final rewritten = [for (final path in written) session.listedPathOf(path)];
  final items = landings ?? const <ItemLanding>[];
  final renumbered = [
    for (final landing in items)
      if (landing.newId != landing.from.id) landing,
  ];
  final moveVerb = dryRun ? 'moves' : 'moved';
  final renumberVerb = dryRun ? 'renumbers' : 'renumbered';
  return ReadAnswer(
    text: [
      for (final move in moves) '$moveVerb ${move.from} to ${move.to}\n',
      for (final landing in items)
        '$moveVerb ${_sourceOf(landing)} to ${_destinationOf(landing)}\n',
      for (final landing in renumbered)
        '$renumberVerb ${_renumberOf(landing)}\n',
      for (final path in rewritten)
        '${dryRun ? 'rewrites' : 'rewrote'} $path\n',
      for (final mention in mentions) mentionLineOf(mention),
      if (dryRun) _dryRunClosing,
    ].join(),
    json: {
      'moved': [
        for (final move in moves) {'from': move.from, 'to': move.to},
        for (final landing in items)
          {'from': _sourceOf(landing), 'to': _destinationOf(landing)},
      ],
      if (landings != null)
        'renumbered': [
          for (final landing in renumbered)
            {
              'doc': landing.to.docPath,
              'from': landing.from.id,
              'to': landing.newId,
            },
        ],
      'rewritten': rewritten,
      'mentions': mentionsJsonOf(mentions),
      if (dryRun) 'dryRun': true,
    },
  );
}

String _sourceOf(ItemLanding landing) =>
    '${landing.from.doc.docPath}#${landing.from.id}';

String _destinationOf(ItemLanding landing) =>
    '${landing.to.docPath}#${landing.newId}';

String _renumberOf(ItemLanding landing) =>
    '${landing.to.docPath} ${landing.from.id} to ${landing.newId}';

const _dryRunClosing = 'dry run: nothing moved\n';
