// Each test name states one behavior on one line.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show MoveJournal;
import 'package:specstone_core/src/document_writing/move_plan.dart';
import 'package:specstone_core/src/document_writing/move_plan_engine.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, spots;
import '../../helpers/grouped_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/no_generators.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/write_fixture.dart';

const _payDomain = 'specs/f02_shop/f02_pay/DOMAIN.md';
const _giftFeature = 'prds/features/f02_shop/f03_gift/FEATURE.md';
const _cartFolder = 'prds/features/f02_shop/f01_cart';
const _payFolder = 'prds/features/f02_shop/f02_pay';
const _giftFolder = 'prds/features/f02_shop/f03_gift';

String _inv(int number) => '- **INV-$number** Rule $number holds.';

String _domain(List<int> numbers) =>
    '# Domain\n\n## Invariants\n\n'
    '${[for (final n in numbers) _inv(n)].join('\n')}\n';

/// The nested project, its shop, cart, and pay domains holding [shop],
/// [cart], and [pay] invariants; every doc approved.
Future<Directory> _project({
  List<int> shop = const [1, 2, 3],
  List<int> cart = const [1],
  List<int> pay = const [5],
}) => writeNestedProject(
  extra: {
    'docs/$shopDomain': _domain(shop),
    'docs/$cartDomain': _domain(cart),
    'docs/$_payDomain': _domain(pay),
  },
);

ReadAnswer _apply(Directory root, String plan, {bool dryRun = false}) =>
    writeIn(
      root,
      (session) => answerPlanMove(
        session,
        parseMovePlan(plan, path: 'plan.txt'),
        dryRun: dryRun,
        generators: noGenerators,
      ),
    );

/// Every doc and record of [root] as bytes, so a test shows a refusal wrote
/// none; the trash, where a journal sits, included.
Map<String, List<int>> _written(Directory root) => {
  for (final entry in treeBytes(root).entries)
    if (entry.key.startsWith('docs/') ||
        entry.key.startsWith('.specstone/records/') ||
        entry.key.startsWith(MoveJournal.trashPath))
      entry.key: entry.value,
};

List<String> _invariantsOf(Directory root, String docPath) => [
  for (final match in RegExp(
    r'^- \*\*(INV-\d+)\*\*',
    multiLine: true,
  ).allMatches(readDoc(root, docPath)))
    match.group(1)!,
];

String? _approvedOf(Directory root, String docPath) => RegExp(
  r'^approved: "([^"]+)"$',
  multiLine: true,
).firstMatch(readDoc(root, docPath))?.group(1);

bool _isDraft(Directory root, String docPath) =>
    readDoc(root, docPath).contains('\ndraft: true\n');

/// Applies [plan] and returns the fault it raised, asserting nothing was
/// written and no journal is left.
Object _refusal(Directory root, String plan, {bool dryRun = false}) {
  final before = _written(root);
  try {
    _apply(root, plan, dryRun: dryRun);
  } on Object catch (fault) {
    expect(_written(root), before, reason: 'a refused plan writes nothing');
    expect(
      Directory('${root.path}/${MoveJournal.trashPath}').existsSync(),
      isFalse,
      reason: 'a refused plan leaves no journal',
    );
    return fault;
  }
  return fail('no fault raised');
}

