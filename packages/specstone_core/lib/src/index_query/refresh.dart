import 'dart:io';

import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/parents.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';

/// What one [refreshIndex] call did.
final class RefreshResult {
  const new({
    required this.warnings,
    required this.reindexed,
    required this.fullBuild,
  });

  /// What went wrong while listing the docs, one sentence each.
  final List<String> warnings;

  /// How many docs the call put into the index or deleted from it.
  final int reindexed;

  /// Whether the call rebuilt the whole index.
  final bool fullBuild;
}

/// Brings [store] up to date with the `.md` files under the docs root of
/// [project].
///
/// A file is read again only when its content hash differs from the stored
/// one. An index written under another stamp is rebuilt whole. The store is
/// not written when no hash differs and the stamp matches.
RefreshResult refreshIndex(IndexStore store, DocsProject project) {
  final warnings = <String>[];
  final listed = _readListing(project, warnings);
  final stamp = IndexStamp.of(project.set);
  final fullBuild = store.readStamp() != stamp;
  if (!fullBuild && !_differs(listed, store.hashes())) {
    return RefreshResult(warnings: warnings, reindexed: 0, fullBuild: false);
  }
  var reindexed = 0;
  store.write(() {
    if (fullBuild) store.reset(stamp);
    // A peer may have reindexed while this call waited for the lock.
    final stored = store.hashes();
    for (final docPath in stored.keys.where((p) => !listed.containsKey(p))) {
      store.deleteDoc(docPath);
      reindexed++;
    }
    for (final MapEntry(key: docPath, value: file) in listed.entries) {
      if (stored[docPath] == file.hash) continue;
      store.putDoc(
        parseIndexedDoc(
          docPath: docPath,
          bytes: file.bytes,
          match: project.matcher.match(docPath),
        ),
      );
      reindexed++;
    }
    final tree = resolveParents(store.loadDocs(), project.set);
    store.setTree(
      parents: tree.parents,
      parentWarnings: tree.warnings,
      order: listed.keys.toList(),
    );
  });
  return RefreshResult(
    warnings: warnings,
    reindexed: reindexed,
    fullBuild: fullBuild,
  );
}

/// The bytes of one listed file with their content hash.
typedef _ListedFile = ({List<int> bytes, String hash});

/// Reads every `.md` file under the docs root, keyed by docPath in tree order.
///
/// A folder that cannot be listed and a file that cannot be read add a
/// warning to [warnings] and are left out.
Map<String, _ListedFile> _readListing(
  DocsProject project,
  List<String> warnings,
) {
  final listed = <String, _ListedFile>{};
  if (!project.docsRoot.existsSync()) return listed;
  final entries = collectDocEntries(
    Target(project.docsRoot, ''),
    project.matcher,
  );
  for (final entry in entries) {
    switch (entry) {
      case UnreadableFolder(:final docPath):
        warnings.add('$docPath/: cannot be read; skipped');
      case DocFile(:final file, :final docPath) when docPath.endsWith('.md'):
        try {
          final bytes = file.readAsBytesSync();
          listed[docPath] = (bytes: bytes, hash: contentHashOf(bytes));
        } on FileSystemException {
          warnings.add('$docPath: cannot be read; skipped');
        }
      case DocFile():
        break;
    }
  }
  return listed;
}

bool _differs(Map<String, _ListedFile> listed, Map<String, String> stored) =>
    listed.length != stored.length ||
    listed.entries.any((e) => stored[e.key] != e.value.hash);
