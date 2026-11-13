import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/tree_rules.dart';
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_path_shape.dart';
import 'package:specstone_core/src/doc_model/doc_splice.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/record_edit.dart';
import 'package:specstone_core/src/document_writing/stale_mentions.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/doc_mentions.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/index_query/refs.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';

/// The bytes of each file of a delete unit, by DocPath, sorted by code point.
typedef _UnitFiles = Map<String, List<int>>;

/// What one delete removes and rewrites: the files of the unit, and each
/// record outside it that loses entries, sorted by DocPath.
typedef _DeletePlan = ({_UnitFiles files, List<RecordEdit> records});

/// Moves the docs [targets] name, with everything each owns, to the trash.
///
/// A target is `<doc type>:<name>` or an untyped doc's DocPath. The unit is
/// each typed doc's own segment plus the spec folders of its values, and each
/// untyped doc's one file; it holds every file under them, whatever the
/// extension, each once. Every target resolves before any file is read, in
/// the order given, and the first refusal refuses the call. A doc outside the
/// unit that refers to a doc inside it refuses the delete, and no file moves,
/// except an untyped doc outside the checked folders, such as a plan: its link
/// is left to dangle, and the answer warns of each such link. A guarded
/// `.md` file in the unit (an untyped one included) leaves the delete to the
/// Owner, as [confirmation] says. At a terminal [prompts] lists
/// the files and each record the delete rewrites, and asks, one answer from
/// [readLine] outside the lock; anything but `y`, or the end of input, keeps
/// them all. After a `y` the index is read afresh, the targets resolve again,
/// and the referrers are checked again; when a file or a record changes while
/// the prompt waits, the list shows again. Under `--yes` the unit goes with
/// no prompt, as after a `y`, but only while its files and those records hash
/// to [planHash], the plan line of the dry run the Owner saw
/// ([answerDeleteDryRun]). Emptied folders go up to the docs root. Each
/// mention of a removed doc in a code file or an agent file is listed after the
/// removed paths, and no such file is written.
///
/// Each record, in every code target, outside the unit that holds an entry of
/// a story or FR of it loses that entry and becomes a draft, through the same
/// journal as the file moves; no record's approval guards the delete. A
/// feature's own records leave with its spec folder.
///
/// [codeTarget] keeps a name to that code target's docs and the shared docs.
///
/// [targets] is non-empty.
/// Throws [WriteFault] `doc_referenced` for a referred doc,
/// `owner_terminal_required` for a guarded unit the Owner cannot confirm,
/// and `plan_mismatch` under `--yes` for a list that changed since the dry
/// run; an `IndexFault` for an address that names neither one typed doc nor an
/// untyped doc's DocPath; `index_busy` when another call holds the lock.
ReadAnswer answerDelete(
  WriteSession session,
  List<String> targets, {
  required OwnerConfirmation confirmation,
  required String? Function() readLine,
  required StringSink prompts,
  String? planHash,
  String? codeTarget,
}) {
  var unit = _resolveTargets(session, targets, codeTarget);
  var dangling = _checkReferrers(session, unit);
  while (true) {
    final shown = _planOf(session, unit.roots);
    if (confirmation == OwnerConfirmation.given &&
        planHash != _planHashOf(shown)) {
      throw WriteFault(
        WriteFaultCode.planMismatch,
        'the delete list is not the one the Owner saw in the dry run; run '
        'specstone delete --dry-run again, show it, and ask for a new ok',
      );
    }
    final guarded = _holdsGuardedDoc(shown.files);
    if (guarded) {
      confirmation.refuseIfMissing(
        '${unit.subject} holds guarded docs; only the Owner deletes them,',
      );
    }
    if (guarded && confirmation.prompts) {
      session.journalTarget.requireTrusted();
      MoveJournal.requireHomeFolder(
        session.journalTarget.homeDirectory,
        session.project.projectRoot,
      );
      prompts
        ..writeln(shown.files.keys.join('\n'))
        ..write(_rewritesOf(shown))
        ..write('delete ${shown.files.length} files? [y/N] ');
      if (readLine() != 'y') return _answerFor(const []);
      session.refresh();
      unit = _resolveTargets(session, targets, codeTarget);
      dangling = _checkReferrers(session, unit);
    }
    final roots = unit.roots;
    final removed = session.locked(() {
      final current = _planOf(session, roots);
      if (!_samePlan(current, shown)) return null;
      final mentions = _mentionsOf(session, current);
      MoveJournal(_stepsFor(session, roots, current))
          .run(session.journalTarget);
      return (files: current.files.keys.toList(), mentions: mentions);
    });
    if (removed != null) {
      return _answerFor(
        removed.files,
        mentions: removed.mentions,
        warnings: dangling,
      );
    }
  }
}