void main() {
  test("a plan's new line creates a grouped feature and a later line moves a story into it", () async {
    final root = await writeGroupedProject();
    _apply(
      root,
      'new feature --slug garden/herbs\n'
      'user_story:kitchen/recipes/add_dish -> feature:garden/herbs\n',
    );
    const herbs = 'prds/features/garden/f01_herbs/FEATURE.md';
    expect(_isDraft(root, herbs), isTrue);
    expect(
      hasDoc(
        root,
        'prds/features/garden/f01_herbs/us01_add_dish/USER_STORY.md',
      ),
      isTrue,
    );
    expect(hasDoc(root, kitchenAddDish), isFalse);
  });

  test("a plan's new line with a one-part slug in a grouped project is argument_missing with its line prefix", () async {
    final root = await writeGroupedProject();
    final fault = _refusal(root, 'new feature --slug herbs\n');
    expect(
      fault,
      isA<IndexFault>()
          .having((f) => f.code, 'code', IndexFaultCode.argumentMissing)
          .having((f) => f.message, 'message', startsWith('plan.txt:1: '))
          .having((f) => f.message, 'message', contains('needs --slug')),
    );
  });

  test("a plan's new line with a three-part slug is argument_invalid with its line prefix", () async {
    final root = await writeGroupedProject();
    final fault = _refusal(root, 'new feature --slug garden/herbs/extra\n');
    expect(
      fault,
      isA<IndexFault>()
          .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
          .having((f) => f.message, 'message', startsWith('plan.txt:1: '))
          .having(
            (f) => f.message,
            'message',
            contains('feature takes 2 slug parts, got 3'),
          ),
    );
  });

  test('plan with a new line creates a draft doc and moves units into it', () async {
    final root = await _project();
    final answer = _apply(
      root,
      'new feature --parent shop --slug gift\n'
      'user_story:shop/cart/drop_item -> feature:shop/gift\n',
    );
    expect(
      answer.text,
      startsWith(
        'created $_giftFeature\n'
        'moved $_cartFolder/us02_drop_item/ to $_giftFolder/us01_drop_item/\n',
      ),
    );
    expect(answer.json['created'], [_giftFeature]);
    expect(_isDraft(root, _giftFeature), isTrue);
    expect(readDoc(root, _giftFeature), contains('\n# gift\n'));
    expect(hasDoc(root, '$_giftFolder/us01_drop_item/USER_STORY.md'), isTrue);
    expect(hasDoc(root, cartDrop), isFalse);
  });

  test('plan refused late leaves no file and no journal', () async {
    final root = await _project();
    final fault = _refusal(
      root,
      'new feature --parent shop --slug gift\n'
      'user_story:shop/cart/drop_item -> feature:shop/gift\n'
      'rulebook:shop#INV-2 -> rulebook:shop/cart\n'
      'rulebook:shop#INV-9 -> rulebook:shop/cart\n',
    );
    expect(
      fault,
      isA<WriteFault>()
          .having((f) => f.code, 'code', WriteFaultCode.itemNotFound)
          .having((f) => f.message, 'message', '$shopDomain holds no INV-9'),
    );
  });

  // D7
  test('a plan moving a story under a parent where a doc of its folder matches no doc type refuses the whole plan', () async {
    final root = await writeNestedProject(
      extra: {
        '.specstone/templates/spike.yaml':
            'id: spike\ndescription: A spike.\npath: $_cartFolder/us02_drop_item/NOTE.md\n',
        'docs/$_cartFolder/us02_drop_item/NOTE.md': '# Note\n',
      },
    );
    final fault = _refusal(
      root,
      'new feature --parent shop --slug gift\n'
      'user_story:shop/cart/drop_item -> feature:shop/pay\n',
    );
    expect(
      fault,
      isA<IndexFault>()
          .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
          .having(
            (f) => f.message,
            'message',
            '$_payFolder/us03_drop_item/NOTE.md matches no doc type',
          ),
    );
  });

  test('stale source hash refuses the plan with plan_mismatch', () async {
    final root = await _project();
    final fault = _refusal(
      root,
      'source rulebook:shop 000000000000\n'
      'rulebook:shop#INV-9 -> rulebook:shop/cart\n',
    );
    expect(
      fault,
      isA<WriteFault>()
          .having((f) => f.code, 'code', WriteFaultCode.planMismatch)
          .having((f) => f.code.exitStatus, 'exit', 75)
          .having(
            (f) => f.message,
            'message',
            '$shopDomain changed since the plan was written; write it again '
                'with move --plan-out',
          ),
    );
    final hash = sourceHashOf(docFile(root, shopDomain).readAsBytesSync());
    _apply(
      root,
      'source rulebook:shop $hash\nrulebook:shop#INV-2 -> rulebook:shop/cart\n',
    );
    expect(_invariantsOf(root, cartDomain), ['INV-1', 'INV-2']);
  });

  test('units land after existing units in plan line order', () async {
    final root = await _project();
    _apply(
      root,
      'rulebook:shop#INV-3 -> rulebook:shop/cart\n'
      'rulebook:shop/pay#INV-5 -> rulebook:shop/cart\n'
      'rulebook:shop#INV-2 -> rulebook:shop/cart\n',
    );
    expect(_invariantsOf(root, cartDomain), [
      'INV-1',
      'INV-3',
      'INV-5',
      'INV-2',
    ]);
    expect(_invariantsOf(root, shopDomain), ['INV-1']);
  });

  test('keep lines naming every unit reorder the doc', () async {
    final root = await _project();
    final approved = _approvedOf(root, shopDomain);
    _apply(
      root,
      'rulebook:shop#INV-3 keep\n'
      'rulebook:shop#INV-1 keep\n'
      'rulebook:shop#INV-2 keep\n',
    );
    expect(_invariantsOf(root, shopDomain), ['INV-3', 'INV-1', 'INV-2']);
    expect(_isDraft(root, shopDomain), isFalse);
    expect(_approvedOf(root, shopDomain), isNot(approved));
  });

  test('keep lines naming part of a doc leave its units in place', () async {
    final root = await _project();
    final before = readDoc(root, shopDomain);
    _apply(root, 'rulebook:shop#INV-3 keep\nrulebook:shop#INV-1 keep\n');
    expect(readDoc(root, shopDomain), before);
  });

  test('plan drafts the docs it moves units between', () async {
    final root = await _project();
    final shopApproved = _approvedOf(root, shopDomain);
    final cartApproved = _approvedOf(root, cartDomain);
    final pay = readDoc(root, _payDomain);
    _apply(
      root,
      'new feature --parent shop --slug gift\n'
      'rulebook:shop#INV-2 -> rulebook:shop/cart\n',
    );
    for (final (docPath, approved) in [
      (shopDomain, shopApproved),
      (cartDomain, cartApproved),
    ]) {
      expect(_isDraft(root, docPath), isTrue, reason: docPath);
      expect(_approvedOf(root, docPath), approved, reason: docPath);
    }
    expect(_isDraft(root, _giftFeature), isTrue);
    expect(_approvedOf(root, _giftFeature), isNull);
    expect(readDoc(root, _payDomain), pay);
  });

  test('doc only rewritten keeps approval with a new hash', () async {
    final root = await _project();
    final approved = _approvedOf(root, shopApi);
    _apply(root, 'user_story:shop/cart/add_item -> feature:shop/pay\n');
    expect(readDoc(root, shopApi), contains('f02_pay/us03_add_item/'));
    expect(_isDraft(root, shopApi), isFalse);
    expect(_approvedOf(root, shopApi), isNot(approved));
    expect(
      spots(await checkOf(root), FindingKind.approvalStale),
      isNot(contains(startsWith(shopApi))),
    );
  });

  test('dry run writes nothing and prints the dry-run verbs', () async {
    final root = await _project();
    final before = _written(root);
    final answer = _apply(
      root,
      'new feature --parent shop --slug gift\n'
      'user_story:shop/cart/drop_item -> feature:shop/gift\n'
      'rulebook:shop#INV-2 -> rulebook:shop/cart\n',
      dryRun: true,
    );
    expect(
      answer.text,
      'creates $_giftFeature\n'
      'moves $_cartFolder/us02_drop_item/ to $_giftFolder/us01_drop_item/\n'
      'moves $shopDomain#INV-2 to $cartDomain#INV-2\n'
      'rewrites $shopDomain\n'
      'rewrites $cartDomain\n'
      'dry run: nothing moved\n',
    );
    expect(answer.json['created'], [_giftFeature]);
    expect(answer.json['dryRun'], isTrue);
    expect(_written(root), before);
  });

  test('plan moves a story and an item in one call', () async {
    final root = await _project();
    final answer = _apply(
      root,
      'user_story:shop/cart/drop_item -> feature:shop/pay\n'
      'rulebook:shop#INV-2 -> rulebook:shop/pay\n',
    );
    expect(
      answer.text,
      startsWith(
        'moved $_cartFolder/us02_drop_item/ to $_payFolder/us03_drop_item/\n'
        'moved $shopDomain#INV-2 to $_payDomain#INV-2\n',
      ),
    );
    expect(hasDoc(root, '$_payFolder/us03_drop_item/USER_STORY.md'), isTrue);
    expect(_invariantsOf(root, _payDomain), ['INV-5', 'INV-2']);
    expect(_invariantsOf(root, shopDomain), ['INV-1', 'INV-3']);
  });

  test('plan sends the items of one doc to two docs', () async {
    final root = await _project();
    _apply(
      root,
      'rulebook:shop#INV-2 -> rulebook:shop/cart\n'
      'rulebook:shop#INV-3 -> rulebook:shop/pay\n',
    );
    expect(_invariantsOf(root, shopDomain), ['INV-1']);
    expect(_invariantsOf(root, cartDomain), ['INV-1', 'INV-2']);
    expect(_invariantsOf(root, _payDomain), ['INV-5', 'INV-3']);
  });

  test('an item that links a story the plan moves lands with the link at the new place', () async {
    final root = await writeNestedProject(
      extra: {
        'docs/$shopDomain':
            '# Domain\n\n## Invariants\n\n${_inv(1)}\n'
            '- **INV-2** Rule 2 holds, as [drop](../../$cartDrop) asks.\n',
        'docs/$cartDomain': _domain([1]),
      },
    );
    _apply(
      root,
      'user_story:shop/cart/drop_item -> feature:shop/pay\n'
      'rulebook:shop#INV-2 -> rulebook:shop/cart\n',
    );
    expect(
      readDoc(root, cartDomain),
      contains(
        '- **INV-2** Rule 2 holds, as '
        '[drop](../../../$_payFolder/us03_drop_item/USER_STORY.md) asks.\n',
      ),
    );
  });

  test(
    'keep lines order the units a doc keeps while others leave it',
    () async {
      final root = await _project();
      _apply(
        root,
        'rulebook:shop#INV-3 keep\n'
        'rulebook:shop#INV-2 -> rulebook:shop/cart\n'
        'rulebook:shop#INV-1 keep\n',
      );
      expect(_invariantsOf(root, shopDomain), ['INV-3', 'INV-1']);
      expect(_invariantsOf(root, cartDomain), ['INV-1', 'INV-2']);
    },
  );

  test('one unit named two ways with two instructions is refused', () async {
    final root = await _project();
    final fault = _refusal(
      root,
      'rulebook:shop#INV-2 -> rulebook:shop/cart\n'
      '$shopDomain#INV-2 keep\n',
    );
    expect(
      fault,
      isA<IndexFault>()
          .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
          .having(
            (f) => f.message,
            'message',
            'plan.txt:2: $shopDomain#INV-2 is on line 1 and line 2 with '
                'different instructions',
          ),
    );
  });

  test('plan lands items in a doc a new line creates', () async {
    final root = await _project();
    const giftDomain = 'specs/f02_shop/f03_gift/DOMAIN.md';
    final answer = _apply(
      root,
      'new feature --parent shop --slug gift\n'
      'new rulebook --parent shop/gift\n'
      'rulebook:shop#INV-3 -> rulebook:shop/gift\n'
      'rulebook:shop#INV-2 -> rulebook:shop/gift\n',
    );
    expect(
      answer.text,
      'created $_giftFeature\n'
      'created $giftDomain\n'
      'moved $shopDomain#INV-3 to $giftDomain#INV-3\n'
      'moved $shopDomain#INV-2 to $giftDomain#INV-2\n'
      'rewrote $shopDomain\n',
    );
    expect(_invariantsOf(root, giftDomain), ['INV-3', 'INV-2']);
    expect(_isDraft(root, giftDomain), isTrue);
    expect(_invariantsOf(root, shopDomain), ['INV-1']);
  });

  test('keep lines in the current order change nothing', () async {
    final root = await _project();
    final before = _written(root);
    final answer = _apply(
      root,
      'rulebook:shop#INV-1 keep\n'
      'rulebook:shop#INV-2 keep\n'
      'rulebook:shop#INV-3 keep\n',
    );
    expect(answer.text, isEmpty);
    expect(_written(root), before);
  });

  test(
    'created and moved docs under one parent take one number sequence',
    () async {
      final root = await _project();
      _apply(
        root,
        'user_story:shop/cart/drop_item -> feature:shop/pay\n'
        'new user_story --parent shop/pay --slug gift_card\n',
      );
      expect(hasDoc(root, '$_payFolder/us03_gift_card/USER_STORY.md'), isTrue);
      expect(hasDoc(root, '$_payFolder/us04_drop_item/USER_STORY.md'), isTrue);
    },
  );

  test(
    'a created doc and a moved doc with one slug under one parent are refused',
    () async {
      final root = await _project();
      final fault = _refusal(
        root,
        'new user_story --parent shop/pay --slug drop_item\n'
        'user_story:shop/cart/drop_item -> feature:shop/pay\n',
      );
      expect(
        fault,
        isA<WriteFault>().having(
          (f) => f.code,
          'code',
          WriteFaultCode.docExists,
        ),
      );
    },
  );

  test(
    'a plan that leaves a feature holding stories and sub-features is refused',
    () async {
      final root = await _project();
      final fault = _refusal(
        root,
        'new feature --parent shop --slug gift\n'
        'new feature --parent shop/gift --slug wrap\n'
        'user_story:shop/cart/drop_item -> feature:shop/gift\n',
      );
      expect(
        fault,
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
            .having(
              (f) => f.message,
              'message',
              'plan.txt:3: shop/gift (feature) holds sub-features, so it takes '
                  'no story',
            ),
      );
    },
  );

  test('keep doc lines in another sibling order are refused', () async {
    final root = await _project();
    final fault = _refusal(
      root,
      'user_story:shop/cart/drop_item keep\n'
      'user_story:shop/cart/add_item keep\n',
    );
    expect(
      fault,
      isA<IndexFault>()
          .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
          .having(
            (f) => f.message,
            'message',
            'plan.txt:2: user_story:shop/cart/add_item keeps its place among '
                'its siblings; reorder them with specstone reorder',
          ),
    );
  });

  test('an item line to top is refused naming the line', () async {
    final root = await _project();
    final fault = _refusal(root, 'rulebook:shop#INV-2 -> top\n');
    expect(
      fault,
      isA<IndexFault>().having(
        (f) => f.message,
        'message',
        'plan.txt:1: rulebook:shop#INV-2 cannot move to top; top takes a feature',
      ),
    );
  });

  test("a plan's new line at a path no doc type matches is argument_invalid naming the DocPath, and the plan changes nothing", () async {
    final root = await writeGroupedProject(
      extra: {
        '.specstone/templates/security.yaml':
            'path: specs/s{nn}_{slug}/SECURITY.md\n',
      },
    );
    final fault = _refusal(
      root,
      'new feature --slug garden/herbs\n'
      'user_story:kitchen/recipes/add_dish -> feature:garden/herbs\n'
      'new security --parent kitchen/recipes\n',
    );
    expect(
      fault,
      isA<IndexFault>()
          .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
          .having(
            (f) => f.message,
            'message',
            'specs/skitchen_01/SECURITY.md matches no doc type',
          ),
    );
  });

  test('a new line that new refuses refuses the plan', () async {
    final root = await _project();
    final fault = _refusal(
      root,
      'rulebook:shop#INV-2 -> rulebook:shop/cart\n'
      'new feature --parent shop --slug cart\n',
    );
    expect(
      fault,
      isA<WriteFault>().having((f) => f.code, 'code', WriteFaultCode.docExists),
    );
  });

  test(
    'a dry run of a refused plan gives the refusal and writes nothing',
    () async {
      final root = await _project();
      final fault = _refusal(
        root,
        'new feature --parent shop --slug gift\n'
        'rulebook:shop#INV-9 -> rulebook:shop/cart\n',
        dryRun: true,
      );
      expect(
        fault,
        isA<WriteFault>().having(
          (f) => f.code,
          'code',
          WriteFaultCode.itemNotFound,
        ),
      );
    },
  );

  test('a new spec doc line with no target among two code targets is argument_invalid', () async {
    final root = await writeNestedProject(
      without: {'docs/$shopDomain', 'docs/$cartDomain'},
      extra: {
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n'
            '  app:\n    code_root: app_lib\n'
            '  server:\n    code_root: server_lib\n',
        'app_lib/.keep': '',
        'server_lib/.keep': '',
      },
    );
    final fault = _refusal(root, 'new rulebook --parent shop/pay\n');
    expect(
      fault,
      isA<IndexFault>()
          .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
          .having(
            (f) => f.message,
            'message',
            'plan.txt:1: new rulebook needs --target: the code targets are '
                'app, server',
          ),
    );
  });

  test('a unit inside a doc the plan creates is item_not_found', () async {
    final root = await _project();
    final fault = _refusal(
      root,
      'new feature --parent shop --slug gift\n'
      'new rulebook --parent shop/gift\n'
      'rulebook:shop/gift#INV-1 -> rulebook:shop\n',
    );
    expect(
      fault,
      isA<WriteFault>()
          .having((f) => f.code, 'code', WriteFaultCode.itemNotFound)
          .having(
            (f) => f.message,
            'message',
            'specs/f02_shop/f03_gift/DOMAIN.md holds no INV-1',
          ),
    );
  });

  test('plan moves an fr and an edge case out of it in one call', () async {
    const keepCart =
        'prds/features/f02_shop/f01_cart/us02_drop_item/fr01_keep_cart.md';
    final root = await writeNestedProject(
      extra: {
        'docs/$keepCart':
            '---\ntraced_from:\n  - S1\nverify_method: test\n---\n\n'
            '# Keep the cart\n\n## Statement\nThe system shall keep the cart.\n\n'
            '## Edge cases\n1. E01 — An empty cart → kept.\n\n'
            '## Rationale\nCarts matter.\n\n## Verification\nTest: kept.\n',
      },
    );
    _apply(
      root,
      'fr:shop/cart/add_item/check_stock -> user_story:shop/pay/card\n'
      'fr:shop/cart/add_item/check_stock#E01 -> fr:shop/cart/drop_item/keep_cart\n',
    );
    const movedFr = '$_payFolder/us01_card/fr01_check_stock.md';
    expect(hasDoc(root, movedFr), isTrue);
    expect(hasDoc(root, cartAddFr), isFalse);
    expect(readDoc(root, movedFr), isNot(contains('E01')));
    expect(readDoc(root, keepCart), contains('E02 — A sold-out item'));
  });

  test(
    'keep doc lines of features in two group folders are no sibling order',
    () async {
      final root = await writeGroupedProject(
        extra: {'docs/prds/features/garden/f01_herbs/FEATURE.md': '# Herbs\n'},
      );
      _apply(root, 'feature:kitchen/menus keep\nfeature:garden/herbs keep\n');
    },
  );

  test('keep doc lines past sibling 99 follow the numeric order', () async {
    String story(String title) =>
        '# $title\n\n## Use Case\n- **As a** Agent\n- **I want to** act\n'
        '- **so that** I finish\n';
    final root = await writeNestedProject(
      extra: {
        'docs/$_cartFolder/us99_wrap_item/USER_STORY.md': story('Wrap'),
        'docs/$_cartFolder/us100_tag_item/USER_STORY.md': story('Tag'),
      },
    );
    final before = _written(root);
    final answer = _apply(
      root,
      'user_story:shop/cart/wrap_item keep\n'
      'user_story:shop/cart/tag_item keep\n',
    );
    expect(answer.text, isEmpty);
    expect(_written(root), before);
  });

  test('a keyed keep line numbers its doc by position', () async {
    final root = await writeNestedProject(
      extra: {
        'docs/$cartAddFr':
            '---\ntraced_from:\n  - S1\nverify_method: test\n---\n\n'
            '# Check the stock\n\n## Statement\n$checkStockStatement\n\n'
            '## Edge cases\n1. E01 — A sold-out item → refused.\n'
            '2. E03 — A missing item → refused.\n\n'
            '## Rationale\n### Background\nStock is finite.\n\n'
            '## Verification\nTest: a sold-out item is refused.\n',
      },
    );
    _apply(
      root,
      'fr:shop/cart/add_item/check_stock#rationale/background keep\n',
    );
    expect(readDoc(root, cartAddFr), contains('2. E02 — A missing item'));
  });

  group('an address of a doc a new line creates', () {
    test('in short form names that doc', () async {
      final root = await _project();
      _apply(
        root,
        'new feature --parent shop --slug gift\n'
        'user_story:shop/cart/drop_item -> feature:gift\n',
      );
      expect(hasDoc(root, '$_giftFolder/us01_drop_item/USER_STORY.md'), isTrue);
    });

    test('in short form that an existing doc ends with too is refused listing both', () async {
      final root = await writeNestedProject(
        extra: {
          'docs/prds/features/f03_promo/FEATURE.md': '# Promo\n',
          'docs/prds/features/f03_promo/f01_gift/FEATURE.md': '# Gift\n',
        },
      );
      final fault = _refusal(
        root,
        'new feature --parent shop --slug gift\n'
        'user_story:shop/cart/drop_item -> feature:gift\n',
      );
      expect(
        fault,
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
            .having(
              (f) => f.message,
              'message',
              'feature:gift ends 2 names: feature:promo/gift, '
                  'feature:shop/gift',
            ),
      );
    });

    test('as a doc unit is refused', () async {
      final root = await _project();
      final fault = _refusal(
        root,
        'new feature --parent shop --slug gift\n'
        'feature:gift -> feature:shop/pay\n',
      );
      expect(
        fault,
        isA<IndexFault>().having(
          (f) => f.message,
          'message',
          'plan.txt:2: feature:gift names a doc this plan creates; a plan '
              'line moves or keeps a doc that stands before the plan',
        ),
      );
    });

    test('on an earlier line is refused naming both lines', () async {
      final root = await _project();
      for (final (plan, message) in [
        (
          'user_story:shop/cart/drop_item -> feature:shop/gift\n'
              'new feature --parent shop --slug gift\n',
          'plan.txt:1: feature:shop/gift names a doc that line 2 creates; '
              'name it after that line',
        ),
        (
          'user_story:shop/cart/drop_item -> feature:gift\n'
              'new feature --parent shop --slug gift\n',
          'plan.txt:1: feature:gift names a doc that line 2 creates; name it '
              'after that line',
        ),
        (
          'new feature --parent shop --slug gift\n'
              'rulebook:shop#INV-2 -> rulebook:shop/gift\n'
              'new rulebook --parent shop/gift\n',
          'plan.txt:2: rulebook:shop/gift names a doc that line 3 creates; '
              'name it after that line',
        ),
      ]) {
        expect(
          _refusal(root, plan),
          isA<IndexFault>()
              .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
              .having((f) => f.message, 'message', message),
          reason: plan,
        );
      }
    });
  });

  group('a nested item', () {
    const nestedShop =
        '# Domain\n\n## Invariants\n\n'
        '- **INV-1** Rule 1 holds.\n'
        '  - **INV-2** Rule 2 holds.\n'
        '- **INV-3** Rule 3 holds.\n'
        '- **INV-4** Rule 4 holds.\n';

    Future<Directory> nestedProject({List<int> cart = const [1]}) =>
        writeNestedProject(
          extra: {
            'docs/$shopDomain': nestedShop,
            'docs/$cartDomain': _domain(cart),
            'docs/$_payDomain':
                '# Domain\n\n## Invariants\n\n'
                '- **INV-5** Rule 5 holds, as [INV-2](../DOMAIN.md#invariants) '
                'asks.\n',
          },
        );

    test('named on its own plan line is refused naming its parent', () async {
      final root = await nestedProject();
      final fault = _refusal(
        root,
        'rulebook:shop#INV-1 -> rulebook:shop/cart\n'
        'rulebook:shop#INV-2 -> rulebook:shop/pay\n',
      );
      expect(
        fault,
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
            .having(
              (f) => f.message,
              'message',
              'plan.txt:2: rulebook:shop#INV-2 is nested in rulebook:shop#INV-1 '
                  'and moves with it',
            ),
      );
    });

    test('named on a keep line is refused naming its parent', () async {
      final root = await nestedProject();
      final fault = _refusal(root, 'rulebook:shop#INV-2 keep\n');
      expect(
        fault,
        isA<IndexFault>().having(
          (f) => f.message,
          'message',
          'plan.txt:1: rulebook:shop#INV-2 is nested in rulebook:shop#INV-1 and '
              'moves with it',
        ),
      );
    });

    test('moves once with its parent, its ID retired and kept clear of the parent new ID', () async {
      final root = await nestedProject();
      _apply(
        root,
        'rulebook:shop#INV-1 -> rulebook:shop/cart\n'
        'rulebook:shop#INV-3 keep\n',
      );
      final shop = readDoc(root, shopDomain);
      expect(_invariantsOf(root, shopDomain), ['INV-3', 'INV-4']);
      expect(shop, isNot(contains('INV-2** Rule 2')));
      expect(shop, contains('retired_ids:\n  - INV-1\n  - INV-2\n'));
      expect(
        readDoc(root, cartDomain),
        endsWith(
          '- **INV-1** Rule 1 holds.\n'
          '- **INV-3** Rule 1 holds.\n'
          '  - **INV-2** Rule 2 holds.\n',
        ),
      );
      expect(
        readDoc(root, _payDomain),
        contains('as [INV-2](../f01_cart/DOMAIN.md#invariants) asks.'),
      );
    });

    test('whose ID its destination holds is refused', () async {
      final root = await nestedProject(cart: const [1, 2]);
      final fault = _refusal(
        root,
        'rulebook:shop#INV-1 -> rulebook:shop/cart\n',
      );
      expect(
        fault,
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
            .having(
              (f) => f.message,
              'message',
              '$cartDomain already holds or retired INV-2, nested in '
                  '$shopDomain#INV-1',
            ),
      );
    });
  });

  test('a confirmed entry of a scenario moved into a created story is stamped from its landed block', () async {
    final root = await _project();
    _apply(
      root,
      'new user_story --parent shop/cart --slug wrap_item\n'
      'user_story:shop/cart/add_item#S1 -> user_story:shop/cart/wrap_item\n',
    );
    final report = await checkOf(root);
    expect(
      [
        ...spots(report, FindingKind.suspect),
        ...spots(report, FindingKind.confirmedEntryStale),
      ].where((spot) => spot.startsWith('$_cartFolder/us01_add_item/')),
      isEmpty,
    );
  });

  test('plan new lines write the record planned line as new does', () async {
    final root = await writeNestedProject(extra: nestedRecords());
    _apply(
      root,
      'new user_story --parent shop/cart --slug wrap_item\n'
      'new fr --parent shop/cart/wrap_item --slug pick_paper\n'
      'new fr --parent shop/cart/add_item --slug hold_stock\n'
      'new user_story --parent shop/cart --slug gift_note\n',
    );
    final lines = readDoc(root, cartRecord).split('\n');
    expect(
      [
        for (final line
            in lines
                .skip(lines.indexOf('statuses:') + 1)
                .takeWhile((line) => line.startsWith('  - ')))
          line.substring(4).replaceAll("'", ''),
      ],
      [
        'add_item:implemented',
        'add_item/check_stock:implemented',
        'add_item/hold_stock:planned',
        'drop_item:implemented',
        'wrap_item:planned',
        'wrap_item/pick_paper:planned',
        'gift_note:planned',
      ],
    );
    final report = await checkOf(root);
    expect(spots(report, FindingKind.recordEntryMissing), isEmpty);
  });

  test('a plan that creates the landing feature and its record carries the moved entries into that record', () async {
    final root = await writeNestedProject(extra: nestedRecords());
    _apply(
      root,
      'new feature --parent shop --slug gift\n'
      'new implementation --parent shop/gift\n'
      'user_story:shop/cart/add_item -> feature:shop/gift\n',
    );
    final gift = readDoc(
      root,
      '.specstone/records/f02_shop/f03_gift/IMPLEMENTATION.md',
    );
    expect(gift, contains('add_item:implemented'));
    expect(gift, contains('add_item/check_stock:implemented'));
    expect(gift, contains('add_item:app/lib/shop.dart:Shop'));
    expect(readDoc(root, cartRecord), isNot(contains('add_item')));
  });

  test('a plan new line adds its planned line beside the record lines a move carries in', () async {
    final root = await writeNestedProject(extra: nestedRecords());
    _apply(
      root,
      'new user_story --parent shop/cart --slug wrap_item\n'
      'user_story:shop/pay/card -> feature:shop/cart\n',
    );
    final lines = readDoc(root, cartRecord).split('\n');
    expect(
      [
        for (final line
            in lines
                .skip(lines.indexOf('statuses:') + 1)
                .takeWhile((line) => line.startsWith('  - ')))
          line.substring(4).replaceAll("'", ''),
      ],
      [
        'add_item:implemented',
        'add_item/check_stock:implemented',
        'drop_item:implemented',
        'wrap_item:planned',
        'card:implemented',
      ],
    );
    expect(readDoc(root, payRecord), isNot(contains("'card:")));
  });

  group('a plan and the path length limit', () {
    const giftHead = 'prds/features/f02_shop/f03_';
    const dropTail = '/us01_drop_item/USER_STORY.md';

    Matcher tooLong(String projectPath, int units) => isA<IndexFault>()
        .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
        .having(
          (f) => f.message,
          'message',
          '$projectPath would have $units characters; the limit is 200',
        );

    // D6
    for (final dryRun in [false, true]) {
      test(
        'a plan whose new line and whose story move both land over 200 code units names the first in tree order and writes nothing${dryRun ? ' under dry run' : ''}',
        () async {
          final root = await _project();
          final slug = 'a' * (201 - 'docs/$giftHead/FEATURE.md'.length);
          final fault = _refusal(
            root,
            'new feature --parent shop --slug $slug\n'
            'user_story:shop/cart/drop_item -> feature:shop/$slug\n',
            dryRun: dryRun,
          );
          expect(fault, tooLong('docs/$giftHead$slug/FEATURE.md', 201));
        },
      );
    }

    // D6
    test('a plan whose story move alone lands over 200 code units names the story path', () async {
      final root = await _project();
      final slug = 'a' * (201 - 'docs/$giftHead$dropTail'.length);
      final fault = _refusal(
        root,
        'new feature --parent shop --slug $slug\n'
        'user_story:shop/cart/drop_item -> feature:shop/$slug\n',
      );
      expect(fault, tooLong('docs/$giftHead$slug$dropTail', 201));
    });

    // D6
    test('a plan whose new line lands at 200 code units is written', () async {
      final root = await _project();
      final slug = 'a' * (200 - 'docs/$giftHead/FEATURE.md'.length);
      _apply(root, 'new feature --parent shop --slug $slug\n');
      expect(hasDoc(root, '$giftHead$slug/FEATURE.md'), isTrue);
    });

    // D6
    for (final dryRun in [false, true]) {
      test(
        'a plan that moves a story into a feature with no record, the story and the new record over 200 code units, names the story, first in tree order, and writes none${dryRun ? ' under dry run' : ''}',
        () async {
          const recordTail = '/IMPLEMENTATION.md';
          const storyTail = '/us01_add_item/USER_STORY.md';
          final slug =
              'a' *
              (201 - '.specstone/records/f02_shop/f03_$recordTail'.length);
          final root = await writeNestedProject(
            extra: {
              ...nestedRecords(),
              'docs/$giftHead$slug/FEATURE.md': '# Gift\n',
            },
          );
          final fault = _refusal(
            root,
            'user_story:shop/cart/add_item -> feature:shop/$slug\n',
            dryRun: dryRun,
          );
          final story = 'docs/$giftHead$slug$storyTail';
          expect(fault, tooLong(story, story.length));
        },
      );
    }
  });

  // D13
  group('a plan moving an fr_trace row into a child api doc', () {
    const cartApi = 'specs/f02_shop/f01_cart/API.md';
    const plan =
        'api:shop#fr_trace/cart/add_item/check_stock -> api:shop/cart\n';

    Future<Directory> cartProject() => writeNestedProject(
      extra: {
        'docs/$cartApi':
            '# Cart API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
            '| drop_item/check | `other` |\n\n'
            '## Operations\n### `other`\nDoes it.\n',
      },
    );

    test('prints moved with the FR path rebased below the destination feature, and its json entry holds the same to', () async {
      final root = await cartProject();
      final answer = _apply(root, plan);
      const key = 'add_item/check_stock';
      expect(readDoc(root, cartApi), contains('| $key | '));
      const line =
          '$shopApi#fr_trace/cart/add_item/check_stock to '
          '$cartApi#fr_trace/$key';
      expect(answer.text, contains('moved $line\n'));
      expect(answer.json['moved'], [
        {
          'from': '$shopApi#fr_trace/cart/add_item/check_stock',
          'to': '$cartApi#fr_trace/$key',
        },
      ]);
    });

    test('a dry run prints the same address after moves', () async {
      final answer = _apply(await cartProject(), plan, dryRun: true);
      expect(
        answer.text,
        contains(
          'moves $shopApi#fr_trace/cart/add_item/check_stock to '
          '$cartApi#fr_trace/add_item/check_stock\n',
        ),
      );
    });
  });
}
