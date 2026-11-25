import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approval_writes.dart';
import 'package:specstone_core/src/document_writing/approve_drafts.dart'
    show approvedCopyLookupOf;
import 'package:specstone_core/src/document_writing/audited_copy_store.dart';
import 'package:specstone_core/src/document_writing/clean_draft_judge.dart';
import 'package:specstone_core/src/document_writing/draft_sections.dart'
    show sectionBodyOf;
import 'package:specstone_core/src/document_writing/held_items.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';

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
/// A long item the draft's approved copy holds, and a finding it gives too at
/// the same place, do not make the draft ask; [history] finds that copy, a
/// fresh one when null. The copy check runs only for a draft with a finding no
/// other rule passes.
///
/// Throws [IndexFault], [WriteFault] `draft_not_found`, `RenderFault`
/// `output_not_writable`, or `MigrateFault` `git_work_tree_required` before the
/// mode gate, `base_mismatch` for a draft gone
/// inside the hold, and `index_busy` when another call holds the lock.
Future<ReadAnswer> approveAuto(
  WriteSession session,
  AutoApproveCall call, {
  MermaidNodeRun? mermaidRunner,
  ApprovalHistory? history,
}) async {
  final drafts = _namedDrafts(session, call);
  if (drafts.firstOrNull case final first?) requireTrusted(session, first);
  final ownHistory = (history ?? ApprovalHistory())
    ..requireOwnGitDir(session.project.projectRoot);
  final ApproveMode(:mode, :warnings) = approveModeOf(call.approveModeVariable);
  final addresses = [for (final doc in drafts) session.index.addressOf(doc)];
  final judgment = mode == _autoMode
      ? await _judgeAndWrite(
          session,
          call,
          drafts,
          addresses,
          mermaidRunner,
          ownHistory,
        )
      : _Judgment(
          verdicts: [
            for (final (at, doc) in drafts.indexed)
              _Verdict(
                doc.docPath,
                addresses[at],
                const DraftAsk(_askModeReason),
                const [],
              ),
          ],
        );
  return _answerOf(mode, judgment.verdicts, [
    ...warnings,
    ...judgment.checkWarnings,
  ]);
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
Future<_Judgment> _judgeAndWrite(
  WriteSession session,
  AutoApproveCall call,
  List<IndexedDoc> drafts,
  List<String> addresses,
  MermaidNodeRun? mermaidRunner,
  ApprovalHistory history,
) async {
  final reports = ReportFiles.read(
    auditPaths: call.auditPaths,
    authorPaths: call.authorPaths,
    workingDirectory: call.workingDirectory,
  );
  return session.lockedAsync(() async {
    final check = await session.runProjectCheck(mermaidRunner: mermaidRunner);
    final current = _currentBytes(session, drafts);
    final passed = await _passedFindingsOf(
      session,
      history,
      check.findings,
      drafts,
      current,
      mermaidRunner,
    );
    final judge = CleanDraftJudge(
      findings: check.findings,
      audit: call.auditPaths.isEmpty
          ? null
          : AuditSequence.parse(reports.audits),
      noAudit: call.noAudit,
      authors: reports.authors,
      unreadableReason: reports.unreadableReason,
      callNames: {
        for (final (at, doc) in drafts.indexed) ...[addresses[at], doc.docPath],
      },
      passedFindings: passed.keys,
      carriedFindings: passed.carried,
    );
    final verdicts = [
      for (final (at, doc) in drafts.indexed)
        _judgeAndApprove(
          session,
          judge,
          doc,
          addresses[at],
          current[at],
          call.codeTarget,
          passed.carriedBy[doc.docPath] ?? const [],
        ),
    ];
    pruneApprovedCopiesLocked(session);
    return _Judgment(verdicts: verdicts, checkWarnings: check.warnings);
  });
}

/// The findings of the drafts the judge does not count, and the ones among
/// them a draft carries from its approved copy.
final class _Passed {
  const new({
    required this.keys,
    required this.carried,
    required this.carriedBy,
  });

  /// The [findingKeyOf] keys of the long items the judge does not count.
  final Set<String> keys;

  /// The findings the judge does not count because their copy gives them.
  final Set<Finding> carried;

  /// The carried findings of each draft, by DocPath, in check order.
  final Map<String, List<CarriedFinding>> carriedBy;
}

/// Returns the findings of [drafts] the judge does not count: an
/// `item_over_limit` finding whose item the approved copy holds, and a finding
/// of any other kind the copy gives too at the same place.
///
/// A draft with no finding no other rule passes looks up no copy, so a clean
/// call runs no history walk and no copy check. A draft whose only such
/// findings are long items runs no copy check either.
Future<_Passed> _passedFindingsOf(
  WriteSession session,
  ApprovalHistory history,
  List<Finding> findings,
  List<IndexedDoc> drafts,
  List<List<int>> current,
  MermaidNodeRun? mermaidRunner,
) async {
  final keys = <String>{};
  final carriedAll = <Finding>{};
  final carriedBy = <String, List<CarriedFinding>>{};
  for (final (at, doc) in drafts.indexed) {
    final judged = [
      for (final finding in findings)
        if (finding.path == doc.docPath && _isPassable(finding)) finding,
    ];
    if (judged.isEmpty) continue;
    final copy = switch (approvedCopyLookupOf(
      session,
      doc,
      current[at],
      history,
    )) {
      ApprovedCopy(:final text) || SavedApprovedCopy(:final text) => toLf(text),
      NoApprovedCopy() || UnknownHistory() => null,
    };
    if (copy == null) continue;
    final draftLf = toLf(utf8.decode(current[at], allowMalformed: true));
    final type = session.index.typeOf(doc);
    keys.addAll(
      heldItemKeysOf(
        findings: judged,
        draftLf: draftLf,
        approvedLf: copy,
        type: type,
      ),
    );
    if (judged.every((finding) => finding.kind == FindingKind.itemOverLimit)) {
      continue;
    }
    final copyCheck = await session.runCopyCheck(
      draft: doc,
      copyLf: copy,
      mermaidRunner: mermaidRunner,
    );
    final carried = carriedFindingsOf(
      draftFindings: judged,
      copyFindings: copyCheck.findings,
      draftLf: draftLf,
      copyLf: copy,
      type: type,
    );
    carriedAll.addAll(carried);
    final places = FindingPlaces(draftLf, type);
    carriedBy[doc.docPath] = [
      for (final finding in judged)
        if (carried.contains(finding))
          CarriedFinding(kind: finding.kind.wire, place: places.of(finding)),
    ];
  }
  return _Passed(keys: keys, carried: carriedAll, carriedBy: carriedBy);
}

/// Whether no test but the carried rules can pass [finding]: the Owner's
/// approval clears an `unconfirmed` one already.
bool _isPassable(Finding finding) => !finding.isClearedByApproval;

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
  String? codeTarget,
  List<CarriedFinding> carried,
) {
  final store = AuditedCopyStore(session.project.projectRoot);
  final ask = judge.askFor(
    JudgedDraft(
      name: address,
      docPath: doc.docPath,
      currentHash: bytesHashOf(bytes),
      currentLf: toLf(utf8.decode(bytes, allowMalformed: true)),
      type: session.index.typeOf(doc),
      auditedTextAt: (hash) => store.find(doc.docPath, hash),
      sectionTextOf: (docName, sectionKey) =>
          _sectionTextOf(session, codeTarget, docName, sectionKey),
    ),
  );
  if (ask == null) writeApproval(session, doc, bytes);
  return _Verdict(doc.docPath, address, ask, ask == null ? carried : const []);
}

