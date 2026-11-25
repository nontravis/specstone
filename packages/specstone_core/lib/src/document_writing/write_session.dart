import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart'
    as check_run;
import 'package:specstone_core/src/consistency_check/mermaid_node_run.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/doc_model/records_root.dart';
import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show bomOf, startsWithUtf8Bom, utf8Bom;
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/models/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/project_config.dart'
    show projectConfigPath;
import 'package:specstone_core/src/templates/template_resolver.dart';

/// How many times [WriteSession.run] runs a command whose read snapshot a peer
/// commit keeps making stale before it gives up.
const _runAttempts = 3;

/// Thrown by [WriteSession.locked] for a snapshot a peer commit made stale;
/// [WriteSession.run] catches it and runs the command again.
final class _StaleSnapshot implements Exception {
  const new();
}

/// One write command's view of a project: a replayed journal, a resolved
/// index, and the write lock on demand.
///
/// [run] opens a session, runs one command body in it, and closes it.
final class WriteSession {
  new _(
    this._read,
    this._templates,
    this._workingDirectory,
    this._homeDirectory,
    this._busyTimeout,
    this._warnings,
  );

  /// Opens the project holding [workingDirectory], finishes an unfinished
  /// move journal, runs [body], and closes the index.
  ///
  /// The journal replays inside the write lock before any name resolves, so
  /// [body] sees the tree the interrupted command meant to leave.
  /// [homeDirectory] is where user-level doc types are read from; null reads
  /// none. A fault from the project, the templates, the replay, or [body]
  /// propagates unchanged.
  ///
  /// When a peer commits to the index between the session's read snapshot and
  /// the first [locked] call, [body] runs again on a fresh session, up to
  /// [_runAttempts] runs in all; the stale run writes nothing. So [body] must
  /// write no file and print nothing before its first [locked] call, except a
  /// prompt the Owner answers again.
  ///
  /// Every warning of the run lands in [warnings], when given, in the order
  /// [WriteSession.warnings] states, whether [body] returns or a fault
  /// propagates; it also holds those of a stale run's session.
  /// Throws [IndexFault] `index_busy` when every run was stale.
  static T run<T>(
    T Function(WriteSession session) body, {
    required TemplateResolver templates,
    required Directory workingDirectory,
    required Directory? homeDirectory,
    Duration busyTimeout = indexBusyTimeout,
    List<String>? warnings,
  }) {
    final collected = warnings ?? <String>[];
    for (var attempt = 1; ; attempt++) {
      final session = _openAttempt(
        templates,
        workingDirectory,
        homeDirectory,
        busyTimeout,
        collected,
      );
      try {
        return body(session);
      } on _StaleSnapshot {
        _requireAnotherAttempt(attempt);
      } finally {
        session._close();
      }
    }
  }

  /// Opens a session as [run] does and returns what [body] awaits from it.
  ///
  /// Reruns [body] on a stale snapshot as [run] does, with the same limits on
  /// what [body] does before its first [lockedAsync] call.
  /// Collects the run's warnings into [warnings] as [run] does.
  /// Throws [IndexFault] `index_busy` when every run was stale.
  static Future<T> runAsync<T>(
    Future<T> Function(WriteSession session) body, {
    required TemplateResolver templates,
    required Directory workingDirectory,
    required Directory? homeDirectory,
    Duration busyTimeout = indexBusyTimeout,
    List<String>? warnings,
  }) async {
    final collected = warnings ?? <String>[];
    for (var attempt = 1; ; attempt++) {
      final session = _openAttempt(
        templates,
        workingDirectory,
        homeDirectory,
        busyTimeout,
        collected,
      );
      try {
        return await body(session);
      } on _StaleSnapshot {
        _requireAnotherAttempt(attempt);
      } finally {
        session._close();
      }
    }
  }

  static WriteSession _openAttempt(
    TemplateResolver templates,
    Directory workingDirectory,
    Directory? homeDirectory,
    Duration busyTimeout,
    List<String> warnings,
  ) {
    refuseMigratePending(workingDirectory, homeDirectory: homeDirectory);
    return WriteSession._(
      _openReplayed(
        templates: templates,
        workingDirectory: workingDirectory,
        homeDirectory: homeDirectory,
        busyTimeout: busyTimeout,
        warnings: warnings,
      ),
      templates,
      workingDirectory,
      homeDirectory,
      busyTimeout,
      warnings,
    ).._collectSnapshotWarnings();
  }

