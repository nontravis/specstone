// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/temp_tree.dart';

void main() {
  File inProject(Directory p, String path) => File('${p.path}/$path');
  final loginV2 = loginProject[featureKey]!.replaceFirst(
    '# Login\n',
    '# Login v2\n',
  );
  List<Object?> answers(ReadSession s) => [
    for (final d in s.docs)
      [
        d.docPath,
        d.docTypeId,
        d.name,
        d.parentPath,
        d.title,
        d.tokens,
        s.store.loadContent(d.docPath).text,
      ],
  ];
  String? titleOf(ReadSession s, String docPath) =>
      s.docs.firstWhere((d) => d.docPath == docPath).title;
  void deleteIndex(Directory p) {
    for (final suffix in ['', '-wal', '-shm']) {
      final f = inProject(p, '$indexFilePath$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }

  group('ReadSession', () {
    test('f01/us01/fr01/e01: outside a project the session refuses with project_not_found, exit 78', () async {
      final folder = await writeTree({});
      expect(
        () => openSession(folder),
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.projectNotFound)
              .having((f) => f.exitStatus, 'exit', 78),
        ),
      );
    });
    test('f01/us01/fr01, f01/us01/fr01/e02: a template fault exits 78 and no index is written', () async {
      final project = await writeLoginProject(
        extra: {'.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n'},
      );
      expect(
        () => openSession(project),
        throwsA(isA<TemplateFault>().having((f) => f.exitStatus, 'exit', 78)),
      );
      expect(inProject(project, indexFilePath).existsSync(), isFalse);
    });
    test(
      'f01/us01/fr01/e03, s03/inv1: no docs folder answers as an empty tree',
      () async {
        final session = openSession(
          await writeTree({
            '.specstone/config.yaml': loginProject['.specstone/config.yaml']!,
          }),
        );
        addTearDown(session.close);
        expect(session.docs, isEmpty);
      },
    );
    test(
      'f01/us01/fr01/e04: a working folder below the root finds the same roots',
      () async {
        final project = await writeLoginProject();
        final session = openSession(Directory('${project.path}/docs/prds'));
        addTearDown(session.close);
        expect(
          session.project.docsRoot.path,
          Directory('${project.path}/docs').resolveSymbolicLinksSync(),
        );
        expect(session.docs, hasLength(25));
      },
    );
    test(
      'f01/us01/s1: an edited doc reads as edited on the next call',
      () async {
        final project = await writeLoginProject();
        openSession(project).close();
        inProject(project, featureKey).writeAsStringSync(loginV2);
        final session = openSession(project);
        addTearDown(session.close);
        expect(titleOf(session, featureDoc), 'Login v2');
      },
    );
    test('f01/us01/s2: the first call builds from every doc and writes only .specstone/.gitignore', () async {
      final project = await writeLoginProject();
      final session = openSession(project);
      addTearDown(session.close);
      expect(session.docs, hasLength(25));
      expect(
        inProject(project, '.specstone/.gitignore').readAsStringSync(),
        'index.sqlite*\nbuild/\ntrash/\n',
      );
      expect(inProject(project, '.gitignore').existsSync(), isFalse);
    });
    test('f01/us01/s3: added docs show and deleted docs do not', () async {
      final project = await writeLoginProject();
      openSession(project).close();
      inProject(project, 'docs/prds/references/new_rule/REFERENCE.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('# New rule\n');
      inProject(project, 'docs/README.md').deleteSync();
      final session = openSession(project);
      addTearDown(session.close);
      final paths = [for (final d in session.docs) d.docPath];
      expect(paths, contains('prds/references/new_rule/REFERENCE.md'));
      expect(paths, isNot(contains('README.md')));
    });
    test('f01/us01/s4: changed templates are read as the current templates read them', () async {
      final project = await writeLoginProject(
        extra: {
          featureKey: '${loginProject[featureKey]}\n## Open Notes\nLater.\n',
        },
      );
      openSession(project).close();
      inProject(project, '.specstone/templates/feature.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'sections:\n  - id: open_notes\n    header: Open Notes\n    after: out_of_scope\n',
        );
      final session = openSession(project);
      addTearDown(session.close);
      expect(
        session.store.loadContent(featureDoc).sections.last.key,
        'open_notes',
      );
    });
    test('f01/us01/s5, f01/us01/fr05/e01: two sessions in two isolates after an edit both read the edit', () async {
      final project = await writeLoginProject();
      openSession(project).close();
      inProject(project, featureKey).writeAsStringSync(loginV2);
      final root = project.path;
      String? titleIn() {
        final session = openSession(Directory(root));
        try {
          return titleOf(session, featureDoc);
        } finally {
          session.close();
        }
      }

      expect(await Future.wait([Isolate.run(titleIn), Isolate.run(titleIn)]), [
        'Login v2',
        'Login v2',
      ]);
    });
    test('f01/us01/fr05/e02: an open session keeps its snapshot while another call reindexes', () async {
      final project = await writeLoginProject();
      final before = openSession(project);
      addTearDown(before.close);
      inProject(project, featureKey).writeAsStringSync(loginV2);
      final after = openSession(project);
      addTearDown(after.close);
      expect(before.store.loadContent(featureDoc).text, contains('# Login\n'));
      expect(
        after.store.loadContent(featureDoc).text,
        contains('# Login v2\n'),
      );
    });
    test(
      'f01/us01/s6, NFR-DI02: a deleted index rebuilds to the same answers',
      () async {
        final project = await writeLoginProject();
        final intact = openSession(project);
        final expected = answers(intact);
        intact.close();
        deleteIndex(project);
        final rebuilt = openSession(project);
        addTearDown(rebuilt.close);
        expect(answers(rebuilt), expected);
        expect(rebuilt.warnings, isNot(contains(damagedIndexWarning)));
      },
    );
    test('f01/us01/s6, f01/us01/fr05/e03: a damaged index rebuilds to the same answers, with the warning', () async {
      final project = await writeLoginProject();
      final intact = openSession(project);
      final expected = answers(intact);
      intact.close();
      deleteIndex(project);
      inProject(project, indexFilePath).writeAsStringSync('not a database');
      final rebuilt = openSession(project);
      addTearDown(rebuilt.close);
      expect(answers(rebuilt), expected);
      expect(rebuilt.warnings.first, damagedIndexWarning);
    });
    test('f01/us01/fr05/e03, s03/inv23: an index whose later pages are lost rebuilds to the same answers, with the warning', () async {
      final project = await writeLoginProject();
      final intact = openSession(project);
      final expected = answers(intact);
      intact.close();
      final index = inProject(project, indexFilePath);
      final bytes = index.readAsBytesSync();
      for (final suffix in ['-wal', '-shm']) {
        final f = inProject(project, '$indexFilePath$suffix');
        if (f.existsSync()) f.deleteSync();
      }
      // Page 1 and the file size survive, so opening the file succeeds; the
      // first read of a lost page is what fails.
      index.writeAsBytesSync([
        ...bytes.sublist(0, 4096),
        ...List<int>.filled(bytes.length - 4096, 0xAB),
      ]);
      inProject(project, featureKey).writeAsStringSync(loginV2);
      final rebuilt = openSession(project);
      addTearDown(rebuilt.close);
      expect(titleOf(rebuilt, featureDoc), 'Login v2');
      expect(rebuilt.docs, hasLength(expected.length));
      expect(rebuilt.warnings.first, damagedIndexWarning);
    });
    test('f01/us01/s8: a doc two doc types describe reads with no doc type and a warning naming both', () async {
      final session = openSession(
        await writeLoginProject(
          extra: {
            '.specstone/templates/legacy_fr.yaml': 'id: legacy_fr\ndescription: Old FRs.\npath: prds/features/f{nn}_{slug}/us{nn}_{slug}/{slug}.md\n',
          },
        ),
      );
      addTearDown(session.close);
      const fr =
          'prds/features/f01_login/us01_email_login/fr02_lock_after_failures.md';
      expect(session.docs.firstWhere((d) => d.docPath == fr).docTypeId, isNull);
      expect(
        session.warnings,
        contains('$fr matches two doc types: fr, legacy_fr'),
      );
    });
    test('f01/us01/s9: schema and API export files never appear', () async {
      final session = openSession(await writeLoginProject());
      addTearDown(session.close);
      expect([
        for (final d in session.docs) d.docPath,
      ], isNot(anyElement(anyOf(endsWith('.dbml'), endsWith('.json')))));
    });
    test(
      'f01/us01/s12, f01/us01/fr02/e07: a read-only index file refuses a needed reindex and keeps its bytes',
      skip: unreadablePathSkipReason(),
      () async {
        final project = await writeLoginProject();
        openSession(project).close();
        final index = inProject(project, indexFilePath);
        final before = index.readAsBytesSync();
        Process.runSync('chmod', ['444', index.path]);
        addTearDown(() => Process.runSync('chmod', ['644', index.path]));
        inProject(project, featureKey).writeAsStringSync(loginV2);
        expect(
          () => openSession(project),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.indexNotWritable)
                .having((f) => f.exitStatus, 'exit', 73),
          ),
        );
        expect(index.readAsBytesSync(), before);
      },
    );
    test('f01/us01/s13, f01/us01/fr05/e05, s03/inv23: a lock held past the timeout is index_busy and changes nothing', () async {
      final project = await writeLoginProject();
      openSession(project).close();
      final holder = sqlite3.open(inProject(project, indexFilePath).path)
        ..execute('BEGIN IMMEDIATE');
      inProject(project, featureKey).writeAsStringSync(loginV2);
      expect(
        () => openSession(
          project,
          busyTimeout: const Duration(milliseconds: 200),
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.indexBusy)
              .having((f) => f.exitStatus, 'exit', 75),
        ),
      );
      final peek = IndexStore.open(project);
      expect(
        peek.hashes()[featureDoc],
        contentHashOf(utf8.encode(loginProject[featureKey]!)),
      );
      peek.close();
      holder
        ..execute('ROLLBACK')
        ..close();
      final session = openSession(project);
      addTearDown(session.close);
      expect(titleOf(session, featureDoc), 'Login v2');
    });
    test('s03/inv1, review focus 3: a non-finite YAML number is indexed as its YAML text', () async {
      const key = 'docs/prds/features/f04_limits/FEATURE.md';
      final session = openSession(
        await writeLoginProject(
          extra: {
            key: '---\nmax_users: .inf\nmin_users: -.inf\nratio: .nan\nlimits:\n  - .inf\n  - cap: .nan\n---\n\n# Limits\n',
          },
        ),
      );
      addTearDown(session.close);
      expect(
        session.docs
            .firstWhere(
              (d) => d.docPath == 'prds/features/f04_limits/FEATURE.md',
            )
            .frontmatter,
        {
          'max_users': '.inf',
          'min_users': '-.inf',
          'ratio': '.nan',
          'limits': [
            '.inf',
            {'cap': '.nan'},
          ],
        },
      );
    });
    test('review focus 2, review focus 3: a non-UTF-8 doc and a bad frontmatter doc are indexed with warnings', () async {
      final project = await writeLoginProject(
        extra: {
          'docs/prds/features/f03_broken/FEATURE.md':
              '---\nvision: [PV-01\n---\n\n# Broken\n',
        },
      );
      inProject(
        project,
        'docs/bad.md',
      ).writeAsBytesSync([0x23, 0x20, 0xFF, 0x0A]);
      final session = openSession(project);
      addTearDown(session.close);
      expect(session.docs, hasLength(27));
      expect(
        session.warnings,
        containsAll([
          'bad.md: not UTF-8 text; indexed with replacement characters',
          'prds/features/f03_broken/FEATURE.md: frontmatter is not valid YAML; its values are not indexed',
        ]),
      );
    });
  });

  group('ReadSession.run', () {
    T runSession<T>(Directory p, T Function(ReadSession s) answer) =>
        ReadSession.run(
          answer,
          templates: TemplateResolver(),
          workingDirectory: p,
          homeDirectory: null,
        );
    SqliteException sqliteError(int code) =>
        SqliteException(extendedResultCode: code, message: 'test error');
    Matcher closed() => everyElement(
      isA<ReadSession>().having(
        (s) =>
            () => s.store.readStamp(),
        'store read',
        throwsStateError,
      ),
    );
    // Zeroes the root page of each table only an answer reads, so the session
    // opens and refreshes, and the answer's first read of them fails.
    void loseAnswerPages(Directory p) {
      final index = inProject(p, indexFilePath);
      final db = sqlite3.open(index.path);
      final pageSize = db.select('PRAGMA page_size').single.columnAt(0) as int;
      final roots = [
        for (final row in db.select(
          'SELECT rootpage FROM sqlite_master '
          "WHERE name IN ('sections', 'links', 'doc_search_content')",
        ))
          row.columnAt(0) as int,
      ];
      db.close();
      final bytes = index.readAsBytesSync();
      for (final root in roots) {
        bytes.fillRange((root - 1) * pageSize, root * pageSize, 0);
      }
      index.writeAsBytesSync(bytes);
    }

    test('f01/us01/fr05/e03, s03/inv23: a page lost where only the answer reads rebuilds the index and answers as an intact index does, with the warning', () async {
      final project = await writeLoginProject();
      final expected = runSession(project, answers);
      loseAnswerPages(project);
      final sessions = <ReadSession>[];
      final answered = runSession(project, (s) {
        sessions.add(s);
        return answers(s);
      });
      expect(answered, expected);
      expect(sessions, hasLength(2));
      expect(sessions.last.warnings.first, damagedIndexWarning);
      expect(sessions, closed());
    });
    test('f01/us01/fr05/e03: a second damage error while answering is index_not_writable, exit 73, and closes both sessions', () async {
      final project = await writeLoginProject();
      final sessions = <ReadSession>[];
      expect(
        () => runSession<void>(project, (s) {
          sessions.add(s);
          throw sqliteError(SqlError.SQLITE_CORRUPT);
        }),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.indexNotWritable)
              .having((f) => f.exitStatus, 'exit', 73),
        ),
      );
      expect(sessions, hasLength(2));
      expect(sessions.last.warnings.first, damagedIndexWarning);
      expect(sessions, closed());
    });
    test('f01/us01/fr05/e05: another database error while answering is its own fault, with no rebuild', () async {
      final project = await writeLoginProject();
      final sessions = <ReadSession>[];
      expect(
        () => runSession<void>(project, (s) {
          sessions.add(s);
          throw sqliteError(SqlError.SQLITE_BUSY);
        }),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.indexBusy)
              .having((f) => f.exitStatus, 'exit', 75),
        ),
      );
      expect(sessions, hasLength(1));
      expect(sessions, closed());
    });
    test('f01/us01/fr05: a fault from the answer passes unchanged and closes the session', () async {
      final project = await writeLoginProject();
      final fault = IndexFault(IndexFaultCode.sectionNotFound, 'no section');
      final sessions = <ReadSession>[];
      expect(
        () => runSession<void>(project, (s) {
          sessions.add(s);
          throw fault;
        }),
        throwsA(same(fault)),
      );
      expect(sessions, hasLength(1));
      expect(sessions, closed());
    });
  });
}
