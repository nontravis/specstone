import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/atomic_write.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
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

const _gitignoreLines = ['index.sqlite*', 'build/'];

const _busyMessage =
    'the index is busy; run the command again once the other call finishes';

const _notWritableMessage =
    'cannot write the index under .specstone/; make it writable and run the '
    'command again';

const _schema = '''
CREATE TABLE meta (
  binary_version TEXT NOT NULL,
  doc_types TEXT NOT NULL
);
CREATE TABLE docs (
  doc_path TEXT PRIMARY KEY,
  doc_type_id TEXT,
  name TEXT NOT NULL,
  parent_path TEXT,
  parent_warning TEXT,
  title TEXT,
  frontmatter TEXT NOT NULL,
  tokens INTEGER NOT NULL,
  ord INTEGER NOT NULL,
  warnings TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  text TEXT NOT NULL,
  frontmatter_text TEXT,
  head TEXT NOT NULL
);
CREATE TABLE sections (
  doc_path TEXT NOT NULL,
  position INTEGER NOT NULL,
  section_key TEXT NOT NULL,
  header_line TEXT NOT NULL,
  body TEXT NOT NULL,
  PRIMARY KEY (doc_path, position)
);
CREATE TABLE links (
  source TEXT NOT NULL,
  position INTEGER NOT NULL,
  target TEXT NOT NULL,
  PRIMARY KEY (source, position)
);
CREATE VIRTUAL TABLE doc_search USING fts5(
  text, path UNINDEXED, section_key UNINDEXED, tokenize = 'trigram'
);
''';

const _tables = ['meta', 'docs', 'sections', 'links', 'doc_search'];

/// The pair of values that decides whether an index is still current.
///
/// An index written under another stamp is dropped and rebuilt.
final class IndexStamp {
  const new({required this.binaryVersion, required this.docTypes});

  /// Returns the stamp of this binary under the merged doc types of [set].
  static IndexStamp of(MergedSet set) => IndexStamp(
    binaryVersion: specstoneVersion,
    docTypes: contentHashOf(
      utf8.encode(jsonEncode([for (final t in set.docTypes) t.toJson()])),
    ),
  );

  /// The version of the binary that wrote the index.
  final String binaryVersion;

  /// The SHA-256 of the merged doc types as hex.
  final String docTypes;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  bool operator ==(Object other) =>
      other is IndexStamp &&
      other.binaryVersion == binaryVersion &&
      other.docTypes == docTypes;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes // all fields final
  int get hashCode => Object.hash(binaryVersion, docTypes);
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
  new _(this._db, this.warnings);