/// Lists every file a delete of [targets] would remove, each record it
/// rewrites, and its plan line.
///
/// The list is the one the terminal prompt shows before its `y`, and nothing
/// is removed. The text is the files, one `rewrites <DocPath>: <entry>, …` line
/// per record, one `mentions <path>:<line> <mention>` line per mention of a
/// removed doc in a code file or an agent file, the `plan <hash>` line, and
/// `dry run: nothing removed`; the JSON holds `files`, `records` (each with its
/// `path` and `entries`), `mentions`, and `plan`. Warns of each link left to
/// dangle, and throws, as [answerDelete] does before its prompt.
ReadAnswer answerDeleteDryRun(
  WriteSession session,
  List<String> targets, {
  String? codeTarget,
}) {
  final unit = _resolveTargets(session, targets, codeTarget);
  final dangling = _checkReferrers(session, unit);
  final plan = _planOf(session, unit.roots);
  final files = plan.files.keys.toList();
  final hash = _planHashOf(plan);
  final mentions = _mentionsOf(session, plan);
  return ReadAnswer(
    text:
        '${_listOf(files)}${_rewritesOf(plan)}${_mentionLinesOf(mentions)}'
        'plan $hash\ndry run: nothing removed\n',
    json: {
      'files': files,
      'records': [
        for (final record in plan.records)
          {'path': record.docPath, 'entries': record.entries},
      ],
      'mentions': mentionsJsonOf(mentions),
      'plan': hash,
    },
    warnings: dangling,
  );
}

/// Returns the plan hash of a delete: its files, then each record it rewrites.
///
/// It covers each listed path with the hash of its text, as `bases.doc` hashes
/// a doc, so an edit to a listed file or record, committed or not, changes it.
String _planHashOf(_DeletePlan plan) => baseHashOf(
  [
    for (final MapEntry(key: docPath, value: bytes) in plan.files.entries)
      '$docPath ${_textHashOf(bytes)}\n',
    for (final record in plan.records)
      '${record.docPath} ${_textHashOf(record.bytes)}\n',
  ].join(),
);

/// Returns the `bases.doc` hash of [bytes] when they are UTF-8 text, else the
/// hash of the bytes themselves, so no two different binary files hash alike.
String _textHashOf(List<int> bytes) {
  try {
    return baseHashOf(toLf(utf8.decode(bytes)));
  } on FormatException {
    // Latin-1 maps each byte to one code point, so the text keeps every byte.
    return baseHashOf(latin1.decode(bytes));
  }
}

String _listOf(Iterable<String> docPaths) =>
    docPaths.map((docPath) => '$docPath\n').join();

/// Returns one `rewrites <DocPath>: <entry>, …` line per record of [plan].
String _rewritesOf(_DeletePlan plan) => [
  for (final record in plan.records)
    'rewrites ${record.docPath}: ${record.entries.join(', ')}\n',
].join();

/// Returns the mentions in code files and agent files of the docs [plan]
/// removes.
List<StaleMention> _mentionsOf(WriteSession session, _DeletePlan plan) =>
    staleMentions(session, [
      for (final docPath in plan.files.keys) (from: docPath, to: removedPath),
    ], namesChange: true);

String _mentionLinesOf(List<StaleMention> mentions) =>
    mentions.map(mentionLineOf).join();

/// The resolved targets of a delete call, in the order given.
class _DeleteSet(
  final List<({String address, String docPath, List<String> roots})> targets,
) {
  /// The roots of every target, each once, in the order given.
  List<String> get roots =>
      {for (final target in targets) ...target.roots}.toList();

  /// Names the set in a refusal: the one address, or the set.
  String get subject =>
      targets.length == 1 ? targets.single.address : 'the delete set';
}

/// Resolves every target of [targets], in the order given.
///
/// A target is untyped when it names one doc, with no doc type, by its DocPath
/// or another path; every other target goes through [WriteSession.target].
/// [codeTarget] keeps a name to that code target's docs and the shared docs.
_DeleteSet _resolveTargets(
  WriteSession session,
  List<String> targets,
  String? codeTarget,
) {
  return _DeleteSet([
    for (final address in targets)
      switch (_untypedDocAt(session, address, codeTarget)) {
        final untyped? => (
          address: address,
          docPath: untyped.docPath,
          roots: [untyped.docPath],
        ),
        null => _typedTarget(session, address, codeTarget),
      },
  ]);
}

({String address, String docPath, List<String> roots}) _typedTarget(
  WriteSession session,
  String address,
  String? codeTarget,
) {
  final doc = session.target(address, codeTarget: codeTarget);
  return (
    address: address,
    docPath: doc.docPath,
    roots: _unitRootsOf(session, doc),
  );
}

