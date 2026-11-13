// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/code_bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/temp_tree.dart';

void main() {
  late Directory project;
  late ReadSession session;
  late DocIndex index;
  setUpAll(() async {
    project = await writeLoginProject(extra: loginRecords);
    session = openSession(project);
    addTearDown(session.close);
    index = session.index;
  });
  const f = 'prds/features/f01_login';
  const s = 'specs/f01_login';
  final specs = <String>{
    '$s/API.md',
    '$s/ARCHITECTURE.md',
    '$s/DOMAIN.md',
    '$s/ERROR.md',
    '$s/IMPLEMENTATION.md',
  };
  Bundle code(String p, BundleMode m, {bool noProject = false}) =>
      pickCodeBundle(
        index,
        resolveCodePath(
          p,
          workingDirectory: project,
          targets: session.project.targets,
          codeRootOf: session.project.codeRootOf,
        ),
        m,
        noProject: noProject,
      );

  test('f01/us05/s6, f01/us05/fr04/e01, s03/inv18: a file one FR names, in a covered folder', () async {
    expect(
      code(
        'app/lib/src/login/credential_validator.dart',
        BundleMode.implement,
      ).docPaths,
      {
        '$f/FEATURE.md',
        ...specs,
        '$f/us01_email_login/USER_STORY.md',
        '$f/us01_email_login/fr01_validate_credentials.md',
        '$f/us01_email_login/nf01_login_latency.md',
      },
    );
  });
  test(
    'f01/us05/fr04/e02: a folder matches every implements entry under it',
    () async {
      final b = code('app/lib/src/login', BundleMode.implement);
      expect(
        b.docPaths,
        containsAll([
          '$f/us01_email_login/fr01_validate_credentials.md',
          '$f/us01_email_login/USER_STORY.md',
        ]),
      );
    },
  );
  test('f01/us05/fr04/e03: a topic covers match with no trace gives the topic and the joined docs', () async {
    final b = code('app/lib/src/tokens/token_store.dart', BundleMode.implement);
    expect(b.docPaths, {'specs/topics/auth_tokens.md'});
    expect(b.joinedPaths, hasLength(3));
  });
  test('f01/us05/fr04/e04: matches in two features form one bundle', () async {
    final b = code('app/lib/src', BundleMode.implement);
    expect(
      b.docPaths,
      containsAll(['$f/FEATURE.md', 'prds/features/f02_signup/FEATURE.md']),
    );
  });
  test('f01/us05/fr04/e05: an architecture match with no trace gives feature, spec docs, and story names', () async {
    final b = code('app/lib/src/login/login_form.dart', BundleMode.implement);
    expect(b.docPaths, {'$f/FEATURE.md', ...specs});
    expect(b.nameListTops, {'$f/FEATURE.md'});
  });
  test('f01/us05/s7, f01/us05/fr04/e06: no match gives the joined docs and the warning', () async {
    final b = code('app/lib/main.dart', BundleMode.implement);
    expect(b.docPaths, isEmpty);
    expect(b.joinedPaths, hasLength(3));
    expect(b.warnings, ['no doc covers or implements app/lib/main.dart']);
  });
  test('f01/us05/fr04/e08: a path that does not exist is code_path_not_found naming it', () async {
    expect(
      () => code('app/lib/nope.dart', BundleMode.implement),
      throwsA(
        isA<IndexFault>()
            .having((x) => x.code, 'code', IndexFaultCode.codePathNotFound)
            .having(
              (x) => x.message,
              'message',
              'the code path app/lib/nope.dart does not exist',
            ),
      ),
    );
  });
  test('code_root: resolveCodePath counts paths from the code root, not the project root', () async {
    final workspace = await writeTree({
      'ws/code/lib/a.dart': '',
      'ws/docs/x.md': '',
    });
    final codeRoot = Directory(
      Directory.fromUri(workspace.uri.resolve('ws/code'))
          .resolveSymbolicLinksSync(),
    );
    final separator = Platform.pathSeparator;

    final inside = resolveCodePath(
      '${codeRoot.path}${separator}lib${separator}a.dart',
      workingDirectory: workspace,
      targets: const [CodeTarget('code', codeRoot: 'ws/code')],
      codeRootOf: (_) => codeRoot,
    );

    expect(inside.path, 'lib/a.dart');
    expect(inside.isFolder, isFalse);
    expect(
      () => resolveCodePath(
        '${codeRoot.parent.path}${separator}docs${separator}x.md',
        workingDirectory: workspace,
        targets: const [CodeTarget('code', codeRoot: 'ws/code')],
        codeRootOf: (_) => codeRoot,
      ),
      throwsA(
        isA<IndexFault>()
            .having(
              (x) => x.code,
              'code',
              IndexFaultCode.codePathOutsideProject,
            )
            .having(
              (x) => x.message,
              'message',
              endsWith('lies outside the code root'),
            ),
      ),
    );
  });
  test('f01/us05/s12, f01/us05/fr04/e09: a path outside the code root is code_path_outside_project', () async {
    expect(
      () => code('../', BundleMode.implement),
      throwsA(
        isA<IndexFault>()
            .having(
              (x) => x.code,
              'code',
              IndexFaultCode.codePathOutsideProject,
            )
            .having(
              (x) => x.message,
              'message',
              'the code path ../ lies outside the code root',
            ),
      ),
    );
  });
  test('f01/us05/fr04/e10, s03/inv3: a .dbml path is matched by pointer values only, never read', () async {
    expect(code('docs/specs/schema.dbml', BundleMode.implement).warnings, [
      'no doc covers or implements docs/specs/schema.dbml',
    ]);
  });
  test('f01/us05/fr04/e11: --no-project with no match holds no doc and still warns', () async {
    final b = code('app/lib/main.dart', BundleMode.implement, noProject: true);
    expect(b.docPaths, isEmpty);
    expect(b.joinedPaths, isEmpty);
    expect(b.warnings, hasLength(1));
  });
  test("f01/us05/fr04: query gives the matched feature's map; design its whole subtree", () async {
    expect(
      code(
        'app/lib/src/login/credential_validator.dart',
        BundleMode.query,
      ).mapTops,
      {'$f/FEATURE.md'},
    );
    expect(
      code(
        'app/lib/src/login/credential_validator.dart',
        BundleMode.design,
      ).docPaths,
      {for (final d in index.subtreeOf(index.at('$f/FEATURE.md')!)) d.docPath},
    );
  });
  test(
    'review focus 4: a code path given through a symbolic link to the project resolves inside it',
    skip: Platform.isWindows ? 'links need privileges on Windows' : null,
    () async {
      final linkParent = await writeTree({});
      Link('${linkParent.path}/proj').createSync(project.path);
      final code = resolveCodePath(
        'app/lib/main.dart',
        workingDirectory: Directory('${linkParent.path}/proj'),
        targets: session.project.targets,
        codeRootOf: session.project.codeRootOf,
      );
      expect(code.path, 'app/lib/main.dart');
      expect(code.isFolder, isFalse);
    },
  );

  group('f01/us05/fr04, two targets', () {
    /// The two-target fixture of E13: the feature `feedback` and its story
    /// `show`, per-target architecture, record, and tech-stack docs, with the
    /// code roots `flutter_lib` and `jaspr_lib`.
    Future<(ReadSession, Directory)> writeFeedbackProject({
      Map<String, String> extra = const {},
    }) async {
      final root = await writeTree({
        '.specstone/templates/architecture.yaml':
            'id: architecture\nper_target: true\n',
        '.specstone/templates/implementation.yaml':
            'id: implementation\n'
            'description: One feature record per target.\n'
            'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
            'parent: feature\n'
            'per_target: true\n'
            'fields:\n'
            '  - id: statuses\n'
            '    type: record_status\n'
            '    list: true\n'
            '  - id: implements\n'
            '    type: output_ref\n'
            '    list: true\n'
            '    pointer: item_exact\n',
        '.specstone/templates/tech_stack.yaml':
            'id: tech_stack\nper_target: true\n',
        '.specstone/config.yaml':
            'packs:\n'
            '  prd-core: ${shippedPackVersions()['prd-core']}\n'
            '  software-tech: ${shippedPackVersions()['software-tech']}\n'
            'targets:\n'
            '  flutter:\n    code_root: flutter_lib\n'
            '  jaspr:\n    code_root: jaspr_lib\n',
        'flutter_lib/.keep': '',
        'jaspr_lib/.keep': '',
        'docs/prds/features/f02_feedback/FEATURE.md': '# Feedback\n',
        'docs/prds/features/f02_feedback/f03_toast/FEATURE.md': '# Toast\n',
        'docs/prds/features/f02_feedback/f03_toast/us01_show/USER_STORY.md':
            '# Agent sees a toast\n',
        'docs/specs/flutter/f02_feedback/f03_toast/ARCHITECTURE.md':
            '---\ncovers:\n  - lib/\n---\n\n# Toast architecture\n',
        'docs/specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md':
            '---\ncovers:\n  - lib/\n---\n\n# Toast architecture\n',
        'docs/specs/flutter/TECH_STACK.md': '# Toast stack\n',
        'docs/specs/jaspr/TECH_STACK.md': '# Toast stack\n',
        'docs/specs/flutter/f02_feedback/IMPLEMENTATION.md':
            '---\nstatuses:\n'
            '  - toast/show:implemented\n'
            'implements:\n'
            '  - toast/show:lib/toast.dart:showToast\n'
            '---\n\n# Record\n',
        'docs/specs/jaspr/f02_feedback/IMPLEMENTATION.md':
            '---\nstatuses:\n'
            '  - toast/show:implemented\n'
            'implements:\n'
            '  - toast/show:lib/toast.dart:showToast\n'
            '---\n\n# Record\n',
        ...extra,
      });
      final session = openSession(root);
      addTearDown(session.close);
      return (session, root);
    }

    test(
      'f01/us05/fr04/e13: a path under one code root picks that target alone',
      () async {
        final (session, root) = await writeFeedbackProject(
          extra: {'jaspr_lib/lib/toast.dart': ''},
        );
        final codePath = resolveCodePath(
          'jaspr_lib/lib/toast.dart',
          workingDirectory: root,
          targets: session.project.targets,
          codeRootOf: session.project.codeRootOf,
        );
        expect(codePath.target.name, 'jaspr');
        expect(codePath.path, 'lib/toast.dart');
        final bundle = pickCodeBundle(
          session.index,
          codePath,
          BundleMode.implement,
          noProject: false,
        );
        expect(bundle.docPaths, {
          'prds/features/f02_feedback/FEATURE.md',
          'prds/features/f02_feedback/f03_toast/FEATURE.md',
          'prds/features/f02_feedback/f03_toast/us01_show/USER_STORY.md',
          'specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md',
          'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
        });
        expect(bundle.joinedPaths, {'specs/jaspr/TECH_STACK.md'});
      },
    );

    test('f01/us05/fr04/e14, review focus 2: nested roots pick the longest that holds the path', () async {
      final root = await writeTree({
        '.specstone/templates/implementation.yaml':
            'id: implementation\n'
            'description: One feature record per target.\n'
            'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
            'parent: feature\n'
            'per_target: true\n'
            'fields:\n'
            '  - id: statuses\n'
            '    type: record_status\n'
            '    list: true\n',
        '.specstone/config.yaml':
            'packs:\n'
            '  prd-core: ${shippedPackVersions()['prd-core']}\n'
            'targets:\n'
            '  app:\n    code_root: .\n'
            '  web:\n    code_root: packages/web\n',
        'lib/main.dart': '',
        'packages/web/lib/main.dart': '',
      });
      const targets = [
        CodeTarget('app', codeRoot: '.'),
        CodeTarget('web', codeRoot: 'packages/web'),
      ];
      final projectRoot = Directory(canonicalPath(root.path));
      CodePath resolve(String given) => resolveCodePath(
        given,
        workingDirectory: root,
        targets: targets,
        codeRootOf: (target) => Directory(
          canonicalPath(
            '${projectRoot.path}/'
            '${target.codeRoot == '.' ? '' : target.codeRoot}',
          ),
        ),
      );
      expect(resolve('packages/web/lib/main.dart').target.name, 'web');
      expect(resolve('packages/web/lib/main.dart').path, 'lib/main.dart');
      expect(resolve('lib/main.dart').target.name, 'app');
    });

    test('f01/us05/fr04 traced docs: a stale implements line with no record entry traces nothing', () async {
      final (session, root) = await writeFeedbackProject(
        extra: {
          'jaspr_lib/lib/toast.dart': '',
          'docs/prds/features/f02_feedback/f03_toast/us02_hide/USER_STORY.md':
              '---\nimplements:\n'
              '  - lib/toast.dart:hideToast\n---\n\n# Agent hides a toast\n',
        },
      );
      final bundle = pickCodeBundle(
        session.index,
        resolveCodePath(
          'jaspr_lib/lib/toast.dart',
          workingDirectory: root,
          targets: session.project.targets,
          codeRootOf: session.project.codeRootOf,
        ),
        BundleMode.implement,
        noProject: false,
      );
      expect(
        bundle.docPaths,
        isNot(
          contains(
            'prds/features/f02_feedback/f03_toast/us02_hide/USER_STORY.md',
          ),
        ),
      );
    });
  });
}
