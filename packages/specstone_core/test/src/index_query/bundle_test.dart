// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';

void main() {
  late DocIndex index;
  setUpAll(() async => index = await indexWith());
  const f = 'prds/features/f01_login';
  const s = 'specs/f01_login';
  final specs = <String>{
    '$s/API.md',
    '$s/ARCHITECTURE.md',
    '$s/DOMAIN.md',
    '$s/ERROR.md',
  };

  test('f01/us05/s1, f01/us05/fr01, f01/us05/fr01/e01, s03/inv11: a story for implement: feature, spec docs, story, its FRs and nfs', () async {
    final b = pickBundle(
      index,
      'login/email_login',
      BundleMode.implement,
      noProject: false,
    );
    expect(b.docPaths, {
      '$f/FEATURE.md',
      ...specs,
      '$f/us01_email_login/USER_STORY.md',
      '$f/us01_email_login/fr01_validate_credentials.md',
      '$f/us01_email_login/fr02_lock_after_failures.md',
      '$f/us01_email_login/nf01_login_latency.md',
    });
    expect(b.joinedPaths, {
      'prds/GNFR.md',
      'prds/PROJECT.md',
      'specs/TECH_STACK.md',
    });
  });
  test("f01/us05/fr01/e02: an FR for implement keeps its story's nfs and drops the other FRs", () async {
    final b = pickBundle(
      index,
      'login/email_login/validate_credentials',
      BundleMode.implement,
      noProject: false,
    );
    expect(b.docPaths, {
      '$f/FEATURE.md',
      ...specs,
      '$f/us01_email_login/USER_STORY.md',
      '$f/us01_email_login/fr01_validate_credentials.md',
      '$f/us01_email_login/nf01_login_latency.md',
    });
  });
  const us01 = '$f/us01_email_login';
  const us02 = '$f/us02_reset_password';
  test('f01/us05/s2, f01/us05/fr01/e03, s03/inv11, db-r1, db-r2: a story for design: its story whole, siblings in summary', () {
    final b = pickBundle(
      index,
      'login/email_login',
      BundleMode.design,
      noProject: false,
    );
    expect(b.docPaths, {
      '$f/FEATURE.md',
      ...specs,
      '$us01/USER_STORY.md',
      '$us01/fr01_validate_credentials.md',
      '$us01/fr02_lock_after_failures.md',
      '$us01/nf01_login_latency.md',
    });
    expect(b.summaryOnly, {
      '$us02/USER_STORY.md',
      '$us02/fr01_send_reset_link.md',
    });
    expect(b.joinedPaths, {
      'prds/PROJECT.md',
      'prds/GNFR.md',
      'specs/TECH_STACK.md',
    });
  });
  test(
    "f01/us05/fr01/e14, db-r3: an FR or nf for design gives its story's bundle",
    () {
      final story = pickBundle(
        index,
        'login/email_login',
        BundleMode.design,
        noProject: false,
      );
      for (final t in [
        'login/email_login/validate_credentials',
        'login/email_login/login_latency',
      ]) {
        final b = pickBundle(index, t, BundleMode.design, noProject: false);
        expect(b.docPaths, story.docPaths, reason: t);
        expect(b.summaryOnly, story.summaryOnly, reason: t);
      }
    },
  );
  test('f01/us05/s14, f01/us05/fr01/e15, db-r4: a feature for design is whole, no summary doc', () {
    final b = pickBundle(index, 'login', BundleMode.design, noProject: false);
    expect(b.summaryOnly, isEmpty);
    expect(
      b.docPaths,
      containsAll(['$us02/USER_STORY.md', '$us02/fr01_send_reset_link.md']),
    );
  });
  test('f01/us05/s15, f01/us05/fr01/e16, s03/inv12, db-r6: a feature with summary: spec docs whole, every story in summary', () {
    final b = pickBundle(
      index,
      'login',
      BundleMode.design,
      noProject: false,
      summary: true,
    );
    expect(b.docPaths, {'$f/FEATURE.md', ...specs});
    expect(b.summaryOnly, {
      '$us01/USER_STORY.md',
      '$us01/fr01_validate_credentials.md',
      '$us01/fr02_lock_after_failures.md',
      '$us01/nf01_login_latency.md',
      '$us02/USER_STORY.md',
      '$us02/fr01_send_reset_link.md',
    });
  });
  test('f01/us05/fr01/e18, db-c2: summary with query or implement is argument_conflict, before the target check', () {
    for (final mode in [BundleMode.query, BundleMode.implement]) {
      expect(
        () => pickBundle(
          index,
          'login/email_login',
          mode,
          noProject: false,
          summary: true,
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentConflict)
              .having(
                (f) => f.message,
                'message',
                '--summary works only with --for design',
              ),
        ),
      );
    }
  });
  test('f01/us05/fr01/e17, db-c2: summary on a story, a spec doc, or project is argument_conflict', () {
    for (final (target, named) in [
      ('login/email_login', 'login/email_login (user_story)'),
      ('architecture:login', 'login (architecture)'),
      ('project', 'project (project)'),
    ]) {
      expect(
        () => pickBundle(
          index,
          target,
          BundleMode.design,
          noProject: false,
          summary: true,
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentConflict)
              .having(
                (f) => f.message,
                'message',
                '--summary takes a doc with children and no parent, such as a feature; $named is not one',
              ),
        ),
      );
    }
  });
  test(
    'db-c9: a doc one target picks whole and another in summary is whole',
    () {
      final b = Bundle(BundleMode.design)
        ..addTarget(index, index.resolve('login/email_login').single)
        ..addTarget(index, index.resolve('login/reset_password').single);
      expect(b.summaryOnly, isEmpty);
    },
  );
  test('f01/us05/s8, db-r1: --no-project on a story for design drops joined docs and keeps summary docs', () {
    final b = pickBundle(
      index,
      'login/email_login',
      BundleMode.design,
      noProject: true,
    );
    expect(b.joinedPaths, isEmpty);
    expect(b.summaryOnly, hasLength(2));
  });
  test(
    's03/inv13, db-c9: a doc a bundle: join adds is whole, never summary-only',
    () async {
      final i = await indexWith({
        '.specstone/templates/fr.yaml': 'bundle: [design]\n',
      });
      final b = pickBundle(
        i,
        'login/email_login',
        BundleMode.design,
        noProject: false,
      );
      expect(b.summaryOnly, {'$us02/USER_STORY.md'});
      expect(b.joinedPaths, contains('$us02/fr01_send_reset_link.md'));
    },
  );
  test('f01/us05/fr01/e04, s03/inv12: a feature for implement gives its spec docs and its story name list', () async {
    final b = pickBundle(
      index,
      'feature:login',
      BundleMode.implement,
      noProject: false,
    );
    expect(b.docPaths, {'$f/FEATURE.md', ...specs});
    expect(b.nameListTops, {'$f/FEATURE.md'});
  });
  test(
    "f01/us05/fr01/e05, s03/inv12: a spec doc builds its parent's bundle",
    () async {
      final b = pickBundle(
        index,
        'architecture:login',
        BundleMode.implement,
        noProject: false,
      );
      expect(b.docPaths, {'$f/FEATURE.md', ...specs});
      expect(b.nameListTops, {'$f/FEATURE.md'});
    },
  );
  test(
    'f01/us05/fr01/e06, s03/inv12: a bare name takes its one chain doc',
    () async {
      expect(
        pickBundle(
          index,
          'login',
          BundleMode.implement,
          noProject: false,
        ).nameListTops,
        {'$f/FEATURE.md'},
      );
    },
  );
  test('f01/us05/s9, f01/us05/fr01/e06: buyer, with no single chain doc, bundles both docs once', () async {
    final b = pickBundle(
      index,
      'buyer',
      BundleMode.implement,
      noProject: false,
    );
    expect(b.docPaths, {
      'prds/personas/buyer/ANTI_PERSONA.md',
      'prds/personas/buyer/PERSONA.md',
    });
    expect(b.joinedPaths, {
      'prds/GNFR.md',
      'prds/PROJECT.md',
      'specs/TECH_STACK.md',
    });
  });
  test('f01/us05/fr01/e07, f01/us05/fr01/e11: project for implement appears once, with gnfr and tech_stack joined', () async {
    final b = pickBundle(
      index,
      'project',
      BundleMode.implement,
      noProject: false,
    );
    expect(b.docPaths, {'prds/PROJECT.md'});
    expect(b.joinedPaths, {'prds/GNFR.md', 'specs/TECH_STACK.md'});
  });
  test(
    'f01/us05/s10, f01/us05/fr01/e08: an untyped target is untyped_target',
    () async {
      expect(
        () => pickBundle(
          index,
          'prds/d01_context.md',
          BundleMode.implement,
          noProject: false,
        ),
        throwsA(
          isA<IndexFault>()
              .having((x) => x.code, 'code', IndexFaultCode.untypedTarget)
              .having(
                (x) => x.message,
                'message',
                'prds/d01_context.md has no doc type, so it never joins a bundle; read it with specstone get',
              ),
        ),
      );
    },
  );
  test('f01/us05/fr01/e09: a target no doc carries is doc_not_found', () async {
    expect(
      () => pickBundle(index, 'nobody', BundleMode.query, noProject: false),
      throwsA(isA<IndexFault>()),
    );
  });
  test(
    'f01/us05/fr01/e10: --for is required and takes the three modes only',
    () {
      expect(
        () => BundleMode.parse(null),
        throwsA(
          isA<IndexFault>().having(
            (x) => x.message,
            'message',
            'context needs --for, such as specstone context login --for implement',
          ),
        ),
      );
      expect(
        () => BundleMode.parse('deploy'),
        throwsA(
          isA<IndexFault>()
              .having((x) => x.code, 'code', IndexFaultCode.argumentInvalid)
              .having(
                (x) => x.message,
                'message',
                '--for takes query, implement, or design, not deploy',
              ),
        ),
      );
      expect(BundleMode.parse('design'), BundleMode.design);
    },
  );
  test('f01/us05/s3, s03/inv11, s03/inv13: a feature for query: its chain, its map, and project joined', () async {
    final b = pickBundle(index, 'login', BundleMode.query, noProject: false);
    expect(b.docPaths, {'$f/FEATURE.md'});
    expect(b.mapTops, {'$f/FEATURE.md'});
    expect(b.joinedPaths, {'prds/PROJECT.md'});
  });
  test('f01/us05/s8, f01/us05/fr01/e13: --no-project drops joined docs, never a chain doc', () async {
    expect(
      pickBundle(
        index,
        'login/email_login',
        BundleMode.implement,
        noProject: true,
      ).joinedPaths,
      isEmpty,
    );
    expect(
      pickBundle(
        index,
        'project',
        BundleMode.implement,
        noProject: true,
      ).docPaths,
      {'prds/PROJECT.md'},
    );
  });
  test('s03/inv13: a set with no bundle keys joins nothing', () async {
    final bare = await indexWith({
      '.specstone/templates/project.yaml':
          'bundle: {remove: [query, implement, design]}\n',
      '.specstone/templates/gnfr.yaml':
          'bundle: {remove: [implement, design]}\n',
      '.specstone/templates/tech_stack.yaml':
          'bundle: {remove: [implement, design]}\n',
    });
    expect(
      pickBundle(
        bare,
        'login/email_login',
        BundleMode.implement,
        noProject: false,
      ).joinedPaths,
      isEmpty,
    );
    expect(
      pickBundle(bare, 'login', BundleMode.query, noProject: false).joinedPaths,
      isEmpty,
    );
  });
  test('preflight F12 c: BundleMode wires match bundleModeWires', () {
    expect(BundleMode.values.map((m) => m.wire).toSet(), bundleModeWires);
  });
}
