import 'dart:convert';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

const _prompt = 'approve? [y/n/q] ';

/// How the Owner confirms a write that only the Owner may make.
enum OwnerConfirmation {
  /// Stdin and stdout are an interactive terminal: the command asks first.
  prompt,

  /// `--yes`: the Owner's ok came before the call, in Claude Code.
  given,

  /// Neither way: the write refuses.
  missing;

  /// Returns the confirmation of a call; [yes] (`--yes`) wins over a terminal.
  ///
  /// - [interactive]: whether stdin and stdout are both terminals.
  factory of({required bool yes, required bool interactive}) => yes
      ? .given
      : interactive
      ? .prompt
      : .missing;

  /// Whether the command asks the Owner at the terminal before it writes.
  bool get prompts => this == .prompt;

  /// Refuses when the Owner can confirm neither way.
  ///
  /// Throws [WriteFault] `owner_terminal_required` for [missing]; its message
  /// is [lead] followed by the two ways the Owner confirms.
  void refuseIfMissing(String lead) {
    if (this != .missing) return;
    throw WriteFault(
      WriteFaultCode.ownerTerminalRequired,
      "$lead at an interactive terminal, or with --yes after the Owner's ok "
      'in Claude Code',
    );
  }
}

/// Shows each typed draft in tree order and approves it at the Owner's `y`.
///
/// The drafts are all of them, or those under any of [names], each once. Each
/// prompt waits outside the write lock; `y` re-reads the file under the lock
/// and writes only when its bytes are those the Owner saw, else the draft
/// shows again. A draft with an approved copy in git shows the hunks changed
/// since, else the whole file. `n` moves on; `q` and the end of input from
/// [readLine] end the walk; any other answer asks again. An approval removes
/// `draft` and adds `approved: true` unless the doc already holds it.
/// Throws [IndexFault] `doc_not_found` for a name no doc carries, before any
/// draft shows, and `index_busy` when another call holds the lock; approvals
/// already written stay.
void approveDrafts(
  WriteSession session, {
  List<String> names = const [],
  required String? Function() readLine,
  required StringSink out,
  ApprovalHistory? history,
}) {
  final drafts = _draftsUnder(session.index, names);
  if (drafts.isEmpty) {
    out.write('no draft waits for approval\n');
    return;
  }
  final lookup = history ?? const ApprovalHistory();
  for (final doc in drafts) {
    if (!_approveOne(session, doc, lookup, readLine, out)) return;
  }
}

/// Approves every typed draft under [names] with no prompt, as `y` does.
///
/// The Owner gave the ok in Claude Code first (`--yes`). Every name resolves
/// and selects a draft before the first write, so a refused name approves
/// nothing. The answer prints `approved <doc type>:<name>` per draft, in tree
/// order, and its JSON is `{"approved": [...]}`.
/// Throws [IndexFault] `doc_not_found` for a name no doc carries, [WriteFault]
/// `draft_not_found` for a name with no draft under it, and `index_busy` when
/// another call holds the lock.
ReadAnswer approveNamed(WriteSession session, List<String> names) {
  final index = session.index;
  for (final name in names) {
    if (!index.under(name).any(_waitsForApproval)) {
      throw WriteFault(
        WriteFaultCode.draftNotFound,
        'no draft waits for approval under $name',
      );
    }
  }
  final drafts = _draftsUnder(index, names);
  final approved = session.locked(() {
    final written = <String>[];
    for (final doc in drafts) {
      final current = session.readDocBytes(doc.docPath);
      if (current == null) continue;
      _writeApproval(session, doc, current);
      written.add('${doc.docTypeId}:${doc.name}');
    }
    return written;
  });
  return ReadAnswer(
    text: approved.map((address) => 'approved $address\n').join(),
    json: {'approved': approved},
  );
}

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

/// Walks one draft to its answer; returns false when the walk ends.
bool _approveOne(
  WriteSession session,
  IndexedDoc doc,
  ApprovalHistory history,
  String? Function() readLine,
  StringSink out,
) {
  while (true) {
    final shown = session.readDocBytes(doc.docPath);
    if (shown == null) return true;
    final text = utf8.decode(shown);
    out
      ..write('${namingLine(doc)}\n')
      ..write(_viewOf(session, doc, history, text))
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

String _viewOf(
  WriteSession session,
  IndexedDoc doc,
  ApprovalHistory history,
  String text,
) {
  final approved = history.lastApproved(
    session.project.projectRoot,
    session.projectPathOf(doc.docPath),
  );
  if (approved is ApprovedCopy) return changedHunks(approved.text, text);
  return text.endsWith('\n') ? text : '$text\n';
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
      : withKeyBlock(undrafted, 'approved', 'approved: true\n');
  session.writeDoc(doc.docPath, approved, LineEnding.of(text));
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