  static void _requireAnotherAttempt(int attempt) {
    if (attempt == _runAttempts) {
      throw IndexFault(IndexFaultCode.indexBusy, indexBusyMessage);
    }
  }

  final TemplateResolver _templates;
  final Directory _workingDirectory;
  final Directory? _homeDirectory;
  final Duration _busyTimeout;

  /// The warnings of the whole run, owned by the caller of [run] and shared by
  /// every attempt and every snapshot of it.
  final List<String> _warnings;
  ReadSession _read;
  bool _snapshotOpen = true;
  bool _closed = false;
  bool _inLockedAsync = false;

  /// The view [index] answers with while [withPlannedDocs] runs its body.
  DocIndex? _plannedView;

  /// The DocPaths whose last [readDocBytes] began with a UTF-8 BOM.
  final _bomDocs = <String>{};

  /// Opens the project afresh and finishes an unfinished move journal, so the
  /// session sees the tree as it is now.
  ///
  /// Call it outside the write lock, after a wait that let another command
  /// write; [index] and [project] are new objects afterwards.
  void refresh() {
    refuseMigratePending(_workingDirectory, homeDirectory: _homeDirectory);
    _close();
    _read = _openReplayed(
      templates: _templates,
      workingDirectory: _workingDirectory,
      homeDirectory: _homeDirectory,
      busyTimeout: _busyTimeout,
      warnings: _warnings,
    );
    _collectSnapshotWarnings();
    _closed = false;
    _snapshotOpen = true;
    _bomDocs.clear();
  }

  /// The project the session writes.
  DocsProject get project => _read.project;

  /// The target a move journal of the session runs on.
  ///
  /// Its warnings join [warnings].
  JournalTarget get journalTarget => JournalTarget.of(
    project,
    homeDirectory: _homeDirectory,
    warn: _warnings.add,
  );

  /// The docs of the session's snapshot, with their names and parent tree;
  /// inside [withPlannedDocs], with the docs it plans after them.
  DocIndex get index => _plannedView ?? _read.index;

  /// The docs of the session's snapshot alone, even inside [withPlannedDocs]:
  /// a doc it lacks is one the call creates.
  DocIndex get snapshotIndex => _read.index;

  /// Returns what [body] returns while [index] also holds [planned], the docs
  /// the call creates, each answering `contentOf` from [contents] by DocPath.
  ///
  /// Every planner of one write then sees the docs its own call creates. An
  /// empty [planned] runs [body] on the snapshot.
  T withPlannedDocs<T>(
    List<IndexedDoc> planned,
    Map<String, DocContent> contents,
    T Function() body,
  ) {
    _plannedView = _read.index.withPlanned(planned, contents: contents);
    try {
      return body();
    } finally {
      _plannedView = null;
    }
  }

  /// The warnings of the run so far, in the order they arose: the open before
  /// a pending journal's replay, the replay's, then each snapshot's (the
  /// store's, the refresh's, then each doc's in tree order), a later snapshot
  /// adding only those not yet listed, and any a journal run through
  /// [journalTarget] raises.
  ///
  /// The list is live: it grows as the run goes on.
  List<String> get warnings => _warnings;

  void _collectSnapshotWarnings() => _addUnlisted(_warnings, _read.warnings);

  /// Returns a check context over the session's index that reads [contents],
  /// by DocPath, in place of those docs' indexed content.
  CheckContext checkContext({Map<String, DocContent> contents = const {}}) =>
      CheckContext(_read, contents: contents);

  /// Returns the file of [docPath], a path relative to the docs root or a
  /// records DocPath.
  File fileOf(String docPath) => fileOfDocPath(
    docPath,
    docsRoot: project.docsRoot,
    projectRoot: project.projectRoot,
  );

  /// Returns [docPath] as a journal step takes it: relative to the project
  /// root and `/`-separated.
  String projectPathOf(String docPath) => projectPathOfDocPath(docPath);

  /// Returns the DocPath of [projectPath], the inverse of [projectPathOf], or
  /// null when it lies under neither root.
  String? docPathOf(String projectPath) => docPathOfProjectPath(projectPath);

  /// Returns [projectPath] as a write is listed: a doc by its DocPath, any
  /// other file, a code file, by its project path; a record's two are one.
  String listedPathOf(String projectPath) =>
      docPathOf(projectPath) ?? projectPath;