  /// Opens the index of [projectRoot], creating it when none exists.
  ///
  /// A file that is no index is deleted and rebuilt empty, and [warnings]
  /// then holds [damagedIndexWarning]. A new index also gets its
  /// `.specstone/.gitignore` lines.
  ///
  /// Throws [IndexFault] when the index is busy or cannot be written.
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
    final warnings = <String>[];
    try {
      if (!discard) {
        try {
          return IndexStore._(_connect(file, busyTimeout), warnings);
        } on _NotAnIndex {
          // Falls through to the rebuild below.
        } on SqliteException catch (e) {
          if (!isDamage(e)) rethrow;
        }
      }
      _deleteFiles(file);
      warnings.add(damagedIndexWarning);
      return IndexStore._(_connect(file, busyTimeout), warnings);
    } on SqliteException catch (e) {
      throw _faultOf(e) ?? e;
    } on FileSystemException {
      throw IndexFault(IndexFaultCode.indexNotWritable, _notWritableMessage);
    }
  }

  final Database _db;

  /// What went wrong while opening, one sentence each.
  final List<String> warnings;

  /// Returns the stamp the index was written under; null when none.
  IndexStamp? readStamp() {
    final rows = _db.select('SELECT binary_version, doc_types FROM meta');
    if (rows.isEmpty) return null;
    return IndexStamp(
      binaryVersion: rows.single['binary_version'] as String,
      docTypes: rows.single['doc_types'] as String,
    );
  }

  /// Returns the content hash of every stored doc by docPath.
  Map<String, String> hashes() => {
    for (final row in _db.select('SELECT doc_path, content_hash FROM docs'))
      row['doc_path'] as String: row['content_hash'] as String,
  };

  /// Runs [body] in one write transaction.
  ///
  /// Rolls back every change and rethrows when [body] throws.
  ///
  /// Throws [IndexFault] when another call holds the write lock or the index
  /// cannot be written.
  void write(void Function() body) {
    try {
      _db.execute('BEGIN IMMEDIATE');
      try {
        body();
        _db.execute('COMMIT');
      } on Object {
        if (!_db.autocommit) _db.execute('ROLLBACK');
        rethrow;
      }
    } on SqliteException catch (e) {
      throw _faultOf(e) ?? e;
    }
  }

  /// Drops every table, recreates them empty, and stores [stamp].
  void reset(IndexStamp stamp) {
    for (final table in _tables) {
      _db.execute('DROP TABLE IF EXISTS $table');
    }
    _db
      ..execute(_schema)
      ..execute('INSERT INTO meta (binary_version, doc_types) VALUES (?, ?)', [
        stamp.binaryVersion,
        stamp.docTypes,
      ]);
  }

  /// Replaces every row of the doc [parsed] describes.
  void putDoc(ParsedDoc parsed) {
    final doc = parsed.doc;
    final content = parsed.content;
    deleteDoc(doc.docPath);
    _db.execute(
      'INSERT INTO docs (doc_path, doc_type_id, name, title, frontmatter, '
      'tokens, ord, warnings, content_hash, text, frontmatter_text, head) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        doc.docPath,
        doc.docTypeId,
        doc.name,
        doc.title,
        jsonEncode(doc.frontmatter),
        doc.tokens,
        doc.order,
        jsonEncode(doc.warnings),
        parsed.contentHash,
        content.text,
        content.frontmatterText,
        content.head,
      ],
    );
    final firstKey = content.sections.firstOrNull?.key;
    for (final heading in [?doc.title, ...doc.valuesOf('slug')]) {
      _putSearch(heading, doc.docPath, firstKey);
    }
    for (final (position, section) in content.sections.indexed) {
      _db.execute(
        'INSERT INTO sections (doc_path, position, section_key, header_line, '
        'body) VALUES (?, ?, ?, ?, ?)',
        [doc.docPath, position, section.key, section.headerLine, section.body],
      );
      _putSearch(section.body, doc.docPath, section.key);
    }
    for (final (position, target) in content.links.indexed) {
      _db.execute(
        'INSERT INTO links (source, position, target) VALUES (?, ?, ?)',
        [doc.docPath, position, target],
      );
    }
  }

  /// Removes every row of the doc at [docPath].
  void deleteDoc(String docPath) {
    _db
      ..execute('DELETE FROM docs WHERE doc_path = ?', [docPath])
      ..execute('DELETE FROM sections WHERE doc_path = ?', [docPath])
      ..execute('DELETE FROM links WHERE source = ?', [docPath])
      ..execute('DELETE FROM doc_search WHERE path = ?', [docPath]);
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
    _db.execute('UPDATE docs SET parent_path = NULL, parent_warning = NULL');
    for (final (position, docPath) in order.indexed) {
      _db.execute('UPDATE docs SET ord = ? WHERE doc_path = ?', [
        position,
        docPath,
      ]);
    }
    for (final MapEntry(:key, :value) in parents.entries) {
      _db.execute('UPDATE docs SET parent_path = ? WHERE doc_path = ?', [
        value,
        key,
      ]);
    }
    for (final MapEntry(:key, :value) in parentWarnings.entries) {
      _db.execute('UPDATE docs SET parent_warning = ? WHERE doc_path = ?', [
        value,
        key,
      ]);
    }
  }

  /// Starts a read transaction so every later read sees one state.
  void beginSnapshot() {
    _db
      ..execute('BEGIN')
      ..select('SELECT count(*) FROM meta');
  }

  /// Ends the read transaction [beginSnapshot] started.
  void endSnapshot() => _db.execute('COMMIT');

  /// Returns every stored doc by tree order.
  ///
  /// A doc's warnings are its own followed by its parent warning.
  List<IndexedDoc> loadDocs() => [
    for (final row in _db.select(
      'SELECT doc_path, doc_type_id, name, parent_path, parent_warning, '
      'title, frontmatter, tokens, ord, warnings FROM docs '
      'ORDER BY ord, doc_path',
    ))
      IndexedDoc(
        docPath: row['doc_path'] as String,
        docTypeId: row['doc_type_id'] as String?,
        name: row['name'] as String,
        parentPath: row['parent_path'] as String?,
        title: row['title'] as String?,
        frontmatter: Map<String, Object?>.from(
          jsonDecode(row['frontmatter'] as String) as Map<String, Object?>,
        ),
        tokens: row['tokens'] as int,
        order: row['ord'] as int,
        warnings: [
          ...(jsonDecode(row['warnings'] as String) as List<Object?>)
              .cast<String>(),
          if (row['parent_warning'] case final String warning) warning,
        ],
      ),
  ];

  /// Returns the text and structure of the doc at [docPath].
  DocContent loadContent(String docPath) {
    final doc = _db.select(
      'SELECT text, frontmatter_text, head FROM docs WHERE doc_path = ?',
      [docPath],
    ).single;
    return DocContent(
      text: doc['text'] as String,
      frontmatterText: doc['frontmatter_text'] as String?,
      head: doc['head'] as String,
      sections: [
        for (final row in _db.select(
          'SELECT section_key, header_line, body FROM sections '
          'WHERE doc_path = ? ORDER BY position',
          [docPath],
        ))
          IndexedSection(
            key: row['section_key'] as String,
            headerLine: row['header_line'] as String,
            body: row['body'] as String,
          ),
      ],
      links: [
        for (final row in _db.select(
          'SELECT target FROM links WHERE source = ? ORDER BY position',
          [docPath],
        ))
          row['target'] as String,
      ],
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

  /// Returns every link as its source and target docPath.
  List<({String source, String target})> loadLinks() => [
    for (final row in _db.select(
      'SELECT source, target FROM links ORDER BY source, position',
    ))
      (source: row['source'] as String, target: row['target'] as String),
  ];

  /// Closes the connection.
  void close() => _db.close();

  void _putSearch(String text, String docPath, String? sectionKey) {
    _db.execute(
      'INSERT INTO doc_search (text, path, section_key) VALUES (?, ?, ?)',
      [text, docPath, sectionKey],
    );
  }
}

/// A database that holds tables but no `meta` table.
final class _NotAnIndex implements Exception {
  const new();
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
    _ensureGitignore(file.parent);
  }
  final db = sqlite3.open(file.path);
  try {
    db
      ..execute('PRAGMA busy_timeout = ${busyTimeout.inMilliseconds}')
      ..execute('PRAGMA journal_mode = WAL');
    if (!_tableNames(db).contains('meta')) _createUnderLock(db, file.parent);
    return db;
  } on Object {
    db.close();
    rethrow;
  }
}

