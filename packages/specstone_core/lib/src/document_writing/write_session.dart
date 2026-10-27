import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
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
  new _(this._read);

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
    ReadSession open() => ReadSession.open(
      templates: templates,
      workingDirectory: workingDirectory,
      homeDirectory: homeDirectory,
      busyTimeout: busyTimeout,
    );

    var read = open();
    if (MoveJournal.pending(read.project.projectRoot)) {
      try {
        read.store.endSnapshot();
        read.store.write(() => MoveJournal.replay(read.project));
      } finally {
        read.store.close();
      }
      read = open();
    }
    final session = WriteSession._(read);
    try {
      return body(session);
    } finally {
      session._close();
    }
  }

  final ReadSession _read;
  bool _snapshotOpen = true;

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

  static const _namePrompt =
      'name the doc as <doc type>:<name>, '
      'such as user_story:login/email_login';

  /// Returns the one typed doc [address] names.
  ///
  /// [address] is `<doc type>:<name>`; a bare name is ambiguous across doc
  /// types and refuses.
  /// Throws [IndexFault] `argument_invalid` for a bare name, found or
  /// not, or a name two docs carry, `untyped_target` for a doc with no doc
  /// type, and `doc_not_found` when a typed name matches
  /// none; a `TemplateFault` for an unknown doc type id passes through.
  IndexedDoc target(String address) {
    final bare = !address.contains(':');
    final List<IndexedDoc> found;
    try {
      found = index.resolve(address);
    } on IndexFault catch (fault) {
      if (bare && fault.code == IndexFaultCode.docNotFound) {
        throw IndexFault(IndexFaultCode.argumentInvalid, _namePrompt);
      }
      rethrow;
    }
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
    if (bare) throw IndexFault(IndexFaultCode.argumentInvalid, _namePrompt);
    if (typed.length > 1) {
      throw IndexFault(
        IndexFaultCode.argumentInvalid,
        '$address names ${typed.length} docs: '
        '${typed.map((doc) => doc.docPath).join(', ')}',
      );
    }
    return typed.single;
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

  /// Writes [lfText] to [docPath] in [lineEnding], replacing the file whole.
  ///
  /// Throws [RenderFault] `output_not_writable` when the disk refuses.
  void writeDoc(String docPath, String lfText, LineEnding lineEnding) {
    try {
      writeFileAtomic(fileOf(docPath), utf8.encode(lineEnding.apply(lfText)));
    } on FileSystemException catch (error) {
      final reason = error.osError?.message ?? error.message;
      throw RenderFault(
        RenderFaultCode.outputNotWritable,
        'cannot write $docPath: $reason',
      );
    }
  }

  void _close() {
    if (_snapshotOpen) {
      _read.close();
    } else {
      _read.store.close();
    }
  }
}