  /// Returns the one typed doc [address] names.
  ///
  /// [address] is read as [DocIndex.resolve] reads it, [codeTarget] included,
  /// among the docs the index holds and [planned] ([DocIndex.withPlanned]).
  /// Throws [IndexFault] `untyped_target` for a doc with no doc type and
  /// `argument_invalid` for an address that names 2 or more docs, listing each
  /// as `<doc type>:<name>` or its DocPath, or whose end 2 or more names share;
  /// `doc_not_found` when it names none; a `TemplateFault` passes through.
  IndexedDoc target(
    String address, {
    String? codeTarget,
    List<IndexedDoc> planned = const [],
  }) => typedTargetOf(
    index.withPlanned(planned),
    address,
    codeTarget: codeTarget,
  );

  /// Returns the one doc of [parentTypeId] among the docs [value] names.
  ///
  /// [value] is read as [target] reads it, [planned] included, with
  /// [parentTypeId] as its doc type when it names none; only the docs of
  /// [parentTypeId] count.
  /// Throws [IndexFault] `doc_not_found` naming [value] when none counts and
  /// `argument_invalid` when 2 or more count, when 2 or more names end with
  /// [value], or for a `#` or `@` suffix; a `TemplateFault` passes through.
  IndexedDoc parentTarget(
    String value,
    String parentTypeId, {
    String? codeTarget,
    List<IndexedDoc> planned = const [],
  }) {
    final names = index.withPlanned(planned);
    final List<IndexedDoc> named;
    try {
      final hasTypePrefix = readDocAddress(value).typeId != null;
      named = names.resolve(
        hasTypePrefix ? value : '$parentTypeId:$value',
        codeTarget: codeTarget,
      );
    } on IndexFault catch (fault) {
      if (fault.code != IndexFaultCode.docNotFound) rethrow;
      throw _noParent(parentTypeId, value);
    }
    final parents = [
      for (final doc in named)
        if (doc.docTypeId == parentTypeId) doc,
    ];
    if (parents.isEmpty) throw _noParent(parentTypeId, value);
    if (parents.length > 1) {
      throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '$value names ${parents.length} $parentTypeId docs: '
        '${parents.map(names.addressOf).join(', ')}',
      );
    }
    return parents.single;
  }

  /// Runs [act] inside the index write lock and returns its result.
  ///
  /// The first call ends the read snapshot and, when a peer committed since it
  /// began, rolls back without running [act] and has [run] start the command
  /// again. A fault from [act] rolls back and propagates.
  /// Throws [IndexFault] `index_busy` when another call holds the lock past
  /// the busy timeout.
  T locked<T>(T Function() act) {
    final endsSnapshot = _endSnapshot();
    late T result;
    _read.store.write(() {
      if (endsSnapshot && _read.store.snapshotIsStale) {
        throw const _StaleSnapshot();
      }
      result = act();
    });
    return result;
  }

  /// Runs [act] inside the index write lock, held across its awaits, and
  /// returns its result.
  ///
  /// Behaves as [locked] does, for an [act] that awaits; [runAsync] reruns the
  /// command on a stale snapshot. [act] may call [runProjectCheck] and
  /// [runCopyCheck].
  /// Throws [IndexFault] `index_busy` when another call holds the lock past
  /// the busy timeout.
  Future<T> lockedAsync<T>(Future<T> Function() act) {
    final endsSnapshot = _endSnapshot();
    return _read.store.writeAsync(() async {
      if (endsSnapshot && _read.store.snapshotIsStale) {
        throw const _StaleSnapshot();
      }
      _inLockedAsync = true;
      try {
        return await act();
      } finally {
        _inLockedAsync = false;
      }
    });
  }

  /// Runs every check rule over the whole project on the session's snapshot.
  ///
  /// Call it inside [lockedAsync]; the parse results it stores join the open
  /// write instead of ending it. Outside, its cache write would restart the
  /// snapshot and hide a peer commit from the first lock.
  /// Throws [StateError] when called outside [lockedAsync].
  Future<CheckReport> runProjectCheck({MermaidNodeRun? mermaidRunner}) {
    if (!_inLockedAsync) {
      throw StateError('runProjectCheck runs only inside lockedAsync');
    }
    return check_run.runCheck(_read, mermaidRunner: mermaidRunner);
  }

  /// Runs the per-doc check rules over [copyLf], the text of [draft]'s
  /// approved copy, as if it sat at the draft's DocPath.
  ///
  /// Call it inside [lockedAsync], as [runProjectCheck] asks.
  /// Throws [StateError] when called outside [lockedAsync].
  Future<CheckReport> runCopyCheck({
    required IndexedDoc draft,
    required String copyLf,
    MermaidNodeRun? mermaidRunner,
  }) {
    if (!_inLockedAsync) {
      throw StateError('runCopyCheck runs only inside lockedAsync');
    }
    return check_run.runCopyCheck(
      _read,
      draft: draft,
      copyLf: copyLf,
      mermaidRunner: mermaidRunner,
    );
  }

  /// Ends the read snapshot when it is still open; returns whether it did.
  bool _endSnapshot() {
    final ends = _snapshotOpen;
    if (ends) {
      _read.store.endSnapshot();
      _snapshotOpen = false;
    }
    return ends;
  }

  /// Returns the bytes of [docPath] for a write, or null when the file is gone.
  ///
  /// Remembers a leading UTF-8 BOM so [writeDoc] puts it back; decode the
  /// bytes with `utf8.decode`, which drops the BOM.
  /// Throws [RenderFault] `output_not_writable` for a file that cannot be read
  /// or whose bytes are not UTF-8, leaving the file untouched.
  List<int>? readDocBytes(String docPath) {
    final List<int> bytes;
    try {
      bytes = fileOf(docPath).readAsBytesSync();
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
        'cannot write $docPath: not UTF-8 text',
      );
    }
    startsWithUtf8Bom(bytes) ? _bomDocs.add(docPath) : _bomDocs.remove(docPath);
    return bytes;
  }

  /// Returns the step that writes [lfText] to [docPath] over the file read as
  /// [bytes], in the line ends and byte-order mark that file had.
  ///
  /// [lfText] is laid out already; the step writes only while the file still
  /// holds the text [bytes] hold.
  WriteStep docWriteStep(String docPath, String lfText, List<int> bytes) {
    final raw = utf8.decode(bytes);
    return WriteStep(
      projectPathOf(docPath),
      '${bomOf(bytes)}${LineEnding.of(raw).apply(lfText)}',
      before: textHashOf(raw),
    );
  }

  /// Refuses a write to [docPath] when the file leads outside the project or
  /// into `.git`, or is read-only.
  ///
  /// A rename replaces a read-only file whatever its mode, so the check is the
  /// caller's.
  /// Throws [RenderFault] `output_not_writable`.
  void requireWritable(String docPath) {
    project.requireWritablePath(fileOf(docPath).path);
    requireNotReadOnly(fileOf(docPath), docPath);
  }

  /// Writes [lfText] to [docPath] in [lineEnding], laid out for its doc type,
  /// and returns the LF text written.
  ///
  /// An untyped doc, and one the formatter refuses, are written as given. A
  /// BOM that the last [readDocBytes] of [docPath] saw is kept.
  /// Throws [RenderFault] `output_not_writable` when the file is read-only or
  /// the disk refuses, and [ArgumentError] for a [docPath] that is not a `.md`
  /// path under the docs root.
  String writeDoc(String docPath, String lfText, LineEnding lineEnding) {
    _requireDocPath(docPath);
    requireWritable(docPath);
    final laidOut = layOutDoc(lfText, docTypeAt(docPath));
    try {
      writeFileAtomic(fileOf(docPath), [
        if (_bomDocs.contains(docPath)) ...utf8Bom,
        ...utf8.encode(lineEnding.apply(laidOut)),
      ]);
    } on FileSystemException catch (error) {
      final reason = error.osError?.message ?? error.message;
      throw RenderFault(
        RenderFaultCode.outputNotWritable,
        'cannot write $docPath: $reason',
      );
    }
    return laidOut;
  }

  /// Returns the doc type the matcher gives [docPath], or null when untyped.
  MergedDocType? docTypeAt(String docPath) =>
      switch (project.matcher.match(docPath)) {
        MatchedDocType(:final docType) => docType,
        _ => null,
      };

  void _requireDocPath(String docPath) {
    final segments = docPath.split('/');
    if (!docPath.endsWith('.md') ||
        segments.any((s) => s.isEmpty || s == '..') ||
        docPath.contains(r'\') ||
        File(docPath).isAbsolute) {
      throw ArgumentError.value(docPath, 'docPath', 'not a .md under docs');
    }
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    if (_snapshotOpen) {
      _read.close();
    } else {
      _read.store.close();
    }
  }
}