/// Returns the one doc with no doc type that [address] names, else null.
IndexedDoc? _untypedDocAt(
  WriteSession session,
  String address,
  String? codeTarget,
) {
  final List<IndexedDoc> found;
  try {
    found = session.index.resolve(address, codeTarget: codeTarget);
  } on Exception {
    // A name no untyped doc carries; WriteSession.target gives the refusal.
    return null;
  }
  return switch (found) {
    [final doc] when doc.docTypeId == null => doc,
    _ => null,
  };
}

/// Returns the paths of the unit of [target]: its own segment, a folder
/// ending in `/` or the file, then the folders of its spec docs.
List<String> _unitRootsOf(WriteSession session, IndexedDoc target) {
  final set = session.index.set;
  final docType =
      session.index.typeOf(target) ??
      (throw StateError('${target.docPath} has no doc type'));
  final roots = unitRootsOf(
    set,
    docType,
    target.docPath,
    targetNames: session.index.twinNames,
    target: target.target,
  );
  if (roots != null) return roots;
  throw StateError(
    DocPathShape.ofDoc(docType, set, target.docPath, target: target.target) ==
            null
        ? '${docType.id} has no path'
        : '${target.docPath} does not match the path of ${docType.id}',
  );
}

/// Returns a warning per link a history file holds into the unit, then one
/// per typed doc outside the unit that mentions a doc of it, each in tree
/// order of the linked or mentioned docs.
///
/// A history file, such as a plan, is an untyped doc outside the checked
/// folders: no write repoints it and no check reads it, so its link dangles.
/// A mention, a path written in text or a doc-name mention in a code span
/// (RULE-11), dangles without blocking. Throws [WriteFault] `doc_referenced`
/// when any other doc outside the unit refers to a doc inside it.
List<String> _checkReferrers(WriteSession session, _DeleteSet unit) {
  final inUnit = {for (final root in unit.roots) ..._filesUnder(session, root)};
  final checkedFolders = checkedFoldersOf(session.index.set);
  final blocking = <String>{};
  final dangling = <String>[];
  for (final doc in session.index.docs) {
    if (!inUnit.contains(doc.docPath)) continue;
    for (final from in referrersOf(session.index, doc)) {
      if (inUnit.contains(from.docPath)) continue;
      if (_isHistory(from, checkedFolders)) {
        dangling.add(
          '${from.docPath} links into ${doc.docPath}; the link will dangle',
        );
      } else {
        blocking.add(from.docPath);
      }
    }
  }
  if (blocking.isNotEmpty) _refuseReferred(session, unit, blocking);
  return [...dangling, ..._mentionWarnings(session, inUnit)];
}

/// Returns a warning per pair of a doc of the unit and a typed doc outside it
/// that mentions it, in tree order of the mentioned docs, then of the
/// mentioning docs. A doc that also links into the unit has refused the
/// delete before this runs.
List<String> _mentionWarnings(WriteSession session, Set<String> inUnit) {
  final warnings = <String>[];
  final unit = [
    for (final doc in session.index.docs)
      if (inUnit.contains(doc.docPath)) doc,
  ];
  final mentionsByDoc = mentionsOfEach(session.index, unit);
  for (final doc in unit) {
    final from = {
      for (final mention in mentionsByDoc[doc.docPath]!)
        if (mention.doc.isTyped && !inUnit.contains(mention.doc.docPath))
          mention.doc.docPath,
    };
    for (final path in from) {
      warnings.add('$path mentions ${doc.docPath}; the mention will dangle');
    }
  }
  return warnings;
}

/// Whether [doc] is untyped and lies outside every folder in [checkedFolders].
bool _isHistory(IndexedDoc doc, Set<String> checkedFolders) =>
    !doc.isTyped && !checkedFolders.contains(doc.docPath.split('/').first);

/// Throws [WriteFault] `doc_referenced`, naming the docs in [outside].
Never _refuseReferred(
  WriteSession session,
  _DeleteSet unit,
  Set<String> outside,
) {
  throw WriteFault(
    WriteFaultCode.docReferenced,
    'docs outside ${unit.subject} link into it',
    file: _firstReferredTarget(session, unit, outside),
    relatedFiles: [
      for (final doc in session.index.docs)
        if (outside.contains(doc.docPath)) doc.docPath,
    ],
  );
}

