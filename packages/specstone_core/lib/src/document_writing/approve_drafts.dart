import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/doc_model/sentences.dart' show sentencesOf;
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approval_view.dart';
import 'package:specstone_core/src/document_writing/approval_writes.dart';
import 'package:specstone_core/src/document_writing/approved_copy_store.dart';
import 'package:specstone_core/src/document_writing/audited_copy_store.dart';
import 'package:specstone_core/src/document_writing/clean_draft_judge.dart'
    show AuditSequence, ReportFiles;
import 'package:specstone_core/src/document_writing/draft_sections.dart'
    show draftDeltaOf;
import 'package:specstone_core/src/document_writing/models/seen_draft.dart';
import 'package:specstone_core/src/document_writing/sentence_changes.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
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
/// waits outside the write lock; `y` reads the index afresh, re-reads the file
/// under the lock, and writes only when its bytes are those the Owner saw,
/// else the draft shows again at the same position. `n` moves on; `q` and the
/// end of input from [readLine] end the walk; any other answer asks again. An
/// approval removes `draft` and writes the doc's ApprovalHash as `approved:`,
/// and saves the approved text in an [ApprovedCopyStore], which the walk's end
/// prunes.
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
  final drafts = _shownDraftsUnder(
    _DraftSource.ofWrite(session),
    names,
    codeTarget,
  );
  if (drafts.isEmpty) {
    out.write(_nothingWaits);
    return;
  }
  requireTrusted(session, drafts.first.doc);
  final reads = _RunReads.read(
    _DraftSource.ofWrite(session),
    drafts,
    history ?? ApprovalHistory(),
  );
  for (final (at, _ShownDraft(:doc)) in drafts.indexed) {
    String viewOf(List<int> bytes) => _viewOf(
      _DraftSource.ofWrite(session),
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
/// With [saveAuditedCopies] it saves each listed draft's LF text in an
/// [AuditedCopyStore] at its `base` hash. With [auditPaths], which needs
/// [workingDirectory] to read a relative path from, each `drafts` entry gains
/// `changedSections`: the keys of the sections that differ from the draft's
/// audited copy at the `Audited:` hash of its last audit part, all of them
/// when no part names it, in doc order, compared before any copy is saved. An
/// entry whose copy is missing or whose title, fields, headings, or section
/// order differ gains none, and a report that cannot be read adds its reason to
/// the warnings and gives no entry the key. It takes no lock, since a dry run
/// changes no doc, and with no draft waiting it reads no doc of the tree.
/// Throws [IndexFault] `doc_not_found` for a name no doc carries, and
/// `RenderFault` `output_not_writable` for a draft or a doc of the tree that
/// cannot be read, or a draft that is not UTF-8, all before any view prints,
/// and `output_not_writable` for roots the Owner has not recorded, before git
/// runs. Throws [ArgumentError] when [auditPaths] is set without
/// [workingDirectory].
ReadAnswer approveDryRun(
  WriteSession session, {
  List<String> names = const [],
  int? context,
  bool color = false,
  ApprovalHistory? history,
  String? codeTarget,
  String? approveModeVariable,
  bool saveAuditedCopies = false,
  List<String> auditPaths = const [],
  Directory? workingDirectory,
}) {
  final ApproveMode(:mode, warnings: modeWarnings) = approveModeOf(
    approveModeVariable,
  );
  final warnings = [...modeWarnings];
  final views = _draftViewsOf(
    _DraftSource.ofWrite(session),
    names,
    codeTarget,
    history ?? ApprovalHistory(),
  );
  final store = AuditedCopyStore(session.project.projectRoot);
  final changed = <String, List<String>>{};
  if (auditPaths.isNotEmpty) {
    final reports = ReportFiles.read(
      auditPaths: auditPaths,
      authorPaths: const [],
      workingDirectory: ArgumentError.checkNotNull(
        workingDirectory,
        'workingDirectory',
      ),
    );
    if (reports.unreadableReason case final reason?) {
      warnings.add(reason);
    } else {
      changed.addAll(
        _changedSectionsOf(views, AuditSequence.parse(reports.audits), store),
      );
    }
  }
  if (views.isEmpty) {
    return ReadAnswer(
      text: _nothingWaits,
      json: {'drafts': <Object>[], 'count': 0, 'approveMode': mode},
      warnings: warnings,
    );
  }
  if (saveAuditedCopies) {
    for (final view in views) {
      store.save(view.docPath, toLf(view.text));
    }
  }
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
      'drafts': [
        for (final view in views)
          draftViewJson(view, changedSections: changed[view.docPath]),
      ],
      'count': views.length,
      'approveMode': mode,
    },
    warnings: warnings,
  );
}

