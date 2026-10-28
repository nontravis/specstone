import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/own_segment.dart';
import 'package:specstone_core/src/document_writing/rewrite_refs.dart';
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
/// written.
///
/// Throws [WriteFault] `doc_type_not_movable` for a doc type that numbers no
/// doc and `position_out_of_range` for a place outside 1 to the sibling
/// count; an `IndexFault` for a bad address or [place], or `doc_not_found`
/// when the doc is gone from disk; `index_busy` when another call holds the
/// lock.
ReadAnswer answerReorder(
  WriteSession session,
  String address, {
  required String? place,
}) {
  final wanted = parsePlace(place);
  final target = session.target(address);
  final docType =
      session.index.typeOf(target) ??
      (throw StateError('${target.docPath} has no doc type'));
  final shape = DocPathShape.of(docType, session.index.set);
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
    if (moves.isEmpty) return _answerFor(session, moves, const []);
    final rewrites = planRewrites(session, moves);
    MoveJournal([..._stageSteps(session, moves), ...rewrites])
        .run(JournalTarget.of(session.project));
    return _answerFor(session, moves, rewrites);
  });
}

/// Renames the doc [address] names to the slug [slug], keeping its number.
///
/// The own segment moves, with the spec folders of a feature, and the links
/// to them and the `doc_ref` values that name a renamed doc follow. The `# `
/// title is never touched and no draft mark is written. The slug a doc
/// already carries changes nothing.
///
/// Throws [WriteFault] `doc_type_not_movable` for a doc type that carries no
/// slug, a spec doc included, and `doc_exists` when a sibling carries
/// [slug] or a path on disk is where the renamed segment would land; an
/// `IndexFault` for a missing or bad [slug] or a bad address, or
/// `doc_not_found` when the doc is gone from disk; `index_busy` when another
/// call holds the lock.
ReadAnswer answerRename(
  WriteSession session,
  String address, {
  required String? slug,
}) {
  if (slug == null) {
    throw missingArgument(
      'rename',
      'a slug',
      'specstone rename user_story:login/reset_password --to recover_account',
    );
  }
  checkSlug(slug);
  final target = session.target(address);
  final docType =
      session.index.typeOf(target) ??
      (throw StateError('${target.docPath} has no doc type'));
  final shape = DocPathShape.of(docType, session.index.set);
  if (shape == null || !shape.slugged) {
    throw _noSlugFault(session, address, target, docType, shape);
  }
  return session.locked(() {
    final moves = _renameMoves(session, target, docType, shape, slug);
    if (moves.isEmpty) return _answerFor(session, moves, const []);
    final renamed = _renamedNames(session, moves);
    final rewrites = planRewrites(session, moves, renamed: renamed);
    MoveJournal([
      for (final move in moves)
        MoveStep(_stepPath(session, move.from), _stepPath(session, move.to)),
      ...rewrites,
    ]).run(JournalTarget.of(session.project));
    return _answerFor(session, moves, rewrites);
  });
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
        : DocPathShape.of(parentDocType, session.index.set);
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
  final siblings = siblingsOnDisk(
    session.project.docsRoot,
    shape,
    parentValues,
  );
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
  for (final move in specFolderMovesOf(set, docType, oldValues, newValues)) {
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
/// [slug], or a path on disk is where one of [moves] lands (PD12); the fault
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

/// Returns the names that change under [moves], each typed doc under a
/// moved path mapped from `(doc type id, old name)` to its new name.
Map<(String, String), String> _renamedNames(
  WriteSession session,
  List<PathMove> moves,
) {
  final renamed = <(String, String), String>{};
  for (final doc in session.index.docs) {
    final typeId = doc.docTypeId;
    final docType = typeId == null ? null : session.index.set.lookup(typeId);
    final newPath = movedPath(doc.docPath, moves);
    if (docType == null || newPath == doc.docPath) continue;
    renamed[(docType.id, doc.name)] = docNameOf(newPath, docType);
  }
  return renamed;
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
  final parentValues = targetValues.take(shape.parentCount).toList();
  final siblings = siblingsOnDisk(
    session.project.docsRoot,
    shape,
    parentValues,
  );
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
    for (final move in specFolderMovesOf(set, docType, oldValues, newValues)) {
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
/// has not yet left (PD3).
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

ReadAnswer _answerFor(
  WriteSession session,
  List<PathMove> moves,
  List<WriteStep> rewrites,
) {
  final rewritten = [for (final step in rewrites) session.docPathOf(step.path)];
  return ReadAnswer(
    text: [
      for (final move in moves) 'moved ${move.from} to ${move.to}\n',
      for (final path in rewritten) 'rewrote $path\n',
    ].join(),
    json: {
      'moved': [
        for (final move in moves) {'from': move.from, 'to': move.to},
      ],
      'rewritten': rewritten,
    },
  );
}
