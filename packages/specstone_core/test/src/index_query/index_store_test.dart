@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/consistency_check/doc_lines.dart';
import 'package:specstone_core/src/consistency_check/models/doc_lines.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/index_query/diagram_parse.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/models/banned_match.dart';
import 'package:specstone_core/src/index_query/models/cited_by.dart';
import 'package:specstone_core/src/index_query/models/cited_place.dart';
import 'package:specstone_core/src/index_query/models/code_file_facts.dart';
import 'package:specstone_core/src/index_query/models/code_file_key.dart';
import 'package:specstone_core/src/index_query/models/file_stat_key.dart';
import 'package:specstone_core/src/index_query/models/line_range.dart';
import 'package:specstone_core/src/index_query/models/matrix_line.dart';
import 'package:specstone_core/src/index_query/models/section_counts.dart';
import 'package:specstone_core/src/index_query/refresh.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:specstone_core/src/version.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/record_doc_type.dart';
import '../../helpers/software_tech.dart';
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
    test('the first open writes .specstone/.gitignore', () async {
      final r = await root();
      IndexStore.open(r).close();
      expect(
        file(r, '.specstone/.gitignore').readAsStringSync(),
        'index.sqlite*\nbuild/\ntrash/\nbundles/\nreports/\napproved/\n',
      );
      expect(file(r, '.specstone/index.sqlite').existsSync(), isTrue);
    });
    test('two cold first opens in two isolates both open the index', () async {
      for (var i = 0; i < 20; i++) {
        final r = await root();
        final path = r.path;
        await Future.wait([
          for (var n = 0; n < 2; n++)
            Isolate.run(() => IndexStore.open(Directory(path)).close()),
        ]);
        expect(
          file(r, '.specstone/.gitignore').readAsStringSync(),
          'index.sqlite*\nbuild/\ntrash/\nbundles/\nreports/\napproved/\n',
        );
      }
    });
    test('a first open waits busyTimeout on a held write lock before it faults '
        'indexBusy', () async {
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
    test('an index path the disk cannot resolve refuses the open with the '
        'reason and writes nothing', () async {
      for (final name in ['index.sqlite', 'index.sqlite-wal', '.gitignore']) {
        final r = await root();
        Link('${r.path}/.specstone/$name').createSync(name);
        expect(
          () => IndexStore.open(r),
          throwsA(
            isA<RenderFault>()
                .having(
                  (f) => f.code,
                  'code',
                  RenderFaultCode.outputNotWritable,
                )
                .having((f) => f.exitStatus, 'exit', 73)
                .having(
                  (f) => f.message,
                  'message',
                  startsWith(
                    'cannot write .specstone/$name: it cannot be resolved: ',
                  ),
                ),
          ),
          reason: name,
        );
        expect(
          [
            for (final entity in Directory('${r.path}/.specstone').listSync())
              if (entity is File) entity.uri.pathSegments.last,
          ],
          ['config.yaml'],
          reason: 'a refused open creates no file',
        );
      }
    }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);
    test('a file SQLite makes beside the index and removes on close '
        'counts as missing at every open', () async {
      final r = await root();
      final path = r.path;
      IndexStore.open(r).close();
      for (final suffix in ['-wal', '-shm', '-journal']) {
        expect(file(r, '.specstone/index.sqlite$suffix').existsSync(), isFalse);
      }
      final opens = await Future.wait([
        for (var n = 0; n < 2; n++)
          Isolate.run(() {
            var opened = 0;
            for (var i = 0; i < 40; i++) {
              IndexStore.open(Directory(path)).close();
              opened++;
            }
            return opened;
          }),
      ]);
      expect(opens, [40, 40]);
    });
    test('the root .gitignore is never written', () async {
      final r = await writeTree({
        '.specstone/config.yaml': '',
        '.gitignore': 'node_modules/\n',
      });
      IndexStore.open(r).close();
      expect(file(r, '.gitignore').readAsStringSync(), 'node_modules/\n');
    });
    for (final (held, expected) in [
      (
        '*.tmp',
        '*.tmp\nindex.sqlite*\nbuild/\ntrash/\nbundles/\nreports/\napproved/\n',
      ),
      (
        'index.sqlite*\nbuild/\n',
        'index.sqlite*\nbuild/\ntrash/\nbundles/\nreports/\napproved/\n',
      ),
    ]) {
      test('an existing ignore file keeps its lines first', () async {
        final r = await writeTree({
          '.specstone/config.yaml': '',
          '.specstone/.gitignore': held,
        });
        IndexStore.open(r).close();
        expect(file(r, '.specstone/.gitignore').readAsStringSync(), expected);
      });
    }
    test('a file holding all six lines is left untouched', () async {
      const text =
          'reports/\nbuild/\n# mine\ntrash/\nbundles/\napproved/\nindex.sqlite*\n';
      final r = await writeTree({
        '.specstone/config.yaml': '',
        '.specstone/.gitignore': text,
      });
      IndexStore.open(r).close();
      expect(file(r, '.specstone/.gitignore').readAsStringSync(), text);
    });
    for (final (tag, staleMeta) in [
      ('a layout-version rebuild', 'layout = ${indexLayoutVersion - 1}'),
      ('a binary-version rebuild', "binary_version = 'older'"),
    ]) {
      test(
        '$tag appends bundles/, reports/, and approved/ and keeps the Owner lines in their order',
        () async {
          const older = 'trash/\n# mine\n*.tmp\nindex.sqlite*\nbuild/\n';
          final project = await writeLoginProject();
          final docs = DocsProject.open(
            templates: TemplateResolver(),
            workingDirectory: project,
            homeDirectory: null,
          );
          final first = IndexStore.open(docs.projectRoot);
          expect(refreshIndex(first, docs).fullBuild, isTrue);
          first.close();
          final raw = sqlite3.open('${project.path}/$indexFilePath')
            ..execute('UPDATE meta SET $staleMeta');
          expect(raw.updatedRows, 1);
          raw.close();
          file(project, '.specstone/.gitignore').writeAsStringSync(older);

          final store = IndexStore.open(docs.projectRoot);
          addTearDown(store.close);
          final result = refreshIndex(store, docs);

          expect(result.fullBuild, isTrue);
          expect(
            file(project, '.specstone/.gitignore').readAsStringSync(),
            '${older}bundles/\nreports/\napproved/\n',
          );
        },
      );
    }
    List<String> storedPaths(IndexStore store) =>
        [for (final doc in store.loadDocs()) doc.docPath]..sort();
    test('a write inside an open write commits with the outer one', () async {
      final r = await root();
      final store = IndexStore.open(r);
      addTearDown(store.close);
      store.write(() {
        store.putDoc(parsed('A.md', '# A\n'));
        store.write(() => store.putDoc(parsed('B.md', '# B\n')));
        expect(
          () => store.write(() {
            store.putDoc(parsed('X.md', '# X\n'));
            throw StateError('inner');
          }),
          throwsStateError,
        );
      });
      expect(storedPaths(store), ['A.md', 'B.md']);

      expect(
        () => store.write(() {
          store.write(() => store.putDoc(parsed('C.md', '# C\n')));
          throw StateError('outer');
        }),
        throwsStateError,
      );
      expect(storedPaths(store), ['A.md', 'B.md']);
    });
    test('writeAsync holds the lock across an await', () async {
      final r = await root();
      final first = IndexStore.open(r);
      addTearDown(first.close);
      final second = IndexStore.open(r, busyTimeout: Duration.zero);
      addTearDown(second.close);
      final gate = Completer<void>();
      final held = first.writeAsync(() async {
        await gate.future;
        first.putDoc(parsed('A.md', '# A\n'));
        return 7;
      });
      expect(
        () => second.write(() {}),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.code,
            'code',
            IndexFaultCode.indexBusy,
          ),
        ),
      );
      gate.complete();
      expect(await held, 7);
      second.write(() {});
      expect(storedPaths(second), ['A.md']);
    });
    test(
      'a snapshot ended and begun inside a write leaves the write open',
      () async {
        final r = await root();
        final first = IndexStore.open(r);
        addTearDown(first.close);
        final second = IndexStore.open(r, busyTimeout: Duration.zero);
        addTearDown(second.close);
        first.write(() {
          first
            ..endSnapshot()
            ..beginSnapshot();
          expect(
            () => second.write(() {}),
            throwsA(
              isA<IndexFault>().having(
                (f) => f.code,
                'code',
                IndexFaultCode.indexBusy,
              ),
            ),
          );
        });
      },
    );
    test('a nested write that loses the outer write fails the outer one, '
        'and no later write lands', () async {
      final r = await root();
      final store = IndexStore.open(r);
      addTearDown(store.close);
      // RAISE(ROLLBACK) ends the whole transaction, as SQLITE_FULL may.
      sqlite3.open(file(r, indexFilePath).path)
        ..execute(
          'CREATE TRIGGER lose_hold BEFORE INSERT ON docs '
          "WHEN NEW.doc_path = 'X.md' "
          "BEGIN SELECT RAISE(ROLLBACK, 'lost'); END",
        )
        ..close();
      void loseHoldThenWrite() {
        store.putDoc(parsed('A.md', '# A\n'));
        try {
          store.write(() => store.putDoc(parsed('X.md', '# X\n')));
        } on IndexFault {
          // A caller that reads a failed nested write as not stored.
        } on SqliteException {
          // The same caller, for an error the store leaves unmapped.
        }
        store.putDoc(parsed('B.md', '# B\n'));
      }

      final lost = isA<IndexFault>().having(
        (f) => f.code,
        'code',
        IndexFaultCode.indexNotWritable,
      );
      expect(() => store.write(loseHoldThenWrite), throwsA(lost));
      await expectLater(
        store.writeAsync(() async => loseHoldThenWrite()),
        throwsA(lost),
      );
      expect(storedPaths(store), isEmpty);
    });
    test(
      'a read-only .specstone/.gitignore at a full rebuild is index_not_writable, exit 73, and leaves the index and the file as they were',
      skip: unreadablePathSkipReason(),
      () async {
        final r = await writeTree({
          '.specstone/config.yaml': '',
          '.specstone/.gitignore':
              'index.sqlite*\nbuild/\ntrash/\nbundles/\nreports/\napproved/\n',
        });
        final store = IndexStore.open(r);
        addTearDown(store.close);
        store.write(
          () => store.reset(
            const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'old'),
          ),
        );
        final ignore = file(r, '.specstone/.gitignore')
          ..writeAsStringSync('*.tmp\n');
        Process.runSync('chmod', ['444', ignore.path]);
        addTearDown(() => Process.runSync('chmod', ['644', ignore.path]));

        expect(
          () => store.write(
            () => store.reset(
              const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x'),
            ),
          ),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.indexNotWritable)
                .having((f) => f.exitStatus, 'exit', 73),
          ),
        );
        expect(ignore.readAsStringSync(), '*.tmp\n');
        expect(store.readStamp()?.docTypes, 'old');
      },
    );
    test(
      'a read-only .specstone/ is index_not_writable, exit 73, and writes nothing',
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
      'a read-only .specstone/.gitignore is index_not_writable, exit 73, and leaves it and no index behind',
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
    test('the index opens in WAL mode', () async {
      final r = await root();
      IndexStore.open(r).close();
      final raw = sqlite3.open(file(r, indexFilePath).path);
      addTearDown(raw.close);
      expect(raw.select('PRAGMA journal_mode').single.columnAt(0), 'wal');
    });
    test(
      'a file that is no index is deleted, rebuilt empty, and warned about',
      () async {
        final r = await writeTree({
          '.specstone/config.yaml': '',
          '.specstone/index.sqlite': 'not a database',
        });
        final store = IndexStore.open(r);
        addTearDown(store.close);
        expect(store.warnings, [damagedIndexWarning]);
        expect(store.readStamp(), isNull);
        expect(store.hashes(), isEmpty);
      },
    );
    test('a database with no tables is a new index, '
        'not a damaged one', () async {
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
        'index.sqlite*\nbuild/\ntrash/\nbundles/\nreports/\napproved/\n',
      );
    });
    test('a database with tables but no meta table is deleted, '
        'rebuilt empty, and warned about', () async {
      final r = await root();
      sqlite3.open(file(r, indexFilePath).path)
        ..execute('CREATE TABLE other (x)')
        ..close();
      final store = IndexStore.open(r);
      addTearDown(store.close);
      expect(store.warnings, [damagedIndexWarning]);
      expect(store.hashes(), isEmpty);
    });
    test('writes after a failed write, and after a clean one, each store '
        'and replace their docs', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      expect(
        () => store.write(() {
          store.putDoc(parsed('A.md', '# A\n'));
          throw StateError('killed');
        }),
        throwsStateError,
      );
      store.write(() {
        store
          ..putDoc(parsed('A.md', '# A\n'))
          ..putDoc(parsed('B.md', '# B\n'))
          ..putDoc(parsed('A.md', '# A again\n'));
      });
      store.write(() => store.putDoc(parsed('B.md', '# B again\n')));
      expect(store.loadDocs().map((d) => d.title), ['A again', 'B again']);
    });
    test(
      'a write lock held past the busy timeout is index_busy, exit 75',
      () async {
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
      },
    );
    test('a reindex that dies part way rolls back, and the next refresh '
        'reindexes the same files', () async {
      final project = await writeLoginProject();
      final docs = DocsProject.open(
        templates: TemplateResolver(),
        workingDirectory: project,
        homeDirectory: null,
      );
      final first = IndexStore.open(docs.projectRoot);
      refreshIndex(first, docs);
      final committed = first.hashes();
      first.close();
      final edited = loginProject[featureKey]!.replaceFirst(
        '# Login\n',
        '# Login v2\n',
      );
      file(project, featureKey).writeAsStringSync(edited);
      final dying = IndexStore.open(docs.projectRoot);
      expect(
        () => dying.write(() {
          dying
            ..putDoc(parsed(featureDoc, edited))
            ..setStatKey(featureDoc, null);
          throw StateError('process killed part way');
        }),
        throwsStateError,
      );
      expect(dying.hashes(), committed);
      dying.close();

      final store = IndexStore.open(docs.projectRoot);
      addTearDown(store.close);
      expect(store.hashes(), committed);
      final result = refreshIndex(store, docs);
      expect(result.reindexed, 1);
      expect(store.hashes(), {
        ...committed,
        featureDoc: contentHashOf(utf8.encode(edited)),
      });
    });
    test('the default busy timeout is 10 s', () {
      expect(indexBusyTimeout, const Duration(seconds: 10));
    });
    test('with no timeout given, a write outwaits a lock another connection '
        'lets go', () async {
      final r = await root();
      IndexStore.open(r).close();
      final holder = sqlite3.open(file(r, indexFilePath).path)
        ..execute('BEGIN IMMEDIATE');
      addTearDown(holder.close);
      final ready = ReceivePort();
      final written = _writeWithDefaultTimeout(r.path, ready.sendPort);

      await Future.any([ready.first, written]);
      await Future<void>.delayed(_lockHeldAfterSignal);
      holder.execute('ROLLBACK');

      expect(await written, 'written');
    });
    test(
      'a read-only index file refuses the write and stays byte-identical',
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
    test(
      'a stamp round-trips, and another merged set gives another stamp',
      () async {
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
        expect(stamp.targetNames, isEmpty);
      },
    );
    test('a template edit that only flips '
        'per_target gives another stamp, so the index rebuilds', () {
      MergedSet setWith({required bool isPerTarget}) => MergedSet(
        docTypes: [
          MergedDocType(
            id: 'charter',
            isPerTarget: isPerTarget,
            fields: const [],
            sections: const [],
            lint: const MergedLint(),
            files: const [],
          ),
        ],
      );
      expect(
        IndexStamp.of(setWith(isPerTarget: false)),
        isNot(IndexStamp.of(setWith(isPerTarget: true))),
      );
    });
    test('a stamp holds the target names in config '
        'order, and other names give another stamp', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      const stamp = IndexStamp(
        binaryVersion: specstoneVersion,
        docTypes: 'x',
        targetNames: ['flutter', 'jaspr'],
      );
      store.write(() => store.reset(stamp));
      expect(store.readStamp(), stamp);
      expect(store.readStamp()?.targetNames, ['flutter', 'jaspr']);
      expect(
        const IndexStamp(
          binaryVersion: specstoneVersion,
          docTypes: 'x',
          targetNames: ['jaspr', 'flutter'],
        ),
        isNot(stamp),
        reason: 'the names read in targets order, so a rename rebuilds',
      );
      expect(
        const IndexStamp(
          binaryVersion: specstoneVersion,
          docTypes: 'x',
          targetNames: ['flutter'],
        ),
        isNot(stamp),
        reason: 'a removed target rebuilds',
      );
    });
    test('a meta row with no target_names column '
        'reads with no column error and no stamp', () async {
      final r = await root();
      final store = IndexStore.open(r);
      addTearDown(store.close);
      const stamp = IndexStamp(
        binaryVersion: specstoneVersion,
        docTypes: 'x',
        targetNames: ['flutter'],
      );
      store.write(() => store.reset(stamp));
      final raw = sqlite3.open(file(r, indexFilePath).path);
      addTearDown(raw.close);
      raw
        ..execute('DROP TABLE meta')
        ..execute(
          'CREATE TABLE meta (binary_version TEXT NOT NULL, '
          'doc_types TEXT NOT NULL, layout INTEGER NOT NULL)',
        )
        ..execute('INSERT INTO meta VALUES (?, ?, ?)', [
          specstoneVersion,
          'x',
          indexLayoutVersion,
        ]);
      expect(store.readStamp(), isNull);
    });
    test('a meta row whose target_names holds no '
        'JSON array of strings has no stamp, so it rebuilds', () async {
      final r = await root();
      final store = IndexStore.open(r);
      addTearDown(store.close);
      const stamp = IndexStamp(
        binaryVersion: specstoneVersion,
        docTypes: 'x',
        targetNames: ['flutter'],
      );
      store.write(() => store.reset(stamp));
      final raw = sqlite3.open(file(r, indexFilePath).path);
      addTearDown(raw.close);
      for (final value in ['not json', '[1, 2]', '"flutter"']) {
        raw.execute('UPDATE meta SET target_names = ?', [value]);
        expect(store.readStamp(), isNull, reason: value);
      }
    });
    test(
      'a stored doc loads back with its line facts and section counts',
      () async {
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
        expect(facts.fenced, [const LineRange(first: 9, last: 11)]);
        expect(
          facts.sectionCounts.last,
          const SectionCounts(lines: 1, chars: 7),
        );
      },
    );
    test('a stored doc loads '
        'back with the item facts putDoc wrote', () async {
      const text =
          '# T\n\nLead.\n\n## A\n- one\n- two\n\n## B\nhéllo \u{1F600}\n';
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
      final facts = store.loadContent('A.md').itemFacts;

      expect(facts.lead, const SectionCounts(lines: 1, chars: 5));
      expect(facts.sectionItems, hasLength(2));
      expect(
        jsonEncode(facts.toJson()),
        jsonEncode(written.content.itemFacts.toJson()),
      );
    });
    test('a record loads back, after a reopen, with the matrix lines it was '
        'written with, a CRLF record included', () async {
      final recordType = recordDocType();
      const text =
          '---\nstatuses:\n  - show_toast:implemented\n---\n\n# T\n\n'
          '## Verification matrix\n\n'
          '- show_toast E01: `` a`b\$c\\d `` 3f9a1c0b7e2d\n'
          '- show_toast E02 skipped: no clock on CI\n'
          '- show_toast: `queues`, `drops, then pins` 3f9a1c0b7e2d\n'
          '- show_toast skipped: no clock on CI\n'
          'stray\n';
      ParsedDoc record(String path, String body) => parseIndexedDoc(
        docPath: path,
        bytes: utf8.encode(body),
        match: DocTypeMatcher(
          MergedSet(docTypes: [recordType]),
          targetNames: const [],
        ).match(path),
      );
      final r = await root();
      final first = IndexStore.open(r);
      final lf = record('specs/f01_a/IMPLEMENTATION.md', text);
      final crlf = record(
        'specs/f02_b/IMPLEMENTATION.md',
        text.replaceAll('\n', '\r\n'),
      );
      first.write(() {
        first
          ..reset(
            const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x'),
          )
          ..putDoc(lf)
          ..putDoc(crlf);
      });
      first.close();

      final store = IndexStore.open(r);
      addTearDown(store.close);
      final loaded = {
        for (final doc in store.loadDocs()) doc.docPath: doc.matrixLines,
      };

      expect(lf.doc.matrixLines, [
        isA<TestRow>().having((row) => row.literals, 'literals', [r'a`b$c\d']),
        isA<SkipRow>(),
        isA<TestRow>().having((row) => row.form, 'form', RowForm.perFr).having(
          (row) => row.literals,
          'literals',
          ['queues', 'drops, then pins'],
        ),
        isA<SkipRow>().having((row) => row.form, 'form', RowForm.perFr),
        isA<MalformedRow>(),
      ]);
      expect(loaded['specs/f01_a/IMPLEMENTATION.md'], lf.doc.matrixLines);
      expect(loaded['specs/f02_b/IMPLEMENTATION.md'], crlf.doc.matrixLines);
      expect(loaded['specs/f02_b/IMPLEMENTATION.md'], lf.doc.matrixLines);
    });
    test('readability facts round-trip through json', () async {
      final doc = (await resolveSoftwareTech()).lookup('feature')!;
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      final written = parseIndexedDoc(
        docPath: 'a.md',
        bytes: utf8.encode(
          '# F\n\n## Problem\n\nThe pair is checked (RULE-1) twice.\n\n'
          'ทุกครั้ง `check`\n',
        ),
        match: MatchedDocType(doc),
        idPrefixes: const {'RULE-'},
      );
      store.write(() {
        store
          ..reset(
            const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x'),
          )
          ..putDoc(written);
      });
      final was = written.content.itemFacts.sectionItems.single;
      final now = store.loadContent('a.md').itemFacts.sectionItems.single;

      expect(was, hasLength(2));
      expect(was.first.readability.notes, isNotEmpty);
      expect(was.last.readability.cells.single.single.language, 'th');
      for (var i = 0; i < was.length; i++) {
        expect(now[i].readability.cells, was[i].readability.cells);
        expect(now[i].readability.notes, was[i].readability.notes);
      }
    });
    test('loadContent keeps the '
        'item facts column undecoded until they are read', () async {
      final r = await root();
      final store = IndexStore.open(r);
      addTearDown(store.close);
      store.write(() {
        store
          ..reset(
            const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x'),
          )
          ..putDoc(parsed('A.md', '# T\n\n## A\nx\n'));
      });
      final raw = sqlite3.open(file(r, indexFilePath).path);
      addTearDown(raw.close);
      raw.execute("UPDATE docs SET item_facts = 'not json'");
      final content = store.loadContent('A.md');

      expect(content.head, startsWith('# T'));
      expect(content.sections, hasLength(1));
      expect(() => content.itemFacts, throwsFormatException);
    });
    test('a stored doc loads back with its banned-pattern matches', () async {
      final type = MergedDocType(
        id: 'note',
        fields: const [],
        sections: const [],
        lint: MergedLint(
          bannedPatterns: [
            PatternEntry(id: 'fast', pattern: r'fast\w*', message: 'm'),
          ],
        ),
        files: const [],
      );
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      final written = parseIndexedDoc(
        docPath: 'n.md',
        bytes: utf8.encode('# N\n\n## A\nfast\n\n## B\nfastly\n'),
        match: MatchedDocType(type),
      );
      store.write(() {
        store
          ..reset(
            const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x'),
          )
          ..putDoc(written);
      });
      expect(store.loadContent('n.md').bannedMatches, [
        const BannedMatch(section: 0, line: 4, entry: 0, match: 'fast'),
        const BannedMatch(section: 1, line: 7, entry: 0, match: 'fastly'),
      ]);
    });
    test('the lines a check reads from a stored doc equal those it reads from '
        'the text', () async {
      const text =
          '---\ntraced_from:\n  - S1\n  - S2\n---\n\n# T\n\n'
          '## A\nx [b](B.md)\n```\n## no\n```\n';
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
      final direct = docLinesOf(text);
      expect(stored.lines, direct.lines);
      expect(stored.lineCount, direct.lineCount);
      expect(stored.charCount, direct.charCount);
      expect(stored.links, direct.links);
      expect(stored.links, isNotEmpty);
      expect(stored.sectionLines, direct.sectionLines);
      expect(stored.sectionCounts, direct.sectionCounts);
      expect(stored.entriesOf('traced_from'), direct.entriesOf('traced_from'));
      expect(stored.keyLine('traced_from'), 2);
      expect(
        [for (var i = 1; i <= 14; i++) stored.isFenced(i)],
        [for (var i = 1; i <= 14; i++) direct.isFenced(i)],
      );
    });
    test('a meta row without the layout marker has no stamp, whatever the '
        'user_version', () async {
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
    test(
      "a doc's stat key and checked_at read back as stored; reset clears them",
      () async {
        final store = IndexStore.open(await root());
        addTearDown(store.close);
        const stamp = IndexStamp(
          binaryVersion: specstoneVersion,
          docTypes: 'x',
        );
        const key = FileStatKey(
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
      },
    );
    test(
      'the FTS5 trigram table finds a Thai substring and a word part',
      () async {
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
        store.fillSearchRows();
        expect(store.search('"ค้นหา"').single.sectionKey, 'notes');
        expect(store.search('"log"').single.docPath, 'README.md');
      },
    );
    test('deleteDoc removes the search rows of that doc only', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      store.write(() {
        store
          ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra crossing\n'))
          ..putDoc(parsed('b.md', '# Beta\n\n## Notes\nzebra herd\n'))
          ..deleteDoc('a.md');
      });
      store.fillSearchRows();
      expect(store.search('"crossing"'), isEmpty);
      expect(store.search('"alpha"'), isEmpty);
      expect(store.search('"zebra"').map((r) => r.docPath), ['b.md']);
      expect(store.search('"beta"').map((r) => r.docPath), ['b.md']);
    });
    test('deleteDoc of an unknown path changes nothing', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      store.write(() {
        store
          ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra crossing\n'))
          ..deleteDoc('missing.md');
      });
      store.fillSearchRows();
      expect(store.search('"zebra"').map((r) => r.docPath), ['a.md']);
    });
    test('a freed doc id is reused without the old search rows', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      store.write(() {
        store
          ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra crossing\n'))
          ..putDoc(parsed('b.md', '# Beta\n\n## Notes\nllama trail\n'))
          ..deleteDoc('b.md')
          ..putDoc(parsed('c.md', '# Gamma\n\n## Notes\nheron marsh\n'));
      });
      store.fillSearchRows();
      expect(store.search('"llama"'), isEmpty);
      expect(store.search('"beta"'), isEmpty);
      expect(store.search('"heron"').map((r) => r.docPath), ['c.md']);
      expect(store.search('"zebra"').map((r) => r.docPath), ['a.md']);
    });
    test(
      'a doc put again with an edit finds the new text, not the old',
      () async {
        final store = IndexStore.open(await root());
        addTearDown(store.close);
        store.write(() {
          store
            ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra crossing\n'))
            ..putDoc(parsed('b.md', '# Beta\n\n## Notes\nzebra herd\n'))
            ..putDoc(parsed('b.md', '# Beta\n\n## Notes\nzebra herd\n'))
            ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nllama trail\n'));
        });
        store.fillSearchRows();
        expect(store.search('"crossing"'), isEmpty);
        expect(store.search('"llama"').map((r) => r.docPath), ['a.md']);
        expect(store.search('"zebra"').map((r) => r.docPath), ['b.md']);
      },
    );
    test(
      'a refresh writes no search row; fillSearchRows writes the rows '
      'putDoc wrote before, and a second call with no change writes none',
      () async {
        final r = await root();
        final store = IndexStore.open(r);
        addTearDown(store.close);
        store.write(() {
          store
            ..reset(
              const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x'),
            )
            ..putDoc(
              parsed(
                'a.md',
                '---\nslug:\n  - sign-in\n---\n\n# Alpha\n\n## Notes\n'
                    'zebra crossing\n\n## More\nllama trail\n',
              ),
            );
        });
        final raw = sqlite3.open(file(r, indexFilePath).path);
        addTearDown(raw.close);
        int rowCount() =>
            raw.select('SELECT count(*) FROM doc_search').single.columnAt(0)
                as int;
        expect(rowCount(), 0);
        expect(store.search('"zebra"'), isEmpty);

        store.fillSearchRows();
        // The title, one alias, and two sections.
        expect(rowCount(), 4);
        expect(
          store.search('"sign-in"').single.sectionKey,
          'notes',
          reason: 'an alias hit names the first section',
        );
        expect(store.search('"llama"').single.sectionKey, 'more');

        raw.execute("UPDATE doc_search SET text = 'tampered text'");
        store.fillSearchRows();
        expect(
          raw
              .select('SELECT text FROM doc_search')
              .every((row) => row.columnAt(0) == 'tampered text'),
          isTrue,
          reason: 'a doc whose rows are current is not written again',
        );
      },
    );
    test('a doc put again with an edit loses its search_hash, and the next '
        'fillSearchRows rebuilds its rows from the new text', () async {
      final r = await root();
      final store = IndexStore.open(r);
      addTearDown(store.close);
      store.write(
        () => store.putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra\n')),
      );
      store.fillSearchRows();
      store.write(
        () => store.putDoc(parsed('a.md', '# Alpha\n\n## Notes\nllama\n')),
      );
      final raw = sqlite3.open(file(r, indexFilePath).path);
      addTearDown(raw.close);
      expect(
        raw.select('SELECT search_hash FROM docs').single.columnAt(0),
        isNull,
      );
      store.fillSearchRows();
      expect(store.search('"zebra"'), isEmpty);
      expect(store.search('"llama"').single.docPath, 'a.md');
    });
    test(
      'a doc whose search_hash differs from its content hash is rebuilt',
      () async {
        final r = await root();
        final store = IndexStore.open(r);
        addTearDown(store.close);
        store.write(
          () => store.putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra\n')),
        );
        store.fillSearchRows();
        final raw = sqlite3.open(file(r, indexFilePath).path);
        addTearDown(raw.close);
        raw
          ..execute("UPDATE doc_search SET text = 'tampered text'")
          ..execute("UPDATE docs SET search_hash = 'old'");
        store.fillSearchRows();
        expect(store.search('"tampered"'), isEmpty);
        expect(store.search('"zebra"').single.docPath, 'a.md');
      },
    );
    test(
      'a fill that throws mid-way rolls back every row and search_hash',
      () async {
        final r = await root();
        final store = IndexStore.open(r);
        addTearDown(store.close);
        store.write(() {
          store
            ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra\n'))
            ..putDoc(parsed('b.md', '# Beta\n\n## Notes\nllama\n'));
        });
        final raw = sqlite3.open(file(r, indexFilePath).path);
        addTearDown(raw.close);
        // The second doc's frontmatter is no JSON, so its rebuild throws after
        // the first doc's rows are written.
        raw.execute(
          "UPDATE docs SET frontmatter = 'x' WHERE doc_path = 'b.md'",
        );
        expect(store.fillSearchRows, throwsFormatException);
        expect(
          raw.select('SELECT count(*) FROM doc_search').single.columnAt(0),
          0,
        );
        expect(
          raw
              .select('SELECT count(*) FROM docs WHERE search_hash IS NOT NULL')
              .single
              .columnAt(0),
          0,
        );
      },
    );
    test('reset leaves the search table empty', () async {
      final r = await root();
      final store = IndexStore.open(r);
      addTearDown(store.close);
      const stamp = IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x');
      store.write(
        () => store
          ..reset(stamp)
          ..putDoc(parsed('a.md', '# Alpha\n\n## Notes\nzebra\n')),
      );
      store.fillSearchRows();
      store.write(() => store.reset(stamp));
      final raw = sqlite3.open(file(r, indexFilePath).path);
      addTearDown(raw.close);
      expect(
        raw.select('SELECT count(*) FROM doc_search').single.columnAt(0),
        0,
      );
      expect(store.search('"zebra"'), isEmpty);
    });
    test('Index each doc: '
        'formatted round-trips as true, false, and null', () async {
      final doc = (await resolveSoftwareTech()).lookup('feature')!;
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      ParsedDoc feature(String path, String text) => parseIndexedDoc(
        docPath: path,
        bytes: utf8.encode(text),
        match: MatchedDocType(doc),
      );
      store.write(() {
        store
          ..reset(
            const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x'),
          )
          ..putDoc(feature('a.md', '# F\n\n## Problem\n\ntext\n'))
          ..putDoc(feature('b.md', '# F\n\n## Problem\ntext  \n'))
          ..putDoc(feature('c.md', '# F\n\n## Bogus\ntext\n'));
      });
      expect(
        {for (final d in store.loadDocs()) d.docPath: d.formatted},
        {'a.md': true, 'b.md': false, 'c.md': null},
      );
    });
    test('a doc with a target '
        'round-trips through the docs table', () async {
      final r = await root();
      final store = IndexStore.open(r);
      addTearDown(store.close);
      const type = MergedDocType(
        id: 'architecture',
        path: 'specs/f{nn}_{slug}/ARCHITECTURE.md',
        isPerTarget: true,
        fields: [],
        sections: [],
        lint: MergedLint(),
        files: [],
      );
      final targeted = parseIndexedDoc(
        docPath: 'specs/jaspr/f01_login/ARCHITECTURE.md',
        bytes: utf8.encode('# A\n'),
        match: MatchedDocType(type, target: 'jaspr'),
      );
      store.write(() {
        store
          ..reset(
            const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x'),
          )
          ..putDoc(targeted)
          ..putDoc(parsed('README.md', '# R\n'));
      });
      expect(
        {for (final d in store.loadDocs()) d.docPath: d.target},
        {'specs/jaspr/f01_login/ARCHITECTURE.md': 'jaspr', 'README.md': null},
      );
    });
  });

  test('is at layout 42, and rebuilds an index stamped 41, whose code-file '
      'rows hold no number label texts', () async {
    // D8: layout 42 stores each label candidate's text with the mentions.
    final r = await root();
    final store = IndexStore.open(r);
    addTearDown(store.close);
    const stamp = IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x');
    store.write(() => store.reset(stamp));
    expect(indexLayoutVersion, 42);
    expect(store.readStamp(), stamp);
    final raw = sqlite3.open(file(r, indexFilePath).path);
    addTearDown(raw.close);
    for (final layout in [
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      20,
      32,
      37,
      38,
      39,
      40,
      41,
    ]) {
      raw.execute('UPDATE meta SET layout = $layout');
      expect(store.readStamp(), isNull, reason: 'layout $layout');
    }
  });

  group('IndexStore code files', () {
    const key = CodeFileKey(root: '/work/app', path: 'lib/a.dart');
    const other = CodeFileKey(root: '/work/app', path: 'lib/b.dart');
    const stat = FileStatKey(size: 12, modified: 3, changed: 4, mode: 33188);
    const stamp = IndexStamp(binaryVersion: specstoneVersion, docTypes: 'x');

    test('a stored row reads back field for field, a fact never read kept '
        'null, and a second put replaces the row', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      store.write(() {
        store
          ..reset(stamp)
          ..putCodeFiles({
            key: CodeFileFacts(
              stat: stat,
              fingerprint: 'abc123',
              mentionTexts: ['one', 'two'],
              resolved: {'lib/a.dart:A'},
            ),
            other: CodeFileFacts(stat: stat),
          });
      });

      final read = store.loadCodeFiles();

      expect(read.keys, {key, other});
      final facts = read[key]!;
      expect(facts.stat, stat);
      expect(facts.fingerprint, 'abc123');
      expect(facts.mentionTexts, ['one', 'two']);
      expect(facts.resolved, {'lib/a.dart:A'});
      expect(read[other]!.fingerprint, isNull);
      expect(read[other]!.mentionTexts, isNull);
      expect(read[other]!.resolved, isEmpty);

      store.write(
        () => store.putCodeFiles({
          key: CodeFileFacts(stat: stat, mentionTexts: const []),
        }),
      );

      final replaced = store.loadCodeFiles();
      expect(replaced.keys, {key, other});
      expect(replaced[key]!.fingerprint, isNull);
      expect(replaced[key]!.mentionTexts, isEmpty);
    });

    test('writeCodeFacts faults index_busy at once on a held lock, and '
        'the next write waits the timeout the store opened with', () async {
      final r = await root();
      const timeout = Duration(milliseconds: 600);
      final store = IndexStore.open(r, busyTimeout: timeout);
      addTearDown(store.close);
      store.write(() => store.reset(stamp));
      final holder = sqlite3.open(file(r, indexFilePath).path)
        ..execute('BEGIN IMMEDIATE');
      addTearDown(() {
        holder
          ..execute('ROLLBACK')
          ..close();
      });
      final busy = throwsA(
        isA<IndexFault>().having(
          (f) => f.code,
          'code',
          IndexFaultCode.indexBusy,
        ),
      );
      final watch = Stopwatch()..start();

      expect(() => store.writeCodeFacts(() {}), busy);
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 300)));

      watch.reset();
      expect(() => store.write(() {}), busy);
      expect(watch.elapsed, greaterThanOrEqualTo(timeout));
    });

    test('a peer write stales a snapshot even when it marks no change, and a '
        'writeCodeFacts write does not', () async {
      final r = await root();
      final reader = IndexStore.open(r);
      addTearDown(reader.close);
      final peer = IndexStore.open(r);
      addTearDown(peer.close);
      reader.write(() => reader.reset(stamp));
      bool staleAfter(void Function() peerWrite) {
        reader
          ..beginSnapshot()
          ..endSnapshot();
        peerWrite();
        var stale = false;
        reader.write(() => stale = reader.snapshotIsStale);
        return stale;
      }

      expect(staleAfter(() => peer.write(() {})), isTrue);
      expect(staleAfter(() => peer.writeCodeFacts(() {})), isFalse);
    });

    test('a reset for a changed stamp drops every row', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      store.write(() {
        store
          ..reset(stamp)
          ..putCodeFiles({key: CodeFileFacts(stat: stat, fingerprint: 'a')});
      });
      expect(store.loadCodeFiles(), isNotEmpty);

      store.write(
        () => store.reset(
          const IndexStamp(binaryVersion: specstoneVersion, docTypes: 'y'),
        ),
      );

      expect(store.loadCodeFiles(), isEmpty);
    });
  });

  group('IndexStore cited-by lines', () {
    const first = CitedPlace(
      docPath: 'a.md',
      kind: CitedKind.item,
      key: 'INV-1',
    );
    const second = CitedPlace(docPath: 'b.md', kind: CitedKind.doc, key: null);
    const onSecond = [
      CitedBy(
        docPath: 'c.md',
        name: 'c',
        docType: 'fr',
        byItem: null,
        bySection: 'purpose',
      ),
    ];
    const onFirst = [
      CitedBy(
        docPath: 'c.md',
        name: 'c',
        docType: 'fr',
        byItem: 'E01',
        bySection: 'edge_cases',
      ),
      CitedBy(
        docPath: 'd.md',
        name: 'd',
        docType: 'charter',
        byItem: null,
        bySection: '_lead',
      ),
    ];
    final lines = {second: onSecond, first: onFirst};

    test('the lines read back as stored, in order, with a null key and '
        'a null item kept', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      store.write(() => store.putCitedBy(lines));
      final read = store.loadCitedBy();
      expect(read, lines);
      expect(read.keys.toList(), [second, first]);
    });

    test('a second put replaces every line of the first', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      store.write(() => store.putCitedBy(lines));
      store.write(() => store.putCitedBy({first: lines[first]!.sublist(1)}));
      expect(store.loadCitedBy(), {first: lines[first]!.sublist(1)});
    });
  });

  group('IndexStore diagram parses', () {
    const parserHash = 'parser-a';
    const failed = DiagramParse(
      blockHash: 'block-1',
      diagram: 'flowchart',
      parses: false,
      message: 'Parse error on line 2',
      blockLine: 7,
    );
    const passed = DiagramParse(blockHash: 'block-2', parses: true);
    Future<IndexStore> stored() async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      store.write(
        () => store.putDiagramParses([failed, passed], parserHash: parserHash),
      );
      return store;
    }

    test('a stored row reads back field for field', () async {
      final store = await stored();
      final rows = store.diagramParsesOf({
        'block-1',
        'block-2',
        'block-3',
      }, parserHash: parserHash);
      expect(rows.keys, unorderedEquals(['block-1', 'block-2']));
      expect(rows['block-1']!.blockHash, 'block-1');
      expect(rows['block-1']!.diagram, 'flowchart');
      expect(rows['block-1']!.parses, isFalse);
      expect(rows['block-1']!.message, 'Parse error on line 2');
      expect(rows['block-1']!.blockLine, 7);
      expect(rows['block-2']!.parses, isTrue);
      expect(rows['block-2']!.diagram, isNull);
      expect(rows['block-2']!.message, isNull);
      expect(rows['block-2']!.blockLine, isNull);
    });
    test('a lookup under another parser hash misses', () async {
      final store = await stored();
      expect(
        store.diagramParsesOf({'block-1'}, parserHash: 'parser-b'),
        isEmpty,
      );
    });
    test('an empty lookup returns no rows', () async {
      final store = await stored();
      expect(store.diagramParsesOf({}, parserHash: parserHash), isEmpty);
    });
    test('a lookup of 2000 hashes returns every row', () async {
      final store = IndexStore.open(await root());
      addTearDown(store.close);
      final hashes = {for (var i = 0; i < 2000; i++) 'block-$i'};
      store.write(
        () => store.putDiagramParses([
          for (final h in hashes) DiagramParse(blockHash: h, parses: true),
        ], parserHash: parserHash),
      );
      expect(
        store.diagramParsesOf(hashes, parserHash: parserHash),
        hasLength(2000),
      );
    });
    test(
      'a second put of the same block and parser replaces the row',
      () async {
        final store = await stored();
        store.write(
          () => store.putDiagramParses([
            const DiagramParse(blockHash: 'block-1', parses: true),
          ], parserHash: parserHash),
        );
        final row = store.diagramParsesOf({
          'block-1',
        }, parserHash: parserHash)['block-1']!;
        expect(row.parses, isTrue);
        expect(row.message, isNull);
      },
    );
    test('reset drops every row', () async {
      final store = await stored();
      store.write(
        () => store.reset(const IndexStamp(binaryVersion: '1', docTypes: 'x')),
      );
      expect(
        store.diagramParsesOf({'block-1', 'block-2'}, parserHash: parserHash),
        isEmpty,
      );
    });
    test('putDoc and deleteDoc leave the rows alone', () async {
      final store = await stored();
      store.write(() {
        store
          ..putDoc(parsed('prds/a.md', '# A\n'))
          ..deleteDoc('prds/a.md')
          ..putDoc(parsed('prds/b.md', '# B\n'));
      });
      expect(
        store.diagramParsesOf({'block-1', 'block-2'}, parserHash: parserHash),
        hasLength(2),
      );
    });
  });

  group('IndexStore rule item words', () {
    const frPath =
        'prds/features/f01_login/us01_email_login/'
        'fr01_validate_credentials.md';
    const frKey = 'docs/$frPath';
    const fr =
        '---\nverify_method: test\n---\n\n# Validate credentials\n\n'
        '## Statement\n'
        'The system shall **check** the [email](x.md) and the `password`.\n\n'
        '## Edge cases\n'
        '<!-- fill in later -->\n'
        '1. E01 — A wrong password → refused.\n'
        '2. Given a stray given line.\n'
        '3. E03 — The context call: first,\n'
        '   then second.\n'
        '\n'
        '| a | b |\n'
        '|---|---|\n'
        '| row cell text | b |\n'
        '\n'
        '```\n'
        'fenced code words\n'
        '```\n\n'
        '## Rationale\n'
        'Not a rule-bearing section.\n';

    IndexStore refreshed(Directory project) {
      final docs = DocsProject.open(
        templates: TemplateResolver(),
        workingDirectory: project,
        homeDirectory: null,
      );
      final store = IndexStore.open(docs.projectRoot);
      addTearDown(store.close);
      refreshIndex(store, docs);
      return store;
    }

    List<(int, String?, String)> wordsOf(IndexStore store, String docPath) => [
      for (final item in store.ruleItemWords())
        if (item.docPath == docPath)
          (item.line, item.itemId, item.words.join(' ')),
    ];

    test(
      'a refresh stores the normalized words '
      'of the items of the rule-bearing sections, and none of a Given '
      'line, a table row, fenced code, a comment, or another section',
      () async {
        final project = await writeLoginProject(extra: {frKey: fr});
        final store = refreshed(project);

        expect(wordsOf(store, frPath), [
          (8, null, 'the system shall check the email and the password'),
          (12, 'E01', 'a wrong password refused'),
          (14, 'E03', 'the context call first then second'),
        ]);
      },
    );

    test('items worded alike but written with another '
        'ID, bold, link, or punctuation read the same words', () async {
      final project = await writeLoginProject(
        extra: {
          frKey: fr,
          'docs/prds/features/f01_login/us01_email_login/fr02_lock_after_failures.md':
              '---\nverify_method: test\n---\n\n# Lock after failures\n\n'
              '## Edge cases\n'
              '1. **E05** — The [context](x.md) call: FIRST, then second\n',
        },
      );
      final store = refreshed(project);

      final other = wordsOf(
        store,
        'prds/features/f01_login/us01_email_login/fr02_lock_after_failures.md',
      );
      expect(other.single.$3, 'the context call first then second');
      expect(other.single.$2, 'E05');
    });

    test('items that restate a rule while citing '
        'two item IDs read the same words, every item ID dropped', () async {
      const other =
          'prds/features/f01_login/us01_email_login/'
          'fr02_lock_after_failures.md';
      String edge(String id) =>
          '---\nverify_method: test\n---\n\n# X\n\n## Edge cases\n'
          '1. E01 — The token check follows $id for every request of the '
          'login flow.\n';
      final project = await writeLoginProject(
        extra: {frKey: edge('INV-6'), 'docs/$other': edge('INV-7')},
      );
      final store = refreshed(project);

      expect(wordsOf(store, frPath).single.$3, wordsOf(store, other).single.$3);
      expect(
        wordsOf(store, frPath).single.$3,
        'the token check follows for every request of the login flow',
      );
    });

    test('only the comment is not read, whether it '
        'spans lines or closes in the middle of a line', () async {
      final project = await writeLoginProject(
        extra: {
          frKey:
              '---\nverify_method: test\n---\n\n# X\n\n## Edge cases\n'
              '1. E02 — foo <!-- note\n'
              '   more --> bar\n'
              '2. E03 — <!-- tip --> The system shall X\n'
              '<!--\n'
              '\n'
              'a hidden rule\n'
              '-->\n',
        },
      );
      final store = refreshed(project);

      expect(wordsOf(store, frPath), [
        (8, 'E02', 'foo bar'),
        (10, 'E03', 'the system shall x'),
      ]);
    });

    test('a link is read as its text as the link '
        'scan reads it, a `]` in a code span of the text included', () async {
      final project = await writeLoginProject(
        extra: {
          frKey:
              '---\nverify_method: test\n---\n\n# X\n\n## Statement\n'
              'Press [the `]` key](x.md) and ![alt text](a.png) now.\n',
        },
      );
      final store = refreshed(project);

      expect(
        wordsOf(store, frPath).single.$3,
        'press the key and alt text now',
      );
    });

    test('a <!-- in a code span opens no comment, so '
        'the items after it keep their words', () async {
      final project = await writeLoginProject(
        extra: {
          frKey:
              '---\nverify_method: test\n---\n\n# X\n\n## Edge cases\n'
              '1. E02 — Write `<!--` to open.\n'
              '2. E03 — The next rule.\n',
        },
      );
      final store = refreshed(project);

      expect(wordsOf(store, frPath), [
        (8, 'E02', 'write to open'),
        (9, 'E03', 'the next rule'),
      ]);
    });

    test('a reference link reads as its text against '
        'the definitions of its doc', () async {
      final project = await writeLoginProject(
        extra: {
          frKey:
              '---\nverify_method: test\n---\n\n# X\n\n## Statement\n'
              'See [the rule][r] and [again].\n\n## Rationale\n'
              'N/A\n\n[r]: x.md\n[again]: y.md\n',
        },
      );
      final store = refreshed(project);

      expect(wordsOf(store, frPath).single.$3, 'see the rule and again');
    });

    test('only a token of an item ID prefix of the '
        'merged set is dropped, so UTF-8 and HTTP2 stay words', () async {
      final project = await writeLoginProject(
        extra: {
          frKey:
              '---\nverify_method: test\n---\n\n# X\n\n## Statement\n'
              'It follows INV-6 and S2 over UTF-8 with HTTP2.\n',
        },
      );
      final store = refreshed(project);

      expect(
        wordsOf(store, frPath).single.$3,
        'it follows and over utf8 with http2',
      );
    });

    test('a doc stored again keeps only its new '
        'words, and a deleted doc drops them all', () async {
      final project = await writeLoginProject(extra: {frKey: fr});
      expect(wordsOf(refreshed(project), frPath), hasLength(3));
      File('${project.path}/$frKey').writeAsStringSync(
        '---\nverify_method: test\n---\n\n# X\n\n## Statement\n'
        'Only this one remains.\n',
      );

      final store = refreshed(project);

      expect(wordsOf(store, frPath), [(8, null, 'only this one remains')]);
      store.write(() => store.deleteDoc(frPath));
      expect(wordsOf(store, frPath), isEmpty);
    });
  });
}

/// How long the lock stays held after the writer signals it is about to write.
const _lockHeldAfterSignal = Duration(milliseconds: 300);

/// Writes one doc in an isolate with `IndexStore`'s default busy timeout.
///
/// Returns `'written'`, or the fault code when the write fails. A top-level
/// function keeps the closure free of the caller's `Database` objects, which
/// an isolate cannot send.
Future<String> _writeWithDefaultTimeout(String path, SendPort ready) {
  return Isolate.run(() {
    final store = IndexStore.open(Directory(path));
    try {
      ready.send(null);
      store.write(
        () => store.putDoc(
          parseIndexedDoc(
            docPath: 'README.md',
            bytes: utf8.encode('# R\n'),
            match: const NoDocType(),
          ),
        ),
      );
      return 'written';
    } on IndexFault catch (fault) {
      return '${fault.code}';
    } finally {
      store.close();
    }
  });
}
