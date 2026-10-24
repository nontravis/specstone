import 'dart:io';

import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/refresh.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';

/// One command's view of a project: the project, a refreshed index, and one
/// read snapshot of it.
///
/// Call [close] when done; it ends the snapshot and closes the index.
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
    final store = IndexStore.open(
      project.projectRoot,
      busyTimeout: busyTimeout,
    );
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

  /// Ends the snapshot and closes the index.
  void close() {
    try {
      store.endSnapshot();
    } finally {
      store.close();
    }
  }
}
