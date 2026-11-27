import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/document_writing/journal_bounds.dart'
    show requireWritableTarget;
import 'package:specstone_core/src/index_query/banned_matches.dart';
import 'package:specstone_core/src/index_query/diagram_parse.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/line_facts.dart';
import 'package:specstone_core/src/index_query/models/cited_by.dart';
import 'package:specstone_core/src/index_query/models/cited_place.dart';
import 'package:specstone_core/src/index_query/models/code_file_facts.dart';
import 'package:specstone_core/src/index_query/models/code_file_key.dart';
import 'package:specstone_core/src/index_query/models/file_stat_key.dart';
import 'package:specstone_core/src/index_query/models/indexed_item_words.dart';
import 'package:specstone_core/src/index_query/models/indexed_link.dart';
import 'package:specstone_core/src/index_query/models/item_facts.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/models/section_counts.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/version.dart';
import 'package:sqlite3/sqlite3.dart';

/// The index file, relative to the project root.
const indexFilePath = '.specstone/index.sqlite';

/// How long a connection waits on another connection's lock before it fails.
const indexBusyTimeout = Duration(seconds: 10);

/// The warning printed when a damaged index file was deleted and rebuilt.
const damagedIndexWarning =
    'the index was damaged and was rebuilt from the markdown files';

/// The lines of `.specstone/.gitignore`, one per ignored path.
const specstoneGitignoreLines = [
  'index.sqlite*',
  'build/',
  'trash/',
  'bundles/',
  'reports/',
  'approved/',
];

/// The message of the fault raised when another call holds the index.
const indexBusyMessage =
    'the index is busy; run the command again once the other call finishes';

const _nestedWrite = 'nested_write';

const _notWritableMessage =
    'cannot write the index under .specstone/; make it writable and run the '
    'command again';

/// The layout of the index, kept in the `layout` column of the meta row.
///
/// Bump it on every change to what a row holds: [_schema], the line-facts,
/// banned-match, and item-facts JSON, and how that JSON is computed. An index
/// of another layout is then rebuilt instead of failing a read. An
/// older build's reset recreates the meta row without it, so its index is
/// rebuilt too. Layout 14 added the `target` column and the stamp's
/// `target_names`: an index of layout 13 holds neither, so it is rebuilt
/// instead of read as one with none. Layout 15 counts the doc's non-blank body
/// lines and a section's non-blank lines, so an index of layout 14, whose
/// counts cover blank lines and frontmatter, is rebuilt. Two builds took
/// layouts 16 and 17 apart: one hashes a record's statuses by the project's
/// statuses rule; the other stores the cite candidates, link texts with each
/// destination as written, and heading levels and lines in the line facts and
/// the `item_words` table. Layout 18 holds both, so an index of any earlier
/// layout, which lacks one or the other, is rebuilt. Layout 19 adds the
/// `search_hash` column, so an index of layout 18, whose `putDoc` wrote the
/// search rows with no hash to tell a lagging doc by, is rebuilt.
/// Layout 20 stores no bare one-slug cite candidate, so an index of layout 19
/// is rebuilt. Layout 21 changes which item IDs a stored cite candidate keeps,
/// so an index of layout 20 is rebuilt. Layout 22 adds each item's readability
/// facts to the item facts, so an index of layout 21, whose items hold none, is
/// rebuilt. Layout 23 stores each item's visible count in place of its raw
/// count, so an index of layout 22 is rebuilt. Layout 24 counts no word or
/// character for a leading language marker, so an index of layout 23, whose
/// sentence facts count it, is rebuilt. Layout 25 adds the tokens of a
/// `mermaid` block to each line's name mentions, so an older index is rebuilt.
/// Layout 26 stores each typed doc's `mermaid` blocks in its line facts and
/// adds the `diagram_parses` table, so an index of layout 25, which holds
/// neither, is rebuilt. Two builds took layout 27 apart: one holds no
/// unreadable links in the line facts; the other stores each prose field's
/// readability facts and pattern matches. Layout 28 adds the `matrix_lines`
/// column and leaves a record's matrix section out of its size counts, so an
/// index of layout 27, whose record rows hold no Verification matrix lines, is
/// rebuilt. Layout 29 holds both, so an index of layout 27 or 28, which lacks
/// one or the other, is rebuilt. Layout 30 counts a section's body alone, so an
/// index of layout 29, whose counts include the header line, is rebuilt.
/// Layout 31 adds the `cited_by` table, so an index of layout 30, which holds
/// none, is rebuilt. Layout 32 adds each bare item ID with its citation to the
/// line facts, so an index of layout 31, which holds none, is rebuilt.
/// Layout 33 stores a Verification matrix test row's literals as a list and a
/// per-FR row's edge case as null, so an index of layout 32, whose rows hold
/// one literal and an edge case, is rebuilt. Layout 34 stores each cited-by
/// row's citing section in place of its link line, so an index of layout 33,
/// whose rows hold a `line` column, is rebuilt. Layout 35 adds each doc's
/// approval-mark characters to the line facts, so an index of layout 34, which
/// holds none, is rebuilt. Layout 36 adds the `code_files` table, so an index
/// of layout 35, which holds none, is rebuilt. Layout 37 adds the
/// `generation` column to the meta row, which tells a peer's write of docs from
/// a peer's write of code-file facts, so an index of layout 36 is rebuilt.
/// Layout 38 stores one fenced range per block, so an index of layout 37,
/// whose ranges merge blocks that touch, is rebuilt. Layout 39 adds each
/// doc's capital-prefix label runs to the line facts, so an index of layout 38,
/// which holds none, is rebuilt. Layout 40 adds each doc's address-shaped link
/// texts to the line facts, so an index of layout 39, which holds none, is
/// rebuilt. Layout 41 stores only the typed address link texts, so an index of
/// layout 40, whose line facts hold bare ones, is rebuilt. Layout 42 stores
/// each code file's label candidate texts with its mention texts, so an index
/// of layout 41, whose rows hold none, is rebuilt.
const indexLayoutVersion = 42;