/// Throws [WriteFault] `migrate_pending` when a folder from [workingDirectory]
/// up holds the journal of an unfinished `specstone migrate`.
///
/// The walk ends at the first folder holding the project config or at the
/// filesystem root. It needs no config, so a folder with no config is refused
/// too.
/// Nothing is replayed. A journal no run on this machine wrote, its digest
/// absent under [homeDirectory], is refused as untrusted first.
void refuseMigratePending(
  Directory workingDirectory, {
  required Directory? homeDirectory,
}) {
  var folder = workingDirectory.absolute;
  while (true) {
    // A journal behind a linked `.specstone` is never read; the project open
    // refuses such a folder when it holds the config.
    final isRealFolder =
        FileSystemEntity.typeSync(
          '${folder.path}${Platform.pathSeparator}.specstone',
          followLinks: false,
        ) ==
        FileSystemEntityType.directory;
    if (isRealFolder && MoveJournal.pendingMigrate(folder)) {
      MoveJournal.requireRecorded(folder, homeDirectory: homeDirectory);
      throw WriteFault(
        WriteFaultCode.migratePending,
        'a migration is unfinished; run specstone migrate '
        '$ownerConfirmationWays, to finish it, then run the command again',
        file: MoveJournal.journalPath,
      );
    }
    if (File.fromUri(folder.uri.resolve(projectConfigPath)).existsSync()) {
      return;
    }
    final parent = folder.parent;
    if (parent.path == folder.path) return;
    folder = parent;
  }
}

