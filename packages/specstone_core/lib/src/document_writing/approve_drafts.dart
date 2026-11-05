import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approval_view.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

const _prompt = 'approve? [y/n/q] ';
const _nothingWaits = 'no draft waits for approval\n';

/// Shows each typed draft in tree order and approves it at the Owner's `y`.
///
/// The drafts are all of them, or those under any of [names], each once, less
/// any whose file is gone. Each shows its approval view (see
/// [renderApprovalView]) as `Draft n/m` over the drafts selected, with
/// [context] lines of context per hunk and ANSI [color] when set. Each prompt
/// waits outside the write lock; `y` re-reads the file under the lock and
/// writes only when its bytes are those the Owner saw, else the draft shows
/// again at the same position. `n` moves on; `q` and the end of input from
/// [readLine] end the walk; any other answer asks again. An approval removes
/// `draft` and adds `approved: true` unless the doc already holds it.
/// Reads every selected draft before the first view shows.
/// Throws [IndexFault] `doc_not_found` for a name no doc carries,
/// `RenderFault` `output_not_writable` for a draft that cannot be read or is
/// not UTF-8, both before any draft shows, and `index_busy` when another call
/// holds the lock; approvals already written stay.
void approveDrafts(
  WriteSession session, {
  List<String> names = const [],
  required String? Function() readLine,
  required StringSink out,
  int? context,
  bool color = false,
  ApprovalHistory? history,
}) {
  final drafts = _shownDraftsUnder(session, names);
  if (drafts.isEmpty) {
    out.write(_nothingWaits);
    return;
  }
  final lookup = history ?? const ApprovalHistory();
  for (final (at, (:doc, bytes: _)) in drafts.indexed) {
    String viewOf(List<int> bytes) => _viewOf(
      session,
      doc,
      bytes,
      lookup,
      position: at + 1,
      count: drafts.length,
      context: context,
      color: color,
    );
    if (!_approveOne(session, doc, viewOf, readLine, out)) return;
  }
}

/// Returns the approval view of each typed draft, for the chat; writes nothing.
///
/// The drafts and their `Draft n/m` numbers are those [approveDrafts] walks for
/// [names]. The text is their views joined by a blank line, else `no draft
/// waits for approval`; the JSON is `{}`. It takes no lock.
/// Throws [IndexFault] `doc_not_found` for a name no doc carries, and
/// `RenderFault` `output_not_writable` for a draft that cannot be read or is
/// not UTF-8, both before any view prints.
ReadAnswer approveDryRun(
  WriteSession session, {
  List<String> names = const [],
  int? context,
  bool color = false,
  ApprovalHistory? history,
}) {
  final drafts = _shownDraftsUnder(session, names);
  final lookup = history ?? const ApprovalHistory();
  final views = [
    for (final (at, (:doc, :bytes)) in drafts.indexed)
      _viewOf(
        session,
        doc,
        bytes,
        lookup,
        position: at + 1,
        count: drafts.length,
        context: context,
        color: color,
      ),
  ];
  return ReadAnswer(
    text: views.isEmpty ? _nothingWaits : views.join('\n'),
    json: const {},
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
/// draft, in tree order, and its JSON is `{"approved": [...]}`.
/// Throws [IndexFault] for a name that is no write target, [WriteFault]
/// `draft_not_found` for a doc that is no draft, `base_mismatch` naming each
/// draft whose text changed, and `index_busy` when another call holds the
/// lock.
ReadAnswer approveNamed(WriteSession session, List<SeenDraft> seen) {
  final hashesByPath = <String, Set<String>>{};
  for (final draft in seen) {
    final doc = _draftAt(session, draft.name);
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
IndexedDoc _draftAt(WriteSession session, String name) {
  final doc = session.target(name);
  if (!doc.isDraft) {
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

/// Returns the typed drafts in tree order: all of them when [names] is empty,
/// else those under any of [names], each once.
///
/// Throws [IndexFault] `doc_not_found` for a name no doc carries.
List<IndexedDoc> _draftsUnder(DocIndex index, List<String> names) {
  final selected = names.isEmpty
      ? null
      : {
          for (final name in names)
            for (final doc in index.under(name)) doc.docPath,
        };
  return [
    for (final doc in index.docs)
      if (_waitsForApproval(doc) && (selected?.contains(doc.docPath) ?? true))
        doc,
  ];
}

bool _waitsForApproval(IndexedDoc doc) => doc.isTyped && doc.isDraft;

/// A draft and the bytes of its file at selection.
typedef _ShownDraft = ({IndexedDoc doc, List<int> bytes});

/// Returns [_draftsUnder] with the bytes of each, less the drafts whose file
/// is gone, so the numbers `Draft n/m` count only drafts the Owner can see.
List<_ShownDraft> _shownDraftsUnder(WriteSession session, List<String> names) {
  final shown = <_ShownDraft>[];
  for (final doc in _draftsUnder(session.index, names)) {
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

/// Returns the approval view of the typed draft [doc] holding [bytes].
String _viewOf(
  WriteSession session,
  IndexedDoc doc,
  List<int> bytes,
  ApprovalHistory history, {
  required int position,
  required int count,
  required int? context,
  required bool color,
}) {
  final projectPath = session.projectPathOf(doc.docPath);
  final draft = DraftView(
    name: doc.name,
    // `_waitsForApproval` kept only typed drafts, so the type id is set.
    docType: doc.docTypeId!,
    mergedType: session.index.typeOf(doc),
    title: doc.title,
    status: session.index.statusOf(doc),
    projectPath: projectPath,
    text: utf8.decode(bytes),
    lookup: history.lastApproved(session.project.projectRoot, projectPath),
  );
  return renderApprovalView(
    draft,
    position: position,
    count: count,
    context: context,
    color: color,
  );
}

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

/// Writes [bytes] of [doc] back without `draft`, adding `approved: true`
/// unless the doc holds it; runs under the lock.
void _writeApproval(WriteSession session, IndexedDoc doc, List<int> bytes) {
  final text = utf8.decode(bytes);
  final lfText = toLf(text);
  final undrafted = withKeyBlock(lfText, 'draft', null);
  final approved = holdsApproved(Doc.parse(lfText))
      ? undrafted
      : withKeyBlock(
          undrafted,
          'approved',
          'approved: true\n',
          fieldOrder: _fieldOrderOf(session, doc),
        );
  session.writeDoc(doc.docPath, approved, LineEnding.of(text));
}

List<String>? _fieldOrderOf(WriteSession session, IndexedDoc doc) {
  final docType = session.index.typeOf(doc);
  return docType == null
      ? null
      : [for (final field in docType.fields) field.id];
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