const _schema = '''
CREATE TABLE meta (
  binary_version TEXT NOT NULL,
  doc_types TEXT NOT NULL,
  target_names TEXT NOT NULL,
  layout INTEGER NOT NULL,
  checked_at INTEGER,
  generation INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE docs (
  id INTEGER PRIMARY KEY,
  doc_path TEXT NOT NULL UNIQUE,
  doc_type_id TEXT,
  name TEXT NOT NULL,
  target TEXT,
  parent_path TEXT,
  parent_warning TEXT,
  title TEXT,
  frontmatter TEXT NOT NULL,
  tokens INTEGER NOT NULL,
  formatted INTEGER,
  approval_hash TEXT,
  ord INTEGER NOT NULL,
  warnings TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  search_hash TEXT,
  text TEXT NOT NULL,
  frontmatter_text TEXT,
  head TEXT NOT NULL,
  line_facts TEXT NOT NULL,
  banned_matches TEXT NOT NULL,
  item_facts TEXT NOT NULL,
  matrix_lines TEXT NOT NULL,
  stat_size INTEGER,
  stat_mtime INTEGER,
  stat_ctime INTEGER,
  stat_mode INTEGER
);
CREATE TABLE sections (
  doc_path TEXT NOT NULL,
  position INTEGER NOT NULL,
  section_key TEXT NOT NULL,
  header_line TEXT NOT NULL,
  body TEXT NOT NULL,
  line_count INTEGER NOT NULL,
  char_count INTEGER NOT NULL,
  PRIMARY KEY (doc_path, position)
);
CREATE TABLE links (
  source TEXT NOT NULL,
  position INTEGER NOT NULL,
  target TEXT NOT NULL,
  PRIMARY KEY (source, position)
);
CREATE TABLE item_words (
  doc_path TEXT NOT NULL,
  position INTEGER NOT NULL,
  line INTEGER NOT NULL,
  item_id TEXT,
  words TEXT NOT NULL,
  PRIMARY KEY (doc_path, position)
);
CREATE TABLE cited_by (
  seq INTEGER PRIMARY KEY,
  place_doc TEXT NOT NULL,
  place_kind TEXT NOT NULL,
  place_key TEXT,
  by_doc TEXT NOT NULL,
  by_name TEXT NOT NULL,
  by_type TEXT NOT NULL,
  by_item TEXT,
  by_section TEXT NOT NULL
);
CREATE TABLE diagram_parses (
  block_hash TEXT NOT NULL,
  parser_hash TEXT NOT NULL,
  diagram TEXT,
  parses INTEGER NOT NULL,
  message TEXT,
  block_line INTEGER,
  PRIMARY KEY (block_hash, parser_hash)
);
CREATE TABLE code_files (
  root TEXT NOT NULL,
  path TEXT NOT NULL,
  stat_size INTEGER NOT NULL,
  stat_mtime INTEGER NOT NULL,
  stat_ctime INTEGER NOT NULL,
  stat_mode INTEGER NOT NULL,
  fingerprint TEXT,
  mention_texts TEXT,
  resolved TEXT NOT NULL,
  PRIMARY KEY (root, path)
);
CREATE VIRTUAL TABLE doc_search USING fts5(
  text, path UNINDEXED, section_key UNINDEXED, tokenize = 'trigram'
);
''';

/// The rowids a doc may use in `doc_search`: its id shifted left by 32 bits,
/// plus a counter below this limit.
const int _searchRowsPerDoc = 1 << 32;

const _tables = [
  'meta',
  'docs',
  'sections',
  'links',
  'item_words',
  'cited_by',
  'diagram_parses',
  'code_files',
  'doc_search',
];

/// The values that decide whether an index is still current.
///
/// An index written under another stamp is dropped and rebuilt.
final class IndexStamp {
  const new({
    required this.binaryVersion,
    required this.docTypes,
    this.targetNames = const [],
  });

  /// Returns the stamp of this binary under the merged doc types of [set] and
  /// the config's [targetNames], in config order.
  static IndexStamp of(MergedSet set, {List<String> targetNames = const []}) =>
      IndexStamp(
        binaryVersion: specstoneVersion,
        docTypes: contentHashOf(
          utf8.encode(jsonEncode([for (final t in set.docTypes) t.toJson()])),
        ),
        targetNames: targetNames,
      );

  /// The version of the binary that wrote the index.
  final String binaryVersion;

  /// The SHA-256 of the merged doc types as hex.
  final String docTypes;

  /// The config's target names in `targets:` order; empty with one unnamed
  /// target, so a rename, add, or removal gives another stamp.
  final List<String> targetNames;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is IndexStamp &&
      other.binaryVersion == binaryVersion &&
      other.docTypes == docTypes &&
      _sameNames(other.targetNames);

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(binaryVersion, docTypes, targetNames.length);

  bool _sameNames(List<String> other) {
    if (targetNames.length != other.length) return false;
    for (final (i, name) in targetNames.indexed) {
      if (other[i] != name) return false;
    }
    return true;
  }
}

/// One full-text hit.
final class SearchRow {
  const new({required this.docPath, this.sectionKey, required this.snippet});

  /// The path of the doc that holds the match.
  final String docPath;

  /// The key of the section that holds the match; null for a title or alias.
  final String? sectionKey;

  /// The matching text with its surroundings.
  final String snippet;
}

/// The per-checkout SQLite index under `.specstone/`.
final class IndexStore {
  new _(this._db, this._specstoneFolder, this.warnings, this._busyTimeout);

  /// Opens the index of [projectRoot], creating it when none exists.
  ///
  /// A file that is no index is deleted and rebuilt empty, and [warnings]
  /// then holds [damagedIndexWarning]. A new index also gets its
  /// `.specstone/.gitignore` lines.
  ///
  /// Throws [IndexFault] when the index is busy or cannot be written, and
  /// `RenderFault` `output_not_writable` when the index, a file SQLite makes
  /// beside it, or `.specstone/.gitignore` leads outside the project or into
  /// `.git`.
  static IndexStore open(
    Directory projectRoot, {
    Duration busyTimeout = indexBusyTimeout,
  }) => _open(projectRoot, busyTimeout, discard: false);

