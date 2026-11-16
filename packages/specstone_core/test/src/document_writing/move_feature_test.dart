// The test names are plan text kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, spots;
import '../../helpers/nested_fixture.dart';
import '../../helpers/record_fixture.dart';
import '../../helpers/write_fixture.dart';

void main() {
  const shop = 'prds/features/f02_shop';
  const cartDir = '$shop/f01_cart';
  const other = 'prds/features/f03_other';
  const landed = '$other/f03_cart';
  const cartSpecs = 'specs/f02_shop/f01_cart';
  const landedSpecs = 'specs/f03_other/f03_cart';

  /// The feature `other`, holding the sub-features `ship` and `track`.
  const otherFiles = {
    'docs/$other/FEATURE.md': '# Other\n',
    'docs/$other/f01_ship/FEATURE.md': '# Ship\n',
    'docs/$other/f02_track/FEATURE.md': '# Track\n',
  };

  Future<Directory> project([Map<String, String> extra = const {}]) =>
      writeNestedProject(extra: {...otherFiles, ...extra});

  ReadAnswer moveAll(
    Directory root,
    List<String> addresses, {
    String? under,
    bool top = false,
    String? codeTarget,
    bool dryRun = false,
  }) => writeIn(
    root,
    (s) => answerMove(
      s,
      addresses,
      under: under,
      top: top,
      codeTarget: codeTarget,
      dryRun: dryRun,
    ),
  );

  List<String> movedPairs(ReadAnswer answer) => [
    for (final move in answer.json['moved']! as List)
      '${(move as Map)['from']} ${move['to']}',
  ];

  /// Returns every file and folder under [root] but the index, which each
  /// session refreshes.
  Map<String, List<int>> tree(Directory root) => {
    for (final MapEntry(:key, :value) in treeBytes(root).entries)
      if (!key.contains('.specstone/index.sqlite')) key: value,
  };

  /// Expects [act] to throw a fault [matcher] takes and to leave [root] as
  /// it was.
  void expectRefused(Directory root, void Function() act, Matcher matcher) {
    writeIn(root, (s) => s.target('feature:shop'));
    final before = tree(root);
    expect(act, throwsA(matcher));
    expect(tree(root), before);
  }

  Matcher invalid(String message) => isA<IndexFault>()
      .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
      .having((f) => f.exitStatus, 'exitStatus', 64)
      .having((f) => f.message, 'message', message);

  Matcher exists(String message, String file) => isA<WriteFault>()
      .having((f) => f.code, 'code', WriteFaultCode.docExists)
      .having((f) => f.exitStatus, 'exitStatus', 64)
      .having((f) => f.message, 'message', message)
      .having((f) => f.file, 'file', file);

  test('a sub-feature lands last under another feature with every doc under it, and the features it left keep their numbers', () async {
    final root = await project();
    final answer = moveAll(root, ['feature:shop/cart'], under: 'other');
    expect(movedPairs(answer), [
      '$cartDir/ $landed/',
      '$cartSpecs/ $landedSpecs/',
    ]);
    expect(
      answer.text,
      startsWith(
        'moved $cartDir/ to $landed/\n'
        'moved $cartSpecs/ to $landedSpecs/\n',
      ),
    );
    const landedDocs = [
      '$landed/FEATURE.md',
      '$landed/us01_add_item/USER_STORY.md',
      '$landed/us01_add_item/fr01_check_stock.md',
      '$landed/us02_drop_item/USER_STORY.md',
      '$landedSpecs/DOMAIN.md',
    ];
    for (final docPath in landedDocs) {
      expect(hasDoc(root, docPath), isTrue, reason: docPath);
      expect(readDoc(root, docPath), isNot(contains('draft: true')));
    }
    expect(Directory('${root.path}/docs/$cartDir').existsSync(), isFalse);
    expect(hasDoc(root, payFeature), isTrue);
    expect(hasDoc(root, shopFeature), isTrue);
    expect(hasDoc(root, '$other/f01_ship/FEATURE.md'), isTrue);
  });

  test(
    'a sub-feature moved to the top lands last among the top features',
    () async {
      final root = await project();
      final answer = moveAll(root, ['feature:shop/cart'], top: true);
      expect(movedPairs(answer), [
        '$cartDir/ prds/features/f04_cart/',
        '$cartSpecs/ specs/f04_cart/',
      ]);
      expect(
        hasDoc(root, 'prds/features/f04_cart/us01_add_item/USER_STORY.md'),
        isTrue,
      );
      expect(hasDoc(root, 'specs/f04_cart/DOMAIN.md'), isTrue);
    },
  );

  test('a parent that holds stories is refused', () async {
    final root = await project();
    expectRefused(
      root,
      () => moveAll(root, ['feature:other/ship'], under: 'shop/pay'),
      invalid('shop/pay (feature) holds stories, so it takes no sub-feature'),
    );
  });

  test(
    'the feature itself or one of its descendants as parent is refused',
    () async {
      final root = await project();
      for (final under in ['shop/cart', 'shop']) {
        expectRefused(
          root,
          () => moveAll(root, ['feature:shop'], under: under),
          invalid('shop cannot move under itself or its own sub-feature'),
        );
      }
    },
  );

  group('a feature template max_depth of 3', () {
    const deep = {
      'docs/$other/f03_a/FEATURE.md': '# A\n',
      'docs/$other/f03_a/f01_b/FEATURE.md': '# B\n',
      'docs/$other/f03_a/f01_b/f01_c/FEATURE.md': '# C\n',
    };

    test('a landing past max_depth is refused naming the deepest depth of the moved subtree', () async {
      final root = await project(deep);
      expectRefused(
        root,
        () => moveAll(root, ['feature:shop'], under: 'other/a/b'),
        invalid(
          "shop would land at depth 4, past the feature template's "
          'max_depth 3',
        ),
      );
    });

    test(
      'a subtree with sub-features that fits under max_depth moves whole',
      () async {
        final root = await project(deep);
        final answer = moveAll(root, ['feature:shop'], under: 'other/a');
        expect(movedPairs(answer), [
          '$shop/ $other/f03_a/f02_shop/',
          'specs/f02_shop/ specs/f03_other/f03_a/f02_shop/',
        ]);
        for (final docPath in [
          '$other/f03_a/f02_shop/f01_cart/us01_add_item/USER_STORY.md',
          '$other/f03_a/f02_shop/f02_pay/us02_refund/USER_STORY.md',
          'specs/f03_other/f03_a/f02_shop/f01_cart/DOMAIN.md',
          'specs/f03_other/f03_a/f02_shop/API.md',
        ]) {
          expect(hasDoc(root, docPath), isTrue, reason: docPath);
        }
      },
    );

    test('a subtree two features deep is refused past max_depth and moves whole when it fits', () async {
      final root = await project(deep);
      expectRefused(
        root,
        () => moveAll(root, ['feature:other/a'], under: 'other/ship'),
        invalid(
          "other/a would land at depth 4, past the feature template's "
          'max_depth 3',
        ),
      );
      final answer = moveAll(root, ['feature:other/a'], top: true);
      expect(movedPairs(answer), ['$other/f03_a/ prds/features/f04_a/']);
      expect(
        hasDoc(root, 'prds/features/f04_a/f01_b/f01_c/FEATURE.md'),
        isTrue,
      );
    });
  });

  for (final (place, order) in [
    ('first', ['feature:shop', 'feature:shop/cart']),
    ('last', ['feature:shop/cart', 'feature:shop']),
  ]) {
    test(
      'a feature named beside its own ancestor moves inside it, the ancestor named $place',
      () async {
        final root = await project();
        final answer = moveAll(root, order, under: 'other');
        expect(movedPairs(answer), [
          '$shop/ $other/f03_shop/',
          'specs/f02_shop/ specs/f03_other/f03_shop/',
        ]);
        expect(answer.text, isNot(contains('cart/ to')));
        expect(
          hasDoc(root, '$other/f03_shop/f01_cart/us01_add_item/USER_STORY.md'),
          isTrue,
        );
        expect(
          hasDoc(root, 'specs/f03_other/f03_shop/f01_cart/DOMAIN.md'),
          isTrue,
        );
        expect(spots(checkOf(root), FindingKind.linkUnresolved), isEmpty);
      },
    );
  }

  test('a feature already under its parent, or a top feature given top, stays, and one named twice moves once', () async {
    final root = await project();
    final under = moveAll(root, ['feature:shop/cart'], under: 'shop');
    expect(under.text, isEmpty);
    expect(under.json['moved'], isEmpty);
    final top = moveAll(root, ['feature:shop'], top: true);
    expect(top.json['moved'], isEmpty);
    expect(hasDoc(root, cartFeature), isTrue);
    final answer = moveAll(root, [
      'feature:other/ship',
      'feature:shop/cart',
      'feature:shop/cart',
    ], under: 'other');
    expect(movedPairs(answer), [
      '$cartDir/ $landed/',
      '$cartSpecs/ $landedSpecs/',
    ]);
    expect(hasDoc(root, '$other/f01_ship/FEATURE.md'), isTrue);
  });

  group('a slug taken there, a slug two targets share, or a taken path for its folder, spec folder, or record folder is doc_exists naming that path', () {
    test('a sub-feature of the new parent with the slug', () async {
      final root = await project({
        'docs/$other/f03_cart/FEATURE.md': '# Cart\n',
      });
      expectRefused(
        root,
        () => moveAll(root, ['feature:shop/cart'], under: 'other'),
        exists(
          'a feature named other/cart exists',
          '$other/f03_cart/FEATURE.md',
        ),
      );
    });

    test('two targets with one slug name the first of them', () async {
      final root = await project({
        'docs/$other/f03_cart/FEATURE.md': '# Cart\n',
      });
      expectRefused(
        root,
        () => moveAll(root, [
          'feature:shop/cart',
          'feature:other/cart',
        ], top: true),
        exists('a feature named shop/cart exists', cartFeature),
      );
    });

    test('a taken path for its folder', () async {
      final root = await project({'docs/$landed/note.md': '# Note\n'});
      expectRefused(
        root,
        () => moveAll(root, ['feature:shop/cart'], under: 'other'),
        exists('a feature named other/cart exists', '$landed/'),
      );
    });

    test('a taken path for its spec folder', () async {
      final root = await project({'docs/$landedSpecs/note.md': '# Note\n'});
      expectRefused(
        root,
        () => moveAll(root, ['feature:shop/cart'], under: 'other'),
        exists('a feature named other/cart exists', '$landedSpecs/'),
      );
    });

    test('a taken path for its record folder', () async {
      const landedRecords = '.specstone/records/f03_other/f03_cart';
      final root = await project({
        ...nestedRecords(),
        '$landedRecords/note.md': '# Note\n',
      });
      expectRefused(
        root,
        () => moveAll(root, ['feature:shop/cart'], under: 'other'),
        exists('a feature named other/cart exists', '$landedRecords/'),
      );
    });
  });

  test('an under value read as a parent value names the feature, and one naming no feature is doc_not_found', () async {
    for (final under in ['feature:other', '$other/FEATURE.md']) {
      final root = await project();
      final answer = moveAll(root, ['feature:shop/cart'], under: under);
      expect(movedPairs(answer).first, '$cartDir/ $landed/', reason: under);
    }
    final root = await project();
    for (final under in ['shop/cart/add_item', 'nothing']) {
      expectRefused(
        root,
        () => moveAll(root, ['feature:shop/cart'], under: under),
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.docNotFound)
            .having((f) => f.exitStatus, 'exitStatus', 64)
            .having(
              (f) => f.message,
              'message',
              'no feature doc carries the name $under',
            ),
      );
    }
  });

  test('moving out the last sub-feature of a parent goes through', () async {
    final root = await project();
    final answer = moveAll(root, [
      'feature:shop/cart',
      'feature:shop/pay',
    ], top: true);
    expect(movedPairs(answer), [
      '$cartDir/ prds/features/f04_cart/',
      '$cartSpecs/ specs/f04_cart/',
      '$shop/f02_pay/ prds/features/f05_pay/',
    ]);
    expect(hasDoc(root, shopFeature), isTrue);
    expect(Directory('${root.path}/docs/$shop/f02_pay').existsSync(), isFalse);
  });

  test('a feature mixed with a story or an item is refused, and with a spec doc is doc_type_not_movable first', () async {
    final root = await project();
    expectRefused(
      root,
      () => moveAll(root, [
        'feature:shop/cart',
        'user_story:shop/pay/card',
      ], under: 'other'),
      invalid('move takes one doc type per call, not feature and user_story'),
    );
    expectRefused(
      root,
      () => moveAll(root, [
        'feature:shop/cart',
        'domain:shop#INV-1',
      ], under: 'other'),
      invalid('move takes item targets or doc targets, not both'),
    );
    expectRefused(
      root,
      () => moveAll(root, [
        'feature:shop/cart',
        'user_story:shop/pay/card',
        'architecture:shop',
      ], under: 'other'),
      isA<WriteFault>()
          .having((f) => f.code, 'code', WriteFaultCode.docTypeNotMovable)
          .having((f) => f.exitStatus, 'exitStatus', 64),
    );
  });

  test(
    'a dry run prints the feature moves and writes nothing, journal included',
    () async {
      final root = await project({
        'app/lib/cart.dart': '// Sells `feature:shop/cart`.\n',
      });
      writeIn(root, (s) => s.target('feature:shop'));
      final before = tree(root);
      final answer = moveAll(
        root,
        ['feature:shop/cart'],
        under: 'other',
        dryRun: true,
      );
      expect(
        answer.text,
        startsWith(
          'moves $cartDir/ to $landed/\n'
          'moves $cartSpecs/ to $landedSpecs/\n',
        ),
      );
      expect(answer.text, contains('rewrites $shopApi\n'));
      expect(
        answer.text,
        endsWith(
          'mentions app/lib/cart.dart:1 feature:shop/cart\n'
          'dry run: nothing moved\n',
        ),
      );
      expect(answer.json['dryRun'], isTrue);
      expect(tree(root), before);
    },
  );

  test("with two code targets, each target's spec folder and record folder follow the feature, and a target lacking them is left alone", () async {
    const flutterRecord =
        '.specstone/records/flutter/f02_shop/f01_cart/IMPLEMENTATION.md';
    const flutterDomain = 'specs/flutter/f02_shop/f01_cart/DOMAIN.md';
    // Every spec doc type of the shipped pack is per target, so the shared
    // spec docs of the nested project give way to one in the flutter folder.
    final root = await writeNestedProject(
      without: {
        'docs/$shopDomain',
        'docs/$cartDomain',
        'docs/$shopArchitecture',
        'docs/$shopApi',
      },
      extra: {
        ...otherFiles,
        '.specstone/config.yaml': twinConfig(),
        'flutter_ws/app/lib/shop.dart': 'class Shop {}\n',
        'jaspr_ws/app/lib/shop.dart': 'class Shop {}\n',
        flutterRecord: recordText(statuses: ['add_item:implemented']),
        'docs/$flutterDomain': '# Cart domain\n',
      },
    );
    final recordBefore = readDoc(root, flutterRecord);
    final answer = moveAll(root, ['feature:shop/cart'], under: 'other');
    expect(movedPairs(answer), [
      '$cartDir/ $landed/',
      '.specstone/records/flutter/f02_shop/f01_cart/ .specstone/records/flutter/f03_other/f03_cart/',
      'specs/flutter/f02_shop/f01_cart/ specs/flutter/f03_other/f03_cart/',
    ]);
    expect(
      readDoc(
        root,
        '.specstone/records/flutter/f03_other/f03_cart/IMPLEMENTATION.md',
      ),
      recordBefore,
    );
    expect(hasDoc(root, 'specs/flutter/f03_other/f03_cart/DOMAIN.md'), isTrue);
    for (final folder in [
      '.specstone/records/jaspr/f03_other',
      'docs/specs/jaspr/f03_other',
    ]) {
      expect(Directory('${root.path}/$folder').existsSync(), isFalse);
    }
  });

  test('several features land in the order given', () async {
    final root = await project();
    final answer = moveAll(root, [
      'feature:shop/pay',
      'feature:shop/cart',
    ], under: 'other');
    expect(movedPairs(answer), [
      '$shop/f02_pay/ $other/f03_pay/',
      '$cartDir/ $other/f04_cart/',
      '$cartSpecs/ specs/f03_other/f04_cart/',
    ]);
  });

  test('a code target on a feature move is argument_invalid', () async {
    final root = await project();
    expectRefused(
      root,
      () => moveAll(
        root,
        ['feature:shop/cart'],
        under: 'other',
        codeTarget: 'flutter',
      ),
      invalid('move takes --target only with item targets'),
    );
  });

  test("a feature moved one level deeper takes spec and record folders at the new depth's paths", () async {
    final root = await project(nestedRecords());
    final recordBefore = readDoc(root, cartRecord);
    final answer = moveAll(root, ['feature:shop/cart'], under: 'other/ship');
    expect(movedPairs(answer), [
      '$cartDir/ $other/f01_ship/f01_cart/',
      '.specstone/records/f02_shop/f01_cart/ .specstone/records/f03_other/f01_ship/f01_cart/',
      '$cartSpecs/ specs/f03_other/f01_ship/f01_cart/',
    ]);
    expect(
      readDoc(
        root,
        '.specstone/records/f03_other/f01_ship/f01_cart/IMPLEMENTATION.md',
      ),
      recordBefore,
    );
    expect(hasDoc(root, 'specs/f03_other/f01_ship/f01_cart/DOMAIN.md'), isTrue);
  });
}
