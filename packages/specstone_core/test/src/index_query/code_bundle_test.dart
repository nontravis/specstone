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
import '../../helpers/shipped_pins.dart';
import '../../helpers/skill_doc_fixture.dart';
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
    '.specstone/records/f01_login/IMPLEMENTATION.md',
  };
  Bundle code(String p, BundleMode m, {bool noProject = false}) =>
      pickCodeBundle(
        index,
        resolveCodePath(
          p,
          workingDirectory: project,
          targets: session.project.targets,
          codeRootOf: session.project.codeRootOf,
          projectRoot: session.project.projectRoot,
          reachedFromProjectRoot: (_) => false,
        ),
        m,
        noProject: noProject,
      );

  test('a file one FR names, in a covered folder', () async {
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
  test('a covers entry and an implements line that carry a fingerprint pick the same spec and traced docs', () async {
    final project = await writeLoginProject(
      extra: {
        'docs/specs/f01_login/ARCHITECTURE.md':
            '---\ncovers:\n  - app/lib/src/login/ 0123456789ab\n---\n\n'
            '# Login architecture\n\n'
            '## Components\n| Component | Responsibility |\n|---|---|\n'
            '| Login form | Collects the email |\n',
        '.specstone/records/f01_login/IMPLEMENTATION.md':
            "---\nstatuses:\n  - 'email_login/validate_credentials:implemented'\n"
            'implements:\n'
            "  - 'email_login/validate_credentials:app/lib/src/login/credential_validator.dart 0123456789ab'\n"
            '---\n\n# Login implementation\n',
      },
    );
    final session = openSession(project);
    addTearDown(session.close);
    Bundle at(String p) => pickCodeBundle(
      session.index,
      resolveCodePath(
        p,
        workingDirectory: project,
        targets: session.project.targets,
        codeRootOf: session.project.codeRootOf,
        projectRoot: session.project.projectRoot,
        reachedFromProjectRoot: (_) => false,
      ),
      BundleMode.implement,
      noProject: false,
    );

    expect(at('app/lib/src/login/credential_validator.dart').docPaths, {
      '$f/FEATURE.md',
      ...specs,
      '$f/us01_email_login/USER_STORY.md',
      '$f/us01_email_login/fr01_validate_credentials.md',
      '$f/us01_email_login/nf01_login_latency.md',
    });
    expect(at('app/lib/src/login/login_form.dart').docPaths, {
      '$f/FEATURE.md',
      ...specs,
    });
  });
  test('with no record doc type, a story implements line that carries a fingerprint traces its file', () async {
    final project = await writeLoginProject(
      extra: {
        '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
        'docs/prds/features/f01_login/us01_email_login/USER_STORY.md':
            '---\nimplements:\n'
            '  - app/lib/src/login/credential_validator.dart 0123456789ab\n'
            '---\n\n# Agent signs in with email\n\n## Use Case\nSign in.\n',
      },
    );
    final session = openSession(project);
    addTearDown(session.close);
    expect(session.index.set.recordDocType, isNull);

    final bundle = pickCodeBundle(
      session.index,
      resolveCodePath(
        'app/lib/src/login/credential_validator.dart',
        workingDirectory: project,
        targets: session.project.targets,
        codeRootOf: session.project.codeRootOf,
        projectRoot: session.project.projectRoot,
        reachedFromProjectRoot: (_) => false,
      ),
      BundleMode.implement,
      noProject: false,
    );

    expect(bundle.docPaths, contains('$f/us01_email_login/USER_STORY.md'));
  });
  test('a folder matches every implements entry under it', () async {
    final b = code('app/lib/src/login', BundleMode.implement);
    expect(
      b.docPaths,
      containsAll([
        '$f/us01_email_login/fr01_validate_credentials.md',
        '$f/us01_email_login/USER_STORY.md',
      ]),
    );
  });
  test('a tests path '
      'matches as a pointer value, its name aside', () async {
    final project = await writeLoginProject(
      extra: {
        'app/lib/schema.dbml': '',
        'app/test/auth_test.dart': '',
        '.specstone/records/f01_login/IMPLEMENTATION.md':
            '---\nstatuses:\n'
            "  - 'email_login/validate_credentials:implemented'\n"
            "  - 'email_login/lock_after_failures:planned'\n"
            'implements:\n'
            "  - 'email_login:app/lib/src/login/sign_in_page.dart:SignInPage'\n"
            'tests:\n'
            "  - 'email_login/validate_credentials:app/lib/schema.dbml:rejects'\n"
            "  - 'email_login/lock_after_failures:app/test/auth_test.dart:locks: after 5'\n"
            '---\n\n# Login implementation\n',
      },
    );
    final session = openSession(project);
    addTearDown(session.close);
    Bundle at(String p) => pickCodeBundle(
      session.index,
      resolveCodePath(
        p,
        workingDirectory: project,
        targets: session.project.targets,
        codeRootOf: session.project.codeRootOf,
        projectRoot: session.project.projectRoot,
        reachedFromProjectRoot: (_) => false,
      ),
      BundleMode.implement,
      noProject: false,
    );
    expect(at('app/lib/schema.dbml').docPaths, {
      '$f/FEATURE.md',
      ...specs,
      '$f/us01_email_login/USER_STORY.md',
      '$f/us01_email_login/fr01_validate_credentials.md',
      '$f/us01_email_login/nf01_login_latency.md',
    });
    expect(at('app/test/auth_test.dart').docPaths, {
      '$f/us01_email_login/USER_STORY.md',
      '$f/us01_email_login/fr02_lock_after_failures.md',
      '$f/us01_email_login/nf01_login_latency.md',
      '$f/FEATURE.md',
      ...specs,
    });
    expect(at('app/test').docPaths, {
      '$f/us01_email_login/USER_STORY.md',
      '$f/us01_email_login/fr02_lock_after_failures.md',
      '$f/us01_email_login/nf01_login_latency.md',
      '$f/FEATURE.md',
      ...specs,
    });
  });
  test(
    'a topic covers match with no trace gives the topic and the joined docs',
    () async {
      final b = code(
        'app/lib/src/tokens/token_store.dart',
        BundleMode.implement,
      );
      expect(b.docPaths, {'specs/topics/auth_tokens.md'});
      expect(b.joinedPaths, hasLength(3));
    },
  );
  test('matches in two features form one bundle', () async {
    final b = code('app/lib/src', BundleMode.implement);
    expect(
      b.docPaths,
      containsAll(['$f/FEATURE.md', 'prds/features/f02_signup/FEATURE.md']),
    );
  });
  test('two features matched by one folder print in tree order', () async {
    final b = code('app/lib/src', BundleMode.implement);
    final printed = [for (final doc in b.printOrder(index)) doc.docPath];
    for (final (login, signup) in [
      ('$f/FEATURE.md', 'prds/features/f02_signup/FEATURE.md'),
      ('$s/ARCHITECTURE.md', 'specs/f02_signup/ARCHITECTURE.md'),
      (
        '.specstone/records/f01_login/IMPLEMENTATION.md',
        '.specstone/records/f02_signup/IMPLEMENTATION.md',
      ),
    ]) {
      expect(printed, contains(login));
      expect(printed, contains(signup));
      expect(printed.indexOf(login), lessThan(printed.indexOf(signup)));
    }
  });
  test('an architecture match with no trace gives feature, spec docs, and story names', () async {
    final b = code('app/lib/src/login/login_form.dart', BundleMode.implement);
    expect(b.docPaths, {'$f/FEATURE.md', ...specs});
    expect(b.nameListTops, {'$f/FEATURE.md'});
  });
  test('no match gives the joined docs and the warning', () async {
    final b = code('app/lib/main.dart', BundleMode.implement);
    expect(b.docPaths, isEmpty);
    expect(b.joinedPaths, hasLength(3));
    expect(b.warnings, ['no doc covers or implements app/lib/main.dart']);
  });
  test('an uncovered path still gets the root spec docs', () async {
    final project = await writeLoginProject(
      extra: {'docs/specs/DOMAIN.md': '# Project domain\n'},
    );
    final session = openSession(project);
    addTearDown(session.close);
    final b = pickCodeBundle(
      session.index,
      resolveCodePath(
        'app/lib/main.dart',
        workingDirectory: project,
        targets: session.project.targets,
        codeRootOf: session.project.codeRootOf,
        projectRoot: session.project.projectRoot,
        reachedFromProjectRoot: (_) => false,
      ),
      BundleMode.implement,
      noProject: false,
    );

    expect(b.docPaths, isEmpty);
    expect(b.joinedPaths, {
      'prds/GNFR.md',
      'prds/PROJECT.md',
      'specs/TECH_STACK.md',
      'specs/DOMAIN.md',
    });
    expect(b.warnings, ['no doc covers or implements app/lib/main.dart']);
  });
  test('a path that does not exist is code_path_not_found naming it', () async {
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
      projectRoot: workspace,
      reachedFromProjectRoot: (_) => false,
    );

    expect(inside.path, 'lib/a.dart');
    expect(inside.isFolder, isFalse);
    expect(
      () => resolveCodePath(
        '${codeRoot.parent.path}${separator}docs${separator}x.md',
        workingDirectory: workspace,
        targets: const [CodeTarget('code', codeRoot: 'ws/code')],
        codeRootOf: (_) => codeRoot,
        projectRoot: workspace,
        reachedFromProjectRoot: (_) => false,
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
  test('a code root beside the project holds its own path, and the project docs folder is outside', () async {
    final workspace = await writeTree({
      'proj/docs/x.md': '',
      'stratum_ui/example/lib/a.dart': '',
    });
    final proj = Directory(
      Directory.fromUri(workspace.uri.resolve('proj'))
          .resolveSymbolicLinksSync(),
    );
    final codeRoot = Directory(
      Directory.fromUri(workspace.uri.resolve('stratum_ui/example'))
          .resolveSymbolicLinksSync(),
    );
    const targets = [CodeTarget('example', codeRoot: '../stratum_ui/example')];
    final separator = Platform.pathSeparator;

    final inside = resolveCodePath(
      '..${separator}stratum_ui${separator}example${separator}lib${separator}a.dart',
      workingDirectory: proj,
      targets: targets,
      codeRootOf: (_) => codeRoot,
      projectRoot: proj,
      reachedFromProjectRoot: (_) => false,
    );

    expect(inside.path, 'lib/a.dart');
    expect(
      () => resolveCodePath(
        'docs${separator}x.md',
        workingDirectory: proj,
        targets: targets,
        codeRootOf: (_) => codeRoot,
        projectRoot: proj,
        reachedFromProjectRoot: (_) => false,
      ),
      throwsA(
        isA<IndexFault>()
            .having(
              (x) => x.code,
              'code',
              IndexFaultCode.codePathOutsideProject,
            )
            .having((x) => x.exitStatus, 'exit', 64)
            .having(
              (x) => x.message,
              'message',
              'the code path docs${separator}x.md lies outside the code root',
            ),
      ),
    );
  });
  test('a path outside the code root is code_path_outside_project', () async {
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
  test('a .dbml path is matched by pointer values only, never read', () async {
    expect(code('docs/specs/schema.dbml', BundleMode.implement).warnings, [
      'no doc covers or implements docs/specs/schema.dbml',
    ]);
  });
  test(
    'a .dbml file whose own text names a doc or a path still matches nothing',
    () async {
      const schema = 'docs/specs/schema.dbml';
      final project = await writeLoginProject(
        extra: {
          schema:
              'Table accounts {}\n'
              '// covers: app/lib/main.dart\n'
              '// implements: email_login/validate_credentials:app/lib/main.dart\n'
              '// see prds/features/f01_login/FEATURE.md\n',
        },
      );
      final session = openSession(project);
      addTearDown(session.close);
      Bundle at(String path) => pickCodeBundle(
        session.index,
        resolveCodePath(
          path,
          workingDirectory: project,
          targets: session.project.targets,
          codeRootOf: session.project.codeRootOf,
          projectRoot: session.project.projectRoot,
          reachedFromProjectRoot: (_) => false,
        ),
        BundleMode.implement,
        noProject: false,
      );

      for (final path in [schema, 'app/lib/main.dart']) {
        final bundle = at(path);
        expect(bundle.docPaths, isEmpty, reason: path);
        expect(bundle.warnings, ['no doc covers or implements $path']);
      }
    },
  );
  test('--no-project with no match holds no doc and still warns', () async {
    final b = code('app/lib/main.dart', BundleMode.implement, noProject: true);
    expect(b.docPaths, isEmpty);
    expect(b.joinedPaths, isEmpty);
    expect(b.warnings, hasLength(1));
  });
  test(
    "query gives the matched feature's map; design its whole subtree",
    () async {
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
        {
          for (final d in index.subtreeOf(index.at('$f/FEATURE.md')!))
            d.docPath,
        },
      );
    },
  );
  test(
    'a code path given through a symbolic link to the project resolves inside it',
    skip: Platform.isWindows ? 'links need privileges on Windows' : null,
    () async {
      final linkParent = await writeTree({});
      Link('${linkParent.path}/proj').createSync(project.path);
      final code = resolveCodePath(
        'app/lib/main.dart',
        workingDirectory: Directory('${linkParent.path}/proj'),
        targets: session.project.targets,
        codeRootOf: session.project.codeRootOf,
        projectRoot: session.project.projectRoot,
        reachedFromProjectRoot: (_) => false,
      );
      expect(code.path, 'app/lib/main.dart');
      expect(code.isFolder, isFalse);
    },
  );

  group('two targets', () {
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
            'path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md\n'
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
        '.specstone/records/flutter/f02_feedback/f03_toast/IMPLEMENTATION.md':
            '---\nstatuses:\n'
            '  - show:implemented\n'
            'implements:\n'
            '  - show:lib/toast.dart:showToast\n'
            '---\n\n# Record\n',
        '.specstone/records/jaspr/f02_feedback/f03_toast/IMPLEMENTATION.md':
            '---\nstatuses:\n'
            '  - show:implemented\n'
            'implements:\n'
            '  - show:lib/toast.dart:showToast\n'
            '---\n\n# Record\n',
        ...extra,
      });
      final session = openSession(root);
      addTearDown(session.close);
      return (session, root);
    }

    test('a path under one code root picks that target alone', () async {
      final (session, root) = await writeFeedbackProject(
        extra: {'jaspr_lib/lib/toast.dart': ''},
      );
      final codePath = resolveCodePath(
        'jaspr_lib/lib/toast.dart',
        workingDirectory: root,
        targets: session.project.targets,
        codeRootOf: session.project.codeRootOf,
        projectRoot: session.project.projectRoot,
        reachedFromProjectRoot: (_) => false,
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
        '.specstone/records/jaspr/f02_feedback/f03_toast/IMPLEMENTATION.md',
      });
      expect(bundle.joinedPaths, {'specs/jaspr/TECH_STACK.md'});
    });

    test("a root spec doc never matches a code path and joins only that path's target", () async {
      final (session, root) = await writeFeedbackProject(
        extra: {
          'jaspr_lib/lib/toast.dart': '',
          'docs/specs/flutter/DOMAIN.md': '# Flutter domain\n',
          'docs/specs/jaspr/DOMAIN.md': '# Jaspr domain\n',
        },
      );
      final bundle = pickCodeBundle(
        session.index,
        resolveCodePath(
          'jaspr_lib/lib/toast.dart',
          workingDirectory: root,
          targets: session.project.targets,
          codeRootOf: session.project.codeRootOf,
          projectRoot: session.project.projectRoot,
          reachedFromProjectRoot: (_) => false,
        ),
        BundleMode.implement,
        noProject: false,
      );
      expect(bundle.docPaths, {
        'prds/features/f02_feedback/FEATURE.md',
        'prds/features/f02_feedback/f03_toast/FEATURE.md',
        'prds/features/f02_feedback/f03_toast/us01_show/USER_STORY.md',
        'specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md',
        '.specstone/records/jaspr/f02_feedback/f03_toast/IMPLEMENTATION.md',
      });
      expect(bundle.joinedPaths, {
        'specs/jaspr/TECH_STACK.md',
        'specs/jaspr/DOMAIN.md',
      });
    });

    test("a shared doc's covers count for no target, so the target's own architecture is the spec match", () async {
      final (session, root) = await writeFeedbackProject(
        extra: {
          'jaspr_lib/lib/toast.dart': '',
          '.specstone/templates/topic.yaml': 'id: topic\nper_target: false\n',
          'docs/specs/topics/toast_rules.md':
              '---\ncovers:\n  - lib/toast.dart\n---\n\n# Toast rules\n',
        },
      );
      final bundle = pickCodeBundle(
        session.index,
        resolveCodePath(
          'jaspr_lib/lib/toast.dart',
          workingDirectory: root,
          targets: session.project.targets,
          codeRootOf: session.project.codeRootOf,
          projectRoot: session.project.projectRoot,
          reachedFromProjectRoot: (_) => false,
        ),
        BundleMode.implement,
        noProject: false,
      );
      expect(
        bundle.docPaths,
        contains('specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md'),
      );
      expect(bundle.docPaths, isNot(contains('specs/topics/toast_rules.md')));
    });

    test('nested roots pick the longest that holds the path', () async {
      final root = await writeTree({
        '.specstone/templates/implementation.yaml':
            'id: implementation\n'
            'description: One feature record per target.\n'
            'path: .specstone/records/f{nn}_{slug}/IMPLEMENTATION.md\n'
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
        projectRoot: projectRoot,
        reachedFromProjectRoot: (_) => false,
      );
      expect(resolve('packages/web/lib/main.dart').target.name, 'web');
      expect(resolve('packages/web/lib/main.dart').path, 'lib/main.dart');
      expect(resolve('lib/main.dart').target.name, 'app');
    });

    test('traced docs: a stale implements line with no record entry traces nothing', () async {
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
          projectRoot: session.project.projectRoot,
          reachedFromProjectRoot: (_) => false,
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
  group('a skill doc whose covers entry reads from the project root', () {
    /// Opens the login project pinned to `agent-skills`, its code root
    /// [codeRoot] when given, over the [files].
    Future<_SkillProject> openSkillProject({
      String? codeRoot,
      Map<String, String> files = const {},
    }) async {
      final root = await writeLoginProject(
        extra: {
          '.specstone/config.yaml':
              '${skillPinsConfig()}${codeRoot == null ? '' : 'code_root: $codeRoot\n'}',
          ...files,
          if (codeRoot != null) '$codeRoot/keep.txt': '',
        },
      );
      final opened = openSession(root);
      addTearDown(opened.close);
      return _SkillProject(opened, root);
    }

    final reviewFolder = {
      ...skillDocFile(['.claude/skills/review/']),
      skillFile: skillText,
    };

    test("a skill doc covering the path's folder is bundled", () async {
      final project = await openSkillProject(files: reviewFolder);

      final bundle = project.pick(skillFile);

      expect(bundle.docPaths, contains(skillDoc));
      expect(bundle.warnings, isEmpty);
    });
    test('a path outside every code root that a skill doc reaches falls back to the first listed target', () async {
      final project = await openSkillProject(
        codeRoot: 'specstone',
        files: reviewFolder,
      );

      final code = project.resolve(skillFile);
      final bundle = project.pick(skillFile);

      expect(code.path, isNull);
      expect(code.projectPath, skillFile);
      expect(code.target, project.session.project.targets.first);
      expect(bundle.docPaths, contains(skillDoc));
      expect(bundle.warnings, isEmpty);
    });
    test('a path outside every code root that nothing reaches still refuses', () async {
      final project = await openSkillProject(
        codeRoot: 'specstone',
        files: reviewFolder,
      );

      expect(
        () => project.pick('docs/prds/PROJECT.md'),
        throwsA(
          isA<IndexFault>()
              .having(
                (x) => x.code,
                'code',
                IndexFaultCode.codePathOutsideProject,
              )
              .having((x) => x.exitStatus, 'exit', 64)
              .having(
                (x) => x.message,
                'message',
                'the code path docs/prds/PROJECT.md lies outside the code root',
              ),
        ),
      );
    });
    test('a path outside every code root that only an empty entry reaches '
        'refuses', () async {
      for (final form in ['./', '.', '/', 'lib/..', './lib/../']) {
        final project = await openSkillProject(
          codeRoot: 'specstone',
          files: {
            ...skillDocFile([form]),
            skillFile: skillText,
          },
        );

        expect(
          () => project.pick(skillFile),
          throwsA(
            isA<IndexFault>()
                .having(
                  (x) => x.code,
                  'code',
                  IndexFaultCode.codePathOutsideProject,
                )
                .having((x) => x.exitStatus, 'exit', 64),
          ),
          reason: form,
        );
      }
    });
    test('a code root file reached by an architecture doc and a skill doc bundles both', () async {
      final project = await openSkillProject(
        files: {
          ...skillDocFile(['app/lib/src/login/']),
          skillFile: skillText,
        },
      );

      final bundle = project.pick(
        'app/lib/src/login/credential_validator.dart',
      );

      expect(bundle.docPaths, contains(skillDoc));
      expect(bundle.docPaths, contains('specs/f01_login/ARCHITECTURE.md'));
    });
    test('the longest project-root entry wins', () async {
      final project = await openSkillProject(
        files: {
          ...skillDocFile(['.claude/skills/']),
          ...agentDocFile(['.claude/skills/review/']),
          skillFile: skillText,
        },
      );

      final bundle = project.pick(skillFile);

      expect(bundle.docPaths, contains(agentDoc));
      expect(bundle.docPaths, isNot(contains(skillDoc)));
    });
    test('a skill doc that names a feature brings that feature doc', () async {
      final skill = skillDocFile(['.claude/skills/review/']);
      final agent = agentDocFile(['.claude/skills/review/']);
      final project = await openSkillProject(
        files: {
          'docs/$skillDoc': skill['docs/$skillDoc']!.replaceFirst(
            'covers:',
            'feature: login\ncovers:',
          ),
          'docs/$agentDoc': agent['docs/$agentDoc']!.replaceFirst(
            'covers:',
            'feature: login\ncovers:',
          ),
          skillFile: skillText,
        },
      );

      for (final mode in BundleMode.values) {
        final bundle = project.pick(skillFile, mode: mode);

        expect(
          bundle.docPaths,
          containsAll([skillDoc, agentDoc, featureDoc]),
          reason: '$mode',
        );
      }
    });
    test(
      'a skill doc owned by another target is bundled for the first target',
      () async {
        final skill = skillDocFile(['.claude/skills/review/']);
        final root = await writeLoginProject(
          extra: {
            '.specstone/config.yaml':
                '${skillPinsConfig()}targets:\n'
                '  flutter:\n    code_root: flutter_lib\n'
                '  jaspr:\n    code_root: jaspr_lib\n',
            '.specstone/templates/skill.yaml': 'id: skill\nper_target: true\n',
            'docs/specs/jaspr/skills/review.md': skill['docs/$skillDoc']!,
            skillFile: skillText,
            'flutter_lib/.keep': '',
            'jaspr_lib/.keep': '',
          },
        );
        final opened = openSession(root);
        addTearDown(opened.close);
        final project = _SkillProject(opened, root);

        final bundle = project.pick(skillFile);

        expect(project.resolve(skillFile).target.name, 'flutter');
        expect(bundle.docPaths, contains('specs/jaspr/skills/review.md'));
        expect(bundle.warnings, isEmpty);
      },
    );
    test('a project-root entry needs whole segments to match', () async {
      final project = await openSkillProject(
        files: {
          ...skillDocFile(['.claude/skills/rev']),
          skillFile: skillText,
        },
      );

      final bundle = project.pick(skillFile);

      expect(bundle.docPaths, isNot(contains(skillDoc)));
      expect(bundle.warnings, ['no doc covers or implements $skillFile']);
    });
    test('a code root outside the project root is never reached by a project-root entry', () async {
      final workspace = await writeTree({
        'proj/docs/x.md': '',
        'other.md': '',
        'stratum/example/lib/a.dart': '',
      });
      final proj = Directory(
        Directory.fromUri(workspace.uri.resolve('proj'))
            .resolveSymbolicLinksSync(),
      );
      final codeRoot = Directory(
        Directory.fromUri(workspace.uri.resolve('stratum/example'))
            .resolveSymbolicLinksSync(),
      );
      CodePath resolve(String given) => resolveCodePath(
        given,
        workingDirectory: proj,
        targets: const [CodeTarget('example', codeRoot: '../stratum/example')],
        codeRootOf: (_) => codeRoot,
        projectRoot: proj,
        reachedFromProjectRoot: (_) => true,
      );

      final inside = resolve('../stratum/example/lib/a.dart');

      expect(inside.path, 'lib/a.dart');
      expect(inside.projectPath, isNull);
      expect(
        () => resolve('../other.md'),
        throwsA(
          isA<IndexFault>().having(
            (x) => x.code,
            'code',
            IndexFaultCode.codePathOutsideProject,
          ),
        ),
      );
    });
  });
}

/// The login project pinned to `agent-skills`, with its open session.
final class _SkillProject {
  const new(this.session, this.root);

  final ReadSession session;
  final Directory root;

  /// Resolves [given] as `context --code` does.
  CodePath resolve(String given) => resolveCodePath(
    given,
    workingDirectory: root,
    targets: session.project.targets,
    codeRootOf: session.project.codeRootOf,
    projectRoot: session.project.projectRoot,
    reachedFromProjectRoot: (projectPath) =>
        projectRootMatch(session.index, projectPath).isNotEmpty,
  );

  /// Returns the bundle [mode] gives for [given].
  Bundle pick(String given, {BundleMode mode = BundleMode.implement}) =>
      pickCodeBundle(session.index, resolve(given), mode, noProject: false);
}