  /// Deletes the index of [projectRoot] and opens an empty one.
  ///
  /// [warnings] holds [damagedIndexWarning]. Use it after a read or write
  /// failed with a damage error ([isDamage]) on an index that opened.
  static IndexStore openRebuilt(
    Directory projectRoot, {
    Duration busyTimeout = indexBusyTimeout,
  }) => _open(projectRoot, busyTimeout, discard: true);

  /// Opens an empty index held in memory: no file, no `.specstone/.gitignore`,
  /// no lock folder, so a caller that reads docs once writes nothing.
  ///
  /// A refresh fills it whole, as for any index that holds no stamp.
  static IndexStore inMemory() {
    final db = sqlite3.openInMemory()..execute(_schema);
    return IndexStore._(db, null, [], indexBusyTimeout);
  }

  /// Whether [e] says the file is no readable index.
  static bool isDamage(SqliteException e) =>
      e.resultCode == SqlError.SQLITE_NOTADB ||
      e.resultCode == SqlError.SQLITE_CORRUPT;

  /// The fault that describes [e]; any error with no fault of its own means
  /// the index cannot be written.
  static IndexFault faultOf(SqliteException e) =>
      _faultOf(e) ??
      IndexFault(IndexFaultCode.indexNotWritable, _notWritableMessage);

  static IndexStore _open(
    Directory projectRoot,
    Duration busyTimeout, {
    required bool discard,
  }) {
    final file = File.fromUri(projectRoot.uri.resolve(indexFilePath));
    for (final suffix in _indexFileSuffixes) {
      requireWritableTarget('${file.path}$suffix', projectRoot: projectRoot);
    }
    final warnings = <String>[];
    try {
      if (!discard) {
        try {
          return IndexStore._(
            _connect(file, busyTimeout),
            file.parent,
            warnings,
            busyTimeout,
          );
        } on _NotAnIndex {
          // Falls through to the rebuild below.
        } on SqliteException catch (e) {
          if (!isDamage(e)) rethrow;
        }
      }
      _deleteFiles(file);
      warnings.add(damagedIndexWarning);
      return IndexStore._(
        _connect(file, busyTimeout),
        file.parent,
        warnings,
        busyTimeout,
      );
    } on SqliteException catch (e) {
      throw _faultOf(e) ?? e;
    } on FileSystemException {
      throw IndexFault(IndexFaultCode.indexNotWritable, _notWritableMessage);
    }
  }

  final Database _db;

  // Null for an index held in memory, which has no `.gitignore` to keep.
  final Directory? _specstoneFolder;

  final Duration _busyTimeout;

  int _snapshotGeneration = 0;

  // Whether an outermost write transaction is open; it is a read view already.
  bool _holdsWrite = false;

  // Whether the open outermost write moves the doc generation at its commit;
  // false only for a [writeCodeFacts] write.
  bool _docsChanged = false;

  // The statements `_exec` prepared in the open outermost write, by SQL text.
  Map<String, PreparedStatement>? _writeStatements;

  /// What went wrong while opening, one sentence each.
  final List<String> warnings;

  // Prepared once: `loadContent` runs per doc, and a check reads every doc.
  final List<PreparedStatement> _prepared = [];
  late final PreparedStatement _contentSql = _prepare(
    'SELECT frontmatter_text, head, line_facts, banned_matches, item_facts '
    'FROM docs '
    'WHERE doc_path = ?',
  );
  late final PreparedStatement _textSql = _prepare(
    'SELECT text FROM docs WHERE doc_path = ?',
  );
  late final PreparedStatement _sectionsSql = _prepare(
    'SELECT section_key, header_line, body, line_count, char_count '
    'FROM sections WHERE doc_path = ? ORDER BY position',
  );
  late final PreparedStatement _linksSql = _prepare(
    'SELECT target FROM links WHERE source = ? ORDER BY position',
  );

  /// Returns the stamp the index was written under; null when none, when
  /// the index has another layout, or when the row is damaged, so a
  /// damaged index rebuilds whole instead of failing the read.
  IndexStamp? readStamp() {
    final row = _db.select('SELECT * FROM meta').firstOrNull;
    if (row == null) return null;
    final hasTargetNames = row.keys.any((k) => k == 'target_names');
    if (!hasTargetNames || indexLayoutVersion != row['layout']) return null;
    if (row['target_names'] case final String text) {
      final names = _namesOf(text);
      if (names == null) return null;
      return IndexStamp(
        binaryVersion: row['binary_version'] as String,
        docTypes: row['doc_types'] as String,
        targetNames: names,
      );
    }
    return null;
  }

