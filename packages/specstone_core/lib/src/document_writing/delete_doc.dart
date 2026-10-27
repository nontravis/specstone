import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/approve_drafts.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/own_segment.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/refs.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

/// The bytes of each file of a delete unit, by DocPath, sorted by code point.
typedef _UnitFiles = Map<String, List<int>>;

/// Moves the doc [address] names, with everything it owns, to the trash.
///
/// The unit is the doc's own segment plus the spec folders of its values; it
/// holds every file under them, whatever the extension. A doc outside the
/// unit that refers to a doc inside it refuses the delete, and no file moves.
/// An approved `.md` file in the unit (an untyped one included) leaves the
/// delete to the Owner: [prompts] lists the files and asks, one answer from
/// [readLine] outside the lock; anything but `y`, or the end of input, keeps
/// them all. When a file or its bytes change while the prompt waits, the list
/// shows again. Emptied folders go up to the docs root.
///
/// Throws [WriteFault] `doc_referenced` for a referred doc and
/// `owner_terminal_required` for an approved unit when [interactive] is
/// false; an `IndexFault` for an address that names no one typed doc;
/// `index_busy` when another call holds the lock.
ReadAnswer answerDelete(
  WriteSession session,
  String address, {
  required bool interactive,
  required String? Function() readLine,
  required StringSink prompts,
}) {
  final target = session.target(address);
  final roots = _unitRootsOf(session, target);
  _refuseIfReferenced(session, address, target, roots);
  while (true) {
    final shown = _readUnit(session, roots);
    if (_holdsApprovedDoc(shown)) {
      requireOwnerTerminal(
        interactive: interactive,
        message:
            '$address holds approved docs; only the Owner deletes them, at '
            'an interactive terminal',
      );
      prompts
        ..writeln(shown.keys.join('\n'))
        ..write('delete ${shown.length} files? [y/N] ');
      if (readLine() != 'y') return _answerFor(const []);
    }
    final removed = session.locked(() {
      final current = _readUnit(session, roots);
      if (!_sameFiles(current, shown)) return null;
      MoveJournal(_stepsFor(session, roots, current.keys)).run(session.project);
      return current.keys.toList();
    });
    if (removed != null) return _answerFor(removed);
  }
}

/// Returns the paths of the unit of [target]: its own segment, a folder
/// ending in `/` or the file, then the folders of its spec docs.
List<String> _unitRootsOf(WriteSession session, IndexedDoc target) {
  final set = session.index.set;
  final docType =
      session.index.typeOf(target) ??
      (throw StateError('${target.docPath} has no doc type'));
  final shape =
      DocPathShape.of(docType, set) ??
      (throw StateError('${docType.id} has no path'));
  final values =
      shape.valuesOf(target.docPath) ??
      (throw StateError('${target.docPath} does not match its doc type'));
  return [
    shape.ownPathOf(target.docPath),
    ...specFoldersOf(set, docType, values),
  ];
}

/// Throws [WriteFault] `doc_referenced` when a doc outside the unit refers
/// to a doc inside it.
void _refuseIfReferenced(
  WriteSession session,
  String address,
  IndexedDoc target,
  List<String> roots,
) {
  final inUnit = {for (final root in roots) ..._filesUnder(session, root)};
  final outside = <String>{};
  for (final doc in session.index.docs) {
    if (!inUnit.contains(doc.docPath)) continue;
    for (final from in referrersOf(session.index, doc)) {
      if (!inUnit.contains(from.docPath)) outside.add(from.docPath);
    }
  }
  if (outside.isEmpty) return;
  throw WriteFault(
    WriteFaultCode.docReferenced,
    'docs outside $address link into it',
    file: target.docPath,
    relatedFiles: [
      for (final doc in session.index.docs)
        if (outside.contains(doc.docPath)) doc.docPath,
    ],
  );
}

/// Returns the DocPath of every file under [root], a folder or a file.
Iterable<String> _filesUnder(WriteSession session, String root) sync* {
  if (!root.endsWith('/')) {
    if (session.fileOf(root).existsSync()) yield root;
    return;
  }
  final folder = Directory(
    session.fileOf(root.substring(0, root.length - 1)).path,
  );
  if (!folder.existsSync()) return;
  final prefixLength = session.project.docsRoot.path.length + 1;
  for (final entity in folder.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    yield entity.path
        .substring(prefixLength)
        .split(Platform.pathSeparator)
        .join('/');
  }
}

/// Reads every file of the unit; the keys are sorted by code point.
_UnitFiles _readUnit(WriteSession session, List<String> roots) {
  final docPaths = {
    for (final root in roots) ..._filesUnder(session, root),
  }.toList()..sort();
  final files = <String, List<int>>{};
  for (final docPath in docPaths) {
    try {
      files[docPath] = session.fileOf(docPath).readAsBytesSync();
    } on PathNotFoundException {
      continue;
    }
  }
  return files;
}

/// Whether a `.md` file of [files] was ever approved.
///
/// Bytes that are not UTF-8 cannot show a draft, so they count as approved.
bool _holdsApprovedDoc(_UnitFiles files) {
  for (final MapEntry(:key, :value) in files.entries) {
    if (!key.endsWith('.md')) continue;
    final String text;
    try {
      text = utf8.decode(value);
    } on FormatException {
      return true;
    }
    if (approvalOf(Doc.parse(toLf(text))) == .approved) return true;
  }
  return false;
}

bool _sameFiles(_UnitFiles a, _UnitFiles b) {
  if (a.length != b.length) return false;
  for (final MapEntry(:key, value: bytes) in a.entries) {
    final other = b[key];
    if (other == null || other.length != bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != other[i]) return false;
    }
  }
  return true;
}

/// Returns the journal steps: each file to the trash, then the pruning of
/// every folder the move may leave empty.
List<JournalStep> _stepsFor(
  WriteSession session,
  List<String> roots,
  Iterable<String> docPaths,
) {
  final projectPaths = [for (final p in docPaths) session.projectPathOf(p)];
  final folders = {
    for (final path in projectPaths) path.substring(0, path.lastIndexOf('/')),
    for (final root in roots)
      if (root.endsWith('/'))
        session.projectPathOf(root.substring(0, root.length - 1)),
  };
  return [
    for (final path in projectPaths)
      MoveStep(path, '${MoveJournal.trashPath}/files/$path'),
    for (final folder in folders) PruneStep(folder),
  ];
}

ReadAnswer _answerFor(List<String> removed) => ReadAnswer(
  text: [for (final docPath in removed) '$docPath\n'].join(),
  json: {'removed': removed},
);
