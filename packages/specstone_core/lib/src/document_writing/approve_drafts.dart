import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

const _prompt = 'approve? [y/n/q] ';

/// Refuses unless the command runs at an interactive terminal.
///
/// Throws [WriteFault] `owner_terminal_required` with [message] when
/// [interactive] is false.
void requireOwnerTerminal({
  required bool interactive,
  required String message,
}) {
  if (!interactive) {
    throw WriteFault(WriteFaultCode.ownerTerminalRequired, message);
  }
}

/// Shows each typed draft in tree order and approves it at the Owner's `y`.
///
/// The drafts are all of them, or those under [name]. Each prompt waits
/// outside the write lock; `y` re-reads the file under the lock and writes
/// only when its bytes are those the Owner saw, else the draft shows again.
/// A draft with an approved copy in git shows the hunks changed since, else
/// the whole file. `n` moves on; `q` and the end of input from [readLine] end
/// the walk; any other answer asks again. An approval removes `draft` and
/// adds `approved: true` unless the doc already holds it.
/// Throws [IndexFault] `doc_not_found` for a [name] no doc carries and
/// `index_busy` when another call holds the lock; approvals already
/// written stay.
void approveDrafts(
  WriteSession session, {
  String? name,
  required String? Function() readLine,
  required StringSink out,
  ApprovalHistory? history,
}) {
  final drafts = [
    for (final doc
        in name == null ? session.index.docs : session.index.under(name))
      if (doc.isTyped && doc.isDraft) doc,
  ];
  if (drafts.isEmpty) {
    out.write('no draft waits for approval\n');
    return;
  }
  final lookup = history ?? const ApprovalHistory();
  for (final doc in drafts) {
    if (!_approveOne(session, doc, lookup, readLine, out)) return;
  }
}

/// Walks one draft to its answer; returns false when the walk ends.
bool _approveOne(
  WriteSession session,
  IndexedDoc doc,
  ApprovalHistory history,
  String? Function() readLine,
  StringSink out,
) {
  final file = session.fileOf(doc.docPath);
  while (true) {
    final shown = _readBytes(file);
    if (shown == null) return true;
    final text = utf8.decode(shown, allowMalformed: true);
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
  final file = session.fileOf(doc.docPath);
  return session.locked(() {
    final current = _readBytes(file);
    if (current == null) return true;
    if (!_sameBytes(current, shown)) return false;
    final text = utf8.decode(current, allowMalformed: true);
    final lfText = toLf(text);
    final undrafted = withKeyBlock(lfText, 'draft', null);
    final approved = holdsApproved(Doc.parse(lfText))
        ? undrafted
        : withKeyBlock(undrafted, 'approved', 'approved: true\n');
    session.writeDoc(doc.docPath, approved, LineEnding.of(text));
    return true;
  });
}

List<int>? _readBytes(File file) {
  try {
    return file.readAsBytesSync();
  } on PathNotFoundException {
    return null;
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