  /// Returns the target names of a stored JSON array; null when [text] is
  /// not a JSON array of strings, so a damaged row rebuilds.
  static List<String>? _namesOf(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! List) return null;
    final names = <String>[];
    for (final name in decoded) {
      if (name is! String) return null;
      names.add(name);
    }
    return names;
  }

  /// Returns the content hash of every stored doc by docPath.
  Map<String, String> hashes() => {
    for (final row in _db.select('SELECT doc_path, content_hash FROM docs'))
      row['doc_path'] as String: row['content_hash'] as String,
  };

  /// Returns the stat key of every stored doc by docPath; null for a doc
  /// stored with none.
  Map<String, FileStatKey?> statKeys() => {
    for (final row in _db.select(
      'SELECT doc_path, stat_size, stat_mtime, stat_ctime, stat_mode '
      'FROM docs',
    ))
      row['doc_path'] as String: switch ((
        row['stat_size'],
        row['stat_mtime'],
        row['stat_ctime'],
        row['stat_mode'],
      )) {
        (
          final int size,
          final int modified,
          final int changed,
          final int mode,
        ) =>
          FileStatKey(
            size: size,
            modified: modified,
            changed: changed,
            mode: mode,
          ),
        _ => null,
      },
  };

  /// Stores [key] as the stat key of the doc at [docPath]; null clears it.
  void setStatKey(String docPath, FileStatKey? key) {
    _markDocsChanged();
    _exec(
      'UPDATE docs SET stat_size = ?, stat_mtime = ?, stat_ctime = ?, '
      'stat_mode = ? WHERE doc_path = ?',
      [key?.size, key?.modified, key?.changed, key?.mode, docPath],
    );
  }

  /// Returns when the refresh that last wrote the index began listing, in
  /// microseconds since the epoch; null when none stored it.
  int? readCheckedAt() =>
      _db.select('SELECT checked_at FROM meta').firstOrNull?['checked_at']
          as int?;

  /// Stores [checkedAt] as the start of the listing that wrote the index.
  void setCheckedAt(int checkedAt) {
    _markDocsChanged();
    _db.execute('UPDATE meta SET checked_at = ?', [checkedAt]);
  }

  /// Runs [body] in one write transaction.
  ///
  /// Rolls back every change and rethrows when [body] throws. Inside an open
  /// transaction, [body] runs in a savepoint instead: a throw undoes [body]
  /// alone, and a return commits with the outer transaction.
  ///
  /// Throws [IndexFault] when another call holds the write lock or the index
  /// cannot be written. A nested write whose error ends the outer write fails
  /// the outer one, past any caller that catches it.
  void write(void Function() body) {
    final nested = !_db.autocommit;
    try {
      _db.execute(nested ? 'SAVEPOINT $_nestedWrite' : 'BEGIN IMMEDIATE');
      if (!nested) _openWrite();
      try {
        body();
        if (nested) {
          _db.execute('RELEASE $_nestedWrite');
        } else {
          _commitWrite();
        }
      } on Object catch (error) {
        if (nested && _holdsWrite && _db.autocommit) throw _LostWrite.of(error);
        _undoWrite(nested);
        rethrow;
      } finally {
        if (!nested) _closeWrite();
      }
    } on _LostWrite catch (lost) {
      if (nested) rethrow;
      throw lost.fault;
    } on SqliteException catch (e) {
      throw _faultOf(e) ?? e;
    }
  }

  /// Runs [body], a write of code-file facts alone, as [write] does, but
  /// throws [IndexFault] `index_busy` at once when another call holds the
  /// write lock, instead of waiting the busy timeout.
  ///
  /// Its own commit leaves the doc generation alone, so a peer's snapshot stays
  /// current; inside an open write, [body] joins it and the outer commit
  /// moves the generation. The busy timeout is restored after.
  void writeCodeFacts(void Function() body) {
    final outermost = _db.autocommit;
    _db.execute('PRAGMA busy_timeout = 0');
    try {
      write(() {
        if (outermost) _docsChanged = false;
        body();
      });
    } finally {
      _db.execute('PRAGMA busy_timeout = ${_busyTimeout.inMilliseconds}');
    }
  }

  /// Runs [body] in one write transaction held across its awaits.
  ///
  /// Rolls back every change and rethrows when [body] throws. Holds the write
  /// lock from the call until [body] completes, so use the store from nothing
  /// else meanwhile.
  ///
  /// Throws [IndexFault] when another call holds the write lock or the index
  /// cannot be written.
  Future<T> writeAsync<T>(Future<T> Function() body) async {
    try {
      _db.execute('BEGIN IMMEDIATE');
      _openWrite();
      try {
        final result = await body();
        _commitWrite();
        return result;
      } on Object {
        _undoWrite(false);
        rethrow;
      } finally {
        _closeWrite();
      }
    } on _LostWrite catch (lost) {
      throw lost.fault;
    } on SqliteException catch (e) {
      throw _faultOf(e) ?? e;
    }
  }

  void _openWrite() {
    _holdsWrite = true;
    // Every write moves the generation unless it is [writeCodeFacts]; a new
    // write path is then seen by a peer's snapshot without a mark of its own.
    _docsChanged = true;
    _writeStatements = {};
  }

  /// Commits the outermost write, moving the doc generation unless it was a
  /// [writeCodeFacts] write.
  void _commitWrite() {
    if (_docsChanged) _bumpGeneration();
    _db.execute('COMMIT');
  }

  /// Notes a change a peer's snapshot must see as stale: at the commit of the
  /// open write, or at once outside one.
  void _markDocsChanged() {
    if (_holdsWrite) {
      _docsChanged = true;
    } else {
      _bumpGeneration();
    }
  }

  void _bumpGeneration() =>
      _db.execute('UPDATE meta SET generation = generation + 1');

  /// Returns the doc generation of the meta row, which moves with each commit
  /// that changes docs or their derived rows but not code-file facts; -1 when
  /// the row holds none.
  int _generation() {
    final row = _db.select('SELECT * FROM meta').firstOrNull;
    if (row == null || !row.keys.contains('generation')) return -1;
    return row['generation'] as int;
  }

  void _closeWrite() {
    _holdsWrite = false;
    _docsChanged = false;
    final statements = _writeStatements;
    _writeStatements = null;
    if (statements == null) return;
    for (final statement in statements.values) {
      statement.close();
    }
  }

  /// Runs [sql] with [args], through a statement kept until the outermost
  /// write ends; outside a write, it prepares and discards one.
  void _exec(String sql, List<Object?> args) {
    final statements = _writeStatements;
    if (statements == null) {
      _db.execute(sql, args);
      return;
    }
    (statements[sql] ??= _db.prepare(sql)).execute(args);
  }

  void _undoWrite(bool nested) {
    if (_db.autocommit) return;
    if (!nested) {
      _db.execute('ROLLBACK');
      return;
    }
    _db
      ..execute('ROLLBACK TO $_nestedWrite')
      ..execute('RELEASE $_nestedWrite');
  }

  /// Checks the `.gitignore` lines, drops every table, recreates them empty in
  /// this layout, and stores [stamp]; an index held in memory has no
  /// `.gitignore` to check.
  ///
  /// Throws [IndexFault] when `.specstone/.gitignore` cannot be written; no
  /// table is touched then.
  void reset(IndexStamp stamp) {
    if (_specstoneFolder case final folder?) {
      try {
        ensureSpecstoneGitignore(folder);
      } on FileSystemException {
        throw IndexFault(IndexFaultCode.indexNotWritable, _notWritableMessage);
      }
    }
    // Past the generation of the index it replaces, so no snapshot of that
    // index reads the new one as fresh.
    final generation = _generation() + 1;
    for (final table in _tables) {
      _db.execute('DROP TABLE IF EXISTS $table');
    }
    _db
      ..execute(_schema)
      ..execute(
        'INSERT INTO meta (binary_version, doc_types, target_names, layout, '
        'generation) VALUES (?, ?, ?, ?, ?)',
        [
          stamp.binaryVersion,
          stamp.docTypes,
          jsonEncode(stamp.targetNames),
          indexLayoutVersion,
          generation,
        ],
      );
    _markDocsChanged();
  }

  /// Replaces every row of the doc [parsed] describes, but its search rows.
  ///
  /// The doc ends with no search rows and no `search_hash`; [fillSearchRows]
  /// writes them.
  void putDoc(ParsedDoc parsed) {
    final doc = parsed.doc;
    final content = parsed.content;
    _markDocsChanged();
    deleteDoc(doc.docPath);
    _exec(
      'INSERT INTO docs (doc_path, doc_type_id, name, target, title, '
      'frontmatter, tokens, formatted, approval_hash, ord, warnings, '
      'content_hash, text, frontmatter_text, head, line_facts, '
      'banned_matches, item_facts, matrix_lines) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        doc.docPath,
        doc.docTypeId,
        doc.name,
        doc.target,
        doc.title,
        jsonEncode(doc.frontmatter),
        doc.tokens,
        switch (doc.formatted) {
          final bool formatted => formatted ? 1 : 0,
          null => null,
        },
        doc.approvalHash,
        doc.order,
        jsonEncode(doc.warnings),
        parsed.contentHash,
        content.text,
        content.frontmatterText,
        content.head,
        jsonEncode(content.lineFacts.toJson()),
        jsonEncode(bannedMatchesToJson(content.bannedMatches)),
        jsonEncode(content.itemFacts.toJson()),
        jsonEncode([for (final line in doc.matrixLines) line.toJson()]),
      ],
    );
    for (final (position, section) in content.sections.indexed) {
      final counts = content.lineFacts.sectionCounts[position];
      _exec(
        'INSERT INTO sections (doc_path, position, section_key, header_line, '
        'body, line_count, char_count) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          doc.docPath,
          position,
          section.key,
          section.headerLine,
          section.body,
          counts.lines,
          counts.chars,
        ],
      );
    }
    for (final (position, target) in content.links.indexed) {
      _exec('INSERT INTO links (source, position, target) VALUES (?, ?, ?)', [
        doc.docPath,
        position,
        target,
      ]);
    }
    for (final (position, item) in content.itemWords.indexed) {
      _exec(
        'INSERT INTO item_words (doc_path, position, line, item_id, words) '
        'VALUES (?, ?, ?, ?, ?)',
        [doc.docPath, position, item.line, item.itemId, item.words.join(' ')],
      );
    }
  }

  /// Returns the stored parse of each block in [blockHashes] under
  /// [parserHash], by block hash; a block with none is absent.
  ///
  /// Reads every row in one query.
  Map<String, DiagramParse> diagramParsesOf(
    Set<String> blockHashes, {
    required String parserHash,
  }) {
    if (blockHashes.isEmpty) return const {};
    final marks = List.filled(blockHashes.length, '?').join(', ');
    return {
      for (final row in _db.select(
        'SELECT block_hash, diagram, parses, message, block_line '
        'FROM diagram_parses WHERE parser_hash = ? AND block_hash IN ($marks)',
        [parserHash, ...blockHashes],
      ))
        row['block_hash'] as String: DiagramParse(
          blockHash: row['block_hash'] as String,
          diagram: row['diagram'] as String?,
          parses: row['parses'] == 1,
          message: row['message'] as String?,
          blockLine: row['block_line'] as int?,
        ),
    };
  }

  /// Stores [rows] under [parserHash], replacing a row of the same block.
  ///
  /// Rows are keyed by content, so [putDoc] and [deleteDoc] leave them alone.
  /// Call it inside [write].
  void putDiagramParses(
    Iterable<DiagramParse> rows, {
    required String parserHash,
  }) {
    _markDocsChanged();
    for (final row in rows) {
      final parses = row.parses ? 1 : 0;
      _db.execute(
        'INSERT OR REPLACE INTO diagram_parses (block_hash, parser_hash, '
        'diagram, parses, message, block_line) VALUES (?, ?, ?, ?, ?, ?)',
        [
          row.blockHash,
          parserHash,
          row.diagram,
          parses,
          row.message,
          row.blockLine,
        ],
      );
    }
  }

  /// Returns the facts `check` kept of each code file, by file.
  ///
  /// The index stamp covers them: a change of binary or doc-type set resets
  /// the table with the rest.
  Map<CodeFileKey, CodeFileFacts> loadCodeFiles() => {
    for (final row in _db.select(
      'SELECT root, path, stat_size, stat_mtime, stat_ctime, stat_mode, '
      'fingerprint, mention_texts, resolved FROM code_files',
    ))
      CodeFileKey(
        root: row['root'] as String,
        path: row['path'] as String,
      ): CodeFileFacts(
        stat: FileStatKey(
          size: row['stat_size'] as int,
          modified: row['stat_mtime'] as int,
          changed: row['stat_ctime'] as int,
          mode: row['stat_mode'] as int,
        ),
        fingerprint: row['fingerprint'] as String?,
        mentionTexts: switch (row['mention_texts']) {
          final String json => _stringsOf(json),
          _ => null,
        },
        resolved: _stringsOf(row['resolved'] as String).toSet(),
      ),
  };

  /// Stores [facts], each replacing the row of its file.
  ///
  /// Call it inside [write].
  void putCodeFiles(Map<CodeFileKey, CodeFileFacts> facts) {
    for (final MapEntry(:key, :value) in facts.entries) {
      _exec(
        'INSERT OR REPLACE INTO code_files (root, path, stat_size, '
        'stat_mtime, stat_ctime, stat_mode, fingerprint, mention_texts, '
        'resolved) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          key.root,
          key.path,
          value.stat.size,
          value.stat.modified,
          value.stat.changed,
          value.stat.mode,
          value.fingerprint,
          switch (value.mentionTexts) {
            final texts? => jsonEncode(texts),
            null => null,
          },
          jsonEncode(value.resolved.toList()),
        ],
      );
    }
  }

  /// Removes the rows of [keys]; a key with no row is a no-op.
  ///
  /// Call it inside [write].
  void deleteCodeFiles(Iterable<CodeFileKey> keys) {
    for (final key in keys) {
      _exec('DELETE FROM code_files WHERE root = ? AND path = ?', [
        key.root,
        key.path,
      ]);
    }
  }

  static List<String> _stringsOf(String json) =>
      (jsonDecode(json) as List<Object?>).cast<String>();

  /// Whether any doc's search rows lag its indexed text.
  bool get searchRowsLag => _db
      .select(
        'SELECT 1 FROM docs '
        'WHERE search_hash IS NULL OR search_hash != content_hash LIMIT 1',
      )
      .isNotEmpty;

  /// Brings the search rows of every doc whose rows lag its indexed text up to
  /// date, in one write transaction.
  ///
  /// A doc lags when `search_hash` is not its `content_hash`. Rebuilds the rows
  /// from the stored title, `slug` values, and sections, and reads no file.
  /// Call it outside a snapshot, before the snapshot that reads the rows.
  ///
  /// Throws [IndexFault] when another call holds the write lock or the index
  /// cannot be written.
  void fillSearchRows() {
    if (!searchRowsLag) return;
    write(_writeLaggingRows);
  }

  void _writeLaggingRows() {
    final lagging = _db.select(
      'SELECT id, doc_path, title, frontmatter FROM docs '
      'WHERE search_hash IS NULL OR search_hash != content_hash',
    );
    if (lagging.isNotEmpty) _markDocsChanged();
    for (final row in lagging) {
      final id = row['id'] as int;
      final docPath = row['doc_path'] as String;
      final title = row['title'] as String?;
      final slugs = IndexedDoc(
        docPath: docPath,
        name: docPath,
        frontmatter:
            jsonDecode(row['frontmatter'] as String) as Map<String, Object?>,
        tokens: 0,
      ).valuesOf('slug');
      final sections = _db.select(
        'SELECT section_key, body FROM sections WHERE doc_path = ? '
        'ORDER BY position',
        [docPath],
      );
      final firstKey = sections.firstOrNull?.columnAt(0) as String?;
      final searchRows = <(String, String?)>[
        for (final heading in [?title, ...slugs]) (heading, firstKey),
        for (final section in sections)
          (section.columnAt(1) as String, section.columnAt(0) as String),
      ];
      _deleteSearchRows(id);
      for (final (n, (text, sectionKey)) in searchRows.indexed) {
        if (n >= _searchRowsPerDoc) {
          throw StateError('$docPath has too many search rows');
        }
        _db.execute(
          'INSERT INTO doc_search (rowid, text, path, section_key) '
          'VALUES (?, ?, ?, ?)',
          [(id << 32) + n, text, docPath, sectionKey],
        );
      }
      _db.execute('UPDATE docs SET search_hash = content_hash WHERE id = ?', [
        id,
      ]);
    }
  }

  void _deleteSearchRows(int docId) {
    final firstRowid = docId << 32;
    _db.execute('DELETE FROM doc_search WHERE rowid BETWEEN ? AND ?', [
      firstRowid,
      firstRowid + _searchRowsPerDoc - 1,
    ]);
  }

  /// Replaces the whole `cited_by` table with [cited], each place in the order
  /// the map holds it and each place's lines in their order.
  ///
  /// Call it inside [write].
  void putCitedBy(Map<CitedPlace, List<CitedBy>> cited) {
    _markDocsChanged();
    _db.execute('DELETE FROM cited_by');
    final insert = _db.prepare(
      'INSERT INTO cited_by (place_doc, place_kind, place_key, by_doc, '
      'by_name, by_type, by_item, by_section) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    );
    try {
      for (final MapEntry(key: place, value: lines) in cited.entries) {
        for (final by in lines) {
          insert.execute([
            place.docPath,
            place.kind.name,
            place.key,
            by.docPath,
            by.name,
            by.docType,
            by.byItem,
            by.bySection,
          ]);
        }
      }
    } finally {
      insert.close();
    }
  }

  /// Returns the cited-by lines [putCitedBy] stored, by the place each cites,
  /// places and lines in the order they were stored.
  Map<CitedPlace, List<CitedBy>> loadCitedBy() {
    final cited = <CitedPlace, List<CitedBy>>{};
    for (final row in _db.select(
      'SELECT place_doc, place_kind, place_key, by_doc, by_name, by_type, '
      'by_item, by_section FROM cited_by ORDER BY seq',
    )) {
      final place = CitedPlace(
        docPath: row['place_doc'] as String,
        kind: CitedKind.values.byName(row['place_kind'] as String),
        key: row['place_key'] as String?,
      );
      (cited[place] ??= []).add(
        CitedBy(
          docPath: row['by_doc'] as String,
          name: row['by_name'] as String,
          docType: row['by_type'] as String,
          byItem: row['by_item'] as String?,
          bySection: row['by_section'] as String,
        ),
      );
    }
    return cited;
  }

  /// Removes every row of the doc at [docPath]; an unknown path is a no-op.
  void deleteDoc(String docPath) {
    final ids = _db.select('SELECT id FROM docs WHERE doc_path = ?', [docPath]);
    if (ids.isEmpty) return;
    _markDocsChanged();
    _deleteSearchRows(ids.single['id'] as int);
    _exec('DELETE FROM docs WHERE doc_path = ?', [docPath]);
    _exec('DELETE FROM sections WHERE doc_path = ?', [docPath]);
    _exec('DELETE FROM links WHERE source = ?', [docPath]);
    _exec('DELETE FROM item_words WHERE doc_path = ?', [docPath]);
  }

  /// Stores the parent of each doc and the order of the docs.
  ///
  /// A doc missing from [parents] ends with no parent. [order] lists docPaths
  /// in tree order.
  void setTree({
    required Map<String, String> parents,
    required Map<String, String> parentWarnings,
    required List<String> order,
  }) {
    _markDocsChanged();
    _db.execute('UPDATE docs SET parent_path = NULL, parent_warning = NULL');
    for (final (position, docPath) in order.indexed) {
      _exec('UPDATE docs SET ord = ? WHERE doc_path = ?', [position, docPath]);
    }
    for (final MapEntry(:key, :value) in parents.entries) {
      _exec('UPDATE docs SET parent_path = ? WHERE doc_path = ?', [value, key]);
    }
    for (final MapEntry(:key, :value) in parentWarnings.entries) {
      _exec('UPDATE docs SET parent_warning = ? WHERE doc_path = ?', [
        value,
        key,
      ]);
    }
  }

  /// Starts a read transaction so every later read sees one state.
  ///
  /// Records the doc generation, so [snapshotIsStale] can tell a later commit
  /// by another connection. Does nothing inside [write] or [writeAsync], whose
  /// transaction is the read view.
  void beginSnapshot() {
    if (_holdsWrite) return;
    _db
      ..execute('BEGIN')
      ..select('SELECT count(*) FROM meta');
    _snapshotGeneration = _generation();
  }

  /// Whether another connection committed a change to docs or their derived
  /// rows since the last [beginSnapshot].
  ///
  /// A commit that stores code-file facts alone is no change. Read it inside a
  /// write transaction: the snapshot's own transaction never sees a later
  /// commit.
  bool get snapshotIsStale => _generation() != _snapshotGeneration;

  /// Ends the read transaction [beginSnapshot] started.
  ///
  /// Does nothing inside [write] or [writeAsync], so a nested index write
  /// cannot commit the outer transaction.
  void endSnapshot() {
    if (_holdsWrite) return;
    _db.execute('COMMIT');
  }

  /// Returns every stored doc by tree order.
  ///
  /// A doc's warnings are its own followed by its parent warning.
  List<IndexedDoc> loadDocs() => [
    for (final row in _db.select(
      'SELECT doc_path, doc_type_id, name, target, parent_path, '
      'parent_warning, title, frontmatter, tokens, formatted, approval_hash, '
      'ord, warnings, matrix_lines FROM docs ORDER BY ord, doc_path',
    ))
      IndexedDoc(
        docPath: row['doc_path'] as String,
        docTypeId: row['doc_type_id'] as String?,
        name: row['name'] as String,
        target: row['target'] as String?,
        parentPath: row['parent_path'] as String?,
        title: row['title'] as String?,
        frontmatter: Map<String, Object?>.from(
          jsonDecode(row['frontmatter'] as String) as Map<String, Object?>,
        ),
        tokens: row['tokens'] as int,
        formatted: switch (row['formatted']) {
          final int flag => flag == 1,
          _ => null,
        },
        approvalHash: row['approval_hash'] as String?,
        order: row['ord'] as int,
        warnings: [
          ...(jsonDecode(row['warnings'] as String) as List<Object?>)
              .cast<String>(),
          if (row['parent_warning'] case final String warning) warning,
        ],
        matrixLines: [
          for (final line
              in jsonDecode(row['matrix_lines'] as String) as List<Object?>)
            MatrixLine.fromJson(line! as Map<String, Object?>),
        ],
      ),
  ];

  /// Returns the text and structure of the doc at [docPath].
  ///
  /// The text is read on first use, so read it before [close].
  DocContent loadContent(String docPath) {
    final doc = _contentSql.select([docPath]).single;
    final rows = _sectionsSql.select([docPath]);
    // Only the column values are captured: the Row would pin line_facts too.
    final banned = doc['banned_matches'] as String;
    final itemFacts = doc['item_facts'] as String;
    return DocContent(
      readText: () => _textSql.select([docPath]).single['text'] as String,
      frontmatterText: doc['frontmatter_text'] as String?,
      head: doc['head'] as String,
      sections: [
        for (final row in rows)
          IndexedSection(
            key: row['section_key'] as String,
            headerLine: row['header_line'] as String,
            body: row['body'] as String,
          ),
      ],
      links: [
        for (final row in _linksSql.select([docPath])) row['target'] as String,
      ],
      lineFacts: lineFactsFromJson(
        jsonDecode(doc['line_facts'] as String) as Map<String, Object?>,
        sectionCounts: [
          for (final row in rows)
            SectionCounts(
              lines: row['line_count'] as int,
              chars: row['char_count'] as int,
            ),
        ],
      ),
      readBannedMatches: () =>
          bannedMatchesFromJson(jsonDecode(banned) as List<Object?>),
      readItemFacts: () => ItemFacts.fromJson(jsonDecode(itemFacts)),
    );
  }

  /// Returns the rows that match [matchExpression], best match first.
  List<SearchRow> search(String matchExpression) => [
    for (final row in _db.select(
      "SELECT path, section_key, snippet(doc_search, 0, '', '', '…', 64) "
      'FROM doc_search WHERE doc_search MATCH ? ORDER BY rank',
      [matchExpression],
    ))
      SearchRow(
        docPath: row.columnAt(0) as String,
        sectionKey: row.columnAt(1) as String?,
        snippet: row.columnAt(2) as String,
      ),
  ];

  /// Returns the docPaths whose text holds [needle], case-sensitive.
  List<String> docPathsHolding(String needle) => [
    for (final row in _db.select(
      'SELECT doc_path FROM docs WHERE instr(text, ?) > 0',
      [needle],
    ))
      row.columnAt(0) as String,
  ];

  /// Returns every link as its source and target docPath.
  List<IndexedLink> loadLinks() => [
    for (final row in _db.select(
      'SELECT source, target FROM links ORDER BY source, position',
    ))
      IndexedLink(
        source: row['source'] as String,
        target: row['target'] as String,
      ),
  ];

  /// Returns the normalized words of every item of a rule-bearing section,
  /// by docPath and then item order.
  ///
  /// Only `check --repeats` reads them, so no other read decodes them.
  Iterable<IndexedItemWords> ruleItemWords() => [
    for (final row in _db.select(
      'SELECT doc_path, line, item_id, words FROM item_words '
      'ORDER BY doc_path, position',
    ))
      IndexedItemWords(
        docPath: row['doc_path'] as String,
        line: row['line'] as int,
        itemId: row['item_id'] as String?,
        words: (row['words'] as String).split(' '),
      ),
  ];

  /// Closes the prepared statements, then the connection.
  ///
  /// An open statement keeps the file open past `Database.close`, so a
  /// rebuild after it could not delete the file.
  void close() {
    for (final statement in _prepared) {
      statement.close();
    }
    _prepared.clear();
    _db.close();
  }

  PreparedStatement _prepare(String sql) {
    final statement = _db.prepare(sql);
    _prepared.add(statement);
    return statement;
  }
}

