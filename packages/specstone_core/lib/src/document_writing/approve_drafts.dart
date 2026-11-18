import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/doc_model/sentences.dart' show sentencesOf;
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approval_view.dart';
import 'package:specstone_core/src/document_writing/approved_copy_store.dart';
import 'package:specstone_core/src/document_writing/models/seen_draft.dart';
import 'package:specstone_core/src/document_writing/sentence_changes.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart' show Target;
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
/// `draft` and writes the doc's ApprovalHash as `approved:`, and saves the
/// approved text in an [ApprovedCopyStore], which the walk's end prunes.
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
  for (final (at, _ShownDraft(:doc)) in drafts.indexed) {
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
    if (!_approveOne(session, doc, viewOf, readLine, out)) break;
  }
  _pruneApprovedCopies(session);
}

/// Returns the approval view of each typed draft, for the chat; writes nothing.
///
/// The drafts and their `Draft n/m` numbers are those [approveDrafts] walks
/// for [names] and [codeTarget]. The text is their views joined by a blank
/// line, else `no draft waits for approval`; the JSON is `drafts` (see
/// [draftViewJson]) and their `count`, empty and 0 for none, and the
/// `approveMode` that [approveModeVariable] names, `ask` unless it is `auto`.
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
  String? approveModeVariable,
}) {
  final _ApproveMode(:mode, :warnings) = _approveModeOf(approveModeVariable);
  final drafts = _shownDraftsUnder(session, names, codeTarget);
  if (drafts.isEmpty) {
    return ReadAnswer(
      text: _nothingWaits,
      json: {'drafts': <Object>[], 'count': 0, 'approveMode': mode},
      warnings: warnings,
    );
  }
  _requireTrusted(session, drafts);
  final reads = _RunReads.read(session, drafts, history ?? ApprovalHistory());
  final views = [
    for (final _ShownDraft(:doc, :bytes) in drafts)
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
      'approveMode': mode,
    },
    warnings: warnings,
  );
}

const _approveModeVariableName = 'SPECSTONE_APPROVE_MODE';

/// The approve mode a variable sets, and the warnings reading it raised.
final class _ApproveMode {
  const new({required this.mode, required this.warnings});

  final String mode;
  final List<String> warnings;
}

_ApproveMode _approveModeOf(String? value) {
  switch (value) {
    case null || '' || 'ask':
      return const _ApproveMode(mode: 'ask', warnings: []);
    case 'auto':
      return const _ApproveMode(mode: 'auto', warnings: []);
    default:
      final warning =
          '$_approveModeVariableName=$value is neither ask nor auto; '
          'ask is used';
      return _ApproveMode(mode: 'ask', warnings: [warning]);
  }
}

/// Approves each draft in [seen] with no prompt, as `y` does.
///
/// Each draft carries the hash its text had when read, under either mode. A
/// name approves only the one draft it names, never those under
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
    if (changed.isNotEmpty) throw _changedSinceHashed(changed);
    for (final doc in drafts) {
      _writeApproval(session, doc, current[doc.docPath]!);
    }
    _pruneApprovedCopiesLocked(session);
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

