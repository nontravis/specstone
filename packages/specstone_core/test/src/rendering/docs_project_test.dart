import 'dart:io';
import 'dart:typed_data';

import 'package:specstone_core/src/rendering/docs_project.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/fixture_doc_types.dart';
import '../../helpers/temp_tree.dart';

/// Shipped files that fail the test when `resolve` reads any of them.
final class _NeverRead implements Map<String, Uint8List> {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('resolve was called: ${invocation.memberName}');
}

TemplateResolver _templates() =>
    TemplateResolver(shippedFiles: fixturePackFiles());

DocsProject _open(Directory workingDirectory) => DocsProject.open(
  templates: _templates(),
  workingDirectory: workingDirectory,
  homeDirectory: null,
);

Directory _dir(Directory base, String relative) =>
    Directory.fromUri(base.uri.resolve(relative));

Matcher _renderFault(RenderFaultCode code, String message) => isA<RenderFault>()
    .having((fault) => fault.code, 'code', code)
    .having((fault) => fault.exitStatus, 'exitStatus', code.exitStatus)
    .having((fault) => fault.message, 'message', message);

void main() {
  group('DocsProject.open', () {
    test('f05/us01/fr01/e01, f05/us02/fr01/e03, s03/inv15: outside a project '
        'it refuses and never loads a pack', () async {
      final outside = await writeTree({'note.txt': 'x'});

      expect(
        () => DocsProject.open(
          templates: TemplateResolver(shippedFiles: _NeverRead()),
          workingDirectory: outside,
          homeDirectory: null,
        ),
        throwsA(
          _renderFault(
            RenderFaultCode.projectNotFound,
            'no Specstone project: no folder from the working directory '
            'upward holds .specstone/config.yaml',
          ),
        ),
      );
    });

    test('f05/us01/fr01, f05/us02/fr01: finds the project from a subfolder '
        'and takes docs/ as the docs root', () async {
      final root = await fixtureProject({'docs/prds/a.md': ''});

      final project = _open(_dir(root, 'docs/prds'));

      expect(project.projectRoot.path, root.resolveSymbolicLinksSync());
      expect(
        project.docsRoot.path,
        _dir(root, 'docs').resolveSymbolicLinksSync(),
      );
    });

    test('f05/us01/fr01/e05, f05/us02/fr01/e07: a template fault propagates '
        'with exit 78', () async {
      final root = await fixtureProject({
        '.specstone/config.yaml': 'packs:\n  prd-core: 9.9.9\n',
      });

      expect(
        () => _open(root),
        throwsA(
          isA<TemplateFault>().having(
            (fault) => fault.exitStatus,
            'exitStatus',
            78,
          ),
        ),
      );
    });

    test('f05/us01/fr01: a project without docs/ still opens', () async {
      final root = await fixtureProject({});

      final project = _open(root);

      expect(project.docsRoot.existsSync(), isFalse);
      expect(project.displayPath(project.docsRoot), 'docs');
    });
  });

  group('DocsProject.resolveTarget', () {
    test('f05/us01/fr01, f05/us01/fr01/e04: no target takes the docs root '
        'when the command defaults to it', () async {
      final root = await fixtureProject({'docs/prds/a.md': ''});
      final project = _open(root);

      final target = project.resolveTarget(
        null,
        workingDirectory: root,
        defaultsToDocsRoot: true,
      );

      expect(target.isDocsRoot, isTrue);
      expect(target.docPath, '');
      expect(target.entity.path, project.docsRoot.path);
    });

    test('f05/us01/fr01/e04: no target and no docs/ is target_not_found '
        'naming docs/', () async {
      final root = await fixtureProject({});
      final project = _open(root);

      expect(
        () => project.resolveTarget(
          null,
          workingDirectory: root,
          defaultsToDocsRoot: true,
        ),
        throwsA(
          _renderFault(
            RenderFaultCode.targetNotFound,
            'the target docs/ does not exist',
          ),
        ),
      );
    });

    test(
      'f05/us02/fr01/e02: no target without a default is target_missing',
      () async {
        final root = await fixtureProject({'docs/a.md': ''});
        final project = _open(root);

        expect(
          () => project.resolveTarget(
            null,
            workingDirectory: root,
            defaultsToDocsRoot: false,
          ),
          throwsA(
            _renderFault(
              RenderFaultCode.targetMissing,
              'no target given: name a file or folder under the docs root to '
              'build',
            ),
          ),
        );
      },
    );

    test('f05/us01/fr01/e02, f05/us02/fr01/e02: a target that does not exist '
        'is target_not_found', () async {
      final root = await fixtureProject({'docs/a.md': ''});
      final project = _open(root);

      expect(
        () => project.resolveTarget(
          'docs/missing.md',
          workingDirectory: root,
          defaultsToDocsRoot: false,
        ),
        throwsA(
          _renderFault(
            RenderFaultCode.targetNotFound,
            'the target docs/missing.md does not exist',
          ),
        ),
      );
    });

    test('f05/us01/fr01/e03, f05/us02/fr01/e02, s03/inv9: a target above the '
        'docs root is outside', () async {
      final root = await fixtureProject({'README.md': '', 'docs/a.md': ''});
      final project = _open(root);

      Object? thrown;
      try {
        project.resolveTarget(
          '../README.md',
          workingDirectory: _dir(root, 'docs'),
          defaultsToDocsRoot: false,
        );
      } on RenderFault catch (fault) {
        thrown = fault;
      }

      expect(
        thrown,
        _renderFault(
          RenderFaultCode.targetOutsideDocsRoot,
          'the target ../README.md lies outside the docs root docs/',
        ),
      );
      expect((thrown! as RenderFault).toJson(), {
        'error': {
          'code': 'target_outside_docs_root',
          'message': 'the target ../README.md lies outside the docs root docs/',
        },
      });
    });

    test('Review Focus 3: a path that leaves docs/ and returns, or climbs '
        'from the project root, is outside', () async {
      final root = await fixtureProject({
        'README.md': '',
        'docs/prds/a.md': '',
      });
      final project = _open(root);

      expect(
        () => project.resolveTarget(
          'docs/../README.md',
          workingDirectory: root,
          defaultsToDocsRoot: false,
        ),
        throwsA(
          _renderFault(
            RenderFaultCode.targetOutsideDocsRoot,
            'the target docs/../README.md lies outside the docs root docs/',
          ),
        ),
      );
    });

    test('Review Focus 3: a relative target resolves from the working '
        'directory', () async {
      final root = await fixtureProject({'docs/prds/a.md': ''});
      final project = _open(root);

      final target = project.resolveTarget(
        'prds',
        workingDirectory: _dir(root, 'docs'),
        defaultsToDocsRoot: false,
      );

      expect(target.docPath, 'prds');
      expect(target.isDocsRoot, isFalse);
      expect(target.entity, isA<Directory>());
    });

    test('Review Focus 3: a file target is a File and an absolute target '
        'works', () async {
      final root = await fixtureProject({'docs/prds/a.md': ''});
      final project = _open(root);

      final target = project.resolveTarget(
        File.fromUri(root.uri.resolve('docs/prds/a.md')).path,
        workingDirectory: Directory.systemTemp,
        defaultsToDocsRoot: false,
      );

      expect(target.entity, isA<File>());
      expect(target.docPath, 'prds/a.md');
    });

    test(
      'Review Focus 3: the docs root named as a target is the docs root',
      () async {
        final root = await fixtureProject({'docs/a.md': ''});
        final project = _open(root);

        final target = project.resolveTarget(
          'docs/',
          workingDirectory: root,
          defaultsToDocsRoot: false,
        );

        expect(target.isDocsRoot, isTrue);
        expect(target.docPath, '');
      },
    );

    test(
      'f05/us01/fr01: a sibling folder named like docs is outside',
      () async {
        final root = await fixtureProject({
          'docs/a.md': '',
          'docs-extra/b.md': '',
        });
        final project = _open(root);

        expect(
          () => project.resolveTarget(
            'docs-extra',
            workingDirectory: root,
            defaultsToDocsRoot: false,
          ),
          throwsA(
            _renderFault(
              RenderFaultCode.targetOutsideDocsRoot,
              'the target docs-extra lies outside the docs root docs/',
            ),
          ),
        );
      },
    );

    test(
      's03/inv9: a link inside docs/ that points outside is outside',
      () async {
        final root = await fixtureProject({'README.md': '', 'docs/a.md': ''});
        await Link.fromUri(root.uri.resolve('docs/out.md'))
            .create(File.fromUri(root.uri.resolve('README.md')).path);
        final project = _open(root);

        expect(
          () => project.resolveTarget(
            'docs/out.md',
            workingDirectory: root,
            defaultsToDocsRoot: false,
          ),
          throwsA(
            _renderFault(
              RenderFaultCode.targetOutsideDocsRoot,
              'the target docs/out.md lies outside the docs root docs/',
            ),
          ),
        );
      },
      skip: Platform.isWindows ? 'links need privileges on Windows' : false,
    );
  });

  group('symbolic links in the working directory', () {
    test('s03/inv9, R-INV-9: a target inside docs/ stays inside and one '
        'above stays outside when run through a link', () async {
      final root = await fixtureProject({
        'README.md': '',
        'docs/prds/a.md': '',
      });
      final holder = await Directory.systemTemp.createTemp('specstone_link_');
      addTearDown(() => holder.delete(recursive: true));
      final link = Link('${holder.path}/project');
      await link.create(root.path);
      final project = _open(_dir(Directory(link.path), 'docs'));
      final working = _dir(Directory(link.path), 'docs');

      final inside = project.resolveTarget(
        'prds',
        workingDirectory: working,
        defaultsToDocsRoot: false,
      );

      expect(inside.docPath, 'prds');
      expect(project.projectRoot.path, root.resolveSymbolicLinksSync());
      expect(
        () => project.resolveTarget(
          '../README.md',
          workingDirectory: working,
          defaultsToDocsRoot: false,
        ),
        throwsA(
          _renderFault(
            RenderFaultCode.targetOutsideDocsRoot,
            'the target ../README.md lies outside the docs root docs/',
          ),
        ),
      );
    }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);

    test('displayPath: relative to the project root through a link, for an '
        'entity that does not exist yet', () async {
      final root = await fixtureProject({'docs/a.md': ''});
      final holder = await Directory.systemTemp.createTemp('specstone_link_');
      addTearDown(() => holder.delete(recursive: true));
      final link = Link('${holder.path}/project');
      await link.create(root.path);
      final project = _open(Directory(link.path));

      expect(
        project.displayPath(File('${link.path}/.specstone/build/docs.html')),
        '.specstone/build/docs.html',
      );
    }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);
  });

  group('DocsProject.displayPath', () {
    test(
      'a path under the project root is relative with / separators',
      () async {
        final root = await fixtureProject({'docs/prds/a.md': ''});
        final project = _open(root);

        expect(
          project.displayPath(File.fromUri(root.uri.resolve('docs/prds/a.md'))),
          'docs/prds/a.md',
        );
        expect(
          project.displayPath(
            File.fromUri(root.uri.resolve('.specstone/build/docs.html')),
          ),
          '.specstone/build/docs.html',
        );
      },
    );

    test(
      'a path whose first segment is missing resolves without throwing',
      () async {
        final root = await fixtureProject({});
        final project = _open(root);

        expect(
          project.displayPath(File('/specstone_missing_out/docs.html')),
          '/specstone_missing_out/docs.html',
        );
      },
      skip: Platform.isWindows ? 'POSIX root path' : false,
    );

    test('a relative path whose every segment is missing is resolved from '
        'the current directory', () async {
      final root = await fixtureProject({});
      final project = _open(root);

      final sep = Platform.pathSeparator;
      final cwd = Directory.current.resolveSymbolicLinksSync();

      expect(
        project.displayPath(File('specstone_missing/none/docs.html')),
        '$cwd${sep}specstone_missing${sep}none${sep}docs.html',
      );
    });

    test('a path outside the project root is absolute', () async {
      final root = await fixtureProject({});
      final elsewhere = await writeTree({'x.html': ''});
      final project = _open(root);
      final output = File.fromUri(elsewhere.uri.resolve('x.html'));

      expect(project.displayPath(output), output.resolveSymbolicLinksSync());
    });
  });

  group('DocsProject.isInsideDocsRoot', () {
    test('a file that does not exist yet below docs/ is inside', () async {
      final root = await fixtureProject({'docs/a.md': ''});
      final project = _open(root);

      expect(
        project.isInsideDocsRoot(File.fromUri(root.uri.resolve('docs/x.html'))),
        isTrue,
      );
      expect(
        project.isInsideDocsRoot(
          File.fromUri(root.uri.resolve('docs/new/deep/x.html')),
        ),
        isTrue,
      );
    });

    test('the docs root itself is inside', () async {
      final root = await fixtureProject({'docs/a.md': ''});
      final project = _open(root);

      expect(project.isInsideDocsRoot(project.docsRoot), isTrue);
    });

    test('a path beside docs/, a sibling prefix, and a .. escape are '
        'outside', () async {
      final root = await fixtureProject({'docs/a.md': ''});
      final project = _open(root);

      for (final path in [
        'x.html',
        'docs2/x.html',
        '.specstone/build/docs.html',
        'docs/../x.html',
      ]) {
        expect(
          project.isInsideDocsRoot(File.fromUri(root.uri.resolve(path))),
          isFalse,
          reason: path,
        );
      }
    });

    test('a .. path that returns into docs/ is inside', () async {
      final root = await fixtureProject({'docs/a.md': ''});
      final project = _open(root);
      final path = '${root.path}/other/../docs/x.html';

      expect(project.isInsideDocsRoot(File(path)), isTrue);
    });

    test('a path through a symbolic link into docs/ is inside', () async {
      final root = await fixtureProject({'docs/a.md': ''});
      final holder = await Directory.systemTemp.createTemp('specstone_link_');
      addTearDown(() => holder.delete(recursive: true));
      final link = Link('${holder.path}/alias');
      await link.create('${root.path}/docs');
      final project = _open(root);

      expect(project.isInsideDocsRoot(File('${link.path}/x.html')), isTrue);
    }, skip: Platform.isWindows ? 'links need privileges on Windows' : false);
  });
}
