import 'dart:io';

import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/rendering/doc_tree.dart';
import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';
import '../../helpers/posix_modes.dart';

const _tree = [
  'prds/zeta.md',
  'prds/d02_features.md',
  'prds/d10_more.md',
  'prds/d1_dup.md',
  'prds/d01_context.md',
  'prds/.DS_Store',
  'prds/.git/HEAD.md',
  'prds/features/f05_rendering/FEATURE.md',
  'prds/features/f05_rendering/us02_b/USER_STORY.md',
  'prds/features/f05_rendering/us01_a/USER_STORY.md',
  'prds/features/f05_rendering/us01_a/functional_requirements/fr02_y.md',
  'prds/features/f05_rendering/us01_a/functional_requirements/fr01_x.md',
  'prds/features/f05_rendering/us01_a/non_functional_requirements/nf01_z.md',
  'specs/rendering/s01_architecture.md',
];

const _prdsInOrder = [
  'prds/zeta.md',
  'prds/d01_context.md',
  'prds/d1_dup.md',
  'prds/d02_features.md',
  'prds/d10_more.md',
  'prds/features/f05_rendering/FEATURE.md',
  'prds/features/f05_rendering/us01_a/USER_STORY.md',
  'prds/features/f05_rendering/us01_a/functional_requirements/fr01_x.md',
  'prds/features/f05_rendering/us01_a/functional_requirements/fr02_y.md',
  'prds/features/f05_rendering/us01_a/non_functional_requirements/nf01_z.md',
  'prds/features/f05_rendering/us02_b/USER_STORY.md',
];

typedef _Walk = ({
  DocsProject project,
  Directory root,
  List<DocEntry> Function(String? target) collect,
});

Future<_Walk> _walk([List<String> files = _tree]) async {
  final root = await fixtureProject({
    for (final file in files) 'docs/$file': '',
  });
  final project = DocsProject.open(
    templates: TemplateResolver(shippedFiles: fixturePackFiles()),
    workingDirectory: root,
    homeDirectory: null,
  );
  final matcher = DocTypeMatcher(await fixtureDocTypes());
  return (
    project: project,
    root: root,
    collect: (String? target) => collectDocEntries(
      project.resolveTarget(
        target,
        workingDirectory: root,
        defaultsToDocsRoot: false,
      ),
      matcher,
    ),
  );
}

List<String> _docPaths(List<DocEntry> files) => [
  for (final file in files) file.docPath,
];

void main() {
  group('collectDocEntries', () {
    test('f05/us02/fr01, f05/us02/fr01/e08, s03/inv10: a folder yields its '
        'docs in tree order', () async {
      final walk = await _walk();

      expect(_docPaths(walk.collect('docs/prds')), _prdsInOrder);
    });

    test(
      'f05/us01/fr01/e06, f05/us02/fr01/e09: dot-named files and folders '
      'are never visited, so an unreadable .git does not fail the walk',
      () async {
        final walk = await _walk();
        final git = Directory('${walk.project.docsRoot.path}/prds/.git');
        await Process.run('chmod', ['000', git.path]);
        addTearDown(() => Process.run('chmod', ['755', git.path]));

        final paths = _docPaths(walk.collect('docs/prds'));

        expect(paths, _prdsInOrder);
        expect(paths.where((path) => path.contains('/.')), isEmpty);
      },
      skip: Platform.isWindows ? 'chmod does not apply on Windows' : false,
    );

    test('f05/us02/fr01/e01: a feature folder yields the feature, then each '
        'story with its requirements', () async {
      final walk = await _walk();

      expect(
        _docPaths(walk.collect('docs/prds/features/f05_rendering')),
        _prdsInOrder.sublist(5),
      );
    });

    test('f05/us02/fr01/e06: a folder target holds only its own subtree, the '
        'docs root holds every folder', () async {
      final walk = await _walk();

      final feature = _docPaths(
        walk.collect('docs/prds/features/f05_rendering'),
      );
      final everything = _docPaths(walk.collect('docs'));

      expect(feature, isNot(contains('prds/d01_context.md')));
      expect(feature.where((path) => path.startsWith('specs/')), isEmpty);
      expect(everything, [
        ..._prdsInOrder,
        'specs/rendering/s01_architecture.md',
      ]);
    });

    test('f05/us02/fr01: a file target yields itself', () async {
      final walk = await _walk();

      final files = walk.collect('docs/prds/d01_context.md');

      expect(_docPaths(files), ['prds/d01_context.md']);
      expect((files.single as DocFile).file.existsSync(), isTrue);
    });

    test(
      'f05/us02/fr01/e08: numbers that overflow an int sort as unnumbered',
      () async {
        final walk = await _walk([
          'prds/d99999999999999999999_big.md',
          'prds/d02_b.md',
          'prds/a.md',
        ]);

        expect(_docPaths(walk.collect('docs/prds')), [
          'prds/a.md',
          'prds/d99999999999999999999_big.md',
          'prds/d02_b.md',
        ]);
      },
    );

    test('f05/us02/fr01/e08: unnumbered names sort by code point, not '
        'by locale', () async {
      final walk = await _walk(['prds/b.md', 'prds/Z.md', 'prds/a.md']);

      expect(_docPaths(walk.collect('docs/prds')), [
        'prds/Z.md',
        'prds/a.md',
        'prds/b.md',
      ]);
    });

    test('f05/us02/fr01: links are not followed', () async {
      final walk = await _walk(['prds/a.md', 'outside/secret.md']);
      final docs = walk.project.docsRoot.path;
      await Link('$docs/prds/loop').create('$docs/outside');
      await Link('$docs/prds/alias.md').create('$docs/prds/a.md');

      expect(_docPaths(walk.collect('docs/prds')), ['prds/a.md']);
    }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);
  });

  group('an unreadable folder', () {
    test('f05/us02/fr01: yields an UnreadableFolder in its place; the rest of '
        'the tree still comes', () async {
      final walk = await _walk(['prds/a.md', 'prds/locked/b.md', 'z.md']);
      final locked = Directory('${walk.root.path}/docs/prds/locked');
      await Process.run('chmod', ['000', locked.path]);
      addTearDown(() => Process.run('chmod', ['755', locked.path]));

      final entries = walk.collect('docs');

      expect(_docPaths(entries), ['z.md', 'prds/a.md', 'prds/locked']);
      expect(entries.last, isA<UnreadableFolder>());
      expect(entries.first, isA<DocFile>());
    }, skip: unreadablePathSkipReason() ?? false);
  });
}