/// Returns, by DocPath, the changed sections of each of [views] that has them:
/// every section when [audit] names no part for the draft, else those that
/// differ from its audited copy in [store]; a draft with no copy, or one that
/// changed outside its sections, has no entry.
Map<String, List<String>> _changedSectionsOf(
  List<DraftView> views,
  AuditSequence audit,
  AuditedCopyStore store,
) {
  final changed = <String, List<String>>{};
  for (final view in views) {
    final hash = audit.auditedHashOf(view.address);
    final currentLf = toLf(view.text);
    if (hash == null) {
      changed[view.docPath] = draftDeltaOf(
        currentLf,
        null,
        view.mergedType,
      ).changedSections;
      continue;
    }
    final copy = store.find(view.docPath, hash);
    if (copy == null) continue;
    final delta = draftDeltaOf(currentLf, copy, view.mergedType);
    if (!delta.changesOutsideSections) {
      changed[view.docPath] = delta.changedSections;
    }
  }
  return changed;
}

/// Returns the view of each typed draft under [names], as [approveDryRun]
/// shows them, from a read session; writes nothing.
///
/// The drafts are those [approveDryRun] lists for [names] and [codeTarget],
/// each with the sentences it dropped and added. It finishes no move journal,
/// since a read session writes none.
/// Throws [IndexFault] `doc_not_found` for a name no doc carries, and
/// `RenderFault` `output_not_writable` for a draft or a doc of the tree that
/// cannot be read, or a draft that is not UTF-8, and for roots the Owner has
/// not recorded, before git runs.
List<DraftView> draftViewsOf(
  ReadSession session, {
  List<String> names = const [],
  ApprovalHistory? history,
  String? codeTarget,
}) => _draftViewsOf(
  _DraftSource.ofRead(session),
  names,
  codeTarget,
  history ?? ApprovalHistory(),
);

/// Returns the views of the drafts under [names], none when no draft waits.
List<DraftView> _draftViewsOf(
  _DraftSource source,
  List<String> names,
  String? codeTarget,
  ApprovalHistory history,
) {
  final drafts = _shownDraftsUnder(source, names, codeTarget);
  if (drafts.isEmpty) return const [];
  source.project.trust.requireTrusted(
    projectPathOfDocPath(drafts.first.doc.docPath),
  );
  final reads = _RunReads.read(source, drafts, history);
  return [
    for (final _ShownDraft(:doc, :bytes) in drafts)
      _draftViewOf(source, doc, bytes, reads, codeTarget),
  ];
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
    final doc = draftAt(session, draft.name, codeTarget);
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
          (hash) => hash != docHashOf(current[doc.docPath]),
        ))
          doc,
    ];
    if (changed.isNotEmpty) throw changedSinceHashed(changed);
    for (final doc in drafts) {
      writeApproval(session, doc, current[doc.docPath]!);
    }
    pruneApprovedCopiesLocked(session);
    return drafts.map(addressOf).toList();
  });
  return ReadAnswer(
    text: approved.map((address) => 'approved $address\n').join(),
    json: {'approved': approved},
  );
}

/// Returns the typed docs that await approval in tree order: all of them when
/// [names] is empty, else those under any of [names], each once; with a
/// [codeTarget], only the shared docs and that target's.
///
/// Throws [IndexFault] `doc_not_found` for a name no doc carries, and
/// `argument_invalid` or `argument_missing` for a [codeTarget] the project
/// does not name.
List<IndexedDoc> _draftsUnder(
  _DraftSource source,
  List<String> names,
  String? codeTarget,
) {
  final index = source.index..checkCodeTarget(codeTarget);
  final selected = names.isEmpty
      ? null
      : {
          for (final name in names)
            for (final doc in index.under(name, codeTarget: codeTarget))
              doc.docPath,
        };
  return [
    for (final doc in index.docs)
      if (source.waitsFor(doc) &&
          (selected?.contains(doc.docPath) ?? true) &&
          doc.inTarget(codeTarget))
        doc,
  ];
}

