import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:specstone_core/src/atomic_write.dart';

// MARK: - Constants

/// The folder of the records under the home folder, `/`-separated.
const _recordsFolder = '.specstone/journals';

const _journalKey = 'journal';

/// The key a later release reads for the files a run writes outside the
/// roots; no 1.1 journal step writes one, so the list stays empty.
const _agentFilesKey = 'agentFiles';

// MARK: - JournalRecords

/// The per-user record of the move journals this machine's runs wrote.
///
/// A journal a git clone carries is not one of them, so a replay trusts only
/// a journal whose SHA-256 is recorded here, outside every work tree. Each
/// record is one file under `<home>/.specstone/journals/`, named by the
/// SHA-256 of the canonical project root and holding the journal's digest.
final class JournalRecords {
  /// Returns the records under [homeDirectory]; null keeps none, so no
  /// journal is trusted and none is written. A home folder that is not
  /// absolute, or that lies inside the project root a record is asked for,
  /// counts as none: a clone could carry the record.
  const new(this.homeDirectory);

  /// The user's home folder, or null when the environment names none.
  final Directory? homeDirectory;

  /// Records [journal], the bytes of the journal file, for [projectRoot].
  ///
  /// Throws [FileSystemException] when there is no usable home folder or the
  /// record cannot be written.
  void record(Directory projectRoot, List<int> journal) {
    requireHome(projectRoot);
    final file = _fileOf(projectRoot)!;
    file.parent.createSync(recursive: true);
    final record = {
      _journalKey: _digestOf(journal),
      _agentFilesKey: <String>[],
    };
    writeFileAtomic(file, utf8.encode(jsonEncode(record)));
  }

  /// Throws [FileSystemException] when there is no home folder to keep a
  /// record of [projectRoot] in.
  void requireHome(Directory projectRoot) {
    if (_fileOf(projectRoot) == null) {
      throw const FileSystemException('no home folder to record it in');
    }
  }

  /// Whether [journal], the bytes of the journal file, is the one recorded
  /// for [projectRoot].
  bool holds(Directory projectRoot, List<int> journal) {
    final file = _fileOf(projectRoot);
    if (file == null) return false;
    try {
      return switch (jsonDecode(file.readAsStringSync())) {
        {_journalKey: final String digest} => digest == _digestOf(journal),
        _ => false,
      };
    } on FileSystemException {
      return false;
    } on FormatException {
      return false;
    }
  }

  /// Removes the record of [projectRoot], when there is one.
  void clear(Directory projectRoot) {
    final file = _fileOf(projectRoot);
    try {
      if (file != null && file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // A record left behind trusts only the digest of a journal that is gone.
    }
  }

  File? _fileOf(Directory projectRoot) {
    final home = homeDirectory;
    if (home == null || !home.isAbsolute) return null;
    final root = projectRoot.resolveSymbolicLinksSync();
    final canonicalHome = _canonical(home);
    if (canonicalHome == root ||
        canonicalHome.startsWith('$root${Platform.pathSeparator}')) {
      return null;
    }
    final key = _digestOf(utf8.encode(projectRoot.resolveSymbolicLinksSync()));
    return File(
      [
        home.path,
        ..._recordsFolder.split('/'),
        key,
      ].join(Platform.pathSeparator),
    );
  }
}

/// Returns the canonical path of [folder], resolving its nearest folder that
/// exists and appending the rest, since a home folder may not exist yet.
String _canonical(Directory folder) {
  final missing = <String>[];
  var existing = folder.absolute;
  while (!existing.existsSync() && existing.parent.path != existing.path) {
    missing.insert(0, existing.uri.pathSegments.lastWhere((s) => s.isNotEmpty));
    existing = existing.parent;
  }
  return [
    existing.resolveSymbolicLinksSync(),
    ...missing,
  ].join(Platform.pathSeparator);
}

String _digestOf(List<int> bytes) => sha256.convert(bytes).toString();
