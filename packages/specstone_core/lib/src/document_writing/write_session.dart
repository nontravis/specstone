import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/document_writing/owner_confirmation.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/doc_reader.dart'
    show startsWithUtf8Bom, utf8Bom;
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/formatter.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/project_config.dart'
    show projectConfigPath;
import 'package:specstone_core/src/templates/template_resolver.dart';

/// The docs root as a journal step spells it.
///
/// Literal, as `DocsProject.displayPath` prints it: a `docs` link to a folder
/// outside the project still resolves through `<project root>/docs`.
const _docsPrefix = 'docs/';

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
  );

  /// Opens the project holding [workingDirectory], finishes an unfinished
  /// move journal, runs [body], and closes the index.
  ///
  /// The journal replays inside the write lock before any name resolves, so
  /// [body] sees the tree the interrupted command meant to leave.
  /// [homeDirectory] is where user-level doc types are read from; null reads
  /// none. A fault from the project, the templates, the replay, or [body]
  /// propagates unchanged.
  static T run<T>(
    T Function(WriteSession session) body, {
    required TemplateResolver templates,
    required Directory workingDirectory,
    required Directory? homeDirectory,
    Duration busyTimeout = indexBusyTimeout,
  }) {
    _refuseMigratePending(workingDirectory);
    final session = WriteSession._(
      _openReplayed(
        templates: templates,
        workingDirectory: workingDirectory,
        homeDirectory: homeDirectory,
        busyTimeout: busyTimeout,
      ),
      templates,
      workingDirectory,
      homeDirectory,
      busyTimeout,
    );
    try {
      return body(session);
    } finally {
      session._close();
    }
  }

  final TemplateResolver _templates;
  final Directory _workingDirectory;
  final Directory? _homeDirectory;
  final Duration _busyTimeout;
  ReadSession _read;
  bool _snapshotOpen = true;
  bool _closed = false;

  /// The DocPaths whose last [readDocBytes] began with a UTF-8 BOM.
  final _bomDocs = <String>{};

  /// Opens the project afresh and finishes an unfinished move journal, so the
  /// session sees the tree as it is now.
  ///
  /// Call it outside the write lock, after a wait that let another command
  /// write; [index] and [project] are new objects afterwards.
  void refresh() {
    _refuseMigratePending(_workingDirectory);
    _close();
    _read = _openReplayed(
      templates: _templates,
      workingDirectory: _workingDirectory,
      homeDirectory: _homeDirectory,
      busyTimeout: _busyTimeout,
    );
    _closed = false;
    _snapshotOpen = true;
    _bomDocs.clear();
  }

  /// The project the session writes.
  DocsProject get project => _read.project;

  /// The docs of the session's snapshot, with their names and parent tree.
  DocIndex get index => _read.index;

  /// The store's warnings, the refresh's, then each doc's in tree order.
  List<String> get warnings => _read.warnings;

  /// Returns the file of [docPath], a path relative to the docs root.
  File fileOf(String docPath) => File(
    '${project.docsRoot.path}${Platform.pathSeparator}'
    '${docPath.split('/').join(Platform.pathSeparator)}',
  );

  /// Returns [docPath] as a journal step takes it: relative to the project
  /// root and `/`-separated.
  String projectPathOf(String docPath) => '$_docsPrefix$docPath';

  /// Returns the DocPath of [projectPath], the inverse of [projectPathOf].
  String docPathOf(String projectPath) =>
      projectPath.substring(_docsPrefix.length);

  /// Returns the one typed doc [address] names.
  ///
  /// [address] is `<doc type>:<name>`, a bare name, or a path to the doc, as
  /// [DocIndex.resolve] reads it.
  /// Throws [IndexFault] `untyped_target` for a doc with no doc type, before
  /// any doc-type test, `argument_invalid` for an address that names 2 or
  /// more docs, listing each as `<doc type>:<name>` or, when that names 2
  /// docs, its DocPath, and `doc_not_found` when it names none; a
  /// `TemplateFault` for an unknown doc type id passes through.
  IndexedDoc target(String address) {
    final found = index.resolve(address);
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
        '${typed.map(index.addressOf).join(', ')}',
      );
    }
    return typed.single;
  }

  /// Returns the one doc of [parentTypeId] among the docs [value] names.
  ///
  /// [value] is read as any target, as [target] reads it, and only the docs of
  /// [parentTypeId] count.
  /// Throws [IndexFault] `doc_not_found` naming [value] when none counts and
  /// `argument_invalid` listing each as `<doc type>:<name>` or, when that names
  /// 2 docs, its DocPath, when 2 or more count; a `TemplateFault` for a doc
  /// type id the set lacks and `argument_invalid` for a `#` or `@` suffix pass
  /// through from [DocIndex.resolve].
  IndexedDoc parentTarget(String value, String parentTypeId) {
    final List<IndexedDoc> named;
    try {
      named = index.resolve(value);
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
        '${parents.map(index.addressOf).join(', ')}',
      );
    }
    return parents.single;
  }

  /// Runs [act] inside the index write lock and returns its result.
  ///
  /// The first call ends the read snapshot. A fault from [act] rolls back and
  /// propagates.
  /// Throws [IndexFault] `index_busy` when another call holds the lock past
  /// the busy timeout.
  T locked<T>(T Function() act) {
    if (_snapshotOpen) {
      _read.store.endSnapshot();
      _snapshotOpen = false;
    }
    late T result;
    _read.store.write(() => result = act());
    return result;
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

  /// Refuses a write to [docPath] when the file is read-only.
  ///
  /// A rename replaces a read-only file whatever its mode, so the check is the
  /// caller's.
  /// Throws [RenderFault] `output_not_writable`.
  void requireWritable(String docPath) {
    if (!isReadOnly(fileOf(docPath))) return;
    throw RenderFault(
      RenderFaultCode.outputNotWritable,
      'cannot write $docPath: read-only',
    );
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
/// filesystem root. It needs no config, so a legacy tree is refused too.
/// Nothing is replayed.
void _refuseMigratePending(Directory workingDirectory) {
  var folder = workingDirectory.absolute;
  while (true) {
    if (MoveJournal.pendingMigrate(folder)) {
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
ReadSession _openReplayed({
  required TemplateResolver templates,
  required Directory workingDirectory,
  required Directory? homeDirectory,
  required Duration busyTimeout,
}) {
  ReadSession open() => ReadSession.open(
    templates: templates,
    workingDirectory: workingDirectory,
    homeDirectory: homeDirectory,
    busyTimeout: busyTimeout,
  );

  final read = open();
  if (!MoveJournal.pending(read.project.projectRoot)) return read;
  try {
    read.store.endSnapshot();
    read.store.write(() => MoveJournal.replay(JournalTarget.of(read.project)));
  } finally {
    read.store.close();
  }
  return open();
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