/// What the draft views read: the index and project of a session, and the
/// bytes of a doc.
///
/// A write session reads through its own [WriteSession.readDocBytes]; a read
/// session has no byte-order mark to keep.
final class _DraftSource {
  const new({
    required this.index,
    required this.project,
    required this.readDocBytes,
  });

  factory ofWrite(WriteSession session) => _DraftSource(
    index: session.index,
    project: session.project,
    readDocBytes: session.readDocBytes,
  );

  factory ofRead(ReadSession session) => _DraftSource(
    index: session.index,
    project: session.project,
    readDocBytes: (docPath) => _readUtf8Bytes(session.project, docPath),
  );

  final DocIndex index;
  final DocsProject project;

  /// Returns the bytes of a doc by DocPath, or null for a file gone.
  final List<int>? Function(String docPath) readDocBytes;

  /// Whether the typed [doc] awaits approval, as [waitsForApproval] says.
  bool waitsFor(IndexedDoc doc) =>
      awaitsApproval(ApprovalFields.ofIndexed(doc), doc.approvalHash);
}

/// Returns the bytes of [docPath] as it is on disk, or null when the file is
/// gone.
///
/// Throws [RenderFault] `output_not_writable` for a file that cannot be read
/// or whose bytes are not UTF-8.
List<int>? _readUtf8Bytes(DocsProject project, String docPath) {
  final List<int> bytes;
  try {
    bytes = _fileOf(project, docPath).readAsBytesSync();
  } on PathNotFoundException {
    return null;
  } on FileSystemException catch (error) {
    throw cannotRead(docPath, error);
  }
  try {
    utf8.decode(bytes);
  } on FormatException {
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot read $docPath: not UTF-8 text',
    );
  }
  return bytes;
}

File _fileOf(DocsProject project, String docPath) => fileOfDocPath(
  docPath,
  docsRoot: project.docsRoot,
  projectRoot: project.projectRoot,
);

/// A draft and the bytes of its file at selection.
final class _ShownDraft {
  const new({required this.doc, required this.bytes});

  final IndexedDoc doc;
  final List<int> bytes;
}

