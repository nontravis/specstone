import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/document_writing/home_record.dart';
import 'package:specstone_core/src/templates/code_point_order.dart';

// MARK: - Constants

/// The folder of the records under the home folder, `/`-separated.
const _recordsFolder = '.specstone/journals';

const _journalKey = 'journal';
const _agentFilesKey = 'agentFiles';

// MARK: - JournalRecords

/// The per-user record of the move journals this machine's runs wrote.
///
/// A journal a git clone carries is not one of them, so a replay trusts only
/// a journal whose SHA-256 is recorded here, outside every work tree. Each
/// record is one file under `<home>/.specstone/journals/`, named by the
/// SHA-256 of the canonical project root and holding the journal's digest
/// and the agent files its run writes outside the roots.
final class JournalRecords {
  /// Returns the records under [homeDirectory]; null keeps none, so no
  /// journal is trusted and none is written. A home folder that is not
  /// absolute, or that lies inside the project root a record is asked for,
  /// counts as none: a clone could carry the record.
  const new(this.homeDirectory);

  /// The user's home folder, or null when the environment names none.
  final Directory? homeDirectory;

  /// Records [journal], the bytes of the journal file, for [projectRoot],
  /// with [agentFiles]: the canonical paths of the agent files its run writes,
  /// each inside the project root (R99).
  ///
  /// Throws [FileSystemException] when there is no usable home folder or the
  /// record cannot be written.
  void record(
    Directory projectRoot,
    List<int> journal, {
    Set<String> agentFiles = const {},
  }) {
    requireHome(projectRoot);
    final file = _fileOf(projectRoot)!;
    final folder = file.parent..createSync(recursive: true);
    restrictToOwner(folder);
    final record = {
      _journalKey: digestOf(journal),
      _agentFilesKey: agentFiles.toList()..sort(compareCodePoints),
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

  /// Returns the agent files recorded with [journal], the bytes of the
  /// journal file, for [projectRoot]; null when the record holds another
  /// journal or none, so [journal] is not trusted.
  Set<String>? agentFilesOf(Directory projectRoot, List<int> journal) {
    final file = _fileOf(projectRoot);
    if (file == null) return null;
    try {
      return switch (jsonDecode(file.readAsStringSync())) {
        {
          _journalKey: final String digest,
          _agentFilesKey: final List<Object?> paths,
        }
            when digest == digestOf(journal) &&
                paths.every((path) => path is String) =>
          {...paths.cast<String>()},
        _ => null,
      };
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
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
    String root() => projectRoot.resolveSymbolicLinksSync();
    return homeRecordFile(
      homeDirectory,
      folder: _recordsFolder,
      key: root,
      keepOut: () => [root()],
    );
  }
}
