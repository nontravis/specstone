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

/// Where a reorder parks each moved path between its two moves, relative to
/// the project root.
const _stagePath = '${MoveJournal.trashPath}/stage';

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
/// count; an `IndexFault` for a bad address or [place]; `index_busy` when
/// another call holds the lock.
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
        .run(session.project);
    return _answerFor(session, moves, rewrites);
  });
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
  ]..insert(wanted - 1, siblings.firstWhere((s) => s.name == ownName));

  String docPathOf(String name) =>
      (target.docPath.split('/')..[shape.ownIndex] = name).join('/');

  final moves = <PathMove>[];
  for (final (index, sibling) in ordered.indexed) {
    final oldPath = docPathOf(sibling.name);
    final oldValues = shape.valuesOf(oldPath)!;
    final newValues = [
      ...parentValues,
      ...shape.ownValues(number: padNumber(index + 1), slug: sibling.slug),
    ];
    final from = shape.ownPathOf(oldPath);
    final to = shape.ownPathOf(shape.build(newValues));
    if (from == to) continue;
    moves.add((from: from, to: to));
    final oldFolders = specFoldersOf(set, docType, oldValues);
    final newFolders = specFoldersOf(set, docType, newValues);
    for (var i = 0; i < oldFolders.length; i++) {
      if (oldFolders[i] != newFolders[i] &&
          _folderExists(session, oldFolders[i])) {
        moves.add((from: oldFolders[i], to: newFolders[i]));
      }
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
List<MoveStep> _stageSteps(WriteSession session, List<PathMove> moves) {
  String projectPath(String docPath) {
    final path = session.projectPathOf(docPath);
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  return [
    for (final (i, move) in moves.indexed)
      MoveStep(projectPath(move.from), '$_stagePath/$i'),
    for (final (i, move) in moves.indexed)
      MoveStep('$_stagePath/$i', projectPath(move.to)),
  ];
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
