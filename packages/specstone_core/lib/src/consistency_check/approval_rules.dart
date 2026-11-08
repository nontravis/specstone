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
    keys: {'value': _writtenValue(lines.entriesOf(_approvedKey))},
  );
}

// The index turns a non-finite number into a string, so the YAML entry, not
// the indexed value, decides: a string reads as itself, any other value as
// its source text.
String _writtenValue(List<YamlEntry> entries) {
  final entry = entries.single;
  return entry.value is String ? entry.value! as String : entry.text;
}