/// Returns the current body of section [sectionKey] of the doc [docName]
/// names, null when the name resolves to no typed doc, the file is gone,
/// unreadable, or not UTF-8, or the doc lacks the section.
String? _sectionTextOf(
  WriteSession session,
  String? codeTarget,
  String docName,
  String sectionKey,
) {
  final List<int>? bytes;
  final IndexedDoc doc;
  try {
    doc = session.target(docName, codeTarget: codeTarget);
    bytes = session.readDocBytes(doc.docPath);
  } on IndexFault {
    return null;
  } on RenderFault {
    return null;
  }
  if (bytes == null) return null;
  return sectionBodyOf(
    toLf(utf8.decode(bytes, allowMalformed: true)),
    session.index.typeOf(doc),
    sectionKey,
  );
}

ReadAnswer _answerOf(
  String mode,
  List<_Verdict> verdicts,
  List<String> warnings,
) => ReadAnswer(
  text: [
    'mode: $mode',
    for (final _Verdict(:address, :ask, :carried) in verdicts)
      if (ask == null) ...[
        'approved $address',
        for (final CarriedFinding(:kind, :place) in carried)
          'carried $address: $kind at $place',
      ],
    for (final _Verdict(:address, :ask) in verdicts)
      if (ask != null) 'ask $address: ${ask.reason}',
  ].map((line) => '$line\n').join(),
  json: {
    'approveMode': mode,
    'approved': [
      for (final _Verdict(:address, :docPath, :ask, :carried) in verdicts)
        if (ask == null)
          {
            'doc': address,
            'path': docPath,
            'carried': [for (final item in carried) item.toJson()],
          },
    ],
    'asked': [
      for (final _Verdict(:address, :docPath, :ask) in verdicts)
        if (ask != null) {'doc': address, 'path': docPath, ...ask.toJson()},
    ],
  },
  warnings: warnings,
);

/// What the call decided for each draft, and what the check warned.
final class _Judgment {
  const new({required this.verdicts, this.checkWarnings = const []});

  final List<_Verdict> verdicts;
  final List<String> checkWarnings;
}

/// What the call decided for one draft: approved when [ask] is null.
final class _Verdict {
  const new(this.docPath, this.address, this.ask, this.carried);

  final String docPath;
  final String address;
  final DraftAsk? ask;

  /// The findings an approved draft carries from its approved copy.
  final List<CarriedFinding> carried;
}
