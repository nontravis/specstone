import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approved_copy_store.dart';
import 'package:specstone_core/src/document_writing/audited_copy_store.dart';
import 'package:specstone_core/src/document_writing/generated_block_steps.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart'
    show IndexFault;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart' show Target;
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/generated_blocks.dart'
    show GeneratorRegistry;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart'
    show RenderFault;

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

bool waitsForApproval(WriteSession session, IndexedDoc doc) =>
    awaitsApproval(ApprovalFields.ofIndexed(doc), doc.approvalHash);

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

/// One draft an approval writes: the doc and its bytes as read under the lock.
final class ApprovalWrite {
  const new(this.doc, this.bytes);

  final IndexedDoc doc;
  final List<int> bytes;
}

/// Returns the LF text an approval writes from [bytes] of [doc]: no `draft`,
/// the ApprovalHash of its content as `approved:`, laid out.
String approvedTextOf(WriteSession session, IndexedDoc doc, List<int> bytes) {
  final type = session.index.typeOf(doc);
  final undrafted = withKeyBlock(toLf(utf8.decode(bytes)), 'draft', null);
  return layOutDoc(withApprovalHash(undrafted, type), type);
}

/// Writes each of [approvals] back approved, each saved as its approved copy,
/// with the generated blocks they make stale ([blockRefreshOf]); runs under the
/// lock and returns the refresh.
///
/// The approvals and the refresh go through one journal, so a refusal leaves
/// every draft as it was; no approval writes nothing and runs no journal.
/// Throws [RenderFault] `output_not_writable` before any write for a draft
/// that cannot be written.
BlockRefresh writeApprovals(
  WriteSession session,
  List<ApprovalWrite> approvals, {
  required GeneratorRegistry<DocIndex> generators,
}) {
  if (approvals.isEmpty) return BlockRefresh.none;
  final texts = {
    for (final ApprovalWrite(:doc, :bytes) in approvals)
      doc.docPath: approvedTextOf(session, doc, bytes),
  };
  final refresh = blockRefreshOf(
    session,
    generators,
    WrittenDocs(texts: texts),
  );
  String textOf(IndexedDoc doc) =>
      refresh.ownTexts[doc.docPath] ?? texts[doc.docPath]!;
  for (final ApprovalWrite(:doc) in approvals) {
    session.requireWritable(doc.docPath);
  }
  MoveJournal([
    for (final ApprovalWrite(:doc, :bytes) in approvals)
      session
          .docWriteStep(doc.docPath, textOf(doc), bytes)
          .keepingApprovedCopy(),
    ...refresh.steps,
  ]).run(session.journalTarget);
  return refresh;
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
          final isReadable = comparedApprovalHash(text, null) != null;
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
  comparedApprovalHash(text, doc == null ? null : session.index.typeOf(doc)),
);
