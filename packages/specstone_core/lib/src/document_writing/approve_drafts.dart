import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/sentences.dart'
    show heldTextOf, sentencesOf;
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approval_view.dart';
import 'package:specstone_core/src/document_writing/sentence_changes.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

const _prompt = 'approve? [y/n/q] ';
const _nothingWaits = 'no draft waits for approval\n';

/// Shows each typed draft in tree order and approves it at the Owner's `y`.
///
/// The drafts are all of them, or those under any of [names], each once, less
/// any whose file is gone; [codeTarget] keeps them to that code target's docs
/// and the shared docs. Each shows its approval view (see
/// [renderApprovalView]) as `Draft n/m` over the drafts selected, with
/// [context] lines of context per hunk and ANSI [color] when set. Each prompt
/// waits outside the write lock; `y` re-reads the file under the lock and
/// writes only when its bytes are those the Owner saw, else the draft shows
/// again at the same position. `n` moves on; `q` and the end of input from
/// [readLine] end the walk; any other answer asks again. An approval removes
/// `draft` and writes the doc's ApprovalHash as `approved:`.
/// Reads every selected draft, the approved copy of each, and every doc of the
/// tree once, before the first view shows; with no draft waiting it reads none
/// of them.
/// Throws [IndexFault] `doc_not_found` for a name no doc carries,
/// `RenderFault` `output_not_writable` for a draft or a doc of the tree that
/// cannot be read, or a draft that is not UTF-8, all before any draft shows,
/// `output_not_writable` for roots the Owner has not recorded, before git runs
/// or a draft shows, and `index_busy` when another call holds the lock;
/// approvals already written stay.
void approveDrafts(
  WriteSession session, {
  List<String> names = const [],
  required String? Function() readLine,
  required StringSink out,
  int? context,
  bool color = false,
  ApprovalHistory? history,
  String? codeTarget,
}) {
  final drafts = _shownDraftsUnder(session, names, codeTarget);
  if (drafts.isEmpty) {
    out.write(_nothingWaits);
    return;
  }
  _requireTrusted(session, drafts);
  final reads = _RunReads.read(session, drafts, history ?? ApprovalHistory());
  for (final (at, (:doc, bytes: _)) in drafts.indexed) {
    String viewOf(List<int> bytes) => _viewOf(
      session,
      doc,
      bytes,
      reads,
      position: at + 1,
      count: drafts.length,
      context: context,
      color: color,
      codeTarget: codeTarget,
    );
    if (!_approveOne(session, doc, viewOf, readLine, out)) return;
  }
}

/// Returns the approval view of each typed draft, for the chat; writes nothing.
///
/// The drafts and their `Draft n/m` numbers are those [approveDrafts] walks
/// for [names] and [codeTarget]. The text is their views joined by a blank
/// line, else `no draft waits for approval`; the JSON is `drafts` (see
/// [draftViewJson]) and their `count`, `{"drafts": [], "count": 0}` for none.
/// It takes no lock, and with no draft waiting it reads no doc of the tree.
/// Throws [IndexFault] `doc_not_found` for a name no doc carries, and
/// `RenderFault` `output_not_writable` for a draft or a doc of the tree that
/// cannot be read, or a draft that is not UTF-8, all before any view prints,
/// and `output_not_writable` for roots the Owner has not recorded, before git
/// runs.
ReadAnswer approveDryRun(
  WriteSession session, {
  List<String> names = const [],
  int? context,
  bool color = false,
  ApprovalHistory? history,
  String? codeTarget,
}) {
  final drafts = _shownDraftsUnder(session, names, codeTarget);
  if (drafts.isEmpty) {
    return const ReadAnswer(
      text: _nothingWaits,
      json: {'drafts': <Object>[], 'count': 0},
    );
  }
  _requireTrusted(session, drafts);
  final reads = _RunReads.read(session, drafts, history ?? ApprovalHistory());
  final views = [
    for (final (:doc, :bytes) in drafts)
      _draftViewOf(session, doc, bytes, reads, codeTarget),
  ];
  return ReadAnswer(
    text: [
      for (final (at, view) in views.indexed)
        renderApprovalView(
          view,
          position: at + 1,
          count: views.length,
          context: context,
          color: color,
        ),
    ].join('\n'),
    json: {
      'drafts': [for (final view in views) draftViewJson(view)],
      'count': views.length,
    },
  );
}