/// Opens the project, then replays an unfinished move journal inside the write
/// lock and opens it again.
///
/// Adds to [warnings] the warnings of the first open when a journal is pending,
/// since that open closes, then each warning the replay raises.
ReadSession _openReplayed({
  required TemplateResolver templates,
  required Directory workingDirectory,
  required Directory? homeDirectory,
  required Duration busyTimeout,
  required List<String> warnings,
}) {
  ReadSession open() => ReadSession.open(
    templates: templates,
    workingDirectory: workingDirectory,
    homeDirectory: homeDirectory,
    busyTimeout: busyTimeout,
  );

  final read = open();
  if (!MoveJournal.pending(read.project.projectRoot)) return read;
  _addUnlisted(warnings, read.warnings);
  try {
    read.store.endSnapshot();
    read.store.write(
      () => MoveJournal.replay(
        JournalTarget.of(
          read.project,
          homeDirectory: homeDirectory,
          warn: warnings.add,
        ),
      ),
    );
  } finally {
    read.store.close();
  }
  return open();
}

/// Adds each of [lines] to [into] unless [into] already lists it.
void _addUnlisted(List<String> into, Iterable<String> lines) {
  final listed = into.toSet();
  into.addAll(lines.where((line) => !listed.contains(line)));
}

/// Returns the `output_not_writable` fault for a [path] that cannot be read.
///
/// [path] is a DocPath or a folder of one, shown as given.
RenderFault cannotRead(String path, FileSystemException error) => RenderFault(
  RenderFaultCode.outputNotWritable,
  'cannot read $path: ${error.osError?.message ?? error.message}',
);

IndexFault _noParent(String parentTypeId, String value) => IndexFault(
  IndexFaultCode.docNotFound,
  'no $parentTypeId doc carries the name $value',
);

/// Returns the one typed doc [address] names among the docs of [names].
///
/// Reads [address] as [DocIndex.resolve] reads it, [codeTarget] included.
/// Throws [IndexFault] `untyped_target` for a doc with no doc type and
/// `argument_invalid` for an address that names 2 or more docs, listing each
/// as `<doc type>:<name>` or its DocPath, or whose end 2 or more names share;
/// `doc_not_found` when it names none; a `TemplateFault` passes through.
IndexedDoc typedTargetOf(DocIndex names, String address, {String? codeTarget}) {
  final found = names.resolve(address, codeTarget: codeTarget);
  final typed = [
    for (final doc in found)
      if (doc.docTypeId != null) doc,
  ];
  if (typed.isEmpty) {
    throw IndexFault(
      IndexFaultCode.untypedTarget,
      '${found.first.docPath} has no doc type; '
      'migrate it to one before a write',
    );
  }
  if (typed.length > 1) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '$address names ${typed.length} docs: '
      '${typed.map(names.addressOf).join(', ')}',
    );
  }
  return typed.single;
}

/// Throws [RenderFault] `output_not_writable` when [file], the file of
/// [docPath], is read-only.
void requireNotReadOnly(File file, String docPath) {
  if (!isReadOnly(file)) return;
  throw RenderFault(
    RenderFaultCode.outputNotWritable,
    'cannot write $docPath: read-only',
  );
}