/// Returns the DocPath of the first target, in the order given, that a doc in
/// [outside] links into.
String _firstReferredTarget(
  WriteSession session,
  _DeleteSet unit,
  Set<String> outside,
) {
  for (final target in unit.targets) {
    final files = {
      for (final root in target.roots) ..._filesUnder(session, root),
    };
    for (final doc in session.index.docs) {
      if (!files.contains(doc.docPath)) continue;
      for (final from in referrersOf(session.index, doc)) {
        if (outside.contains(from.docPath)) return target.docPath;
      }
    }
  }
  throw StateError('no target is referred to');
}

/// Returns the DocPath of every entry under [root], a folder or a file, that
/// is no folder; a symbolic link counts and is never followed.
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
  final List<FileSystemEntity> entities;
  try {
    entities = folder.listSync(recursive: true, followLinks: false);
  } on FileSystemException catch (error) {
    throw cannotRead(root.substring(0, root.length - 1), error);
  }
  for (final entity in entities) {
    if (entity is Directory) continue;
    yield entity.path
        .substring(prefixLength)
        .split(Platform.pathSeparator)
        .join('/');
  }
}

/// Returns the project path of every folder under [root], a folder ending
/// in `/`.
Iterable<String> _foldersUnder(WriteSession session, String root) sync* {
  final folder = Directory(
    session.fileOf(root.substring(0, root.length - 1)).path,
  );
  if (!folder.existsSync()) return;
  final prefixLength = session.project.docsRoot.path.length + 1;
  for (final entity in folder.listSync(recursive: true, followLinks: false)) {
    if (entity is! Directory) continue;
    yield session.projectPathOf(
      entity.path
          .substring(prefixLength)
          .split(Platform.pathSeparator)
          .join('/'),
    );
  }
}

/// Reads the files of the unit and the records that lose entries with it.
_DeletePlan _planOf(WriteSession session, List<String> roots) {
  final files = _readUnit(session, roots);
  return (files: files, records: recordEditsOf(session, files.keys.toSet()));
}

/// Reads every file of the unit; the keys are sorted by code point.
///
/// A symbolic link is never followed: its bytes are its target text.
_UnitFiles _readUnit(WriteSession session, List<String> roots) {
  final docPaths = {
    for (final root in roots) ..._filesUnder(session, root),
  }.toList()..sort();
  final files = <String, List<int>>{};
  for (final docPath in docPaths) {
    final file = session.fileOf(docPath);
    try {
      files[docPath] = FileSystemEntity.isLinkSync(file.path)
          ? utf8.encode(Link(file.path).targetSync())
          : file.readAsBytesSync();
    } on PathNotFoundException {
      continue;
    } on FileSystemException catch (error) {
      throw cannotRead(docPath, error);
    }
  }
  return files;
}

/// Whether a `.md` file of [files] is guarded (INV-7).
///
/// Bytes that are not UTF-8 cannot show a draft, so they count as guarded.
bool _holdsGuardedDoc(_UnitFiles files) {
  for (final MapEntry(:key, :value) in files.entries) {
    if (!key.endsWith('.md')) continue;
    final String text;
    try {
      text = utf8.decode(value);
    } on FormatException {
      return true;
    }
    if (isGuarded(ApprovalFields.of(Doc.parse(toLf(text))))) return true;
  }
  return false;
}

bool _samePlan(_DeletePlan a, _DeletePlan b) =>
    _sameFiles(a.files, b.files) &&
    _sameFiles(_recordBytesOf(a), _recordBytesOf(b));

_UnitFiles _recordBytesOf(_DeletePlan plan) => {
  for (final record in plan.records) record.docPath: record.bytes,
};

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
/// every folder the move may leave empty, the deepest first, then the write
/// of each record that loses entries.
List<JournalStep> _stepsFor(
  WriteSession session,
  List<String> roots,
  _DeletePlan plan,
) {
  final projectPaths = [
    for (final p in plan.files.keys) session.projectPathOf(p),
  ];
  final folders = {
    for (final path in projectPaths) path.substring(0, path.lastIndexOf('/')),
    for (final root in roots)
      if (root.endsWith('/')) ...[
        session.projectPathOf(root.substring(0, root.length - 1)),
        ..._foldersUnder(session, root),
      ],
  }.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final path in projectPaths)
      MoveStep(path, '${MoveJournal.trashPath}/files/$path'),
    for (final folder in folders) PruneStep(folder),
    for (final record in plan.records) recordStepOf(session, record),
  ];
}

ReadAnswer _answerFor(
  List<String> removed, {
  List<StaleMention> mentions = const [],
  List<String> warnings = const [],
}) => ReadAnswer(
  text:
      '${[for (final docPath in removed) '$docPath\n'].join()}'
      '${_mentionLinesOf(mentions)}',
  json: {'removed': removed, 'mentions': mentionsJsonOf(mentions)},
  warnings: warnings,
);
