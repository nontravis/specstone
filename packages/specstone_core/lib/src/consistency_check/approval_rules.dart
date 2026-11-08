import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/doc_lines.dart';
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
/// frontmatter is invalid YAML has `frontmatter_invalid` alone.
Iterable<Finding> staleApproval(CheckContext context, IndexedDoc doc) sync* {
  final hash = doc.approvalHash;
  if (hash == null || doc.isDraft) return;
  final lines = context.linesOf(doc);
  if (lines.frontmatterErrorLine != null) return;
  final fields = ApprovalFields.ofIndexed(doc);
  if (!awaitsApproval(fields, hash, stampsHaveRun: context.stampsHaveRun)) {
    return;
  }
  final value = fields.approvedValue;
  if (value == null) {
    yield context.finding(
      doc,
      FindingKind.approvalStale,
      line: 1,
      message: _unapprovedMessage,
    );
    return;
  }
  yield context.finding(
    doc,
    FindingKind.approvalStale,
    line: lines.keyLine(_approvedKey) ?? 1,
    message: _changedMessage,
    keys: {'value': _writtenValue(lines.entriesOf(_approvedKey), value)},
  );
}

// A string reads as itself; any other value reads as its source text, since
// the parsed value of `123e45678901` is no longer what was written.
String _writtenValue(List<YamlEntry> entries, Object value) =>
    value is String || entries.length != 1 ? '$value' : entries.single.text;