/// A draft as the Owner saw it in Claude Code: its `<doc type>:<name>` and the
/// hash `approve --dry-run` printed in its `hash` row, the `bases.doc` hash
/// `get --json` gives.
typedef SeenDraft = ({String name, String hash});

/// Approves each draft in [seen] with no prompt, as `y` does.
///
/// The Owner gave the ok in Claude Code first (`--yes`), each draft shown with
/// its hash. A name approves only the one draft it names, never those under
/// it. Every name resolves to a draft before the lock, and under the lock every
/// hash is checked before the first write, so a refused name or a changed
/// draft approves nothing. The answer prints `approved <doc type>:<name>` per
/// draft, in tree order, and its JSON is `{"approved": [...]}`. [codeTarget]
/// keeps each name to that code target's docs and the shared docs.
/// Throws [IndexFault] for a name that is no write target, [WriteFault]
/// `draft_not_found` for a doc that is no draft, `base_mismatch` naming each
/// draft whose text changed, and `index_busy` when another call holds the
/// lock.
ReadAnswer approveNamed(
  WriteSession session,
  List<SeenDraft> seen, {
  String? codeTarget,
}) {
  final hashesByPath = <String, Set<String>>{};
  for (final draft in seen) {
    final doc = _draftAt(session, draft.name, codeTarget);
    (hashesByPath[doc.docPath] ??= {}).add(draft.hash);
  }
  final drafts = [
    for (final doc in session.index.docs)
      if (hashesByPath.containsKey(doc.docPath)) doc,
  ];
  final approved = session.locked(() {
    final current = {
      for (final doc in drafts) doc.docPath: session.readDocBytes(doc.docPath),
    };
    final changed = [
      for (final doc in drafts)
        if (hashesByPath[doc.docPath]!.any(
          (hash) => hash != _docHashOf(current[doc.docPath]),
        ))
          doc,
    ];
    if (changed.isNotEmpty) throw _changedSinceSeen(changed);
    for (final doc in drafts) {
      _writeApproval(session, doc, current[doc.docPath]!);
    }
    return drafts.map(_addressOf).toList();
  });
  return ReadAnswer(
    text: approved.map((address) => 'approved $address\n').join(),
    json: {'approved': approved},
  );
}

/// Returns the draft [name] names as a write target.
///
/// Throws [IndexFault] for a name that is no write target, and [WriteFault]
/// `draft_not_found` for a doc that is no draft.
IndexedDoc _draftAt(WriteSession session, String name, String? codeTarget) {
  final doc = session.target(name, codeTarget: codeTarget);
  if (!_waitsForApproval(session, doc)) {
    throw WriteFault(
      WriteFaultCode.draftNotFound,
      '$name is no draft waiting for approval',
    );
  }
  return doc;
}

/// Returns the `bases.doc` hash of [bytes], or null for a file gone.
String? _docHashOf(List<int>? bytes) =>
    bytes == null ? null : baseHashOf(toLf(utf8.decode(bytes)));

WriteFault _changedSinceSeen(List<IndexedDoc> changed) => WriteFault(
  WriteFaultCode.baseMismatch,
  'changed since the Owner saw them: ${changed.map(_addressOf).join(', ')}; '
  'show each again and ask for a new ok',
  file: changed.first.docPath,
  key: 'doc',
  relatedFiles: [for (final doc in changed.skip(1)) doc.docPath],
);

String _addressOf(IndexedDoc doc) => '${doc.docTypeId}:${doc.name}';

/// Returns the typed docs that await approval in tree order: all of them when
/// [names] is empty, else those under any of [names], each once; with a
/// [codeTarget], only the shared docs and that target's.
///
/// Throws [IndexFault] `doc_not_found` for a name no doc carries, and
/// `argument_invalid` or `argument_missing` for a [codeTarget] the project
/// does not name.
List<IndexedDoc> _draftsUnder(
  WriteSession session,
  List<String> names,
  String? codeTarget,
) {
  final index = session.index..checkCodeTarget(codeTarget);
  final selected = names.isEmpty
      ? null
      : {
          for (final name in names)
            for (final doc in index.under(name, codeTarget: codeTarget))
              doc.docPath,
        };
  return [
    for (final doc in index.docs)
      if (_waitsForApproval(session, doc) &&
          (selected?.contains(doc.docPath) ?? true) &&
          doc.inTarget(codeTarget))
        doc,
  ];
}