/// A database that holds tables but no `meta` table.
final class _NotAnIndex implements Exception {
  const new();
}

/// A nested write's error that made SQLite roll back the outer write.
///
/// Neither an [IndexFault] nor a [SqliteException], so no caller of the nested
/// write swallows it; the outer write throws [fault].
final class _LostWrite implements Exception {
  new of(Object error)
    : fault = switch (error) {
        _LostWrite(:final fault) => fault,
        IndexFault() => error,
        SqliteException() => IndexStore.faultOf(error),
        _ => IndexFault(IndexFaultCode.indexNotWritable, _notWritableMessage),
      };

  final IndexFault fault;
}

/// Opens [file] and returns the connection to an index with a `meta` table.
///
/// A missing or empty file first gets its `.gitignore` lines. A database with
/// no table is new: its `.gitignore` lines are checked and its schema created
/// inside one write transaction. A database with tables but no `meta` is
/// judged damaged only after the same lock confirms it, so a parallel first
/// open never deletes the index the other call is making.
///
/// Throws [_NotAnIndex] when the file is a database that is no index, and
/// [FileSystemException] when the `.gitignore` cannot be written.
Database _connect(File file, Duration busyTimeout) {
  // Before sqlite3.open creates the file, so a refused write leaves no
  // unignored index behind.
  if (!file.existsSync() || file.lengthSync() == 0) {
    ensureSpecstoneGitignore(file.parent);
  }
  final db = sqlite3.open(file.path);
  try {
    db.execute('PRAGMA busy_timeout = ${busyTimeout.inMilliseconds}');
    _enterWal(db, busyTimeout);
    if (!_tableNames(db).contains('meta')) _createUnderLock(db, file.parent);
    return db;
  } on Object {
    db.close();
    rethrow;
  }
}

