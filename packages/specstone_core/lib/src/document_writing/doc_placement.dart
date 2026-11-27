import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/path_length.dart';
import 'package:specstone_core/src/doc_model/records_root.dart'
    show docPathOfProjectPath;
import 'package:specstone_core/src/document_writing/models/path_move.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show CreateStep;
import 'package:specstone_core/src/document_writing/moved_paths.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';

/// A doc a write lands: its DocPath once written and the doc type it keeps.
final class LandedDoc {
  const new({required this.docPath, required this.docTypeId, this.target});

  /// The DocPath the doc has once the write lands.
  final String docPath;

  /// The id of the doc type the doc keeps; null for an untyped doc, which
  /// takes no type test.
  final String? docTypeId;

  /// The code target the doc belongs to; null for a shared doc.
  final String? target;
}

/// Throws [IndexFault] `argument_invalid` for the first of [landed], in tree
/// order, whose path from the project root holds more than [pathLengthLimit]
/// UTF-16 code units; else for the first, in the same order, whose DocPath no
/// doc type matches, that two or more match, or that a doc type other than its
/// own matches.
///
/// An untyped entry takes the length test only. A doc's target counts only in
/// a project with twin targets: with one named target the index tags every
/// per-target doc, while its path names no target. A [judgeLength] of false
/// skips the length test, for a caller whose path is not final.
void requirePlaced(
  WriteSession session,
  List<LandedDoc> landed, {
  bool judgeLength = true,
}) {
  final matcher = DocTypeMatcher(
    session.index.set,
    targetNames: session.index.twinNames,
  );
  // The order names the first failure, so only failures are sorted.
  if (judgeLength) {
    _throwFirst(session, {
      for (final doc in landed) doc.docPath: ?_lengthRefusalOf(session, doc),
    });
  }
  final twins = session.index.hasTwins;
  _throwFirst(session, {
    for (final doc in landed)
      if (doc.docTypeId != null)
        doc.docPath: ?_refusalOf(doc, matcher.match(doc.docPath), twins: twins),
  });
}

/// Runs [requirePlaced] over each doc under [moves] at its landed DocPath, each
/// of [created], and each record [creates] writes.
///
/// One list, so placement and length judge every doc the write lands.
void requireMovePlaced(
  WriteSession session,
  List<PathMove> moves, {
  List<LandedDoc> created = const [],
  List<CreateStep> creates = const [],
}) => requirePlaced(session, [
  ...landedDocsOf(session, moves),
  ...created,
  ...landedRecordCreatesOf(creates),
]);

String? _lengthRefusalOf(WriteSession session, LandedDoc doc) {
  final length = projectPathLength(doc.docPath);
  if (length <= pathLengthLimit) return null;
  return '${session.projectPathOf(doc.docPath)} would have $length '
      'characters; the limit is $pathLengthLimit';
}

/// Throws [IndexFault] `argument_invalid` with the refusal, of [refusals] by
/// DocPath, of the first DocPath in tree order; returns when [refusals] is
/// empty.
void _throwFirst(WriteSession session, Map<String, String> refusals) {
  if (refusals.isEmpty) return;
  final first = session.index.inTreeOrder(refusals.keys).first;
  throw IndexFault(IndexFaultCode.argumentInvalid, refusals[first]!);
}

/// Returns each doc of the index that lies under a move of [moves], at the
/// DocPath it has after them, with its own doc type and target.
///
/// Records are docs of the index, so they come too.
List<LandedDoc> landedDocsOf(WriteSession session, List<PathMove> moves) => [
  for (final doc in session.index.docs)
    if (movedPath(doc.docPath, moves) case final landed
        when landed != doc.docPath)
      LandedDoc(docPath: landed, docTypeId: doc.docTypeId, target: doc.target),
];

/// Returns each record [creates] writes as an untyped landed doc.
///
/// The writer of a record builds its path from the record type's own path, so
/// no doc type test applies.
/// Throws [StateError] for a create under neither root, since every record
/// create sits under the records root.
List<LandedDoc> landedRecordCreatesOf(List<CreateStep> creates) => [
  for (final step in creates)
    LandedDoc(
      docPath:
          docPathOfProjectPath(step.path) ??
          (throw StateError('${step.path} is under no doc root')),
      docTypeId: null,
    ),
];

String? _refusalOf(LandedDoc doc, DocTypeMatch match, {required bool twins}) {
  final docPath = doc.docPath;
  return switch (match) {
    NoDocType() => '$docPath matches no doc type',
    AmbiguousDocType(:final docTypeIds) =>
      '$docPath matches ${docTypeIds.join(', ')}',
    MatchedDocType() => _otherTypeMessage(doc, match, twins: twins),
  };
}

/// Returns the refusal when [match] is not the doc type, and in a twin project
/// the target, of [doc]; else null.
///
/// A per-target doc's own type is its type for its target.
String? _otherTypeMessage(
  LandedDoc doc,
  MatchedDocType match, {
  required bool twins,
}) {
  final matchedTarget = twins ? match.target : null;
  final ownTarget = twins ? doc.target : null;
  if (match.docType.id == doc.docTypeId && matchedTarget == ownTarget) {
    return null;
  }
  return '${doc.docPath} matches '
      '${_labelOf(match.docType.id, matchedTarget)}, '
      'not ${_labelOf(doc.docTypeId!, ownTarget)}';
}

String _labelOf(String docTypeId, String? target) =>
    target == null ? docTypeId : '$docTypeId for $target';
