import 'dart:io';

import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/parents.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';

/// How much older than `checked_at` a file's mtime must be before its stat
/// key vouches for its stored hash.
///
/// An edit in the same mtime tick as the listing keeps the stat key, so such a
/// file is hashed again; 2 s covers the coarsest mtime clocks, as git's
/// racy-file rule does.
const _racyWindow = Duration(seconds: 2);

/// What one [refreshIndex] call did.
final class RefreshResult {
  const new({
    required this.warnings,
    required this.reindexed,
    required this.hashed,
    required this.fullBuild,
  });

  /// What went wrong while listing the docs, one sentence each.
  final List<String> warnings;

  /// How many docs the call put into the index or deleted from it.
  final int reindexed;

  /// How many files the call read and hashed.
  final int hashed;

  /// Whether the call rebuilt the whole index.
  final bool fullBuild;
}

/// Brings [store] up to date with the `.md` files under the docs root of
/// [project].
///
/// A file is read and hashed unless its stored stat key still matches and its
/// mtime lies more than 2 s before the listing that last wrote the index; a
/// hash that differs reindexes it. An index written under another stamp or
/// layout is rebuilt whole. The store is written only when a file was added or
/// deleted, a hash or a stat key changed, a file read in the racy window has
/// aged out of it, or the stamp differs.
RefreshResult refreshIndex(IndexStore store, DocsProject project) {
  final stamp = IndexStamp.of(project.set);
  final current = store.readStamp() == stamp;
  final stored = current ? _Stored.of(store) : _Stored.none;
  final listing = _Listing(DateTime.now().microsecondsSinceEpoch)
    ..list(project, stored);
  if (current && !listing.differsFrom(stored, store)) {
    return RefreshResult(
      warnings: listing.warnings,
      reindexed: 0,
      hashed: listing.hashed,
      fullBuild: false,
    );
  }
  var reindexed = 0;
  var fullBuild = false;
  store.write(() {
    // A peer may have rebuilt or reindexed while this call waited for the
    // lock, so the stamp, the stat keys, and the hashes are read again here.
    fullBuild = store.readStamp() != stamp;
    if (fullBuild) store.reset(stamp);
    final stored = _Stored.of(store);
    listing.readUnvouched(stored);
    final hashes = store.hashes();
    final files = listing.files;
    for (final docPath in hashes.keys.where((p) => !files.containsKey(p))) {
      store.deleteDoc(docPath);
      reindexed++;
    }
    for (final MapEntry(key: docPath, value: file) in files.entries) {
      final content = file.content;
      final changed = content != null && content.hash != hashes[docPath];
      if (changed) {
        store.putDoc(
          parseIndexedDoc(
            docPath: docPath,
            bytes: content.bytes,
            match: project.matcher.match(docPath),
          ),
        );
        reindexed++;
      }
      if (changed || stored.stats[docPath] != file.stat) {
        store.setStatKey(docPath, file.stat);
      }
    }
    // With no doc put or deleted, the parents and the order still hold.
    if (reindexed > 0) {
      final tree = resolveParents(store.loadDocs(), project.set);
      store.setTree(
        parents: tree.parents,
        parentWarnings: tree.warnings,
        order: files.keys.toList(),
      );
    }
    store.setCheckedAt(listing.checkedAt);
  });
  return RefreshResult(
    warnings: listing.warnings,
    reindexed: reindexed,
    hashed: listing.hashed,
    fullBuild: fullBuild,
  );
}

/// The stat keys of the index and the start of the listing that wrote them.
final class _Stored {
  const new(this.stats, this.checkedAt);

  /// Returns what [store] holds now.
  static _Stored of(IndexStore store) =>
      _Stored(store.statKeys(), store.readCheckedAt());

  /// An index that vouches for no file.
  static const none = _Stored({}, null);

  /// The stat key of every stored doc by docPath.
  final Map<String, FileStatKey?> stats;

  /// In microseconds since the epoch; null when no listing stored it.
  final int? checkedAt;

  /// Whether the stored hash of [docPath] still holds for a file with [stat].
  ///
  /// Holds only when the stat succeeded, the stat key matches, and the mtime
  /// lies outside the racy window before [checkedAt].
  bool vouches(String docPath, FileStatKey? stat) {
    final checkedAt = this.checkedAt;
    return checkedAt != null &&
        stats[docPath] == stat &&
        _outsideWindow(checkedAt, stat);
  }
}

