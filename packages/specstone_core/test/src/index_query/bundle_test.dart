// The test titles and literals are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_render.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

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

  test(
    'a story for implement: feature, spec docs, story, its FRs and nfs',
    () async {
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
    },
  );
  test(
    "an FR for implement keeps its story's nfs and drops the other FRs",
    () async {
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
    },
  );
  const us01 = '$f/us01_email_login';
  const us02 = '$f/us02_reset_password';
  test('a story for design: its story whole, siblings in summary', () {
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
  test("an FR or nf for design gives its story's bundle", () {
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
  });
  test('a feature for design is whole, no summary doc', () {
    final b = pickBundle(index, 'login', BundleMode.design, noProject: false);
    expect(b.summaryOnly, isEmpty);
    expect(
      b.docPaths,
      containsAll(['$us02/USER_STORY.md', '$us02/fr01_send_reset_link.md']),
    );
  });
  test('a feature with summary: spec docs whole, every story in summary', () {
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
  test('summary with query or implement is argument_conflict, before the target check', () {
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
  test('summary on a story, a spec doc, or project is argument_conflict', () {
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
                '--summary takes a doc with children, such as a feature; $named is not one',
              ),
        ),
      );
    }
  });
  test('a doc one target picks whole and another in summary is whole', () {
    final b = Bundle(BundleMode.design)
      ..addTarget(index, index.resolve('login/email_login').single)
      ..addTarget(index, index.resolve('login/reset_password').single);
    expect(b.summaryOnly, isEmpty);
  });
  test('--no-project on a story for design drops joined docs and keeps summary docs', () {
    final b = pickBundle(
      index,
      'login/email_login',
      BundleMode.design,
      noProject: true,
    );
    expect(b.joinedPaths, isEmpty);
    expect(b.summaryOnly, hasLength(2));
  });
  test('a doc a bundle: join adds is whole, never summary-only', () async {
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
  });
  test(
    'a feature for implement gives its spec docs and its story name list',
    () async {
      final b = pickBundle(
        index,
        'feature:login',
        BundleMode.implement,
        noProject: false,
      );
      expect(b.docPaths, {'$f/FEATURE.md', ...specs});
      expect(b.nameListTops, {'$f/FEATURE.md'});
    },
  );
  test("a spec doc builds its parent's bundle", () async {
    final b = pickBundle(
      index,
      'architecture:login',
      BundleMode.implement,
      noProject: false,
    );
    expect(b.docPaths, {'$f/FEATURE.md', ...specs});
    expect(b.nameListTops, {'$f/FEATURE.md'});
  });
  test('a bare name takes its one chain doc', () async {
    expect(
      pickBundle(
        index,
        'login',
        BundleMode.implement,
        noProject: false,
      ).nameListTops,
      {'$f/FEATURE.md'},
    );
  });
  test('buyer, with no single chain doc, bundles both docs once', () async {
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
  test(
    'project for implement appears once, with gnfr and tech_stack joined',
    () async {
      final b = pickBundle(
        index,
        'project',
        BundleMode.implement,
        noProject: false,
      );
      expect(b.docPaths, {'prds/PROJECT.md'});
      expect(b.joinedPaths, {'prds/GNFR.md', 'specs/TECH_STACK.md'});
    },
  );
  test('an untyped target is untyped_target', () async {
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
  });
  test('a target no doc carries is doc_not_found', () async {
    expect(
      () => pickBundle(index, 'nobody', BundleMode.query, noProject: false),
      throwsA(isA<IndexFault>()),
    );
  });
  test('--for is required and takes the three modes only', () {
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
  });
  test('a feature for query: its chain, its map, and project joined', () async {
    final b = pickBundle(index, 'login', BundleMode.query, noProject: false);
    expect(b.docPaths, {'$f/FEATURE.md'});
    expect(b.mapTops, {'$f/FEATURE.md'});
    expect(b.joinedPaths, {'prds/PROJECT.md'});
  });
  test('a query on an FR records the FR as its one target', () {
    final b = pickBundle(
      index,
      'login/email_login/validate_credentials',
      BundleMode.query,
      noProject: false,
    );
    expect(b.targetPaths, {'$f/us01_email_login/fr01_validate_credentials.md'});
  });
  test('a query on a spec doc adds that doc and records it as the target', () {
    final b = pickBundle(
      index,
      'architecture:login',
      BundleMode.query,
      noProject: false,
    );
    expect(b.docPaths, containsAll(['$f/FEATURE.md', '$s/ARCHITECTURE.md']));
    expect(b.targetPaths, {'$s/ARCHITECTURE.md'});
    expect(b.mapTops, {'$f/FEATURE.md'});
  });
  test(
    'a query on a shared name with no chain doc records each doc as a target',
    () {
      final b = pickBundle(index, 'buyer', BundleMode.query, noProject: false);
      expect(b.targetPaths, {
        'prds/personas/buyer/PERSONA.md',
        'prds/personas/buyer/ANTI_PERSONA.md',
      });
    },
  );
  test('no mode but query records a target', () {
    for (final mode in [BundleMode.implement, BundleMode.design]) {
      expect(
        pickBundle(
          index,
          'login/email_login',
          mode,
          noProject: false,
        ).targetPaths,
        isEmpty,
      );
    }
  });
  test('--no-project drops joined docs, never a chain doc', () async {
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
  test("a story's implement bundle holds the goal doc", () async {
    final withGoal = await indexWith({
      'docs/prds/GOAL.md': '# Goals\n\n## Long-term goals\n- **PG-01** One.\n',
    });
    Set<String> joined(
      BundleMode mode, {
      bool noProject = false,
      String target = 'login/email_login',
    }) => pickBundle(withGoal, target, mode, noProject: noProject).joinedPaths;

    expect(joined(BundleMode.implement), {
      'prds/GOAL.md',
      'prds/GNFR.md',
      'prds/PROJECT.md',
      'specs/TECH_STACK.md',
    });
    expect(joined(BundleMode.design), contains('prds/GOAL.md'));
    expect(joined(BundleMode.implement, noProject: true), isEmpty);
    expect(
      pickBundle(
        withGoal,
        'login/email_login',
        BundleMode.implement,
        noProject: true,
      ).droppedPaths,
      contains('prds/GOAL.md'),
    );
    expect(joined(BundleMode.query, target: 'login'), {'prds/PROJECT.md'});
  });
  group('the glossary doc', () {
    const glossary = 'prds/GLOSSARY.md';
    late DocIndex withGlossary;
    setUpAll(
      () async => withGlossary = await indexWith({
        'docs/$glossary': '# Domain glossary\n\n## Terms\n\n- **Doc** — one markdown file under the docs root.\n',
      }),
    );
    Bundle pick(String target, BundleMode mode, {bool noProject = false}) =>
        pickBundle(withGlossary, target, mode, noProject: noProject);

    test('a story bundle in every mode holds it, joined', () {
      expect(pick('login/email_login', BundleMode.implement).joinedPaths, {
        glossary,
        'prds/GNFR.md',
        'prds/PROJECT.md',
        'specs/TECH_STACK.md',
      });
      expect(
        pick('login/email_login', BundleMode.design).joinedPaths,
        contains(glossary),
      );
      for (final target in ['login', 'login/email_login']) {
        expect(pick(target, BundleMode.query).joinedPaths, {
          glossary,
          'prds/PROJECT.md',
        }, reason: target);
      }
      for (final mode in BundleMode.values) {
        expect(
          pick('login/email_login', mode).docPaths,
          isNot(contains(glossary)),
          reason: mode.wire,
        );
      }
    });
    test('it joins the refs file in implement and design', () {
      for (final mode in [BundleMode.implement, BundleMode.design]) {
        final b = pick('login/email_login', mode);
        expect(b.joinsRefs(withGlossary, withGlossary.at(glossary)!), isTrue);
      }
    });
    test('--no-project drops it from a story bundle', () {
      for (final mode in BundleMode.values) {
        final b = pick('login/email_login', mode, noProject: true);
        expect(b.joinedPaths, isEmpty, reason: mode.wire);
        expect(b.droppedPaths, contains(glossary), reason: mode.wire);
      }
    });
    test('--no-project keeps it as the chain doc of its own target', () {
      for (final mode in BundleMode.values) {
        final b = pick('glossary', mode, noProject: true);
        expect(b.docPaths, {glossary}, reason: mode.wire);
        expect(b.joinedPaths, isEmpty, reason: mode.wire);
      }
    });
    test('its own target holds it once, never as a join', () {
      for (final mode in BundleMode.values) {
        final b = pick('glossary', mode);
        expect(b.docPaths, {glossary}, reason: mode.wire);
        expect(b.joinedPaths, isNot(contains(glossary)), reason: mode.wire);
        expect(b.joinsRefs(withGlossary, withGlossary.at(glossary)!), isFalse);
      }
    });
  });
  test('a set with no bundle keys joins nothing', () async {
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
  group('joinsRefs', () {
    Bundle implementBundle(DocIndex i, String target) =>
        pickBundle(i, target, BundleMode.implement, noProject: false);

    test('joinsRefs reads bundleRefs, never a type id', () async {
      final i = await indexWith({
        '.specstone/templates/gnfr.yaml': 'bundle_refs: false\n',
      });
      final b = implementBundle(i, 'login/email_login');

      bool joinsRefs(String docPath) => b.joinsRefs(i, i.at(docPath)!);
      expect(joinsRefs('prds/PROJECT.md'), isTrue);
      expect(joinsRefs('prds/GNFR.md'), isFalse);
      expect(joinsRefs('specs/TECH_STACK.md'), isFalse);
    });
    test(
      'a doc the chain picks never joins refs, whatever its doc type sets',
      () async {
        final i = await indexWith();
        final b = implementBundle(i, 'project');

        expect(b.joinsRefs(i, i.at('prds/PROJECT.md')!), isFalse);
        expect(b.joinsRefs(i, i.at('prds/GNFR.md')!), isTrue);
      },
    );
    test('a doc the bundle does not hold joins no refs', () async {
      final i = await indexWith();
      final b = pickBundle(
        i,
        'login/email_login',
        BundleMode.implement,
        noProject: true,
      );

      expect(b.joinsRefs(i, i.at('prds/PROJECT.md')!), isFalse);
    });
  });
  const shopSpecs = {shopDomain, shopArchitecture, shopApi};
  test("implement on shop/cart/add_item gives the chain, shop's spec docs, cartDomain, and the FR", () async {
    final b = pickBundle(
      await nestedIndexWith(),
      'shop/cart/add_item',
      BundleMode.implement,
      noProject: false,
    );
    expect(b.docPaths, {
      shopFeature,
      ...shopSpecs,
      cartFeature,
      cartDomain,
      cartAdd,
      cartAddFr,
    });
    expect(b.summaryPaths, isEmpty);
    expect(b.nameListTops, isEmpty);
  });
  test(
    'a story left in shop joins the implement bundle of shop/cart/add_item',
    () async {
      const left = 'prds/features/f02_shop/us01_browse/USER_STORY.md';
      final b = pickBundle(
        await nestedIndexWith({'docs/$left': '# Agent browses\n'}),
        'shop/cart/add_item',
        BundleMode.implement,
        noProject: false,
      );
      expect(b.docPaths, {
        shopFeature,
        ...shopSpecs,
        left,
        cartFeature,
        cartDomain,
        cartAdd,
        cartAddFr,
      });
      expect(b.summaryPaths, isEmpty);
      expect(b.nameListTops, isEmpty);
    },
  );
  test("design on shop/cart/add_item gives cart whole, drop_item in summary, shop with its spec docs, and shop's names list", () async {
    final b = pickBundle(
      await nestedIndexWith(),
      'shop/cart/add_item',
      BundleMode.design,
      noProject: false,
    );
    expect(b.docPaths, {
      shopFeature,
      ...shopSpecs,
      cartFeature,
      cartDomain,
      cartAdd,
      cartAddFr,
    });
    expect(b.summaryPaths, {cartDrop});
    expect(b.nameListTops, {shopFeature});
    expect(b.docPaths.union(b.summaryPaths), isNot(contains(payFeature)));
    expect(b.docPaths.union(b.summaryPaths), isNot(contains(payCard)));
  });
  test("design on shop/cart gives cart's subtree, shop with its spec docs, and shop's names list", () async {
    final b = pickBundle(
      await nestedIndexWith(),
      'shop/cart',
      BundleMode.design,
      noProject: false,
    );
    expect(b.docPaths, {
      shopFeature,
      ...shopSpecs,
      cartFeature,
      cartDomain,
      cartAdd,
      cartAddFr,
      cartDrop,
    });
    expect(b.summaryPaths, isEmpty);
    expect(b.nameListTops, {shopFeature});
  });
  test('summary takes a nested feature with children', () async {
    final b = pickBundle(
      await nestedIndexWith(),
      'shop/cart',
      BundleMode.design,
      noProject: false,
      summary: true,
    );
    expect(b.docPaths, {cartFeature, cartDomain, shopFeature, ...shopSpecs});
    expect(b.summaryPaths, {cartAdd, cartAddFr, cartDrop});
    expect(b.nameListTops, {shopFeature});
    expect(b.docPaths.union(b.summaryPaths), isNot(contains(payFeature)));
    expect(b.docPaths.union(b.summaryPaths), isNot(contains(payCard)));
  });
  test(
    'summary on a nested feature holds a deeper feature story in summary',
    () async {
      const promo = 'prds/features/f02_shop/f01_cart/f01_promo/FEATURE.md';
      const coupon =
          'prds/features/f02_shop/f01_cart/f01_promo/us01_coupon/USER_STORY.md';
      final b = pickBundle(
        await nestedIndexWith({
          'docs/$promo': '# Promo\n',
          'docs/$coupon': '# Agent uses a coupon\n',
        }),
        'shop/cart',
        BundleMode.design,
        noProject: false,
        summary: true,
      );
      expect(b.summaryPaths, contains(coupon));
      expect(b.docPaths, isNot(contains(coupon)));
      expect(b.summaryPaths, isNot(contains(payCard)));
    },
  );
  test('summary still refuses a story', () async {
    final nested = await nestedIndexWith();
    expect(
      () => pickBundle(
        nested,
        'shop/cart/add_item',
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
              '--summary takes a doc with children, such as a feature; shop/cart/add_item (user_story) is not one',
            ),
      ),
    );
  });
  test('summary still refuses a doc with no children', () async {
    final nested = await nestedIndexWith();
    for (final (target, named) in [
      ('architecture:shop', 'shop (architecture)'),
      ('project', 'project (project)'),
    ]) {
      expect(
        () => pickBundle(
          nested,
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
                '--summary takes a doc with children, such as a feature; $named is not one',
              ),
        ),
      );
    }
  });
  test('design on shop keeps its whole subtree', () async {
    final b = pickBundle(
      await nestedIndexWith(),
      'shop',
      BundleMode.design,
      noProject: false,
    );
    expect(b.docPaths, {
      shopFeature,
      ...shopSpecs,
      cartFeature,
      cartDomain,
      cartAdd,
      cartAddFr,
      cartDrop,
      payFeature,
      payCard,
      payRefund,
    });
    expect(b.summaryPaths, isEmpty);
    expect(b.nameListTops, isEmpty);
  });
  test('sf-c7 (pin): design on an FR gives the bundle of its story under the nearest feature', () async {
    final b = pickBundle(
      await nestedIndexWith(),
      'shop/cart/add_item/check_stock',
      BundleMode.design,
      noProject: false,
    );
    expect(b.docPaths, {
      shopFeature,
      ...shopSpecs,
      cartFeature,
      cartDomain,
      cartAdd,
      cartAddFr,
    });
    expect(b.summaryPaths, {cartDrop});
    expect(b.nameListTops, {shopFeature});
  });
  test('sf-c7 (pin): design at depth 2 prints every feature above the nearest one whole with its names list', () async {
    const promo = 'prds/features/f02_shop/f01_cart/f01_promo/FEATURE.md';
    const coupon =
        'prds/features/f02_shop/f01_cart/f01_promo/us01_coupon/USER_STORY.md';
    final b = pickBundle(
      await nestedIndexWith({
        'docs/$promo': '# Promo\n',
        'docs/$coupon': '# Agent uses a coupon\n',
      }),
      'shop/cart/promo/coupon',
      BundleMode.design,
      noProject: false,
    );
    expect(b.docPaths, {
      promo,
      coupon,
      cartFeature,
      cartDomain,
      shopFeature,
      ...shopSpecs,
    });
    expect(b.summaryPaths, isEmpty);
    expect(b.nameListTops, {cartFeature, shopFeature});
  });
  test("query on shop/cart/add_item gives the chain and shop's map", () async {
    final b = pickBundle(
      await nestedIndexWith(),
      'shop/cart/add_item',
      BundleMode.query,
      noProject: false,
    );
    expect(b.docPaths, {shopFeature, cartFeature, cartAdd});
    expect(b.mapTops, {shopFeature});
    expect(b.summaryPaths, isEmpty);
    expect(b.nameListTops, isEmpty);
  });
  test('preflight: BundleMode wires match bundleModeWires', () {
    expect(BundleMode.values.map((m) => m.wire).toSet(), bundleModeWires);
  });

  group('index_query/get_task_bundle/pick_bundle_docs, per code target', () {
    const archToast = 'f02_feedback/f03_toast/ARCHITECTURE.md';
    const flutterArch = 'specs/flutter/$archToast';
    const jasprArch = 'specs/jaspr/$archToast';
    const showStory =
        'prds/features/f02_feedback/f03_toast/us01_show/USER_STORY.md';
    final projectFiles = <String, String>{
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
          '    list: true\n',
      '.specstone/templates/tech_stack.yaml':
          'id: tech_stack\nper_target: true\n',
      '.specstone/config.yaml':
          '${shippedPinsConfig()}targets:\n'
          '  flutter:\n    code_root: flutter_lib\n'
          '  jaspr:\n    code_root: jaspr_lib\n',
      'flutter_lib/.keep': '',
      'jaspr_lib/.keep': '',
      'docs/prds/features/f02_feedback/FEATURE.md': '# Feedback\n',
      'docs/prds/features/f02_feedback/f03_toast/FEATURE.md': '# Toast\n',
      'docs/$showStory': '# Agent sees a toast\n',
      'docs/$flutterArch': '# Toast architecture\n',
      'docs/$jasprArch': '# Toast architecture\n',
      'docs/specs/flutter/TECH_STACK.md': '# Flutter stack\n',
      'docs/specs/jaspr/TECH_STACK.md': '# Jaspr stack\n',
      'docs/specs/flutter/f02_feedback/IMPLEMENTATION.md': '# Record\n',
      'docs/specs/jaspr/f02_feedback/IMPLEMENTATION.md': '# Record\n',
    };

    /// Returns the index of the two-target toast fixture.
    Future<DocIndex> toastIndex([Map<String, String> extra = const {}]) async {
      final session = openSession(await writeTree({...projectFiles, ...extra}));
      addTearDown(session.close);
      return session.index;
    }

    test('one target needs no --target in implement', () async {
      final session = openSession(
        await writeTree({
          ...projectFiles,
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n  flutter:\n    code_root: flutter_lib\n',
          'docs/$flutterArch': '',
          'docs/$jasprArch': '',
          'docs/specs/$archToast': '# Toast architecture\n',
        }),
      );
      addTearDown(session.close);
      final b = pickBundle(
        session.index,
        'feedback/toast/show',
        BundleMode.implement,
        noProject: false,
      );
      expect(b.docPaths, contains('specs/$archToast'));
    });

    test('implement with two targets and no --target is argument_missing', () async {
      final index = await toastIndex();
      expect(
        () => pickBundle(
          index,
          'feedback/toast/show',
          BundleMode.implement,
          noProject: false,
        ),
        throwsA(
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentMissing)
              .having(
                (f) => f.message,
                'message',
                '--for implement needs --target with two or more code targets; '
                    'the targets are flutter, jaspr',
              ),
        ),
      );
    });

    test('--target jaspr keeps jaspr docs alone in implement', () async {
      final b = pickBundle(
        await toastIndex(),
        'feedback/toast/show',
        BundleMode.implement,
        noProject: false,
        codeTarget: 'jaspr',
      );
      expect(b.docPaths, {
        'prds/features/f02_feedback/FEATURE.md',
        'prds/features/f02_feedback/f03_toast/FEATURE.md',
        showStory,
        jasprArch,
        'specs/jaspr/f02_feedback/IMPLEMENTATION.md',
      });
      expect(b.docPaths, isNot(contains(flutterArch)));
      expect(b.joinedPaths, {'specs/jaspr/TECH_STACK.md'});
    });

    test('design and query with no --target take every target doc', () async {
      final index = await toastIndex();
      final design = pickBundle(
        index,
        'feedback/toast/show',
        BundleMode.design,
        noProject: false,
      );
      expect(design.docPaths, contains(flutterArch));
      expect(design.docPaths, contains(jasprArch));
      final query = pickBundle(
        index,
        'feedback/toast/show',
        BundleMode.query,
        noProject: false,
      );
      expect(query.mapTops, {'prds/features/f02_feedback/FEATURE.md'});
      final queryAnswer = answerContext(
        index,
        query,
        label: 'feedback/toast/show',
        byCode: false,
      );
      expect(
        queryAnswer.text
            .split('\n')
            .where((l) => l.contains('feedback/toast (architecture)'))
            .length,
        2,
        reason: 'the map holds each target spec doc',
      );
      final queryTargeted = answerContext(
        index,
        pickBundle(
          index,
          'feedback/toast/show',
          BundleMode.query,
          noProject: false,
          codeTarget: 'jaspr',
        ),
        label: 'feedback/toast/show',
        byCode: false,
      );
      expect(
        queryTargeted.text
            .split('\n')
            .where((l) => l.contains('feedback/toast (architecture)'))
            .length,
        1,
        reason: 'the map holds the named target spec doc alone',
      );
      expect(queryTargeted.text, isNot(contains('flutter')));
      final withTarget = pickBundle(
        index,
        'feedback/toast',
        BundleMode.design,
        noProject: false,
        codeTarget: 'jaspr',
      );
      expect(withTarget.docPaths, contains(jasprArch));
      expect(withTarget.docPaths, isNot(contains(flutterArch)));
    });

    test('a per-target chain doc of another target stays out', () async {
      final session = openSession(
        await writeTree({
          ...projectFiles,
          '.specstone/templates/feature.yaml': 'per_target: true\n',
          'docs/prds/features/f02_feedback/FEATURE.md': '',
          'docs/prds/features/f02_feedback/f03_toast/FEATURE.md': '',
          'docs/prds/flutter/features/f02_feedback/FEATURE.md': '# Feedback\n',
          'docs/prds/flutter/features/f02_feedback/f04_pay/FEATURE.md':
              '# Pay\n',
          'docs/prds/features/f02_feedback/f04_pay/us01_card/USER_STORY.md':
              '# Agent pays by card\n',
        }),
      );
      addTearDown(session.close);
      final b = pickBundle(
        session.index,
        'feedback/pay/card',
        BundleMode.implement,
        noProject: false,
        codeTarget: 'jaspr',
      );
      expect(
        b.docPaths.where((p) => p.contains('prds/flutter/')),
        isEmpty,
        reason: 'the chain walk keeps the named target alone',
      );
    });

    test('the names list holds no other-target chain doc', () async {
      final session = openSession(
        await writeTree(
          {
            ...projectFiles,
            '.specstone/templates/user_story.yaml':
                'id: user_story\nper_target: true\n',
            'docs/prds/flutter/features/f02_feedback/us01_show/USER_STORY.md':
                '# Agent sees a toast\n',
            'docs/prds/jaspr/features/f02_feedback/us01_show/USER_STORY.md':
                '# Agent sees a toast\n',
          }..remove('docs/$showStory'),
        ),
      );
      addTearDown(session.close);
      final index = session.index;
      final b = pickBundle(
        index,
        'feedback',
        BundleMode.implement,
        noProject: false,
        codeTarget: 'jaspr',
      );
      expect(b.nameListTops, {'prds/features/f02_feedback/FEATURE.md'});
      final answer = answerContext(index, b, label: 'feedback', byCode: false);
      expect(
        answer.text
            .split('\n')
            .where((l) => l.contains('feedback/show (user_story)'))
            .length,
        1,
        reason: 'the names list names the target story alone',
      );
    });

    test('one named target takes its spec docs with no --target in every mode', () async {
      final session = openSession(
        await writeTree({
          ...projectFiles,
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n  flutter:\n    code_root: flutter_lib\n',
          'docs/$flutterArch': '',
          'docs/$jasprArch': '',
          'docs/specs/$archToast': '# Toast architecture\n',
        }),
      );
      addTearDown(session.close);
      for (final mode in BundleMode.values) {
        final b = pickBundle(
          session.index,
          'feedback/toast/show',
          mode,
          noProject: false,
        );
        if (mode == BundleMode.query) {
          expect(b.mapTops, {
            'prds/features/f02_feedback/FEATURE.md',
          }, reason: '$mode');
        } else {
          expect(b.docPaths, contains('specs/$archToast'), reason: '$mode');
        }
      }
    });

    test('two targets change no trim order in implement', () async {
      final index = await toastIndex();
      final b = pickBundle(
        index,
        'feedback/toast/show',
        BundleMode.implement,
        noProject: false,
        codeTarget: 'jaspr',
      );
      final answer = answerContext(
        index,
        b,
        label: 'feedback/toast/show',
        byCode: false,
      );
      expect(
        answer.text
            .split('\n')
            .where((l) => l.startsWith('==> ') && !l.contains('bundle: '))
            .toList(),
        [
          '==> tech_stack (tech_stack) · specs/jaspr/TECH_STACK.md <==',
          '==> feedback (feature) · prds/features/f02_feedback/FEATURE.md <==',
          '==> feedback/toast (feature) · prds/features/f02_feedback/f03_toast/FEATURE.md <==',
          '==> feedback/toast/show (user_story) · $showStory <==',
          '==> feedback/toast (architecture) · $jasprArch <==',
          '==> feedback (implementation) · specs/jaspr/f02_feedback/IMPLEMENTATION.md <==',
        ],
      );
    });

    test('the budget counts only the docs that print under --target', () async {
      final index = await toastIndex();
      final flutterAnswer = answerContext(
        index,
        pickBundle(
          index,
          'feedback/toast/show',
          BundleMode.implement,
          noProject: false,
          codeTarget: 'flutter',
        ),
        label: 'feedback/toast/show',
        byCode: false,
        budget: 1,
      );
      final jasprAnswer = answerContext(
        index,
        pickBundle(
          index,
          'feedback/toast/show',
          BundleMode.implement,
          noProject: false,
          codeTarget: 'jaspr',
        ),
        label: 'feedback/toast/show',
        byCode: false,
        budget: 1,
      );
      expect(flutterAnswer.exitStatus, 1);
      expect(jasprAnswer.exitStatus, 1);
      for (final (name, answer) in [
        ('flutter', flutterAnswer),
        ('jaspr', jasprAnswer),
      ]) {
        expect(
          answer.text.split('\n').where((l) => l.startsWith('- ')).length,
          6,
          reason: '$name lists only the docs that print',
        );
        expect(
          answer.text,
          isNot(contains('specs/${name == 'flutter' ? 'jaspr' : 'flutter'}')),
          reason: '$name holds no other-target doc',
        );
      }
    });
  });

  group('project spec docs at the spec folder root', () {
    const rootDomain = 'specs/DOMAIN.md';
    final chainOfStory = {
      '$f/FEATURE.md',
      ...specs,
      '$f/us01_email_login/USER_STORY.md',
      '$f/us01_email_login/fr01_validate_credentials.md',
      '$f/us01_email_login/fr02_lock_after_failures.md',
      '$f/us01_email_login/nf01_login_latency.md',
    };
    Future<DocIndex> oneTargetIndex() =>
        indexWith({'docs/$rootDomain': '# Project domain\n'});

    test(
      "a root spec doc joins a story's implement bundle beside the tech stack",
      () async {
        final b = pickBundle(
          await oneTargetIndex(),
          'login/email_login',
          BundleMode.implement,
          noProject: false,
        );
        expect(b.docPaths, chainOfStory);
        expect(b.joinedPaths, {
          'prds/GNFR.md',
          'prds/PROJECT.md',
          'specs/TECH_STACK.md',
          rootDomain,
        });
      },
    );

    test(
      'a root spec doc as target bundles itself plus the joined docs',
      () async {
        final b = pickBundle(
          await oneTargetIndex(),
          'project_domain',
          BundleMode.implement,
          noProject: false,
        );
        expect(b.docPaths, {rootDomain});
        expect(b.joinedPaths, {
          'prds/GNFR.md',
          'prds/PROJECT.md',
          'specs/TECH_STACK.md',
        });
      },
    );

    test('no-project drops the root spec doc', () async {
      final b = pickBundle(
        await oneTargetIndex(),
        'login/email_login',
        BundleMode.implement,
        noProject: true,
      );
      expect(b.docPaths, chainOfStory);
      expect(b.joinedPaths, isEmpty);
      expect(b.droppedPaths, contains(rootDomain));
    });

    group('with two targets', () {
      const flutterDomain = 'specs/flutter/DOMAIN.md';
      const jasprDomain = 'specs/jaspr/DOMAIN.md';
      Future<DocIndex> twoTargetIndex() async {
        final session = openSession(
          await writeTree({
            '.specstone/templates/tech_stack.yaml':
                'id: tech_stack\nper_target: true\n',
            '.specstone/config.yaml':
                '${shippedPinsConfig()}targets:\n'
                '  flutter:\n    code_root: flutter_lib\n'
                '  jaspr:\n    code_root: jaspr_lib\n',
            'flutter_lib/.keep': '',
            'jaspr_lib/.keep': '',
            'docs/prds/features/f02_feedback/FEATURE.md': '# Feedback\n',
            'docs/prds/features/f02_feedback/us01_show/USER_STORY.md':
                '# Agent sees a toast\n',
            'docs/$flutterDomain': '# Flutter domain\n',
            'docs/$jasprDomain': '# Jaspr domain\n',
            'docs/specs/flutter/TECH_STACK.md': '# Flutter stack\n',
            'docs/specs/jaspr/TECH_STACK.md': '# Jaspr stack\n',
          }),
        );
        addTearDown(session.close);
        return session.index;
      }

      test("with two targets and a target flag only that target's root spec docs join", () async {
        final index = await twoTargetIndex();
        for (final mode in [BundleMode.implement, BundleMode.design]) {
          final b = pickBundle(
            index,
            'feedback/show',
            mode,
            noProject: false,
            codeTarget: 'jaspr',
          );
          expect(b.joinedPaths, {
            'specs/jaspr/TECH_STACK.md',
            jasprDomain,
          }, reason: '$mode');
        }
        final unflagged = pickBundle(
          index,
          'feedback/show',
          BundleMode.design,
          noProject: false,
        );
        expect(unflagged.joinedPaths, {
          'specs/flutter/TECH_STACK.md',
          'specs/jaspr/TECH_STACK.md',
          flutterDomain,
          jasprDomain,
        });
      });
    });

    test('a query bundle holds no root spec doc', () async {
      final b = pickBundle(
        await oneTargetIndex(),
        'login',
        BundleMode.query,
        noProject: false,
      );
      expect(b.docPaths, {'$f/FEATURE.md'});
      expect(b.joinedPaths, {'prds/PROJECT.md'});
      expect(b.droppedPaths, isEmpty);
    });
  });
}
