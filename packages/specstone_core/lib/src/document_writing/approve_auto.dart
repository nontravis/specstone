import 'dart:io';

import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:specstone_core/src/document_writing/approval_writes.dart';
import 'package:specstone_core/src/document_writing/clean_draft_judge.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';

const _autoMode = 'auto';
const _askModeReason = 'approve mode is ask';

/// One `approve --auto` call: the drafts it names and the reports it passes.
final class AutoApproveCall {
  const new({
    required this.names,
    required this.auditPaths,
    required this.authorPaths,
    required this.noAudit,
    required this.workingDirectory,
    this.codeTarget,
    this.approveModeVariable,
  });

  /// The drafts to judge, each a name `session.target` reads, with no hash.
  final List<String> names;

  /// The `--audit` files, oldest first; relative ones read from
  /// [workingDirectory].
  final List<String> auditPaths;

  /// The `--author` files.
  final List<String> authorPaths;

  /// Whether the flow has no audit, so the audit tests are not taken.
  final bool noAudit;

  /// Where a relative report path starts.
  final Directory workingDirectory;

  /// Keeps each name to this code target's docs and the shared docs.
  final String? codeTarget;

  /// The raw value of `SPECSTONE_APPROVE_MODE`, or null when unset.
  final String? approveModeVariable;
}

/// Judges the drafts [call] names and approves each clean one.
///
/// Under `auto` the check, the judgment, the writes, and the prune share one
/// lock hold; under any other mode nothing is written and every draft is asked.
/// Prints a `mode:` line, `approved` lines, then `ask` lines with their
/// reasons, in tree order; JSON keys are `approveMode`, `approved`, `asked`,
/// and the mode warning is the answer's `warnings`.
/// Throws [IndexFault], [WriteFault] `draft_not_found`, or `RenderFault`
/// `output_not_writable` before the mode gate, `base_mismatch` for a draft gone
/// inside the hold, and `index_busy` when another call holds the lock.
Future<ReadAnswer> approveAuto(
  WriteSession session,
  AutoApproveCall call, {
  MermaidNodeRun? mermaidRunner,
}) async {
  final drafts = _namedDrafts(session, call);
  if (drafts.firstOrNull case final first?) requireTrusted(session, first);
  final ApproveMode(:mode, :warnings) = approveModeOf(call.approveModeVariable);
  final addresses = [for (final doc in drafts) session.index.addressOf(doc)];
  final verdicts = mode == _autoMode
      ? await _judgeAndWrite(session, call, drafts, addresses, mermaidRunner)
      : [
          for (final (at, doc) in drafts.indexed)
            _Verdict(doc.docPath, addresses[at], _askModeReason),
        ];
  return _answerOf(mode, verdicts, warnings);
}

/// Returns the docs [call] names, each once, in tree order.
List<IndexedDoc> _namedDrafts(WriteSession session, AutoApproveCall call) {
  final paths = {
    for (final name in call.names)
      draftAt(session, name, call.codeTarget).docPath,
  };
  return [
    for (final doc in session.index.docs)
      if (paths.contains(doc.docPath)) doc,
  ];
}

/// Reads the reports, then runs the check, judges each draft, writes each
/// clean one, and prunes, in one hold of the write lock.
Future<List<_Verdict>> _judgeAndWrite(
  WriteSession session,
  AutoApproveCall call,
  List<IndexedDoc> drafts,
  List<String> addresses,
  MermaidNodeRun? mermaidRunner,
) async {
  final reports = ReportFiles.read(
    auditPaths: call.auditPaths,
    authorPaths: call.authorPaths,
    workingDirectory: call.workingDirectory,
  );
  return session.lockedAsync(() async {
    final check = await session.runProjectCheck(mermaidRunner: mermaidRunner);
    final judge = CleanDraftJudge(
      findings: check.findings,
      audit: call.auditPaths.isEmpty
          ? null
          : AuditSequence.parse(reports.audits),
      noAudit: call.noAudit,
      authors: reports.authors,
      unreadableReason: reports.unreadableReason,
    );
    final current = _currentBytes(session, drafts);
    final verdicts = [
      for (final (at, doc) in drafts.indexed)
        _judgeAndApprove(session, judge, doc, addresses[at], current[at]),
    ];
    pruneApprovedCopiesLocked(session);
    return verdicts;
  });
}

/// Returns the bytes of each of [drafts] as they are now, in order.
///
/// Throws [WriteFault] `base_mismatch`, as `approveNamed` does, when a draft's
/// file is gone; nothing is written then.
List<List<int>> _currentBytes(WriteSession session, List<IndexedDoc> drafts) {
  final bytes = <List<int>>[];
  final gone = <IndexedDoc>[];
  for (final doc in drafts) {
    final read = session.readDocBytes(doc.docPath);
    read == null ? gone.add(doc) : bytes.add(read);
  }
  if (gone.isNotEmpty) throw changedSinceHashed(gone);
  return bytes;
}

_Verdict _judgeAndApprove(
  WriteSession session,
  CleanDraftJudge judge,
  IndexedDoc doc,
  String address,
  List<int> bytes,
) {
  final reason = judge.reasonFor(
    JudgedDraft(
      name: address,
      docPath: doc.docPath,
      currentHash: bytesHashOf(bytes),
    ),
  );
  if (reason == null) writeApproval(session, doc, bytes);
  return _Verdict(doc.docPath, address, reason);
}

ReadAnswer _answerOf(
  String mode,
  List<_Verdict> verdicts,
  List<String> warnings,
) => ReadAnswer(
  text: [
    'mode: $mode',
    for (final _Verdict(:address, :reason) in verdicts)
      if (reason == null) 'approved $address',
    for (final _Verdict(:address, :reason) in verdicts)
      if (reason != null) 'ask $address: $reason',
  ].map((line) => '$line\n').join(),
  json: {
    'approveMode': mode,
    'approved': [
      for (final _Verdict(:address, :docPath, :reason) in verdicts)
        if (reason == null) {'name': address, 'docPath': docPath},
    ],
    'asked': [
      for (final _Verdict(:address, :docPath, :reason) in verdicts)
        if (reason != null)
          {'name': address, 'docPath': docPath, 'reason': reason},
    ],
  },
  warnings: warnings,
);

/// What the call decided for one draft: approved when [reason] is null.
final class _Verdict {
  const new(this.docPath, this.address, this.reason);

  final String docPath;
  final String address;
  final String? reason;
}
