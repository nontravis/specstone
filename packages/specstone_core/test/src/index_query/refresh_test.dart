// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/refresh.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/posix_modes.dart';
import '../../helpers/temp_tree.dart';

/// Refreshes the index of the project at [path] in the calling isolate and
/// returns whether that refresh rebuilt the whole index.
bool _peerFullBuild(String path) {
  final docs = DocsProject.open(
    templates: TemplateResolver(),
    workingDirectory: Directory(path),
    homeDirectory: null,
  );
  final store = IndexStore.open(docs.projectRoot);
  try {
    return refreshIndex(store, docs).fullBuild;
  } finally {
    store.close();
  }
}

/// Runs [_peerFullBuild] in a new isolate.
///
/// Top level so the closure captures no open index.
Future<bool> _startPeer(String path) => Isolate.run(() => _peerFullBuild(path));

void main() {
  ({RefreshResult result, IndexStore store}) refresh(Directory project) {
    final docs = DocsProject.open(
      templates: TemplateResolver(),
      workingDirectory: project,
      homeDirectory: null,
    );
    final store = IndexStore.open(docs.projectRoot);
    addTearDown(store.close);
    return (result: refreshIndex(store, docs), store: store);
  }

  List<String> paths(IndexStore s) => [for (final d in s.loadDocs()) d.docPath];
  IndexedDoc docAt(IndexStore s, String p) =>
      s.loadDocs().firstWhere((d) => d.docPath == p);

  /// Sets the mtime of every file under the docs root of [project] an hour
  /// back, outside the racy window of every later refresh.
  void backdate(Directory project) {
    final anHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    for (final f in Directory(
      '${project.path}/docs',
    ).listSync(recursive: true).whereType<File>()) {
      f.setLastModifiedSync(anHourAgo);
    }
  }

  /// Stores a checked_at 1 s after the mtime of [file], as when a bulk change
  /// was listed inside the racy window, and returns it.
  int listedInsideWindow(IndexStore s, File file) {
    final checkedAt =
        file.statSync().modified.microsecondsSinceEpoch +
        Duration.microsecondsPerSecond;
    s.write(() => s.setCheckedAt(checkedAt));
    return checkedAt;
  }

  /// Returns a check that tells whether a write landed on the index of
  /// [project] after this call.
  bool Function() watchWrites(Directory project) {
    final raw = sqlite3.open('${project.path}/$indexFilePath');
    addTearDown(raw.close);
    int dataVersion() =>
        raw.select('PRAGMA data_version').single.columnAt(0) as int;
    final before = dataVersion();
    return () => dataVersion() != before;
  }

  group('refreshIndex', () {
    test('f01/us01/fr02, f01/us01/fr02/e01, s03/inv1: a first refresh builds one entry per .md file', () async {
      final (:result, :store) = refresh(await writeLoginProject());
      expect(result.fullBuild, isTrue);
      expect(result.reindexed, 25);
      expect(paths(store).toSet(), {
        for (final k in loginProject.keys)
          if (k.startsWith('docs/') && k.endsWith('.md'))
            k.substring('docs/'.length),
      });
    });
    test('f01/us01/fr02/e03: an unchanged file is never reindexed; one edit reindexes one file', () async {
      final project = await writeLoginProject();
      refresh(project);
      expect(refresh(project).result.reindexed, 0);
      File('${project.path}/$featureKey').writeAsStringSync('# Login v2\n');
      final again = refresh(project).result;
      expect(again.fullBuild, isFalse);
      expect(again.reindexed, 1);
    });
    test(
      'f01/us01/fr02/e06: the answer reflects every edit made before the call',
      () async {
        final project = await writeLoginProject();
        refresh(project);
        File('${project.path}/$featureKey').writeAsStringSync('# Login v2\n');
        expect(docAt(refresh(project).store, featureDoc).title, 'Login v2');
      },
    );
    test('f01/us01/fr02, f01/us01/fr02/e03, s03/inv1: a warm refresh with no change hashes no file and writes nothing', () async {
      final project = await writeLoginProject();
      backdate(project);
      expect(refresh(project).result.hashed, 25);
      final written = watchWrites(project);
      final (:result, :store) = refresh(project);
      expect(result.hashed, 0);
      expect(result.reindexed, 0);
      expect(written(), isFalse);
      expect(paths(store), hasLength(25));
    });
    test('f01/us01/fr02, f01/us01/fr02/e06, s03/inv1: an edit that keeps the size and the mtime is seen inside the racy window', () async {
      final project = await writeLoginProject();
      backdate(project);
      final feature = File('${project.path}/$featureKey')
        // An mtime later than the refresh's start keeps the file inside the
        // racy window however slow the run.
        ..setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
      refresh(project);
      final before = feature.statSync();
      feature
        ..writeAsStringSync(
          feature.readAsStringSync().replaceFirst('# Login\n', '# Logon\n'),
        )
        ..setLastModifiedSync(before.modified);
      final after = feature.statSync();
      expect(
        (after.size, after.modified, after.mode),
        (before.size, before.modified, before.mode),
      );
      final (:result, :store) = refresh(project);
      expect(result.reindexed, 1);
      expect(docAt(store, featureDoc).title, 'Logon');
    });
    test('f01/us01/fr02, f01/us01/fr02/e06, s03/inv1: an edit that changes the size or the mtime is seen', () async {
      final project = await writeLoginProject();
      backdate(project);
      refresh(project);
      final feature = File('${project.path}/$featureKey');
      final mtime = feature.statSync().modified;
      feature
        ..writeAsStringSync(
          feature.readAsStringSync().replaceFirst('# Login\n', '# Login v2\n'),
        )
        ..setLastModifiedSync(mtime);
      expect(docAt(refresh(project).store, featureDoc).title, 'Login v2');
      final size = feature.lengthSync();
      feature
        ..writeAsStringSync(
          feature.readAsStringSync().replaceFirst(
            '# Login v2\n',
            '# Login v3\n',
          ),
        )
        ..setLastModifiedSync(mtime.subtract(const Duration(minutes: 1)));
      expect(feature.lengthSync(), size);
      expect(docAt(refresh(project).store, featureDoc).title, 'Login v3');
    });
    test('f01/us01/fr02, f01/us01/fr02/e03, s03/inv1: a touched file is not reindexed, and its new stat is stored so the next call hashes no file', () async {
      final project = await writeLoginProject();
      backdate(project);
      refresh(project);
      final feature = File('${project.path}/$featureKey');
      feature.setLastModifiedSync(
        feature.statSync().modified.add(const Duration(minutes: 1)),
      );
      final written = watchWrites(project);
      final touched = refresh(project).result;
      expect(touched.hashed, 1);
      expect(touched.reindexed, 0);
      expect(written(), isTrue);
      expect(refresh(project).result.hashed, 0);
    });
    test('f01/us01/fr02, f01/us01/fr02/e03, s03/inv1: a bulk change listed inside the racy window is hashed once more, then checked_at moves and the next call hashes no file', () async {
      final project = await writeLoginProject();
      backdate(project);
      final rewound = listedInsideWindow(
        refresh(project).store,
        File('${project.path}/$featureKey'),
      );
      var written = watchWrites(project);
      final second = refresh(project);
      expect(second.result.hashed, 25);
      expect(second.result.reindexed, 0);
      expect(written(), isTrue);
      expect(second.store.readCheckedAt(), greaterThan(rewound));
      written = watchWrites(project);
      expect(refresh(project).result.hashed, 0);
      expect(written(), isFalse);
    });
    test('f01/us01/fr02, f01/us01/fr02/e06, s03/inv1: a file still inside the racy window stays hashed after checked_at moves', () async {
      final project = await writeLoginProject();
      backdate(project);
      final feature = File('${project.path}/$featureKey')
        // An mtime later than every refresh's start keeps the file inside the
        // racy window however slow the run.
        ..setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
      listedInsideWindow(
        refresh(project).store,
        File('${project.path}/docs/README.md'),
      );
      final written = watchWrites(project);
      expect(refresh(project).result.hashed, 25);
      expect(written(), isTrue);
      final before = feature.statSync();
      feature
        ..writeAsStringSync(
          feature.readAsStringSync().replaceFirst('# Login\n', '# Logon\n'),
        )
        ..setLastModifiedSync(before.modified);
      final (:result, :store) = refresh(project);
      expect(result.hashed, 1);
      expect(result.reindexed, 1);
      expect(docAt(store, featureDoc).title, 'Logon');
    });
    test(
      'f01/us01/fr02, f01/us01/fr02/e08, s03/inv1: a chmod that makes a trusted file unreadable warns and drops it',
      skip: unreadablePathSkipReason(),
      () async {
        final project = await writeLoginProject();
        backdate(project);
        refresh(project);
        final readme = File('${project.path}/docs/README.md');
        Process.runSync('chmod', ['000', readme.path]);
        addTearDown(() => Process.runSync('chmod', ['644', readme.path]));
        final (:result, :store) = refresh(project);
        expect(result.warnings, ['README.md: cannot be read; skipped']);
        expect(paths(store), hasLength(24));
        expect(paths(store), isNot(contains('README.md')));
      },
    );
    test('f01/us01/fr02, f01/us01/fr02/e02, s03/inv2: an index written under an older layout is rebuilt with no fault', () async {
      final project = await writeLoginProject();
      refresh(project);
      sqlite3.open('${project.path}/$indexFilePath')
        ..execute('ALTER TABLE docs DROP COLUMN content_hash')
        ..userVersion = 0
        ..close();
      final (:result, :store) = refresh(project);
      expect(result.fullBuild, isTrue);
      expect(paths(store), hasLength(25));
    });
    test('f01/us01/fr05/e01, s03/inv23: a call that waited for the lock finds the stamp current and does not rebuild', () async {
      final project = await writeLoginProject();
      refresh(project);
      File('${project.path}/.specstone/templates/feature.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'sections:\n  - id: open_notes\n    header: Open Notes\n    after: out_of_scope\n',
        );
      final docs = DocsProject.open(
        templates: TemplateResolver(),
        workingDirectory: project,
        homeDirectory: null,
      );
      final holder = IndexStore.open(docs.projectRoot);
      addTearDown(holder.close);
      late final Future<bool> peer;
      holder.write(() {
        holder.reset(IndexStamp.of(docs.set));
        // The peer starts under the lock, reads the old stamp, then waits.
        peer = _startPeer(project.path);
        sleep(const Duration(milliseconds: 1500));
      });
      expect(await peer, isFalse);
    });
    test('f01/us01/fr05/e01, s03/inv1: a call that waited for the lock reads again each file the index no longer vouches for', () async {
      final project = await writeLoginProject();
      backdate(project);
      refresh(project);
      File('${project.path}/docs/NEW.md').writeAsStringSync('# New\n');
      final docs = DocsProject.open(
        templates: TemplateResolver(),
        workingDirectory: project,
        homeDirectory: null,
      );
      final holder = IndexStore.open(docs.projectRoot);
      addTearDown(holder.close);
      late final Future<bool> peer;
      holder.write(() {
        holder.reset(IndexStamp.of(docs.set));
        // The peer trusts the old stat keys of 25 files, then waits.
        peer = _startPeer(project.path);
        sleep(const Duration(milliseconds: 1500));
      });
      expect(await peer, isFalse);
      expect(paths(holder), hasLength(26));
    });
    test('f01/us01/fr02/e02, s03/inv2: an edit under .specstone/templates/ rebuilds the whole index', () async {
      final project = await writeLoginProject(
        extra: {
          featureKey: '${loginProject[featureKey]}\n## Open Notes\nLater.\n',
        },
      );
      String lastKey(IndexStore s) =>
          s.loadContent(featureDoc).sections.last.key;
      expect(lastKey(refresh(project).store), 'open-notes');
      File('${project.path}/.specstone/templates/feature.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'sections:\n  - id: open_notes\n    header: Open Notes\n'
          '    after: out_of_scope\n',
        );
      final (:result, :store) = refresh(project);
      expect(result.fullBuild, isTrue);
      expect(lastKey(store), 'open_notes');
    });
    test('f01/us01/fr02/e02, s03/inv2: an index built by another binary version is rebuilt', () async {
      final project = await writeLoginProject();
      final first = refresh(project).store;
      first.write(
        () => first.reset(
          const IndexStamp(binaryVersion: '0.0.0', docTypes: 'other'),
        ),
      );
      final (:result, :store) = refresh(project);
      expect(result.fullBuild, isTrue);
      expect(paths(store), hasLength(25));
    });
    test('f01/us01/fr02/e04, s03/inv3: .dbml and .apidog.json files are never indexed', () async {
      final store = refresh(await writeLoginProject()).store;
      expect(paths(store).where((p) => !p.endsWith('.md')), isEmpty);
    });
    test('f01/us01/fr02/e05: a renamed doc leaves its old DocPath and gains its new one in one refresh', () async {
      final project = await writeLoginProject();
      refresh(project);
      File('${project.path}/docs/README.md')
          .renameSync('${project.path}/docs/START.md');
      final (:result, :store) = refresh(project);
      expect(result.reindexed, 2);
      expect(paths(store), contains('START.md'));
      expect(paths(store), isNot(contains('README.md')));
    });
    test(
      'f01/us01/fr02/e08, s03/inv1: an unreadable file and an unlistable folder are left out with warnings',
      skip: unreadablePathSkipReason(),
      () async {
        final project = await writeLoginProject(
          extra: {'docs/locked/a.md': '# A\n'},
        );
        final readme = File('${project.path}/docs/README.md');
        final locked = Directory('${project.path}/docs/locked');
        Process.runSync('chmod', ['000', readme.path]);
        Process.runSync('chmod', ['000', locked.path]);
        addTearDown(() {
          Process.runSync('chmod', ['644', readme.path]);
          Process.runSync('chmod', ['755', locked.path]);
        });
        final (:result, :store) = refresh(project);
        expect(
          result.warnings,
          unorderedEquals([
            'README.md: cannot be read; skipped',
            'locked/: cannot be read; skipped',
          ]),
        );
        expect(paths(store), hasLength(24));
        expect(paths(store), isNot(contains('README.md')));
      },
    );
    test('f01/us01/fr02/e09, s03/inv1: dot-named files and folders are never listed', () async {
      final store = refresh(
        await writeLoginProject(
          extra: {
            'docs/.obsidian/workspace.md': '# W\n',
            'docs/prds/.draft.md': '# D\n',
          },
        ),
      ).store;
      expect(paths(store), hasLength(25));
      expect(
        paths(store).where((p) => p.split('/').any((s) => s.startsWith('.'))),
        isEmpty,
      );
    });
    test(
      'f01/us01/fr02/e10, s03/inv1: a symbolic link to a file or a folder is not followed',
      skip: Platform.isWindows ? 'links need privileges on Windows' : null,
      () async {
        final project = await writeLoginProject();
        final outside = await writeTree({'notes/b.md': '# B\n'});
        Link('${project.path}/docs/linked').createSync('${outside.path}/notes');
        Link('${project.path}/docs/alias.md')
            .createSync('${project.path}/docs/README.md');
        final store = refresh(project).store;
        expect(paths(store), hasLength(25));
        expect(paths(store), isNot(contains('alias.md')));
        expect(paths(store), isNot(contains('linked/b.md')));
      },
    );
    test("f01/us01/fr03/e01, f01/us01/fr03/e04, s03/inv7: a refresh stores each doc's parent doc", () async {
      final store = refresh(await writeLoginProject()).store;
      expect(
        docAt(
          store,
          'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md',
        ).parentPath,
        'prds/features/f01_login/us01_email_login/USER_STORY.md',
      );
      expect(
        docAt(store, 'specs/f01_login/ARCHITECTURE.md').parentPath,
        featureDoc,
      );
      expect(docAt(store, 'prds/PROJECT.md').parentPath, isNull);
    });
    test("f01/us01/fr03/e01, s03/inv7: a refresh that reindexes one doc keeps that doc's parent doc", () async {
      const requirement =
          'prds/features/f01_login/us01_email_login/fr01_validate_credentials.md';
      final project = await writeLoginProject();
      refresh(project);
      File('${project.path}/docs/$requirement')
          .writeAsStringSync('# Validate credentials v2\n');
      final (:result, :store) = refresh(project);
      expect(result.reindexed, 1);
      expect(
        docAt(store, requirement).parentPath,
        'prds/features/f01_login/us01_email_login/USER_STORY.md',
      );
    });
    test('f01/us01/fr03/e10: a second feature named login leaves the story with no parent and a stored warning', () async {
      const story = 'prds/features/f01_login/us01_email_login/USER_STORY.md';
      final store = refresh(
        await writeLoginProject(
          extra: {'docs/prds/features/f03_login/FEATURE.md': '# Login again\n'},
        ),
      ).store;
      expect(docAt(store, story).parentPath, isNull);
      const warning =
          '$story has two candidate parent docs: '
          'prds/features/f01_login/FEATURE.md, '
          'prds/features/f03_login/FEATURE.md; it has no parent doc';
      expect(docAt(store, story).warnings, [warning]);
    });
    test('f01/us01/fr03/e11: a spec folder numbered f02_login takes the feature login as parent', () async {
      final store = refresh(
        await writeLoginProject(
          extra: {'docs/specs/f02_login/API.md': '# Login API v2\n'},
        ),
      ).store;
      expect(docAt(store, 'specs/f02_login/API.md').parentPath, featureDoc);
    });
  });
}