/// Switches [db] to WAL, retrying on `SQLITE_BUSY` until [busyTimeout] lapses.
///
/// The switch promotes a read lock inside its own statement, and SQLite then
/// skips the busy handler and returns `SQLITE_BUSY` at once so the caller can
/// drop its lock; the wait is left to the caller. Rethrows the last busy error
/// after the timeout, and any other error at once.
void _enterWal(Database db, Duration busyTimeout) {
  final watch = Stopwatch()..start();
  while (true) {
    try {
      db.execute('PRAGMA journal_mode = WAL');
      return;
    } on SqliteException catch (e) {
      if (e.resultCode != SqlError.SQLITE_BUSY ||
          watch.elapsed >= busyTimeout) {
        rethrow;
      }
      sleep(const Duration(milliseconds: 10));
    }
  }
}

void _createUnderLock(Database db, Directory folder) {
  db.execute('BEGIN IMMEDIATE');
  try {
    final names = _tableNames(db);
    if (names.isEmpty) {
      ensureSpecstoneGitignore(folder);
      db.execute(_schema);
    } else if (!names.contains('meta')) {
      throw const _NotAnIndex();
    }
    db.execute('COMMIT');
  } on Object {
    if (!db.autocommit) db.execute('ROLLBACK');
    rethrow;
  }
}