bool _waitsForApproval(WriteSession session, IndexedDoc doc) => awaitsApproval(
  ApprovalFields.ofIndexed(doc),
  doc.approvalHash,
  stampsHaveRun: session.project.stampsHaveRun,
);

/// Throws `output_not_writable` unless the Owner trusts the roots, before git
/// runs or a view shows: an approval written there would be refused anyway.
void _requireTrusted(WriteSession session, List<_ShownDraft> drafts) => session
    .project
    .trust
    .requireTrusted(session.projectPathOf(drafts.first.doc.docPath));

/// A draft and the bytes of its file at selection.
typedef _ShownDraft = ({IndexedDoc doc, List<int> bytes});

/// Returns [_draftsUnder] with the bytes of each, less the drafts whose file
/// is gone, so the numbers `Draft n/m` count only drafts the Owner can see.
List<_ShownDraft> _shownDraftsUnder(
  WriteSession session,
  List<String> names,
  String? codeTarget,
) {
  final shown = <_ShownDraft>[];
  for (final doc in _draftsUnder(session, names, codeTarget)) {
    final bytes = session.readDocBytes(doc.docPath);
    if (bytes != null) shown.add((doc: doc, bytes: bytes));
  }
  return shown;
}

/// Walks one draft to its answer; returns false when the walk ends.
///
/// [viewOf] renders the draft from the bytes read on each showing.
bool _approveOne(
  WriteSession session,
  IndexedDoc doc,
  String Function(List<int> bytes) viewOf,
  String? Function() readLine,
  StringSink out,
) {
  while (true) {
    final shown = session.readDocBytes(doc.docPath);
    if (shown == null) return true;
    out
      ..write(viewOf(shown))
      ..write(_prompt);
    switch (_answer(readLine, out)) {
      case 'y':
        if (_approveIfUnchanged(session, doc, shown)) return true;
      case 'n':
        return true;
      case _:
        return false;
    }
  }
}

/// Reads until `y`, `n`, or `q`; returns null for `q` and the end of input.
String? _answer(String? Function() readLine, StringSink out) {
  while (true) {
    final answer = readLine();
    if (answer == 'y' || answer == 'n') return answer;
    if (answer == 'q' || answer == null) return null;
    out.write(_prompt);
  }
}

/// What a run reads once, before its first view: the approved copy of each
/// shown draft, the two texts a sentence is looked for in, and which approved
/// sentences the tree holds, found in one pass over it for the whole run.
///
/// A re-shown draft reads its new bytes, and nothing else is read again.
final class _RunReads {
  new _(this._lookups, this._approved, this._treeHeld)
    : _tree = joinHeldTexts(_treeHeld.values),
      _runCopies = heldTextsOf(_approved.values),
      _approvedSentences = {
        for (final MapEntry(:key, :value) in _approved.entries)
          key: sentencesOf(value),
      } {
    _treeHolds = heldSentencesIn([
      for (final sentences in _approvedSentences.values) ...sentences,
    ], _tree);
  }

  /// Reads the approved copy of each of [drafts] through [history], then the
  /// text of every doc the index lists, typed or not, as on disk.
  ///
  /// Throws `RenderFault` `output_not_writable` for a doc that cannot be read.
  factory read(
    WriteSession session,
    List<_ShownDraft> drafts,
    ApprovalHistory history,
  ) {
    final lookups = <String, ApprovalLookup>{};
    final approved = <String, String>{};
    for (final (:doc, bytes: _) in drafts) {
      final lookup = history.lastApproved(
        session.project.projectRoot,
        session.projectPathOf(doc.docPath),
        docType: session.index.typeOf(doc),
      );
      lookups[doc.docPath] = lookup;
      if (lookup case ApprovedCopy(:final text)) {
        approved[doc.docPath] = comparableTextOf(
          text,
          session.index.typeOf(doc),
        );
      }
    }
    return _RunReads._(lookups, approved, {
      for (final doc in session.index.docs)
        doc.docPath: heldTextOf(_textOnDisk(session, doc.docPath)),
    });
  }

  final Map<String, ApprovalLookup> _lookups;

  /// The laid-out approved copy of each draft whose lookup found one.
  final Map<String, String> _approved;

