// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/code_bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/temp_tree.dart';

void main() {
  late Directory project;
  late ReadSession session;
  late DocIndex index;
  setUpAll(() async {
    project = await writeLoginProject();
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
  };
  Bundle code(String p, BundleMode m, {bool noProject = false}) =>
      pickCodeBundle(
        index,
        resolveCodePath(
          p,
          workingDirectory: project,
          projectRoot: session.project.projectRoot,
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
  test('f01/us05/s12, f01/us05/fr04/e09: a path outside the project root is code_path_outside_project', () async {
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
              'the code path ../ lies outside the project root',
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
        projectRoot: session.project.projectRoot,
      );
      expect(code.path, 'app/lib/main.dart');
      expect(code.isFolder, isFalse);
    },
  );
}
