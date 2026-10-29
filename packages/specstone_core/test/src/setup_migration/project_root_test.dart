import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/document_writing/move_journal.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/setup_migration/project_root.dart';
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
  group('findMigrateRoot', () {
    test('f06/us01/fr01: the walk stops at the first folder holding config, '
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
        final root = findMigrateRoot(Directory('${tree.path}/repo/a/b'));

        expect(
          _canonical(root),
          _canonical(Directory('${tree.path}/repo')),
          reason: marker.key,
        );
      }
    });

    test('f06/us01/fr01/e01: no marker up to the filesystem root is '
        'project_not_found', () async {
      final tree = await writeTree({'a/b/keep.txt': ''});

      expect(
        () => findMigrateRoot(Directory('${tree.path}/a/b')),
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

      final root = findMigrateRoot(Directory('${tree.path}/repo/code/lib'));

      expect(_canonical(root), _canonical(Directory('${tree.path}/docsrepo')));
    });

    test('f06/us01/fr01/e05: a nested project with its own legacy context '
        'doc is its own root', () async {
      final tree = await writeTree({
        'outer/docs/prds/d01_context.md': '# D-01\n',
        'outer/example-app/docs/prds/d01_context.md': '# D-01\n',
        'outer/example-app/lib/keep.txt': '',
      });

      final root = findMigrateRoot(
        Directory('${tree.path}/outer/example-app/lib'),
      );

      expect(
        _canonical(root),
        _canonical(Directory('${tree.path}/outer/example-app')),
      );
    });

    test('f06/us01/fr01/e07: a pending journal marks the root when the '
        'context doc has moved and no config exists', () async {
      final tree = await writeTree({
        MoveJournal.journalPath: _journal,
        'docs/prds/PROJECT.md': '# Project\n',
        'docs/prds/sub/keep.txt': '',
      });

      final root = findMigrateRoot(Directory('${tree.path}/docs/prds/sub'));

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

      final root = findMigrateRoot(Directory('${tree.path}/acme'));

      expect(_canonical(root), _canonical(Directory('${tree.path}/acme-docs')));
    });
  });

  group('rootThroughDocsLink', () {
    test('f06/us01/fr01/e02: a dangling docs link leaves the folder as its '
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

    test(
      'f06/us01/fr01/e02: a folder without a docs link stays itself',
      () async {
        final tree = await writeTree({'docs/prds/d01_context.md': '# D-01\n'});

        expect(_canonical(rootThroughDocsLink(tree)), _canonical(tree));
      },
    );
  });
}
