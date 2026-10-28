import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/version.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/posix_modes.dart';
import '../../helpers/temp_tree.dart';

void main() {
  Future<Directory> root() => writeTree({'.specstone/config.yaml': ''});
  ParsedDoc parsed(String path, String text) => parseIndexedDoc(
    docPath: path,
    bytes: utf8.encode(text),
    match: const NoDocType(),
  );
  File file(Directory r, String p) => File('${r.path}/$p');

  group('IndexStore', () {
    test('f01/us01/fr04, f01/us01/fr04/e01, f01/us01/fr04/e02, s03/inv22: the first open writes .specstone/.gitignore', () async {
      final r = await root();
      IndexStore.open(r).close();
      expect(
        file(r, '.specstone/.gitignore').readAsStringSync(),
        'index.sqlite*\nbuild/\ntrash/\n',
      );
      expect(file(r, '.specstone/index.sqlite').existsSync(), isTrue);
    });
    test('f01/us01/fr04, s03/inv22: two cold first opens in two isolates both open the index', () async {
      for (var i = 0; i < 20; i++) {
        final r = await root();
        final path = r.path;
        await Future.wait([
          for (var n = 0; n < 2; n++)
            Isolate.run(() => IndexStore.open(Directory(path)).close()),
        ]);
        expect(
          file(r, '.specstone/.gitignore').readAsStringSync(),
          'index.sqlite*\nbuild/\ntrash/\n',
        );
      }
    });
    test('f01/us01/fr05/e05, s03/inv23: a first open waits busyTimeout on a held write lock before it faults indexBusy', () async {
      final r = await root();
      file(r, '.specstone/index.sqlite').writeAsBytesSync(const []);
      final holder = sqlite3.open(file(r, '.specstone/index.sqlite').path)
        ..execute('BEGIN IMMEDIATE');
      addTearDown(() {
        holder
          ..execute('ROLLBACK')
          ..close();
      });
      const timeout = Duration(milliseconds: 300);
      final watch = Stopwatch()..start();

      expect(
        () => IndexStore.open(r, busyTimeout: timeout),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.indexBusy,
          ),
        ),
      );
      watch.stop();

      expect(watch.elapsed, greaterThanOrEqualTo(timeout));
    });
    test('f01/us01/fr04/e03: the root .gitignore is never written', () async {
      final r = await writeTree({
        '.specstone/config.yaml': '',
        '.gitignore': 'node_modules/\n',
      });
      IndexStore.open(r).close();
      expect(file(r, '.gitignore').readAsStringSync(), 'node_modules/\n');
    });
    test('f01/us01/s10, f01/us01/fr04/e04, s03/inv22: an existing ignore file keeps its lines first', () async {
      final r = await writeTree({
        '.specstone/config.yaml': '',
        '.specstone/.gitignore': '*.tmp',
      });
      IndexStore.open(r).close();
      expect(
        file(r, '.specstone/.gitignore').readAsStringSync(),
        '*.tmp\nindex.sqlite*\nbuild/\ntrash/\n',
      );
    });
    test(
      'f01/us01/fr04/e05: a file holding all three lines is left untouched',
      () async {
        const text = 'build/\n# mine\ntrash/\nindex.sqlite*\n';
        final r = await writeTree({
          '.specstone/config.yaml': '',
          '.specstone/.gitignore': text,
        });
        IndexStore.open(r).close();
        expect(file(r, '.specstone/.gitignore').readAsStringSync(), text);
      },
    );
    test('f01/us01/fr04/e05, f02/us04/fr03/e06: a file holding the two F-01 lines gains trash/ at its end', () async {
      final r = await writeTree({
        '.specstone/config.yaml': '',
        '.specstone/.gitignore': 'index.sqlite*\nbuild/\n',
      });
      ensureSpecstoneGitignore(Directory('${r.path}/.specstone'));
      expect(
        file(r, '.specstone/.gitignore').readAsStringSync(),
        'index.sqlite*\nbuild/\ntrash/\n',
      );
    });
    test(
      'f01/us01/fr04/e06, s03/inv23: a read-only .specstone/ is index_not_writable, exit 73, and writes nothing',
      skip: unreadablePathSkipReason(),
      () async {
        final r = await root();
        final dot = Directory('${r.path}/.specstone');
        Process.runSync('chmod', ['555', dot.path]);
        addTearDown(() => Process.runSync('chmod', ['755', dot.path]));
        expect(
          () => IndexStore.open(r),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.indexNotWritable)
                .having((f) => f.exitStatus, 'exit', 73),
          ),
        );
        expect(file(r, '.specstone/index.sqlite').existsSync(), isFalse);
      },
    );
    test(
      'f01/us01/fr04/e06, s03/inv23: a read-only .specstone/.gitignore is index_not_writable, exit 73, and leaves it and no index behind',
      skip: unreadablePathSkipReason(),
      () async {
        final r = await writeTree({
          '.specstone/config.yaml': '',
          '.specstone/.gitignore': '*.tmp\n',
        });
        final ignore = file(r, '.specstone/.gitignore');
        Process.runSync('chmod', ['444', ignore.path]);
        addTearDown(() => Process.runSync('chmod', ['644', ignore.path]));
        expect(
          () => IndexStore.open(r),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.indexNotWritable)
                .having((f) => f.exitStatus, 'exit', 73),
          ),
        );
        expect(ignore.readAsStringSync(), '*.tmp\n');
        expect(file(r, indexFilePath).existsSync(), isFalse);
      },
    );
    test('f01/us01/fr05, s03/inv23: the index opens in WAL mode', () async {
      final r = await root();
      IndexStore.open(r).close();
      final raw = sqlite3.open(file(r, indexFilePath).path);
      addTearDown(raw.close);
      expect(raw.select('PRAGMA journal_mode').single.columnAt(0), 'wal');
    });
    test('f01/us01/fr05/e03, s03/inv23: a file that is no index is deleted, rebuilt empty, and warned about', () async {
      final r = await writeTree({
        '.specstone/config.yaml': '',
        '.specstone/index.sqlite': 'not a database',
      });
      final store = IndexStore.open(r);
      addTearDown(store.close);
      expect(store.warnings, [damagedIndexWarning]);
      expect(store.readStamp(), isNull);
      expect(store.hashes(), isEmpty);
    });
    test(
      'f01/us01/fr05, f01/us01/fr04: a database with no tables is a new index, '
      'not a damaged one',
      () async {
        final r = await root();
        sqlite3.open(file(r, indexFilePath).path)
          ..execute('PRAGMA user_version = 1')
          ..close();
        expect(file(r, indexFilePath).lengthSync(), greaterThan(0));
        final store = IndexStore.open(r);
        addTearDown(store.close);
        expect(store.warnings, isEmpty);
        expect(store.readStamp(), isNull);
        expect(
          file(r, '.specstone/.gitignore').readAsStringSync(),
          'index.sqlite*\nbuild/\ntrash/\n',
        );
      },
    );
    test(
      'f01/us01/fr05/e03: a database with tables but no meta table is deleted, '
      'rebuilt empty, and warned about',
      () async {
        final r = await root();
        sqlite3.open(file(r, indexFilePath).path)
          ..execute('CREATE TABLE other (x)')
          ..close();
        final store = IndexStore.open(r);
        addTearDown(store.close);
        expect(store.warnings, [damagedIndexWarning]);
        expect(store.hashes(), isEmpty);
      },
    );
    test(
      'f01/us01/fr05/e04: a write that throws rolls back every change',
      () async {
        final store = IndexStore.open(await root());
        addTearDown(store.close);
        expect(
          () => store.write(() {
            store.putDoc(parsed('README.md', '# R\n'));
            throw StateError('killed');
          }),
          throwsStateError,
        );
        expect(store.hashes(), isEmpty);
      },
    );
    test('f01/us01/fr05/e05, s03/inv23: a write lock held past the busy timeout is index_busy, exit 75', () async {
      final r = await root();
      IndexStore.open(r).close();
      final holder = sqlite3.open(file(r, indexFilePath).path)
        ..execute('BEGIN IMMEDIATE');
      addTearDown(
        () => holder
          ..execute('ROLLBACK')
          ..close(),
      );
      final store = IndexStore.open(
        r,
        busyTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(store.close);
      expect(
        () => store.write(() => store.putDoc(parsed('README.md', '# R\n'))),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.indexBusy)
              .having((f) => f.exitStatus, 'exit', 75),
        ),
      );
    });
    test(
      'f01/us01/fr02/e07: a read-only index file refuses the write and stays byte-identical',
      skip: unreadablePathSkipReason(),
      () async {
        final r = await root();
        final first = IndexStore.open(r);
        first.write(() => first.putDoc(parsed('README.md', '# R\n')));
        first.close();
        final index = file(r, indexFilePath);
        final before = index.readAsBytesSync();
        Process.runSync('chmod', ['444', index.path]);
        addTearDown(() => Process.runSync('chmod', ['644', index.path]));
        final store = IndexStore.open(r);
        addTearDown(store.close);
        expect(
          () => store.write(() => store.putDoc(parsed('NOTES.md', '# N\n'))),
          throwsA(
            isA<IndexFault>().having(
              (f) => f.code,
              'code',
              IndexFaultCode.indexNotWritable,
            ),
          ),
        );
        expect(index.readAsBytesSync(), before);
      },
    );
    test('s03/inv2: a stamp round-trips, and another merged set gives another stamp', () async {
      MergedSet setWith(String description) => MergedSet(
        docTypes: [
          MergedDocType(
            id: 'feature',
            description: description,
            fields: const [],
            sections: const [],
            lint: const MergedLint(),
            files: const [],
          ),
        ],
      );
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      final stamp = IndexStamp.of(setWith('A feature'));
      store.write(() => store.reset(stamp));
      expect(store.readStamp(), stamp);
      expect(IndexStamp.of(setWith('Another feature')), isNot(stamp));
      expect(stamp.binaryVersion, specstoneVersion);
    });
    test('f04/nfr-p03, s03/inv2: a stored doc loads back with its line facts and section counts', () async {
      const text =
          '---\nstatus: planned\n---\n\n# T\n\n## A\nx\n```\n## no\n```\n\n'
          '## B\nhéllo \u{1F600}\n';
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      final written = parsed('A.md', text);
      store.write(() {
        store
          ..reset(
            const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x'),
          )
          ..putDoc(written);
      });
      final facts = store.loadContent('A.md').lineFacts;
      expect(facts.toJson(), written.content.lineFacts.toJson());
      expect(facts.sectionCounts, written.content.lineFacts.sectionCounts);
      expect(facts.sectionLines, [7, 13]);
      expect(facts.fenced, [(first: 9, last: 11)]);
      expect(facts.sectionCounts.last, (lines: 2, chars: 12));
    });
    test('f04/nfr-p03: the lines a check reads from a stored doc equal those it reads from the text', () async {
      const text =
          '---\ntraced_from:\n  - S1\n  - S2\n---\n\n# T\n\n'
          '## A\nx\n```\n## no\n```\n';
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      store.write(() {
        store
          ..reset(
            const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x'),
          )
          ..putDoc(parsed('A.md', text.replaceAll('\n', '\r\n')));
      });
      final stored = DocLines.from(store.loadContent('A.md'));
      final direct = DocLines.of(text);
      expect(stored.lines, direct.lines);
      expect(stored.lineCount, direct.lineCount);
      expect(stored.charCount, direct.charCount);
      expect(stored.titleLine, direct.titleLine);
      expect(stored.sectionLines, direct.sectionLines);
      expect(stored.sectionCounts, direct.sectionCounts);
      expect(stored.entriesOf('traced_from'), direct.entriesOf('traced_from'));
      expect(stored.keyLine('traced_from'), 2);
      expect(
        [for (var i = 1; i <= 14; i++) stored.isFenced(i)],
        [for (var i = 1; i <= 14; i++) direct.isFenced(i)],
      );
    });
    test('f01/us01/fr02/e02, s03/inv2: a meta row without the layout marker has no stamp, whatever the user_version', () async {
      final r = await root();
      final store = IndexStore.open(r);
      addTearDown(store.close);
      const stamp = IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x');
      store.write(() => store.reset(stamp));
      final raw = sqlite3.open(file(r, indexFilePath).path);
      addTearDown(raw.close);
      raw.userVersion = 7;
      expect(store.readStamp(), stamp);
      raw
        ..execute('DROP TABLE meta')
        ..execute(
          'CREATE TABLE meta (binary_version TEXT NOT NULL, '
          'doc_types TEXT NOT NULL)',
        )
        ..execute('INSERT INTO meta VALUES (?, ?)', [specstoneVersion, 'x'])
        ..userVersion = 1;
      expect(store.readStamp(), isNull);
    });
    test("f01/us01/fr02, s03/inv1: a doc's stat key and checked_at read back as stored; reset clears them", () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      const stamp = IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x');
      const key = (
        size: 4,
        modified: 1700000000123456,
        changed: 1700000000654321,
        mode: 33188,
      );
      store.write(() {
        store
          ..reset(stamp)
          ..putDoc(parsed('README.md', '# R\n'))
          ..putDoc(parsed('NOTES.md', '# N\n'))
          ..setStatKey('README.md', key)
          ..setCheckedAt(1700000005000000);
      });
      expect(store.statKeys(), {'README.md': key, 'NOTES.md': null});
      expect(store.readCheckedAt(), 1700000005000000);
      store.write(() => store.reset(stamp));
      expect(store.statKeys(), isEmpty);
      expect(store.readCheckedAt(), isNull);
    });
    test('s03/inv21, F1-D22: the FTS5 trigram table finds a Thai substring and a word part', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      store.write(
        () => store.putDoc(
          parsed(
            'README.md',
            '# Readme\n\n## Notes\nค้นหา เอกสาร in the catalog\n',
          ),
        ),
      );
      expect(store.search('"ค้นหา"').single.sectionKey, 'notes');
      expect(store.search('"log"').single.docPath, 'README.md');
    });
    test(
      'nfr-p02: a doc put twice leaves exactly one set of search rows',
      () async {
        final store = IndexStore.open(await root());
        addTearDown(store.close);
        final doc = parsed('a.md', '# Alpha\n\n## Notes\nzebra crossing\n');
        store.write(() {
          store
            ..putDoc(doc)
            ..putDoc(doc);
        });
        expect(store.search('"zebra"'), hasLength(1));
        expect(store.search('"alpha"'), hasLength(1));
      },
    );
    test(
      'nfr-p02: deleteDoc removes the search rows of that doc only',
      () async {
        final store = IndexStore.open(await root());
        addTearDown(store.close);
        store.write(() {
          store
            ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra crossing\n'))
            ..putDoc(parsed('b.md', '# Beta\n\n## Notes\nzebra herd\n'))
            ..deleteDoc('a.md');
        });
        expect(store.search('"crossing"'), isEmpty);
        expect(store.search('"alpha"'), isEmpty);
        expect(store.search('"zebra"').map((r) => r.docPath), ['b.md']);
        expect(store.search('"beta"').map((r) => r.docPath), ['b.md']);
      },
    );
    test('nfr-p02: deleteDoc of an unknown path changes nothing', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      store.write(() {
        store
          ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra crossing\n'))
          ..deleteDoc('missing.md');
      });
      expect(store.search('"zebra"').map((r) => r.docPath), ['a.md']);
    });
    test(
      'nfr-p02: a freed doc id is reused without the old search rows',
      () async {
        final store = IndexStore.open(await root());
        addTearDown(store.close);
        store.write(() {
          store
            ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra crossing\n'))
            ..putDoc(parsed('b.md', '# Beta\n\n## Notes\nllama trail\n'))
            ..deleteDoc('b.md')
            ..putDoc(parsed('c.md', '# Gamma\n\n## Notes\nheron marsh\n'));
        });
        expect(store.search('"llama"'), isEmpty);
        expect(store.search('"beta"'), isEmpty);
        expect(store.search('"heron"').map((r) => r.docPath), ['c.md']);
        expect(store.search('"zebra"').map((r) => r.docPath), ['a.md']);
      },
    );
    test(
      'nfr-p02: a doc put again with an edit finds the new text, not the old',
      () async {
        final store = IndexStore.open(await root());
        addTearDown(store.close);
        store.write(() {
          store
            ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra crossing\n'))
            ..putDoc(parsed('b.md', '# Beta\n\n## Notes\nzebra herd\n'))
            ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nllama trail\n'));
        });
        expect(store.search('"crossing"'), isEmpty);
        expect(store.search('"llama"').map((r) => r.docPath), ['a.md']);
        expect(store.search('"zebra"').map((r) => r.docPath), ['b.md']);
      },
    );
  });
}