WriteFault _changedSinceHashed(List<IndexedDoc> changed) => WriteFault(
  WriteFaultCode.baseMismatch,
  'changed since their hash was taken: ${changed.map(_addressOf).join(', ')}; '
  'read each again and approve it with its new hash',
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
final class _ShownDraft {
  const new({required this.doc, required this.bytes});

  final IndexedDoc doc;
  final List<int> bytes;
}

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
    if (bytes != null) shown.add(_ShownDraft(doc: doc, bytes: bytes));
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
/// shown draft and the sentences of every doc of the tree.
///
/// A re-shown draft reads its new bytes, and nothing else is read again.
final class _RunReads {
  new _(this._lookups, this._approved, this._treeSentences)
    : _tree = _unionOf(_treeSentences.values),
      _runCopies = sentenceSetOf(_approved.values);

  /// Reads the approved copy of each of [drafts], from the saved copy its
  /// `approved:` mark names, else through [history] from git, then the text of
  /// every doc the index lists, typed or not, as on disk.
  ///
  /// Throws `RenderFault` `output_not_writable` for a doc that cannot be read.
  factory read(
    WriteSession session,
    List<_ShownDraft> drafts,
    ApprovalHistory history,
  ) {
    final lookups = <String, ApprovalLookup>{};
    final approved = <String, String>{};
    final store = ApprovedCopyStore(session.project.projectRoot);
    for (final _ShownDraft(:doc, :bytes) in drafts) {
      final type = session.index.typeOf(doc);
      final markOnDisk = ApprovalFields.of(Doc.parse(toLf(utf8.decode(bytes))))
          .approvedValue;
      final lookup =
          store.find(markOnDisk, type) ??
          history.lastApproved(
            session.project.projectRoot,
            session.projectPathOf(doc.docPath),
            docType: type,
          );
      lookups[doc.docPath] = lookup;
      switch (lookup) {
        case ApprovedCopy(:final text) || SavedApprovedCopy(:final text):
          approved[doc.docPath] = comparableTextOf(text, type);
        case NoApprovedCopy() || UnknownHistory():
      }
    }
    return _RunReads._(lookups, approved, {
      for (final doc in session.index.docs)
        doc.docPath: sentencesOf(_textOnDisk(session, doc.docPath)).toSet(),
    });
  }

  final Map<String, ApprovalLookup> _lookups;

  /// The laid-out approved copy of each draft whose lookup found one.
  final Map<String, String> _approved;

  /// The sentences of each doc of the tree, by DocPath.
  final Map<String, Set<String>> _treeSentences;

  /// The sentences of every doc of the tree.
  final Set<String> _tree;

  /// The sentences of the approved copy of each draft the run shows.
  final Set<String> _runCopies;

  /// Returns where the approved copy of [doc] was found, the saved copy or
  /// git's history, or that none was.
  ApprovalLookup lookupOf(IndexedDoc doc) => _lookups[doc.docPath]!;

  /// Returns the sentences [doc] dropped and added, [text] being its draft as
  /// shown now.
  SentenceChanges changesOf(IndexedDoc doc, String text, MergedDocType? type) {
    final shown = sentencesOf(toLf(text)).toSet();
    return sentenceChangesOf(
      draft: comparableTextOf(text, type),
      approved: _approved[doc.docPath],
      tree: _isSameSet(shown, _treeSentences[doc.docPath])
          ? _tree
          : _unionOf([
              for (final MapEntry(:key, :value) in _treeSentences.entries)
                if (key != doc.docPath) value,
              shown,
            ]),
      runCopies: _runCopies,
    );
  }
}

Set<String> _unionOf(Iterable<Set<String>> sets) => {
  for (final set in sets) ...set,
};

bool _isSameSet(Set<String> a, Set<String>? b) =>
    b != null && a.length == b.length && a.containsAll(b);

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
  final written = session.writeDoc(doc.docPath, approved, LineEnding.of(text));
  ApprovedCopyStore(session.project.projectRoot).save(written);
}

/// Takes the lock and prunes the saved approved copies (see
/// [_pruneApprovedCopiesLocked]); a busy lock skips it, as the next run prunes.
void _pruneApprovedCopies(WriteSession session) {
  try {
    session.locked(() => _pruneApprovedCopiesLocked(session));
  } on IndexFault catch (fault) {
    if (fault.code != IndexFaultCode.indexBusy) rethrow;
  }
}

/// Deletes each saved approved copy whose hash no doc on disk carries as its
/// `approved:` value; runs under the lock.
///
/// The docs are listed and read as they are on disk now, not as the session's
/// snapshot held them, so a doc another session made or approved meanwhile
/// keeps its copy. A folder or doc that cannot be read, and a doc whose
/// frontmatter is not valid YAML, leave every copy in place.
void _pruneApprovedCopiesLocked(WriteSession session) {
  final project = session.project;
  final carried = <String>{};
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
          final mark = ApprovalFields.of(Doc.parse(text)).approvedValue;
          if (mark is String) carried.add(mark);
        case DocFile():
          break;
      }
    }
  }
  ApprovedCopyStore(project.projectRoot).prune(carried);
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
