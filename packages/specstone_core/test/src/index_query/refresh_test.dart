import 'dart:io';
import 'dart:isolate';

import 'package:specstone_core/src/index_query/index_store.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/refresh.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
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
