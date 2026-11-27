import 'package:specstone_core/src/document_writing/move_plan.dart';
import 'package:specstone_core/src/document_writing/move_plan_judge.dart';
import 'package:specstone_core/src/document_writing/move_reply.dart';
import 'package:specstone_core/src/document_writing/move_work.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart'
    show GeneratorRegistry;

const _sourceHashLength = 12;

/// Returns the hash a plan's `source` line records for a doc's [bytes]: the
/// first 12 hex characters of their sha256.
String sourceHashOf(List<int> bytes) =>
    contentHashOf(bytes).substring(0, _sourceHashLength);

/// Applies every line of [plan] in one call, or refuses the whole plan.
///
/// Each `source` hash is compared first, then every line is judged against
/// its own destination, all before the lock. Under it, one journal creates
/// each `new` line's doc as a draft, lands each unit in plan line order, and
/// rewrites every reference in one pass with one re-stamp pass. A doc that
/// gains or loses an item is marked draft; a doc only rewritten keeps its
/// approval with its new hash. Every address resolves among [codeTarget]'s
/// docs and the shared docs. [dryRun] writes nothing, not even a journal.
/// [generators] refresh the generated blocks the plan makes stale, as
/// [applyMoveWork] gives.
///
/// Throws [WriteFault] `plan_mismatch` for a `source` hash that differs from
/// its doc's bytes, then the faults of each line's move, `new` included, and
/// [IndexFault] `argument_invalid` for one unit two lines instruct
/// differently.
ReadAnswer answerPlanMove(
  WriteSession session,
  MovePlan plan, {
  String? codeTarget,
  required bool dryRun,
  required GeneratorRegistry<DocIndex> generators,
}) {
  _requireSources(session, plan, codeTarget);
  final work = judgeMovePlan(session, plan, codeTarget: codeTarget);
  return applyMoveWork(
    session,
    work,
    shape: MoveReplyShape.plan,
    dryRun: dryRun,
    generators: generators,
  );
}

/// Throws [WriteFault] `plan_mismatch` for the first `source` line of [plan]
/// whose hash differs from its doc's bytes now.
void _requireSources(WriteSession session, MovePlan plan, String? codeTarget) {
  for (final line in plan.lines.whereType<SourceLine>()) {
    final doc = session.target(line.address.docPart, codeTarget: codeTarget);
    final bytes = session.readDocBytes(doc.docPath);
    if (bytes != null && sourceHashOf(bytes) == line.hash) continue;
    throw WriteFault(
      WriteFaultCode.planMismatch,
      '${doc.docPath} changed since the plan was written; write it again '
      'with move --plan-out',
    );
  }
}