/// Returns [_draftsUnder] with the bytes of each, less the drafts whose file
/// is gone, so the numbers `Draft n/m` count only drafts the Owner can see.
List<_ShownDraft> _shownDraftsUnder(
  _DraftSource source,
  List<String> names,
  String? codeTarget,
) {
  final shown = <_ShownDraft>[];
  for (final doc in _draftsUnder(source, names, codeTarget)) {
    final bytes = source.readDocBytes(doc.docPath);
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

  /// Reads the approved copy of each of [drafts], through [history] from the
  /// commit that holds the `approved:` mark the doc carries, else from the
  /// saved copy that mark names, else as git reports it, then the text of every
  /// doc the index lists, typed or not, as on disk.
  ///
  /// Throws `RenderFault` `output_not_writable` for a doc that cannot be read.
  factory read(
    _DraftSource source,
    List<_ShownDraft> drafts,
    ApprovalHistory history,
  ) {
    final lookups = <String, ApprovalLookup>{};
    final approved = <String, String>{};
    for (final _ShownDraft(:doc, :bytes) in drafts) {
      final type = source.index.typeOf(doc);
      final lookup = _approvedCopyLookupIn(
        source.index,
        source.project,
        doc,
        bytes,
        history,
      );
      lookups[doc.docPath] = lookup;
      switch (lookup) {
        case ApprovedCopy(:final text) || SavedApprovedCopy(:final text):
          approved[doc.docPath] = comparableTextOf(text, type);
        case NoApprovedCopy() || UnknownHistory():
      }
    }
    return _RunReads._(lookups, approved, {
      for (final doc in source.index.docs)
        doc.docPath: sentencesOf(_textOnDisk(source.project, doc.docPath))
            .toSet(),
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

/// Where the approved copy of [doc] holding [bytes] is: the commit [history]
/// finds that holds the `approved:` mark the doc carries, else the saved copy
/// that mark names, else as git reports it.
ApprovalLookup approvedCopyLookupOf(
  WriteSession session,
  IndexedDoc doc,
  List<int> bytes,
  ApprovalHistory history,
) => _approvedCopyLookupIn(session.index, session.project, doc, bytes, history);

ApprovalLookup _approvedCopyLookupIn(
  DocIndex index,
  DocsProject project,
  IndexedDoc doc,
  List<int> bytes,
  ApprovalHistory history,
) {
  final type = index.typeOf(doc);
  final markOnDisk = ApprovalFields.of(
    Doc.parse(toLf(utf8.decode(bytes, allowMalformed: true))),
  ).approvedValue;
  final committed = history.lastApproved(
    project.projectRoot,
    projectPathOfDocPath(doc.docPath),
    docType: type,
  );
  return _holdsMark(committed, markOnDisk)
      ? committed
      : ApprovedCopyStore(project.projectRoot).find(markOnDisk, type) ??
            committed;
}

/// Whether [lookup] is a committed copy whose own `approved:` value is [mark].
bool _holdsMark(ApprovalLookup lookup, Object? mark) =>
    lookup is ApprovedCopy &&
    ApprovalFields.of(Doc.parse(toLf(lookup.text))).approvedValue == mark;

Set<String> _unionOf(Iterable<Set<String>> sets) => {
  for (final set in sets) ...set,
};

bool _isSameSet(Set<String> a, Set<String>? b) =>
    b != null && a.length == b.length && a.containsAll(b);

/// Returns the LF text of [docPath] as it is on disk, or `''` for a file gone;
/// invalid UTF-8 reads as replacement characters, since this doc is only looked
/// in.
String _textOnDisk(DocsProject project, String docPath) {
  try {
    return toLf(
      utf8.decode(
        _fileOf(project, docPath).readAsBytesSync(),
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
  _DraftSource source,
  IndexedDoc doc,
  List<int> bytes,
  _RunReads reads,
  String? codeTarget,
) {
  final index = source.index;
  final type = index.typeOf(doc);
  final text = utf8.decode(bytes);
  final perTarget =
      index.hasTwins && codeTarget == null && isStatusTracked(doc);
  return DraftView(
    name: doc.name,
    address: index.addressOf(doc),
    // `waitsForApproval` kept only typed drafts, so the type id is set.
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
    projectPath: projectPathOfDocPath(doc.docPath),
    text: text,
    lookup: reads.lookupOf(doc),
    sentences: reads.changesOf(doc, text, type),
  );
}

/// Returns the approval view of the typed draft [doc] holding [bytes].
String _viewOf(
  _DraftSource source,
  IndexedDoc doc,
  List<int> bytes,
  _RunReads reads, {
  required int position,
  required int count,
  required int? context,
  required bool color,
  required String? codeTarget,
}) => renderApprovalView(
  _draftViewOf(source, doc, bytes, reads, codeTarget),
  position: position,
  count: count,
  context: context,
  color: color,
);

/// Writes the approval under the lock; returns false when the bytes changed.
///
/// Reads the index afresh first, so a peer commit during the prompt wait does
/// not make the lock rerun the walk; a draft the fresh index lacks is gone.
bool _approveIfUnchanged(
  WriteSession session,
  IndexedDoc shownDoc,
  List<int> shown,
) {
  session.refresh();
  // A draft the fresh index lacks still goes to the re-read under the lock,
  // which refuses a link out of the project and passes over a deleted file.
  final doc =
      session.index.docs
          .where((candidate) => candidate.docPath == shownDoc.docPath)
          .firstOrNull ??
      shownDoc;
  return session.locked(() {
    final current = session.readDocBytes(doc.docPath);
    if (current == null) return true;
    if (!_sameBytes(current, shown)) return false;
    writeApproval(session, doc, current);
    return true;
  });
}

/// Takes the lock and prunes the saved approved copies (see
/// [pruneApprovedCopiesLocked]); a busy lock skips it, as the next run prunes.
void _pruneApprovedCopies(WriteSession session) {
  try {
    session.locked(() => pruneApprovedCopiesLocked(session));
  } on IndexFault catch (fault) {
    if (fault.code != IndexFaultCode.indexBusy) rethrow;
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