/// Whether [stat] succeeded and its mtime lies more than [_racyWindow] before
/// [checkedAt].
bool _outsideWindow(int checkedAt, FileStatKey? stat) =>
    stat != null && checkedAt - stat.modified > _racyWindow.inMicroseconds;

/// One `.md` file the listing found.
final class _ListedFile {
  new(this.file, this.stat);

  final File file;

  /// Taken before any read, so an edit between the two shows on the next call;
  /// null when the stat failed, so the file is read on every call.
  final FileStatKey? stat;

  /// The bytes and their hash; null while the stored hash is trusted.
  ({List<int> bytes, String hash})? content;
}

/// The `.md` files of one refresh, each read at most once.
final class _Listing {
  new(this.checkedAt);

  /// When the listing began, in microseconds since the epoch.
  final int checkedAt;

  /// Every listed file by docPath, in tree order.
  final files = <String, _ListedFile>{};

  /// What went wrong while listing and reading, one sentence each.
  final warnings = <String>[];

  /// How many files were read and hashed.
  int hashed = 0;

  /// Stats every `.md` file under the docs root of [project] and reads each
  /// one [stored] does not vouch for.
  ///
  /// A folder that cannot be listed and a file that cannot be read add a
  /// warning and are left out.
  void list(DocsProject project, _Stored stored) {
    if (!project.docsRoot.existsSync()) return;
    final entries = collectDocEntries(
      Target(project.docsRoot, ''),
      project.matcher,
    );
    for (final entry in entries) {
      switch (entry) {
        case UnreadableFolder(:final docPath):
          warnings.add('$docPath/: cannot be read; skipped');
        case DocFile(:final file, :final docPath) when docPath.endsWith('.md'):
          final listed = _ListedFile(file, _statKeyOf(file));
          if (stored.vouches(docPath, listed.stat) || _read(docPath, listed)) {
            files[docPath] = listed;
          }
        case DocFile():
          break;
      }
    }
  }

  /// Reads each unread file that [stored] does not vouch for; a file that
  /// cannot be read adds a warning and leaves the listing.
  void readUnvouched(_Stored stored) {
    final unreadable = <String>[];
    for (final MapEntry(key: docPath, value: listed) in files.entries) {
      if (listed.content != null || stored.vouches(docPath, listed.stat)) {
        continue;
      }
      if (!_read(docPath, listed)) unreadable.add(docPath);
    }
    unreadable.forEach(files.remove);
  }

  /// Whether the listing saw a file added, deleted, or changed since
  /// [stored] was written, or a racy file that a new checked_at would trust.
  bool differsFrom(_Stored stored, IndexStore store) {
    final stats = stored.stats;
    if (files.length != stats.length ||
        files.entries.any(
          (e) => !stats.containsKey(e.key) || stats[e.key] != e.value.stat,
        )) {
      return true;
    }
    // Every stat key matches, so only a file read in the racy window can
    // differ: by a new hash, or by having aged out of the window, which a
    // write of checked_at turns into trust from the next call on.
    final read = [
      for (final MapEntry(key: docPath, value: listed) in files.entries)
        if (listed.content case final content?)
          (docPath: docPath, hash: content.hash, stat: listed.stat),
    ];
    if (read.isEmpty) return false;
    final hashes = store.hashes();
    return read.any(
      (r) => hashes[r.docPath] != r.hash || _outsideWindow(checkedAt, r.stat),
    );
  }

  /// Reads and hashes [listed]; a read failure adds a warning and returns
  /// false.
  bool _read(String docPath, _ListedFile listed) {
    try {
      final bytes = listed.file.readAsBytesSync();
      listed.content = (bytes: bytes, hash: contentHashOf(bytes));
      hashed++;
      return true;
    } on FileSystemException {
      warnings.add('$docPath: cannot be read; skipped');
      return false;
    }
  }
}

/// Returns the stat key of [file]; null when the stat fails or finds no file.
///
/// A failed stat yields placeholder values, which must never vouch for a hash.
FileStatKey? _statKeyOf(File file) {
  final stat = file.statSync();
  if (stat.type != FileSystemEntityType.file) return null;
  return (
    size: stat.size,
    modified: stat.modified.microsecondsSinceEpoch,
    changed: stat.changed.microsecondsSinceEpoch,
    mode: stat.mode,
  );
}
