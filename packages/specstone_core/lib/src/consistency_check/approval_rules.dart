import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';

const _approvedKey = 'approved';
const _changedMessage =
    "the doc changed since the Owner approved it; it waits for the Owner's "
    'specstone approve';
const _unapprovedMessage =
    "the doc carries no approval; it waits for the Owner's specstone approve";

/// Returns the `approval_stale` finding of a typed [doc] that awaits the
/// Owner's approval and is no draft.
///
/// Reads the stored approval hash and lays nothing out. A doc whose
/// frontmatter is invalid YAML never awaits approval ([awaitsApproval]), so
/// it has `frontmatter_invalid` alone.
Iterable<Finding> staleApproval(CheckContext context, IndexedDoc doc) sync* {
  if (doc.isDraft) return;
  final fields = ApprovalFields.ofIndexed(doc);
  if (!awaitsApproval(
    fields,
    doc.approvalHash,
    stampsHaveRun: context.stampsHaveRun,
  )) {
    return;
  }
  final lines = context.linesOf(doc);
  final keyLine = lines.keyLine(_approvedKey);
  if (fields.approvedValue == null) {
    // An `approved:` key with no value sits on its own line; no key, line 1.
    yield context.finding(
      doc,
      FindingKind.approvalStale,
      line: keyLine ?? 1,
      message: _unapprovedMessage,
    );
    return;
  }
  yield context.finding(
    doc,
    FindingKind.approvalStale,
    line: keyLine ?? 1,
    message: _changedMessage,
    keys: {
      'value': lines.writtenValueOf(_approvedKey) ?? '${fields.approvedValue}',
    },
  );
}
