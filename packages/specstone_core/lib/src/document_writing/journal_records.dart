import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:specstone_core/src/atomic_write.dart';

// MARK: - Constants

/// The folder of the records under the home folder, `/`-separated.
const _recordsFolder = '.specstone/journals';

// MARK: - JournalRecords

/// The per-user record of the move journals this machine's runs wrote.
///
/// A journal a git clone carries is not one of them, so a replay trusts only
/// a journal whose SHA-256 is recorded here, outside every work tree. Each
/// record is one file under `<home>/.specstone/journals/`, named by the
/// SHA-256 of the canonical project root and holding the journal's digest.
final class JournalRecords {
  /// Returns the records under [homeDirectory]; null keeps none, so no
  /// journal is trusted.
  const new(this.homeDirectory);

  /// The user's home folder, or null when the environment names none.
  final Directory? homeDirectory;

  /// Records [journal], the bytes of the journal file, for [projectRoot].
  ///
  /// Records nothing when there is no home folder.
  ///
  /// Throws [FileSystemException] when the record cannot be written.
  void record(Directory projectRoot, List<int> journal) {
    final file = _fileOf(projectRoot);
    if (file == null) return;
    final folder = file.parent..createSync(recursive: true);
    restrictToOwner(folder);
    writeFileAtomic(file, ascii.encode(_digestOf(journal)));
  }

  /// Whether [journal], the bytes of the journal file, is the one recorded
  /// for [projectRoot].
  bool holds(Directory projectRoot, List<int> journal) {
    final file = _fileOf(projectRoot);
    if (file == null) return false;
    try {
      return file.readAsStringSync() == _digestOf(journal);
    } on FileSystemException {
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
    if (home == null) return null;
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

String _digestOf(List<int> bytes) => sha256.convert(bytes).toString();
