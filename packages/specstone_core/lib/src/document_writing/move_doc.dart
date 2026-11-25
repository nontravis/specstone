import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/doc_model/models/doc_address.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show readDocAddress;
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/move_plan.dart';
import 'package:specstone_core/src/document_writing/move_plan_judge.dart'
    show judgeMovePlan, movableTypeOf;
import 'package:specstone_core/src/document_writing/move_reply.dart';
import 'package:specstone_core/src/document_writing/move_work.dart';
import 'package:specstone_core/src/document_writing/own_segment.dart';
import 'package:specstone_core/src/document_writing/rewrite_records.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart';
import 'package:specstone_core/src/document_writing/stale_mentions.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
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
/// doc or fixes its numbers, and `position_out_of_range` for a place outside
/// 1 to the sibling count; an `IndexFault` for a bad address or [place], or
/// `doc_not_found` when the doc is gone from disk; `index_busy` when another
/// call holds the lock; `RenderFault` `output_not_writable` for roots the
/// Owner has not recorded, naming the journal, before any rewrite is planned.
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
  if (docType.fixedNumbers) {
    throw WriteFault(
      WriteFaultCode.docTypeNotMovable,
      '${docType.id} docs keep their number, so reorder cannot move them',
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
      return moveReplyOf(session, shape: MoveReplyShape.docs, dryRun: dryRun);
    }
    session.journalTarget.requireTrusted();
    final planned = planRewrites(session, moves);
    final mentions = staleMentions(session, moves, namesChange: false);
    if (!dryRun) {
      MoveJournal([...stagedMoveSteps(session, moves), ...planned.rewrites])
          .run(session.journalTarget);
    }
    return moveReplyOf(
      session,
      shape: MoveReplyShape.docs,
      moves: moves,
      rewrites: planned.rewrites,
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
      return moveReplyOf(session, shape: MoveReplyShape.docs, dryRun: dryRun);
    }
    session.journalTarget.requireTrusted();
    final renamed = renamedNamesOf(session, moves);
    final records = planRecordRewrites(session, renamed);
    final planned = planRewrites(
      session,
      moves,
      renamed: renamed,
      docEdits: records.edits,
      creates: records.creates,
    );
    final mentions = staleMentions(
      session,
      moves,
      namesChange: true,
      docWrites: planned.rewrites,
    );
    if (!dryRun) {
      MoveJournal([
        for (final move in moves)
          MoveStep(
            moveStepPath(session, move.from),
            moveStepPath(session, move.to),
          ),
        ...planned.rewrites,
        ...planned.creates,
      ]).run(session.journalTarget);
    }
    return moveReplyOf(
      session,
      shape: MoveReplyShape.docs,
      moves: moves,
      rewrites: planned.rewrites,
      recordCreates: planned.creates,
      mentions: mentions,
      dryRun: dryRun,
    );
  });
}

/// Moves the docs or items [addresses] name under [under], rewriting every
/// reference in one pass.
///
/// The flags are judged before any address resolves; only an item target
/// takes [codeTarget], and only a feature takes [top]. The targets then run
/// as the plan [planOfArgv] builds, through the engine a plan file runs.
///
/// Throws [WriteFault], [IndexFault], and the faults of [judgeMovePlan] and
/// [applyMoveWork].
ReadAnswer answerMove(
  WriteSession session,
  List<String> addresses, {
  required String? under,
  bool top = false,
  String? codeTarget,
  bool dryRun = false,
}) {
  final areItems = _checkArgv(
    session,
    addresses,
    under: under,
    top: top,
    codeTarget: codeTarget,
  );
  final work = judgeMovePlan(
    session,
    planOfArgv(addresses, under: under, top: top),
    codeTarget: codeTarget,
  );
  return applyMoveWork(
    session,
    work,
    shape: areItems ? MoveReplyShape.items : MoveReplyShape.docs,
    dryRun: dryRun,
  );
}

/// Throws the refusals of the argv form alone, before its plan is built, and
/// returns whether the targets are items.
bool _checkArgv(
  WriteSession session,
  List<String> addresses, {
  required String? under,
  required bool top,
  required String? codeTarget,
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
  if (!items.any((isItem) => isItem)) {
    _checkDocTargets(session, addresses, top: top, codeTarget: codeTarget);
    return false;
  }
  _checkItemTargets(
    session,
    addresses,
    isItem: items,
    top: top,
    codeTarget: codeTarget,
  );
  return true;
}

/// Returns the plan an argv `move` runs as: one line per target, each with
/// the destination [under] names, or `top`.
///
/// The plan has no file, so its path is empty.
///
/// Throws [IndexFault] `argument_invalid` for an [under] with a `#` suffix.
MovePlan planOfArgv(List<String> targets, {String? under, required bool top}) {
  final destination = top ? null : _underOf(under);
  return MovePlan(
    path: '',
    lines: [
      for (final (at, target) in targets.indexed)
        MoveLine(
          lineNumber: at + 1,
          unit: readDocAddress(target),
          destination: destination,
        ),
    ],
  );
}

DocAddress _underOf(String? under) {
  final address = readDocAddress(
    under ?? (throw StateError('an argv move reached with no --under')),
  );
  if (address.sectionKey == null) return address;
  throw IndexFault(
    IndexFaultCode.argumentInvalid,
    '$under: this command takes no #<section key> or @<hash>',
  );
}

/// Throws the argv-only refusals of doc targets: a type `move` takes none
/// of, two types in one call, [top] beside a target that is no feature, and
/// [codeTarget].
void _checkDocTargets(
  WriteSession session,
  List<String> addresses, {
  required bool top,
  required String? codeTarget,
}) {
  final targets = _distinct([for (final a in addresses) session.target(a)]);
  final docType = _movableTypeOf(session, targets);
  if (top && docType.id != featureType) throw _topFault();
  if (codeTarget == null) return;
  throw IndexFault(
    IndexFaultCode.argumentInvalid,
    'move takes --target only with item targets',
  );
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

/// Throws the argv-only refusals of item targets, once every target resolves,
/// [isItem] marking each address that is an item: [WriteFault]
/// `doc_type_not_movable` for a doc target of another type, [IndexFault]
/// `argument_invalid` for a doc target at all or [top].
void _checkItemTargets(
  WriteSession session,
  List<String> addresses, {
  required List<bool> isItem,
  required bool top,
  required String? codeTarget,
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
) => [for (final target in targets) movableTypeOf(session, target)];

/// Returns [targets] without a doc named twice, first mention first.
List<IndexedDoc> _distinct(List<IndexedDoc> targets) {
  final seen = <String>{};
  return [
    for (final target in targets)
      if (seen.add(target.docPath)) target,
  ];
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
  final parentValues = oldValues.take(shape.containerCount).toList();
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
    PathMove(
      from: shape.ownPathOf(target.docPath),
      to: shape.ownPathOf(newDocPath),
    ),
  ];
  for (final move in specFolderMovesOf(
    set,
    docType,
    oldValues,
    newValues,
    depth: shape.depth,
    targetNames: session.index.twinNames,
  )) {
    if (isOnDisk(session, move.from)) moves.add(move);
  }
  checkNoClash(
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
  final parentValues = targetValues.take(shape.containerCount).toList();
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
    moves.add(PathMove(from: from, to: to));
    for (final move in specFolderMovesOf(
      set,
      docType,
      oldValues,
      newValues,
      depth: shape.depth,
      targetNames: session.index.twinNames,
    )) {
      if (isOnDisk(session, move.from)) moves.add(move);
    }
  }
  return moves;
}
