import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart'
    show runCopyCheck;
import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:specstone_core/src/doc_model/records_root.dart'
    show fileOfDocPath;
import 'package:specstone_core/src/doc_model/reference_grammar.dart'
    show readDocAddress;
import 'package:specstone_core/src/document_writing/clean_draft_judge.dart'
    show carriedFindingsOf, findingKeyOf;
import 'package:specstone_core/src/document_writing/held_items.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/retired_ids.dart';
import 'package:specstone_core/src/document_writing/set_doc.dart';
import 'package:specstone_core/src/document_writing/write_session.dart'
    show refuseMigratePending, requireNotReadOnly, typedTargetOf;
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/formatter.dart' show layOutDoc;
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _dryRunExample =
    'specstone set user_story:login/email_login#use_case --dry-run';

/// The checked arguments of one `set --dry-run` call.
final class DryRunRequest {
  const new({
    required this.address,
    required this.target,
    this.base,
    this.codeTarget,
  });

  /// Reads the arguments of `set --dry-run`: [target] is
  /// `<type>:<name>#<key>`, the key a section or `_lead`.
  ///
  /// With an [index], a [target] that names a doc as a path has no section
  /// key, even when it holds `#`. Throws what [requireShape] throws.
  static DryRunRequest parse(
    String? target, {
    String? base,
    DocIndex? index,
    String? codeTarget,
  }) {
    requireShape(target);
    final SetAddress(:docPart, :sectionKey) = SetAddress.parse(target!, index);
    if (sectionKey == null) throw _missingSectionKey();
    return DryRunRequest(
      address: docPart,
      target: sectionKey == leadKey
          ? const LeadTarget()
          : SectionTarget(sectionKey),
      base: base,
      codeTarget: codeTarget,
    );
  }

  /// Throws [IndexFault] `argument_missing` unless [target] is given and holds
  /// a `#` with text after it.
  ///
  /// Needs no index, so a command calls it before it reads stdin.
  static void requireShape(String? target) {
    if (target == null) {
      throw missingArgument('set', 'a target', _dryRunExample);
    }
    if (readDocAddress(target).sectionKey case null || '') {
      throw _missingSectionKey();
    }
  }

  static IndexFault _missingSectionKey() =>
      missingArgument('set', 'a section key or #_lead', _dryRunExample);

  /// The doc as `<type>:<name>`.
  final String address;

  /// The section or the lead to judge.
  final SetTarget target;

  /// The base hash of [target] the caller last read; null judges it as it
  /// stands.
  final String? base;

  /// The code target [address] is kept to; null keeps every target.
  final String? codeTarget;
}

/// Prints the naming line of [request]'s target with its current base, then the
/// findings a write of [text] would add to the doc, and writes nothing.
///
/// The doc is judged as the write would leave it: spliced, its removed item
/// IDs retired, marked a draft, and laid out, all in memory. A finding the
/// current text gives too, at the same kind and place, is left out. A
/// [homeDirectory] reads the journal records. Throws what the write throws
/// before it writes: [IndexFault] for a doc, section, or text it refuses,
/// `WriteFault` `base_mismatch`, `required_target`, or `migrate_pending`, and a
/// `RenderFault` for a pending journal no run on this machine wrote; never one
/// for a missing trust record. A target that is no section or lead throws
/// `IndexFault` `argument_conflict`.
Future<ReadAnswer> answerSetDryRun(
  ReadSession session,
  DryRunRequest request,
  String text, {
  required Directory? homeDirectory,
  MermaidNodeRun? mermaidRunner,
}) async {
  final target = request.target;
  if (target is! SectionTarget && target is! LeadTarget) {
    throw IndexFault(
      IndexFaultCode.argumentConflict,
      '--dry-run takes a section target or #_lead alone',
    );
  }
  refuseMigratePending(session.workingDirectory, homeDirectory: homeDirectory);
  MoveJournal.requireRecorded(
    session.project.projectRoot,
    homeDirectory: homeDirectory,
  );
  final doc = typedTargetOf(
    session.index,
    request.address,
    codeTarget: request.codeTarget,
  );
  final docType =
      session.index.typeOf(doc) ??
      (throw StateError('${doc.docPath} is typed but its type is gone'));
  checkPartText(doc: doc, docType: docType, target: target, text: text);

  final content = session.index.contentOf(doc);
  final current = toLf(content.text);
  final currentBase = partBaseOf(content, target, docType);
  final written = _writtenTextOf(
    session,
    doc,
    docType,
    target,
    current,
    content.sections,
    request.base ?? currentBase,
    text,
  );
  requireNotReadOnly(
    fileOfDocPath(
      doc.docPath,
      docsRoot: session.project.docsRoot,
      projectRoot: session.project.projectRoot,
    ),
    doc.docPath,
  );
  final report = await _addedFindingsOf(
    session,
    doc,
    docType,
    current: current,
    written: written,
    mermaidRunner: mermaidRunner,
  );
  return ReadAnswer(
    text: '${partNamingLineOf(doc, target, currentBase)}\n${report.text}',
    json: {'findings': report.json['findings']!},
    warnings: report.warnings,
  );
}

/// Returns the LF text a write of [text] to [target] would leave in [doc]:
/// spliced, its removed item IDs retired, marked a draft, and laid out.
///
/// Throws what the write throws while it splices.
String _writtenTextOf(
  ReadSession session,
  IndexedDoc doc,
  MergedDocType docType,
  SetTarget target,
  String current,
  List<IndexedSection> sections,
  String base,
  String text,
) {
  final part = splicePart(
    doc: doc,
    docType: docType,
    lfText: current,
    sections: sections,
    target: target,
    base: base,
    text: text,
  );
  final retired = retireRemovedIds(
    docPath: doc.docPath,
    before: current,
    after: part.lfText,
    type: docType,
  );
  return layOutDoc(
    part.marksDraft ? markDraft(retired, docType) : retired,
    docType,
  );
}

/// Returns the findings of [written] that [current] does not give too, at the
/// same kind and place.
Future<CheckReport> _addedFindingsOf(
  ReadSession session,
  IndexedDoc doc,
  MergedDocType docType, {
  required String current,
  required String written,
  required MermaidNodeRun? mermaidRunner,
}) async {
  final after = await runCopyCheck(
    session,
    draft: doc,
    copyLf: written,
    mermaidRunner: mermaidRunner,
  );
  final before = await runCopyCheck(
    session,
    draft: doc,
    copyLf: current,
    mermaidRunner: mermaidRunner,
  );
  final heldLong = heldItemKeysOf(
    findings: after.findings,
    draftLf: written,
    approvedLf: current,
    type: docType,
  );
  final carried = carriedFindingsOf(
    draftFindings: after.findings,
    copyFindings: before.findings,
    draftLf: written,
    copyLf: current,
    type: docType,
    includeApprovalCleared: true,
  );
  return CheckReport(
    findings: [
      for (final finding in after.findings)
        if (!carried.contains(finding) &&
            !heldLong.contains(findingKeyOf(finding)))
          finding,
    ],
    warnings: after.warnings,
  );
}
