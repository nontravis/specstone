import 'dart:io';

import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/models/code_file_facts.dart';
import 'package:specstone_core/src/index_query/models/code_file_key.dart';
import 'package:specstone_core/src/index_query/models/file_stat_key.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/index_query/refresh.dart'
    show isOutsideRacyWindow, statKeyOf;
import 'package:sqlite3/sqlite3.dart';

/// The facts about code files that survive between `check` runs, kept in the
/// index's `code_files` table.
///
/// A file's facts are trusted only while its stat key, as the refresh reads
/// it, matches the stored one and the file opens. A file whose mtime lies
/// within the racy window before the run began is never stored: the run began
/// before it read any code file, so a file edited during the run has an mtime
/// past that start and an edit in the same mtime tick as a stored stat key
/// cannot slip by. A file that cannot be statted is never stored or trusted.
final class CodeFileCache {
  /// Reads every stored row of [store], once.
  ///
  /// [startedAt] is when the run began, in microseconds since the epoch, taken
  /// before the run read any code file.
  new load(IndexStore store, {required int startedAt})
    : _facts = store.loadCodeFiles(),
      _startedAt = startedAt;

  final Map<CodeFileKey, CodeFileFacts> _facts;
  final int _startedAt;
  final Map<CodeFileKey, FileStatKey?> _stats = {};
  final Map<CodeFileKey, bool> _opens = {};
  final Set<CodeFileKey> _changed = {};

  /// Returns the fingerprint stored for [path] under [root], or null when the
  /// file's facts are not trusted.
  String? fingerprintOf(Directory root, String path) =>
      _trusted(root, path)?.fingerprint;

  /// Returns the distinct mention texts stored for [path] under [root], or
  /// null when none are trusted.
  List<String>? mentionTextsOf(Directory root, String path) =>
      _trusted(root, path)?.mentionTexts;

  /// Whether the `implements` entry [code] is stored as resolved in [path]
  /// under [root].
  bool isResolved(Directory root, String path, String code) =>
      _trusted(root, path)?.resolved.contains(code) ?? false;

  /// Remembers [fingerprint] as that of [path] under [root].
  void putFingerprint(Directory root, String path, String fingerprint) {
    final key = _key(root, path);
    final facts = _storable(key);
    if (facts == null || facts.fingerprint == fingerprint) return;
    facts.fingerprint = fingerprint;
    _changed.add(key);
  }

  /// Remembers [texts] as the distinct mention texts of [path] under [root].
  void putMentionTexts(Directory root, String path, List<String> texts) {
    final key = _key(root, path);
    final facts = _storable(key);
    if (facts == null || _sameTexts(facts.mentionTexts, texts)) return;
    facts.mentionTexts = texts;
    _changed.add(key);
  }

  /// Remembers that the `implements` entry [code] resolved in [path] under
  /// [root].
  void putResolved(Directory root, String path, String code) {
    final key = _key(root, path);
    final facts = _storable(key);
    if (facts == null || !facts.resolved.add(code)) return;
    _changed.add(key);
  }

  /// Writes the rows this run changed in one write transaction of [session]'s
  /// index; writes nothing when none changed.
  ///
  /// With [keepRoots], the rows of a root outside it and the rows of a file
  /// this run never statted, or statted to no file, are deleted in the same
  /// transaction. Pass it only for a run that reads every code file the rules
  /// want. The write never waits for a lock, and writes nothing under another
  /// stamp than the session's. An index that is busy, locked, or cannot be
  /// written leaves the cache unwritten: the next run reads the files again.
  void save(ReadSession session, {Set<String>? keepRoots}) {
    final dropped = [
      if (keepRoots != null)
        for (final key in _facts.keys)
          if (!keepRoots.contains(key.root) || _stats[key] == null) key,
    ];
    if (_changed.isEmpty && dropped.isEmpty) return;
    final changed = {for (final key in _changed) key: _facts[key]!};
    final stamp = IndexStamp.of(
      session.project.set,
      targetNames: session.project.targetNames,
    );
    try {
      session.writeIndex((store) {
        if (store.readStamp() != stamp) return;
        store
          ..deleteCodeFiles(dropped)
          ..putCodeFiles(changed);
      }, codeFactsOnly: true);
    } on IndexFault {
      return;
    } on SqliteException {
      return;
    }
    _changed.clear();
  }

  CodeFileKey _key(Directory root, String path) =>
      CodeFileKey(root: root.path, path: path);

  /// The stat key of the file at [key], taken once per run.
  FileStatKey? _statOf(CodeFileKey key) =>
      _stats.putIfAbsent(key, () => statKeyOf(File('${key.root}/${key.path}')));

  /// Whether the file at [key] opens, checked once per run; a file that was
  /// readable when stored may be unreadable under an unchanged stat key.
  bool _canOpen(CodeFileKey key) => _opens.putIfAbsent(key, () {
    try {
      File('${key.root}/${key.path}').openSync().closeSync();
      return true;
    } on FileSystemException {
      return false;
    }
  });

  CodeFileFacts? _trusted(Directory root, String path) {
    final key = _key(root, path);
    final stat = _statOf(key);
    final facts = _facts[key];
    if (stat == null || facts == null || facts.stat != stat) return null;
    return _canOpen(key) ? facts : null;
  }

  /// The facts of [key] to add to: the trusted ones, or fresh ones when the
  /// file's stat key may be stored; null when it may not.
  CodeFileFacts? _storable(CodeFileKey key) {
    final stat = _statOf(key);
    if (stat == null) return null;
    final known = _facts[key];
    if (known != null && known.stat == stat) return known;
    if (!isOutsideRacyWindow(_startedAt, stat)) return null;
    return _facts[key] = CodeFileFacts(stat: stat);
  }

  static bool _sameTexts(List<String>? stored, List<String> texts) {
    if (stored == null || stored.length != texts.length) return false;
    for (final (i, text) in texts.indexed) {
      if (stored[i] != text) return false;
    }
    return true;
  }
}
