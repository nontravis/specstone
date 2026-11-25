// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/canonical_path.dart';
import 'package:specstone_core/src/index_query/ancestor_pieces.dart';
import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/code_bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/models/ancestor_piece.dart';
import 'package:specstone_core/src/index_query/models/bundle_entry.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/code_target.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/pick_modes.dart';
import '../../helpers/rulebook_fixture.dart';
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
    '.specstone/records/f01_login/IMPLEMENTATION.md',
  };
  Bundle code(
    String p,
    BundleMode m, {
    bool noProject = false,
    Set<String> importedPaths = const {},
  }) => pickCodeBundle(
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
    importedPaths: importedPaths,
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
        '.specstone/records/f01_login/IMPLEMENTATION.md':
            "---\nstatuses:\n  - 'email_login/validate_credentials:implemented'\n"
            'implements:\n'
            "  - 'email_login/validate_credentials:app/lib/src/login/credential_validator.dart 0123456789ab'\n"
            'covers:\n  - app/lib/src/login/ 0123456789ab\n'
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
  group('a record covers folder that only the record names', () {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    const profileFile = 'app/lib/src/profile/page.dart';
    const specFolder = {'$s/API.md', '$s/ARCHITECTURE.md', '$s/DOMAIN.md'};
    late Directory profileProject;
    late ReadSession profileSession;
    setUpAll(() async {
      profileProject = await writeLoginProject(
        extra: {
          profileFile: '',
          'app/lib/src/profile_old/page.dart': '',
          'docs/specs/DOMAIN.md': '# Project domain\n',
          record:
              "---\nstatuses:\n  - 'email_login:planned'\n"
              'covers:\n  - app/lib/src/profile/\n'
              '---\n\n# Login implementation\n',
        },
      );
      profileSession = openSession(profileProject);
      addTearDown(profileSession.close);
    });
    Bundle at(String path, BundleMode mode, {bool noProject = false}) =>
        pickCodeBundle(
          profileSession.index,
          resolveCodePath(
            path,
            workingDirectory: profileProject,
            targets: profileSession.project.targets,
            codeRootOf: profileSession.project.codeRootOf,
            projectRoot: profileSession.project.projectRoot,
            reachedFromProjectRoot: (_) => false,
          ),
          mode,
          noProject: noProject,
        );

    test('a file under it bundles the feature, its whole spec folder, and the story names', () async {
      final b = at(profileFile, BundleMode.implement);

      expect(b.docPaths, {'$f/FEATURE.md', ...specFolder, record});
      expect(b.nameListTops, {'$f/FEATURE.md'});
      expect(b.warnings, isEmpty);
    });
    test('each spec doc of the folder is a must part in implement and design, and the record none', () async {
      for (final mode in [BundleMode.implement, BundleMode.design]) {
        final b = at(profileFile, mode);

        expect(
          b.targetSubtreePaths,
          containsAll(specFolder),
          reason: mode.wire,
        );
        expect(
          b.targetSubtreePaths,
          isNot(contains(record)),
          reason: mode.wire,
        );
      }
    });
    test(
      'a project spec doc never matches, and joins through bundle alone',
      () async {
        const projectSpecs = {'specs/DOMAIN.md', 'specs/TECH_STACK.md'};

        final joined = at(profileFile, BundleMode.implement);
        final dropped = at(profileFile, BundleMode.implement, noProject: true);

        expect(joined.docPaths.intersection(projectSpecs), isEmpty);
        expect(joined.joinedPaths, containsAll(projectSpecs));
        expect(dropped.docPaths, joined.docPaths);
        expect(dropped.joinedPaths.intersection(projectSpecs), isEmpty);
      },
    );
    test(
      'a folder that only shares its name prefix matches nothing and warns',
      () async {
        final b = at('app/lib/src/profile_old/page.dart', BundleMode.implement);

        expect(b.docPaths, isEmpty);
        expect(b.warnings, [
          'no doc covers or implements app/lib/src/profile_old/page.dart',
        ]);
      },
    );
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
  test('a code path bundle marks the imported docs it joins', () {
    final b = code(
      'app/lib/src/login/credential_validator.dart',
      BundleMode.implement,
      importedPaths: {'prds/PROJECT.md', '$f/FEATURE.md'},
    );
    expect(b.joinedPaths, contains('prds/PROJECT.md'));
    expect(b.importedPaths, {'prds/PROJECT.md', '$f/FEATURE.md'});
    expect(b.isImported(index.at('prds/PROJECT.md')!), isTrue);
    expect(b.isImported(index.at('prds/GNFR.md')!), isFalse);
  });
  test('an imported doc a code path matches is not marked', () {
    const matched = '$f/us01_email_login/fr01_validate_credentials.md';
    final b = code(
      'app/lib/src/login/credential_validator.dart',
      BundleMode.implement,
      importedPaths: {matched, 'prds/PROJECT.md'},
    );
    expect(b.docPaths, contains(matched));
    expect(b.importedPaths, {'prds/PROJECT.md'});
  });
  for (final mode in [BundleMode.implement, BundleMode.design]) {
    test(
      'an imported spec-folder sibling of a matched spec doc is not marked in ${mode.wire}',
      () {
        final b = code(
          'app/lib/src/login/credential_validator.dart',
          mode,
          importedPaths: {'$s/DOMAIN.md', 'prds/PROJECT.md'},
        );
        expect(b.docPaths, contains('$s/DOMAIN.md'));
        expect(b.importedPaths, {'prds/PROJECT.md'});
      },
    );
  }
  test('a --code query bundle marks an imported spec-folder sibling of a matched doc, and leaves the matched doc unmarked', () {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    final b = code(
      'app/lib/src/login/credential_validator.dart',
      BundleMode.query,
      importedPaths: {'$s/DOMAIN.md', record},
    );

    expect(b.importedPaths, {'$s/DOMAIN.md'});
  });
  test('--no-project marks no dropped doc on a code bundle', () {
    final b = code(
      'app/lib/src/login/credential_validator.dart',
      BundleMode.implement,
      noProject: true,
      importedPaths: {'prds/PROJECT.md'},
    );
    expect(b.droppedPaths, contains('prds/PROJECT.md'));
    expect(b.importedPaths, isEmpty);
  });
  test('--no-project with no match holds no doc and still warns', () async {
    final b = code('app/lib/main.dart', BundleMode.implement, noProject: true);
    expect(b.docPaths, isEmpty);
    expect(b.joinedPaths, isEmpty);
    expect(b.warnings, hasLength(1));
  });
  test("query gives the matched feature's map", () async {
    final b = code(
      'app/lib/src/login/credential_validator.dart',
      BundleMode.query,
    );
    expect(b.mapTops, {'$f/FEATURE.md'});
    expect(b.docPaths, {'$f/FEATURE.md'});
  });
  test('an implement code path keeps its must parts in the read-first file', () async {
    final wide = '${'word ' * 12000}\n';
    final project = await writeLoginProject(
      extra: {
        ...loginRecords,
        'docs/$f/us01_email_login/USER_STORY.md':
            '# Agent signs in with email\n\n## Use Case\n$wide',
        'docs/$s/DOMAIN.md': '# Login domain\n\n## Entities\n$wide',
      },
    );
    final session = openSession(project);
    addTearDown(session.close);
    const path = 'app/lib/src/login/credential_validator.dart';
    final bundle = pickCodeBundle(
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

    final answer = answerCodeContext(
      session.index,
      bundle,
      label: path,
      split: true,
    );

    for (final head in [
      '==> login (feature) · $f/FEATURE.md <==',
      '==> login/email_login (user_story) · $f/us01_email_login/USER_STORY.md <==',
      '==> login/email_login/validate_credentials (fr) · $f/us01_email_login/fr01_validate_credentials.md <==',
      '==> login/email_login/login_latency (nf) · $f/us01_email_login/nf01_login_latency.md <==',
      '==> login (rulebook) · $s/DOMAIN.md <==',
      '==> login (architecture) · $s/ARCHITECTURE.md <==',
    ]) {
      expect(answer.text, contains(head), reason: head);
      expect(answer.refs!.text, isNot(contains(head)), reason: head);
    }
    expect(
      answer.refs!.text,
      contains('==> tech_stack (tech_stack) · specs/TECH_STACK.md <=='),
    );
  });
  test('a record in the matched spec folder is no must part, so an oversized one moves to refs', () async {
    const record = '.specstone/records/f01_login/IMPLEMENTATION.md';
    final project = await writeLoginProject(
      extra: {
        ...loginRecords,
        record: '${loginRecords[record]!}\n## Notes\n${'word ' * 20000}\n',
      },
    );
    final session = openSession(project);
    addTearDown(session.close);
    const path = 'app/lib/src/login/credential_validator.dart';
    Bundle pick(BundleMode mode) => pickCodeBundle(
      session.index,
      resolveCodePath(
        path,
        workingDirectory: project,
        targets: session.project.targets,
        codeRootOf: session.project.codeRootOf,
        projectRoot: session.project.projectRoot,
        reachedFromProjectRoot: (_) => false,
      ),
      mode,
      noProject: false,
    );

    for (final mode in [BundleMode.implement, BundleMode.design]) {
      final bundle = pick(mode);
      expect(bundle.docPaths, contains(record), reason: mode.wire);
      expect(
        bundle.targetSubtreePaths,
        isNot(contains(record)),
        reason: mode.wire,
      );
    }
    final answer = answerCodeContext(
      session.index,
      pick(BundleMode.implement),
      label: path,
      split: true,
    );
    expect(answer.text, isNot(contains('$record <==')));
    expect(
      answer.refs!.entries
          .singleWhere(
            (e) => e.kind == BundleEntryKind.doc && e.doc.docPath == record,
          )
          .moved,
      isTrue,
    );
  });
  group('a design code path over the nested project', () {
    const cartArchitecture = 'specs/f02_shop/f01_cart/ARCHITECTURE.md';
    const cartFile = 'app/lib/cart.dart';

    /// The cart's architecture, linking a shop invariant, and the cart's
    /// record over [cartFile], tracing the FR `check_stock` to it.
    final cartFiles = <String, String>{
      cartFile: 'class Cart {}\n',
      'docs/$cartArchitecture':
          '# Cart architecture\n\n'
          '## Components\n| Component | Responsibility |\n|---|---|\n'
          '| Cart | Keeps [INV-1](../DOMAIN.md#invariants) |\n',
      cartRecord:
          "---\nstatuses:\n  - 'add_item:implemented'\n"
          "  - 'add_item/check_stock:implemented'\n"
          "  - 'drop_item:implemented'\nimplements:\n"
          "  - 'add_item/check_stock:$cartFile:Cart'\n"
          'covers:\n  - $cartFile\n'
          '---\n\n# Cart implementation\n',
    };

    /// Opens the nested project with the cart files and [extra] files.
    Future<_NestedProject> openNested(Map<String, String> extra) async {
      final root = await writeNestedProject(extra: {...cartFiles, ...extra});
      final opened = openSession(root);
      addTearDown(opened.close);
      return _NestedProject(opened, root);
    }

    test('a design code path bundles each match as its own target', () async {
      final project = await openNested(const {});

      final b = project.design(cartFile);

      expect(b.targetSubtreePaths, {
        cartAdd,
        cartAddFr,
        cartDomain,
        cartArchitecture,
      });
      expect(b.chainAbovePaths, {cartFeature, shopFeature});
      expect(b.ancestorSpecPaths.difference(b.targetSubtreePaths), {
        shopDomain,
        shopArchitecture,
        shopApi,
        cartRecord,
      });
      expect(b.summaryOnly, {cartDrop});
      expect(b.docPaths, isNot(contains(payFeature)));
      expect(
        {
          for (final piece in ancestorPiecesOf(project.session.index, b))
            (piece.doc.docPath, piece.direction),
        },
        {
          (shopDomain, PieceDirection.outbound),
          (shopApi, PieceDirection.inbound),
        },
      );
    });
    test('a design code match joins the holders of its own subtree', () async {
      Map<String, String> agent(String slug, String feature) => {
        'docs/specs/agents/$slug.md':
            '---\nfeature:\n  - $feature\n---\n\n'
            '# $slug\n\n## Role\n\nReviews a diff.\n',
      };
      final project = await openNested({
        '.specstone/config.yaml': skillPinsConfig(),
        ...agent('cart_reviewer', 'shop/cart'),
        ...agent('pay_reviewer', 'shop/pay'),
        ...agent('shop_reviewer', 'shop'),
      });

      final b = project.design(cartFile);

      expect(
        {
          for (final MapEntry(:key, :value) in b.linkedDocs.entries)
            key: (value.anchorPath, value.direction),
        },
        {'specs/agents/cart_reviewer.md': (cartFeature, JoinDirection.inward)},
      );
    });
  });
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
            '# Toast architecture\n',
        'docs/specs/jaspr/f02_feedback/f03_toast/ARCHITECTURE.md':
            '# Toast architecture\n',
        'docs/specs/flutter/TECH_STACK.md': '# Toast stack\n',
        'docs/specs/jaspr/TECH_STACK.md': '# Toast stack\n',
        '.specstone/records/flutter/f02_feedback/f03_toast/IMPLEMENTATION.md':
            '---\nstatuses:\n'
            '  - show:implemented\n'
            'implements:\n'
            '  - show:lib/toast.dart:showToast\n'
            'covers:\n'
            '  - lib/\n'
            '---\n\n# Record\n',
        '.specstone/records/jaspr/f02_feedback/f03_toast/IMPLEMENTATION.md':
            '---\nstatuses:\n'
            '  - show:implemented\n'
            'implements:\n'
            '  - show:lib/toast.dart:showToast\n'
            'covers:\n'
            '  - lib/\n'
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
          'docs/specs/flutter/SECURITY.md': '# Flutter security\n',
          'docs/specs/jaspr/SECURITY.md': '# Jaspr security\n',
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
        'specs/jaspr/SECURITY.md',
      });
    });

    test("a shared doc's covers count for no target, so the target's own architecture is the spec match", () async {
      final (session, root) = await writeFeedbackProject(
        extra: {
          'jaspr_lib/lib/toast.dart': '',
          charterLayerFile: charterLayer.replaceFirst(
            'per_target: true',
            'per_target: false',
          ),
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
    test(
      'a code root file reached by a record and a skill doc bundles both',
      () async {
        final project = await openSkillProject(
          files: {
            ...loginRecords,
            ...skillDocFile(['app/lib/src/login/']),
            skillFile: skillText,
          },
        );

        final bundle = project.pick(
          'app/lib/src/login/credential_validator.dart',
        );

        expect(bundle.docPaths, contains(skillDoc));
        expect(bundle.docPaths, contains('specs/f01_login/ARCHITECTURE.md'));
      },
    );
    test(
      'a project-root match doc stays read-first in implement and design',
      () async {
        final wide = 'word ' * 20000;
        final skill = skillDocFile(['.claude/skills/review/']);
        final project = await openSkillProject(
          files: {
            'docs/$skillDoc': skill['docs/$skillDoc']!.replaceFirst(
              'Reviews a diff.',
              wide,
            ),
            skillFile: skillText,
          },
        );
        const head = '==> review (skill) · $skillDoc <==';

        for (final mode in [BundleMode.implement, BundleMode.design]) {
          final answer = answerCodeContext(
            project.session.index,
            project.pick(skillFile, mode: mode),
            label: skillFile,
            split: true,
          );

          expect(answer.text, contains(head), reason: mode.wire);
          expect(answer.refs!.text, isNot(contains(head)), reason: mode.wire);
        }
      },
    );
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

    /// A skill doc over [covers] and an agent doc over [agentCovers], each
    /// naming the login feature.
    Map<String, String> featureNaming(
      List<String> covers, {
      List<String> agentCovers = const ['.claude/skills/review/'],
    }) {
      final skill = skillDocFile(covers);
      final agent = agentDocFile(agentCovers);
      return {
        'docs/$skillDoc': skill['docs/$skillDoc']!.replaceFirst(
          'covers:',
          'feature: login\ncovers:',
        ),
        'docs/$agentDoc': agent['docs/$agentDoc']!.replaceFirst(
          'covers:',
          'feature: login\ncovers:',
        ),
        skillFile: skillText,
      };
    }

    test('a skill doc match joins the feature its bundle_with field names, in every mode', () async {
      final project = await openSkillProject(
        files: featureNaming(['.claude/skills/review/']),
      );

      for (final mode in pickModes) {
        final bundle = project.pick(skillFile, mode: mode);

        expect(
          bundle.docPaths,
          containsAll([skillDoc, agentDoc]),
          reason: '$mode',
        );
        expect(bundle.docPaths, isNot(contains(featureDoc)), reason: '$mode');
        expect(bundle.linkedDocs.keys, [featureDoc], reason: '$mode');
        expect(
          bundle.linkedDocs[featureDoc]!.direction,
          JoinDirection.outward,
          reason: '$mode',
        );
      }
    });
    test('the joined feature of a code match in design', () async {
      final project = await openSkillProject(
        files: featureNaming(['.claude/skills/review/']),
      );

      final bundle = project.pick(skillFile, mode: BundleMode.design);

      expect(bundle.linkedDocs.keys, [featureDoc]);
      expect(
        bundle.docPaths,
        isNot(contains('$f/us01_email_login/USER_STORY.md')),
      );
      expect(bundle.patternListerPaths, contains(featureDoc));
    });
    test(
      'a design code bundle joins holders inward from each matched feature',
      () async {
        final project = await openSkillProject(
          files: {
            ...loginRecords,
            ...featureNaming(['.claude/skills/review/']),
          },
        );

        final bundle = project.pick(
          'app/lib/src/login/credential_validator.dart',
          mode: BundleMode.design,
        );

        expect(bundle.docPaths, contains(featureDoc));
        expect(bundle.linkedDocs.keys, containsAll([skillDoc, agentDoc]));
        expect(bundle.linkedDocs[skillDoc]!.direction, JoinDirection.inward);
        expect(bundle.linkedDocs[skillDoc]!.anchorPath, featureDoc);
        expect(bundle.patternListerPaths, containsAll([skillDoc, agentDoc]));

        final implement = project.pick(
          'app/lib/src/login/credential_validator.dart',
        );
        expect(implement.linkedDocs, isEmpty);
      },
    );
    test('a spec-matched feature that a skill doc also names', () async {
      final project = await openSkillProject(
        files: {
          ...loginRecords,
          ...featureNaming(['app/lib/src/login/'], agentCovers: ['elsewhere/']),
        },
      );

      for (final mode in pickModes) {
        final bundle = project.pick(
          'app/lib/src/login/credential_validator.dart',
          mode: mode,
        );

        expect(
          bundle.docPaths,
          containsAll([skillDoc, featureDoc]),
          reason: '$mode',
        );
        expect(
          bundle.linkedDocs.keys,
          isNot(contains(featureDoc)),
          reason: '$mode',
        );
      }
    });
    test('no doc type id keys the code join', () async {
      final skill = skillDocFile(['.claude/skills/review/']);
      final project = await openSkillProject(
        files: {
          '.specstone/templates/skill.yaml':
              'id: skill\nfields:\n  - id: reviewer\n    type: doc_ref\n'
              '    doc_types: [agent]\n    bundle_with: true\n',
          'docs/$skillDoc': skill['docs/$skillDoc']!.replaceFirst(
            'covers:',
            'reviewer: reviewer\ncovers:',
          ),
          ...agentDocFile(['elsewhere/']),
          skillFile: skillText,
        },
      );

      final bundle = project.pick(skillFile);

      expect(bundle.docPaths, contains(skillDoc));
      expect(bundle.linkedDocs.keys, [agentDoc]);
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
  group('a project architecture doc whose covers entry reads from the project root', () {
    const architectureDoc = 'specs/ARCHITECTURE.md';
    const billingFile = 'app/lib/src/billing/ledger.dart';
    const loginFile = 'app/lib/src/login/credential_validator.dart';
    const loginSpecFolder = [
      'specs/f01_login/API.md',
      'specs/f01_login/ARCHITECTURE.md',
      'specs/f01_login/DOMAIN.md',
    ];

    /// Opens the login project on the shipped pins over a project
    /// ARCHITECTURE.md covering [covers], padded by [padding].
    Future<_SkillProject> openArchitectureProject(
      List<String> covers, {
      String padding = '',
      Map<String, String> files = const {},
    }) async {
      final entries = [for (final entry in covers) '  - $entry\n'].join();
      final root = await writeLoginProject(
        extra: {
          '.specstone/config.yaml': shippedPinsConfig(),
          'docs/$architectureDoc':
              '${covers.isEmpty ? '' : '---\ncovers:\n$entries---\n\n'}'
              '# Login demo architecture\n\n'
              '## Components\n| Component | Responsibility |\n|---|---|\n'
              '| Ledger | Keeps the books |\n$padding',
          billingFile: '',
          ...files,
        },
      );
      final opened = openSession(root);
      addTearDown(opened.close);
      return _SkillProject(opened, root);
    }

    test('a file only its entry reaches bundles the doc as a must part, in implement and design', () async {
      final project = await openArchitectureProject(['app/lib/src/billing/']);

      for (final mode in [BundleMode.implement, BundleMode.design]) {
        final bundle = project.pick(billingFile, mode: mode);

        expect(bundle.docPaths, contains(architectureDoc), reason: mode.wire);
        expect(
          bundle.targetSubtreePaths,
          contains(architectureDoc),
          reason: mode.wire,
        );
        expect(bundle.warnings, isEmpty, reason: mode.wire);
      }
    });
    test('a file no entry reaches bundles no doc and warns', () async {
      final project = await openArchitectureProject(const []);

      final bundle = project.pick(billingFile);

      expect(bundle.docPaths, isNot(contains(architectureDoc)));
      expect(bundle.warnings, ['no doc covers or implements $billingFile']);
    });
    test('the doc stays read-first in implement and design', () async {
      const head =
          '==> project_architecture (project_architecture) · $architectureDoc <==';
      final project = await openArchitectureProject([
        'app/lib/src/billing/',
      ], padding: '\n${'word ' * 20000}\n');

      for (final mode in [BundleMode.implement, BundleMode.design]) {
        final answer = answerCodeContext(
          project.session.index,
          project.pick(billingFile, mode: mode),
          label: billingFile,
          split: true,
        );

        expect(answer.text, contains(head), reason: mode.wire);
        expect(answer.refs!.text, isNot(contains(head)), reason: mode.wire);
      }
    });
    test('a file a longer entry reaches bundles the doc beside the record spec folder, a project-root match in design', () async {
      final skill = skillDocFile(['elsewhere/']);
      final project = await openArchitectureProject(
        [loginFile],
        files: {
          ...loginRecords,
          '.specstone/config.yaml': skillPinsConfig(),
          '.specstone/templates/skill.yaml':
              'id: skill\nfields:\n  - id: architecture\n    type: doc_ref\n'
              '    doc_types: [project_architecture]\n'
              '    bundle_with: true\n',
          'docs/$skillDoc': skill['docs/$skillDoc']!.replaceFirst(
            'covers:',
            'architecture: project_architecture\ncovers:',
          ),
        },
      );

      for (final mode in [BundleMode.implement, BundleMode.design]) {
        final bundle = project.pick(loginFile, mode: mode);

        expect(
          bundle.docPaths,
          containsAll([architectureDoc, ...loginSpecFolder]),
          reason: mode.wire,
        );
        expect(
          bundle.targetSubtreePaths,
          contains(architectureDoc),
          reason: mode.wire,
        );
        expect(bundle.warnings, isEmpty, reason: mode.wire);
      }

      final design = project.pick(loginFile, mode: BundleMode.design);
      final docTarget = pickBundle(
        project.session.index,
        ['project_architecture'],
        BundleMode.design,
        noProject: false,
      );

      expect(design.targetSubtreePaths, containsAll(loginSpecFolder));
      expect(
        docTarget.linkedDocs[skillDoc]?.direction,
        JoinDirection.inward,
        reason: 'control: as a design target the doc draws its holder inward',
      );
      expect(
        design.linkedDocs.keys,
        isNot(contains(skillDoc)),
        reason: 'the doc is no design target, so its holder joins no inward',
      );
    });
  });
}

/// The nested project, with its open session.
final class _NestedProject {
  const new(this.session, this.root);

  final ReadSession session;
  final Directory root;

  /// Returns the design bundle of [given], a path from [root].
  Bundle design(String given) => pickCodeBundle(
    session.index,
    resolveCodePath(
      given,
      workingDirectory: root,
      targets: session.project.targets,
      codeRootOf: session.project.codeRootOf,
      projectRoot: session.project.projectRoot,
      reachedFromProjectRoot: (_) => false,
    ),
    BundleMode.design,
    noProject: false,
  );
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