  /// The held text of each doc of the tree, by DocPath.
  final Map<String, String> _treeHeld;

  final String _tree;
  final String _runCopies;

  /// The sentences of each approved copy, by DocPath.
  final Map<String, List<String>> _approvedSentences;

  /// The approved sentences of every draft of the run that [_tree] holds.
  late final Set<String> _treeHolds;

  /// Returns what git said about the approved copy of [doc].
  ApprovalLookup lookupOf(IndexedDoc doc) => _lookups[doc.docPath]!;

  /// Returns the sentences [doc] dropped and added, [text] being its draft as
  /// shown now.
  SentenceChanges changesOf(IndexedDoc doc, String text, MergedDocType? type) {
    final held = heldTextOf(toLf(text));
    final draft = comparableTextOf(text, type);
    if (held != _treeHeld[doc.docPath]) {
      return sentenceChangesOf(
        draft: draft,
        approved: _approved[doc.docPath],
        tree: joinHeldTexts({..._treeHeld, doc.docPath: held}.values),
        runCopies: _runCopies,
      );
    }
    return sentenceChangesGiven(
      draft: draft,
      approvedSentences: _approvedSentences[doc.docPath] ?? const [],
      treeHeld: _treeHolds,
      runCopies: _runCopies,
    );
  }
}

/// Returns the LF text of [docPath] as it is on disk, or `''` for a file gone;
/// invalid UTF-8 reads as replacement characters, since this doc is only looked
/// in.
String _textOnDisk(WriteSession session, String docPath) {
  try {
    return toLf(
      utf8.decode(
        session.fileOf(docPath).readAsBytesSync(),
        allowMalformed: true,
      ),
    );
  } on PathNotFoundException {
    return '';
  } on FileSystemException catch (error) {
    throw cannotRead(docPath, error);
  }
}

/// Returns the draft [doc] holding [bytes], as the view and the JSON show it.
DraftView _draftViewOf(
  WriteSession session,
  IndexedDoc doc,
  List<int> bytes,
  _RunReads reads,
  String? codeTarget,
) {
  final type = session.index.typeOf(doc);
  final text = utf8.decode(bytes);
  final index = session.index;
  final perTarget =
      index.hasTwins && codeTarget == null && isStatusTracked(doc);
  return DraftView(
    name: doc.name,
    // `_waitsForApproval` kept only typed drafts, so the type id is set.
    docType: doc.docTypeId!,
    mergedType: type,
    title: doc.title,
    status: perTarget ? null : index.statusOf(doc, codeTarget: codeTarget),
    statusByTarget: perTarget
        ? {
            for (final name in index.targetNames)
              name: index.statusOf(doc, codeTarget: name),
          }
        : const {},
    docPath: doc.docPath,
    projectPath: session.projectPathOf(doc.docPath),
    text: text,
    lookup: reads.lookupOf(doc),
    sentences: reads.changesOf(doc, text, type),
  );
}

/// Returns the approval view of the typed draft [doc] holding [bytes].
String _viewOf(
  WriteSession session,
  IndexedDoc doc,
  List<int> bytes,
  _RunReads reads, {
  required int position,
  required int count,
  required int? context,
  required bool color,
  required String? codeTarget,
}) => renderApprovalView(
  _draftViewOf(session, doc, bytes, reads, codeTarget),
  position: position,
  count: count,
  context: context,
  color: color,
);

/// Writes the approval under the lock; returns false when the bytes changed.
bool _approveIfUnchanged(
  WriteSession session,
  IndexedDoc doc,
  List<int> shown,
) {
  return session.locked(() {
    final current = session.readDocBytes(doc.docPath);
    if (current == null) return true;
    if (!_sameBytes(current, shown)) return false;
    _writeApproval(session, doc, current);
    return true;
  });
}

/// Writes [bytes] of [doc] back without `draft`, with the ApprovalHash of its
/// content as `approved:`; runs under the lock.
void _writeApproval(WriteSession session, IndexedDoc doc, List<int> bytes) {
  final text = utf8.decode(bytes);
  final undrafted = withKeyBlock(toLf(text), 'draft', null);
  final approved = withApprovalHash(
    undrafted,
    session.index.typeOf(doc),
    statusesOutside: session.project.statusesOutsideApproval,
  );
  session.writeDoc(doc.docPath, approved, LineEnding.of(text));
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
