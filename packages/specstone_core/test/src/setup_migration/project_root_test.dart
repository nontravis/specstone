import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
import 'package:specstone_core/src/templates/project_config.dart';
import 'package:test/test.dart';

import '../../helpers/relative_link.dart';
import '../../helpers/temp_tree.dart';

final String _journal = jsonEncode(
  const MoveJournal([
    CommitStep(message: 'move', paths: ['a'], base: 'abc'),
  ]).toJson(),
);

String _canonical(Directory dir) => dir.resolveSymbolicLinksSync();

void main() {
  group('locateMigrateRoot', () {
    test('the walk stops at the first folder holding config, '
        'legacy context doc, or journal', () async {
      for (final marker in {
        '.specstone/config.yaml': 'packs:\n',
        legacyContextPath: '# D-01\n',
        MoveJournal.journalPath: _journal,
      }.entries) {
        final tree = await writeTree({
          'repo/${marker.key}': marker.value,
          'repo/a/b/keep.txt': '',
        });
        final root = locateMigrateRoot(Directory('${tree.path}/repo/a/b')).root;

        expect(
          _canonical(root),
          _canonical(Directory('${tree.path}/repo')),
          reason: marker.key,
        );
      }
    });

    test('no marker up to the filesystem root is '
        'project_not_found', () async {
      final tree = await writeTree({'a/b/keep.txt': ''});

      expect(
        () => locateMigrateRoot(Directory('${tree.path}/a/b')).root,
        throwsA(
          isA<RenderFault>()
              .having((f) => f.code, 'code', RenderFaultCode.projectNotFound)
              .having((f) => f.exitStatus, 'exitStatus', 78),
        ),
      );
    });

    test('f06/us01/fr01/e02, f06/us01/s10: a docs link stands for the '
        'parent of its target', () async {
      final tree = await writeTree({
        'docsrepo/docs/prds/d01_context.md': '# D-01\n',
        'repo/code/lib/keep.txt': '',
      });
      try {
        createRelativeLink(
          '${tree.path}/repo/code/docs',
          '../../docsrepo/docs',
        );
      } on FileSystemException {
        markTestSkipped('symbolic links need privileges on this machine');
        return;
      }

      final root = locateMigrateRoot(Directory('${tree.path}/repo/code/lib'))
          .root;

      expect(_canonical(root), _canonical(Directory('${tree.path}/docsrepo')));
    });

    test('a nested project with its own legacy context '
        'doc is its own root', () async {
      final tree = await writeTree({
        'outer/docs/prds/d01_context.md': '# D-01\n',
        'outer/example-app/docs/prds/d01_context.md': '# D-01\n',
        'outer/example-app/lib/keep.txt': '',
      });

      final root = locateMigrateRoot(
        Directory('${tree.path}/outer/example-app/lib'),
      ).root;

      expect(
        _canonical(root),
        _canonical(Directory('${tree.path}/outer/example-app')),
      );
    });

    test('a pending journal marks the root when the '
        'context doc has moved and no config exists', () async {
      final tree = await writeTree({
        MoveJournal.journalPath: _journal,
        'docs/prds/PROJECT.md': '# Project\n',
        'docs/prds/sub/keep.txt': '',
      });

      final root = locateMigrateRoot(Directory('${tree.path}/docs/prds/sub'))
          .root;

      expect(_canonical(root), _canonical(tree));
    });

    test('f06/us01/fr01/e07, final M8: a pending journal beside the linked '
        'docs marks the root from the code folder', () async {
      final tree = await writeTree({
        'acme-docs/${MoveJournal.journalPath}': _journal,
        'acme-docs/docs/prds/PROJECT.md': '# Project\n',
        'acme/lib/keep.txt': '',
      });
      try {
        createRelativeLink('${tree.path}/acme/docs', '../acme-docs/docs');
      } on FileSystemException {
        markTestSkipped('symbolic links need privileges on this machine');
        return;
      }

      final root = locateMigrateRoot(Directory('${tree.path}/acme')).root;

      expect(_canonical(root), _canonical(Directory('${tree.path}/acme-docs')));
    });
  });

  group('locateMigrateRoot and findProjectRoot share one walk', () {
    Future<Directory?> nestedTree(Map<String, String> files) async {
      final tree = await writeTree({...files, 'ws/code/example/keep.txt': ''});
      try {
        createRelativeLink(
          '${tree.path}/ws/code/example/docs',
          '../../example/docs',
        );
      } on FileSystemException {
        markTestSkipped('symbolic links need privileges on this machine');
        return null;
      }
      return tree;
    }

    test('both find the nested project, not the outer one', () async {
      final tree = await nestedTree({
        'ws/.specstone/config.yaml': 'packs:\n',
        'ws/example/.specstone/config.yaml': 'packs:\n',
        'ws/example/docs/keep.txt': '',
      });
      if (tree == null) return;
      final start = Directory('${tree.path}/ws/code/example');
      final nested = _canonical(Directory('${tree.path}/ws/example'));

      expect(_canonical(locateMigrateRoot(start).root), nested);
      expect(_canonical(findProjectRoot(start)!), nested);
    });

    test('a nested project with only a legacy context doc is the migrate '
        'root, not the outer one', () async {
      final tree = await nestedTree({
        'ws/.specstone/config.yaml': 'packs:\n',
        'ws/example/$legacyContextPath': '# D-01\n',
      });
      if (tree == null) return;

      final root = locateMigrateRoot(Directory('${tree.path}/ws/code/example'))
          .root;

      expect(
        _canonical(root),
        _canonical(Directory('${tree.path}/ws/example')),
      );
    });

    test('a folder with its own config whose docs link leaves every project '
        'is its own migrate root', () async {
      final tree = await writeTree({
        'ws/code/.specstone/config.yaml': 'packs:\n',
        'plain/docs/keep.txt': '',
      });
      try {
        createRelativeLink('${tree.path}/ws/code/docs', '../../plain/docs');
      } on FileSystemException {
        markTestSkipped('symbolic links need privileges on this machine');
        return;
      }

      final root = locateMigrateRoot(Directory('${tree.path}/ws/code')).root;

      expect(_canonical(root), _canonical(Directory('${tree.path}/ws/code')));
    });
  });

  group('locateMigrateRoot returns the link folder', () {
    Future<Directory?> linkedTree() async {
      final tree = await writeTree({
        'ws/$legacyContextPath': '# D-01\n',
        'ws/code/lib/keep.txt': '',
      });
      try {
        createRelativeLink('${tree.path}/ws/code/docs', '../docs');
      } on FileSystemException {
        markTestSkipped('symbolic links need privileges on this machine');
        return null;
      }
      return tree;
    }

    test('the folder whose docs link led to the root is the link folder, '
        'from itself and from below', () async {
      final tree = await linkedTree();
      if (tree == null) return;
      final ws = _canonical(Directory('${tree.path}/ws'));
      final code = _canonical(Directory('${tree.path}/ws/code'));

      for (final start in ['ws/code', 'ws/code/lib']) {
        final (:root, :linkFolder) = locateMigrateRoot(
          Directory('${tree.path}/$start'),
        );

        expect(root.path, ws, reason: start);
        expect(linkFolder?.path, code, reason: start);
      }
    });

    test('a root with a real docs folder has no link folder', () async {
      final tree = await writeTree({
        'ws/$legacyContextPath': '# D-01\n',
        'ws/lib/keep.txt': '',
      });
      final ws = _canonical(Directory('${tree.path}/ws'));

      for (final start in ['ws', 'ws/lib']) {
        final (:root, :linkFolder) = locateMigrateRoot(
          Directory('${tree.path}/$start'),
        );

        expect(root.path, ws, reason: start);
        expect(linkFolder, isNull, reason: start);
      }
    });

    test('a folder outside every project is project_not_found', () async {
      final tree = await writeTree({'a/keep.txt': ''});

      expect(
        () => locateMigrateRoot(Directory('${tree.path}/a')),
        throwsA(
          isA<RenderFault>().having(
            (f) => f.code,
            'code',
            RenderFaultCode.projectNotFound,
          ),
        ),
      );
    });
  });

  group('relativeFolderPath', () {
    late Directory ws;

    setUp(() async {
      final tree = await writeTree({
        'ws/stratum_ui/example/keep.txt': '',
        'ws/example/keep.txt': '',
      });
      ws = Directory(_canonical(Directory('${tree.path}/ws')));
    });

    Directory at(String relative) =>
        Directory('${ws.path}${Platform.pathSeparator}$relative');

    test('a folder to itself is .', () {
      expect(relativeFolderPath(ws, ws), '.');
    });

    test('a child folder is its name', () {
      expect(relativeFolderPath(ws, at('stratum_ui')), 'stratum_ui');
    });

    test('a folder below a sibling climbs with ..', () {
      expect(
        relativeFolderPath(
          at('example'),
          Directory(
            '${ws.path}${Platform.pathSeparator}stratum_ui'
            '${Platform.pathSeparator}example',
          ),
        ),
        '../stratum_ui/example',
      );
    });

    test('folders on two drives have no relative path', () {
      expect(
        relativeFolderPath(Directory(r'C:\a'), Directory(r'D:\b')),
        isNull,
      );
    }, skip: Platform.isWindows ? false : 'only Windows has drive letters');
  });

  group('rootThroughDocsLink', () {
    test('a dangling docs link leaves the folder as its '
        'own root', () async {
      final tree = await writeTree({'keep.txt': ''});
      try {
        Link('${tree.path}/docs').createSync('${tree.path}/missing/docs');
      } on FileSystemException {
        markTestSkipped('symbolic links need privileges on this machine');
        return;
      }

      expect(_canonical(rootThroughDocsLink(tree)), _canonical(tree));
    });

    test('a folder without a docs link stays itself', () async {
      final tree = await writeTree({'docs/prds/d01_context.md': '# D-01\n'});

      expect(_canonical(rootThroughDocsLink(tree)), _canonical(tree));
    });
  });
}
