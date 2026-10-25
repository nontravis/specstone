import 'dart:io';

import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/refresh.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:sqlite3/sqlite3.dart';

/// One command's view of a project: the project, a refreshed index, and one
/// read snapshot of it.
///
/// [run] opens a session, answers from it, and closes it. A session from
/// [open] needs [close], which ends the snapshot and closes the index.
final class ReadSession {
  new _({
    required this.project,
    required this.store,
    required this.docs,
    required this.warnings,
  });

  /// Opens the project holding [workingDirectory], brings its index up to
  /// date, and reads every doc from one snapshot.
  ///
  /// [homeDirectory] is where user-level doc types are read from; null reads
  /// none. A fault from the project, the templates, or the index propagates
  /// unchanged, and no index is opened before the project and templates load.
  /// An index that fails with a damage error is deleted and rebuilt once,
  /// with [damagedIndexWarning]; any other database error is an
  /// [IndexFault].
  static ReadSession open({
    required TemplateResolver templates,
    required Directory workingDirectory,
    required Directory? homeDirectory,
    Duration busyTimeout = indexBusyTimeout,
  }) {
    final project = DocsProject.open(
      templates: templates,
      workingDirectory: workingDirectory,
      homeDirectory: homeDirectory,
    );
    try {
      return _read(
        project,
        IndexStore.open(project.projectRoot, busyTimeout: busyTimeout),
      );
    } on SqliteException catch (e) {
      if (!IndexStore.isDamage(e)) throw IndexStore.faultOf(e);
    }
    // A page the first read hit is lost: discard the index and read once more.
    return _rebuilt(project, busyTimeout);
  }

  /// Opens a session as [open] does, returns what [answer] computes from it,
  /// and closes it.
  ///
  /// A damage error from [answer] closes the session, rebuilds the index as
  /// [open] does, and computes [answer] once more from the new session. A
  /// second damage error, or any other database error, is an [IndexFault].
  static T run<T>(
    T Function(ReadSession session) answer, {
    required TemplateResolver templates,
    required Directory workingDirectory,
    required Directory? homeDirectory,
    Duration busyTimeout = indexBusyTimeout,
  }) {
    final session = open(
      templates: templates,
      workingDirectory: workingDirectory,
      homeDirectory: homeDirectory,
      busyTimeout: busyTimeout,
    );
    try {
      return _answer(session, answer);
    } on SqliteException catch (e) {
      if (!IndexStore.isDamage(e)) throw IndexStore.faultOf(e);
    }
    // A page only the answer reads is lost: discard the index and answer again.
    try {
      return _answer(_rebuilt(session.project, busyTimeout), answer);
    } on SqliteException catch (e) {
      throw IndexStore.faultOf(e);
    }
  }

  static ReadSession _rebuilt(DocsProject project, Duration busyTimeout) {
    try {
      return _read(
        project,
        IndexStore.openRebuilt(project.projectRoot, busyTimeout: busyTimeout),
      );
    } on SqliteException catch (e) {
      throw IndexStore.faultOf(e);
    }
  }

  static T _answer<T>(
    ReadSession session,
    T Function(ReadSession session) answer,
  ) {
    try {
      return answer(session);
    } finally {
      session.close();
    }
  }

  static ReadSession _read(DocsProject project, IndexStore store) {
    try {
      final refreshed = refreshIndex(store, project);
      store.beginSnapshot();
      final docs = store.loadDocs();
      return ReadSession._(
        project: project,
        store: store,
        docs: docs,
        warnings: [
          ...store.warnings,
          ...refreshed.warnings,
          for (final doc in docs) ...doc.warnings,
        ],
      );
    } on Object {
      store.close();
      rethrow;
    }
  }

  /// The project the session reads.
  final DocsProject project;

  /// The index, open on the session's snapshot.
  final IndexStore store;

  /// Every doc in tree order, as of the snapshot.
  final List<IndexedDoc> docs;

  /// The store's warnings, the refresh's, then each doc's in tree order.
  final List<String> warnings;

  /// The merged doc types of the project.
  MergedSet get set => project.set;

  /// The docs of the snapshot, with their names, parent tree, and links.
  late final DocIndex index = DocIndex(set, docs, store);

  /// Ends the snapshot and closes the index.
  void close() {
    try {
      store.endSnapshot();
    } finally {
      store.close();
    }
  }
}