void _createUnderLock(Database db, Directory folder) {
  db.execute('BEGIN IMMEDIATE');
  try {
    final names = _tableNames(db);
    if (names.isEmpty) {
      _ensureGitignore(folder);
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

void _deleteFiles(File file) {
  for (final suffix in ['', '-wal', '-shm']) {
    final sibling = File('${file.path}$suffix');
    if (sibling.existsSync()) sibling.deleteSync();
  }
}

IndexFault? _faultOf(SqliteException e) => switch (e.resultCode) {
  SqlError.SQLITE_BUSY => IndexFault(IndexFaultCode.indexBusy, _busyMessage),
  SqlError.SQLITE_READONLY ||
  SqlError.SQLITE_CANTOPEN ||
  SqlError.SQLITE_PERM => IndexFault(
    IndexFaultCode.indexNotWritable,
    _notWritableMessage,
  ),
  _ => null,
};

/// Adds each missing line of [_gitignoreLines] to `.gitignore` in [folder].
///
/// Throws [FileSystemException] when a line is missing and the file is
/// read-only: a rename would replace it whatever its mode.
void _ensureGitignore(Directory folder) {
  final target = File.fromUri(folder.uri.resolve('.gitignore'));
  final text = target.existsSync() ? target.readAsStringSync() : '';
  final present = const LineSplitter().convert(text).toSet();
  final missing = [
    for (final line in _gitignoreLines)
      if (!present.contains(line)) '$line\n',
  ];
  if (missing.isEmpty) return;
  if (isReadOnly(target)) {
    throw FileSystemException('the file is read-only', target.path);
  }
  final separator = text.isEmpty || text.endsWith('\n') ? '' : '\n';
  writeFileAtomic(target, utf8.encode('$text$separator${missing.join()}'));
}
