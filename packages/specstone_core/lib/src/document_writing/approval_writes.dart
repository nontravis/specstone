import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approved_copy_store.dart';
import 'package:specstone_core/src/document_writing/audited_copy_store.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart'
    show IndexFault;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart' show Target;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/models/line_ending.dart';

const _approveModeVariableName = 'SPECSTONE_APPROVE_MODE';

/// The approve mode a variable sets, and the warnings reading it raised.
final class ApproveMode {
  const new({required this.mode, required this.warnings});

  final String mode;
  final List<String> warnings;
}

/// Returns the approve mode the value of `SPECSTONE_APPROVE_MODE` sets: `auto`
/// for `auto`, else `ask`, with a warning naming a value that is neither.
ApproveMode approveModeOf(String? value) {
  switch (value) {
    case null || '' || 'ask':
      return const ApproveMode(mode: 'ask', warnings: []);
    case 'auto':
      return const ApproveMode(mode: 'auto', warnings: []);
    default:
      final warning =
          '$_approveModeVariableName=$value is neither ask nor auto; '
          'ask is used';
      return ApproveMode(mode: 'ask', warnings: [warning]);
  }
}

/// Returns the draft [name] names as a write target.
///
/// Throws [IndexFault] for a name that is no write target, and [WriteFault]
/// `draft_not_found` for a doc that is no draft.
IndexedDoc draftAt(WriteSession session, String name, String? codeTarget) {
  final doc = session.target(name, codeTarget: codeTarget);
  if (!waitsForApproval(session, doc)) {
    throw WriteFault(
      WriteFaultCode.draftNotFound,
      '$name is no draft waiting for approval',
    );
  }
  return doc;
}

bool waitsForApproval(WriteSession session, IndexedDoc doc) => awaitsApproval(
  ApprovalFields.ofIndexed(doc),
  doc.approvalHash,
  stampsHaveRun: session.project.stampsHaveRun,
);

/// Throws `output_not_writable` unless the Owner trusts the roots [doc] lies
/// in, before git runs or a view shows: an approval written there would be
/// refused anyway.
void requireTrusted(WriteSession session, IndexedDoc doc) =>
    session.project.trust.requireTrusted(session.projectPathOf(doc.docPath));

/// Returns the whole-doc `base` hash of [bytes], or null for a file gone.
String? docHashOf(List<int>? bytes) =>
    bytes == null ? null : bytesHashOf(bytes);

/// Returns the whole-doc `base` hash of [bytes].
String bytesHashOf(List<int> bytes) => baseHashOf(toLf(utf8.decode(bytes)));

/// Returns the `<doc type>:<name>` of the typed [doc].
String addressOf(IndexedDoc doc) => '${doc.docTypeId}:${doc.name}';

/// Returns the refusal for [changed], drafts whose file changed or is gone
/// since their hash was taken.
WriteFault changedSinceHashed(List<IndexedDoc> changed) => WriteFault(
  WriteFaultCode.baseMismatch,
  'changed since their hash was taken: ${changed.map(addressOf).join(', ')}; '
  'read each again and approve it with its new hash',
  file: changed.first.docPath,
  key: 'doc',
  relatedFiles: [for (final doc in changed.skip(1)) doc.docPath],
);

/// Writes [bytes] of [doc] back without `draft`, with the ApprovalHash of its
/// content as `approved:`; runs under the lock.
void writeApproval(WriteSession session, IndexedDoc doc, List<int> bytes) {
  final text = utf8.decode(bytes);
  final undrafted = withKeyBlock(toLf(text), 'draft', null);
  final approved = withApprovalHash(
    undrafted,
    session.index.typeOf(doc),
    statusesOutside: session.project.statusesOutsideApproval,
  );
  final written = session.writeDoc(doc.docPath, approved, LineEnding.of(text));
  ApprovedCopyStore(session.project.projectRoot).save(written);
}

/// Deletes each saved approved copy whose hash no doc on disk carries as its
/// `approved:` value, and each audited copy of a doc that no longer awaits
/// approval; runs under the lock.
///
/// The docs are listed and read as they are on disk now, not as the session's
/// snapshot held them, so a doc another session made or approved meanwhile
/// keeps its copy. A folder or doc that cannot be read, and a doc whose
/// frontmatter is not valid YAML, leave every copy in place.
void pruneApprovedCopiesLocked(WriteSession session) {
  final project = session.project;
  final indexed = {for (final doc in session.index.docs) doc.docPath: doc};
  final carried = <String>{};
  final awaiting = <String>{};
  for (final root in [
    if (project.docsRoot.existsSync()) Target(project.docsRoot, ''),
    ?project.recordsTarget,
  ]) {
    for (final entry in collectDocEntries(root, project.matcher)) {
      switch (entry) {
        case UnreadableFolder():
          return;
        case DocFile(:final file, :final docPath) when docPath.endsWith('.md'):
          final String text;
          try {
            text = toLf(
              utf8.decode(file.readAsBytesSync(), allowMalformed: true),
            );
          } on FileSystemException {
            return;
          }
          final isReadable =
              comparedApprovalHash(text, null, statusesOutside: true) != null;
          if (!isReadable) return;
          final fields = ApprovalFields.of(Doc.parse(text));
          final mark = fields.approvedValue;
          if (mark is String) carried.add(mark);
          if (_awaitsApprovalOnDisk(session, indexed[docPath], text, fields)) {
            awaiting.add(docPath);
          }
        case DocFile():
          break;
      }
    }
  }
  ApprovedCopyStore(project.projectRoot).prune(carried);
  AuditedCopyStore(project.projectRoot).prune(awaiting.contains);
}

/// Whether the doc holding [text] awaits approval; a doc the session's index
/// lacks reads untyped, so its copies stay unless an approval matches.
bool _awaitsApprovalOnDisk(
  WriteSession session,
  IndexedDoc? doc,
  String text,
  ApprovalFields fields,
) => awaitsApproval(
  fields,
  comparedApprovalHash(
    text,
    doc == null ? null : session.index.typeOf(doc),
    statusesOutside: session.project.statusesOutsideApproval,
  ),
  stampsHaveRun: session.project.stampsHaveRun,
);