Set<String> _tableNames(Database db) => {
  for (final row in db.select(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  ))
    row['name'] as String,
};

/// The names SQLite makes beside the index file, by their suffix.
const _indexFileSuffixes = ['', '-wal', '-shm', '-journal'];

void _deleteFiles(File file) {
  for (final suffix in ['', '-wal', '-shm']) {
    final sibling = File('${file.path}$suffix');
    if (sibling.existsSync()) sibling.deleteSync();
  }
}

IndexFault? _faultOf(SqliteException e) => switch (e.resultCode) {
  SqlError.SQLITE_BUSY => IndexFault(
    IndexFaultCode.indexBusy,
    indexBusyMessage,
  ),
  SqlError.SQLITE_READONLY ||
  SqlError.SQLITE_CANTOPEN ||
  SqlError.SQLITE_PERM => IndexFault(
    IndexFaultCode.indexNotWritable,
    _notWritableMessage,
  ),
  _ => null,
};

/// Appends each missing line of [specstoneGitignoreLines] to `.gitignore` in
/// [specstoneFolder], keeping every line it holds in place.
///
/// Throws [FileSystemException] when a line is missing and the file is
/// read-only: a rename would replace it whatever its mode, and `RenderFault`
/// `output_not_writable` when the file leads outside the project or into
/// `.git`.
void ensureSpecstoneGitignore(Directory specstoneFolder) {
  final target = File.fromUri(specstoneFolder.uri.resolve('.gitignore'));
  requireWritableTarget(target.path, projectRoot: specstoneFolder.parent);
  final text = target.existsSync() ? target.readAsStringSync() : '';
  final present = const LineSplitter().convert(text).toSet();
  final missing = [
    for (final line in specstoneGitignoreLines)
      if (!present.contains(line)) '$line\n',
  ];
  if (missing.isEmpty) return;
  if (isReadOnly(target)) {
    throw FileSystemException('the file is read-only', target.path);
  }
  final separator = text.isEmpty || text.endsWith('\n') ? '' : '\n';
  writeFileAtomic(target, utf8.encode('$text$separator${missing.join()}'));
}
