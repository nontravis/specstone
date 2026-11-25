// Each test name states one behavior on one line.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/document_writing/keyed_units.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show MoveJournal;
import 'package:specstone_core/src/document_writing/move_plan.dart';
import 'package:specstone_core/src/document_writing/move_plan_engine.dart';
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:test/test.dart';

import '../../helpers/nested_fixture.dart';
import '../../helpers/write_fixture.dart';

const _cartApi = 'specs/f02_shop/f01_cart/API.md';

const _catalogHead =
    '| Code | Status or exit | Condition | Client action | Retryable |\n'
    '|---|---|---|---|---|\n';

String _row(String code) =>
    '| `$code` | 65 | A call names it. | Fix the call. | no |\n';

String _errors(String title, List<String> codes, {String after = ''}) =>
    '# $title API\n\n## Errors\n$_catalogHead'
    '${codes.map(_row).join()}$after';

const _shopApiText =
    '# Shop API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
    '| cart/add_item/check_stock | `addItem` |\n\n'
    '## Operations\n### `addItem`\nAdds an item; see [drop](#dropitem).\n\n'
    '### `dropItem`\nDrops an item for the story '
    '[drop item](../../prds/features/f02_shop/f01_cart/us02_drop_item/USER_STORY.md).\n';

const _cartApiText =
    '# Cart API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
    '| add_item/check_stock | `listItems` |\n\n'
    '## Operations\n### `listItems`\nLists the items.\n';

Future<Directory> _project(Map<String, String> docs) => writeNestedProject(
  extra: {for (final e in docs.entries) 'docs/${e.key}': e.value},
);

ReadAnswer _apply(Directory root, String plan) => writeIn(
  root,
  (session) => answerPlanMove(
    session,
    parseMovePlan(plan, path: 'plan.txt'),
    dryRun: false,
  ),
);

/// Every doc of [root] as bytes.
Map<String, List<int>> _docBytes(Directory root) => {
  for (final entry in treeBytes(root).entries)
    if (entry.key.startsWith('docs/')) entry.key: entry.value,
};

/// Applies [plan] and returns the fault it raised, asserting no doc was
/// written and no journal is left.
Object _refusal(Directory root, String plan) {
  final before = _docBytes(root);
  try {
    _apply(root, plan);
  } on Object catch (fault) {
    expect(_docBytes(root), before, reason: 'a refused plan writes nothing');
    expect(
      Directory('${root.path}/${MoveJournal.trashPath}').existsSync(),
      isFalse,
    );
    return fault;
  }
  return fail('no fault raised');
}

List<String> _codesOf(Directory root, String docPath) => [
  for (final match in RegExp(
    r'^\| `([a-z_]+)` \|',
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

void main() {
  test('api block moves to the destination section and its anchor links follow', () async {
    final root = await _project({
      shopApi: _shopApiText,
      _cartApi: _cartApiText,
      cartDomain:
          '# Cart domain\n\n## Invariants\n'
          '- **INV-1** A cart drops lines; see [drop](../API.md#dropitem).\n',
    });
    final answer = _apply(
      root,
      'api:shop#operations/dropitem -> api:shop/cart\n',
    );
    expect(
      answer.text,
      startsWith(
        'moved $shopApi#operations/dropitem to $_cartApi#operations/dropitem\n',
      ),
    );
    final shop = readDoc(root, shopApi);
    expect(shop, isNot(contains('dropItem')));
    expect(
      shop,
      contains('Adds an item; see [drop](f01_cart/API.md#dropitem).'),
    );
    expect(
      readDoc(root, _cartApi),
      endsWith(
        '### `listItems`\n\nLists the items.\n\n'
        '### `dropItem`\n\nDrops an item for the story '
        '[drop item](../../../prds/features/f02_shop/f01_cart/us02_drop_item/USER_STORY.md).\n',
      ),
    );
    expect(readDoc(root, cartDomain), contains('see [drop](API.md#dropitem).'));
    expect(_isDraft(root, shopApi), isTrue);
    expect(_isDraft(root, _cartApi), isTrue);
  });

  test('block lands in a doc a new line creates', () async {
    const giftApi = 'specs/f02_shop/f03_gift/API.md';
    final root = await _project({shopApi: _shopApiText});
    _apply(
      root,
      'new feature --parent shop --slug gift\n'
      'new api --parent shop/gift\n'
      'api:shop#operations/dropitem -> api:shop/gift\n',
    );
    expect(
      readDoc(root, giftApi),
      contains(
        '## Operations\n\n### `dropItem`\n\nDrops an item for the story '
        '[drop item](../../../prds/features/f02_shop/f01_cart/us02_drop_item/USER_STORY.md).\n',
      ),
    );
    expect(
      readDoc(root, shopApi),
      contains('[drop](f03_gift/API.md#dropitem)'),
    );
  });

  test('error row moves with its code span paragraphs', () async {
    final root = await _project({
      shopApi: _errors(
        'Shop',
        ['doc_exists', 'item_not_found'],
        after:
            '\n`item_not_found` is raised when a line names a missing item.\n\n'
            'A plan refuses with `item_not_found` too.\n',
      ),
      _cartApi: _errors('Cart', ['cart_empty']),
    });
    _apply(root, 'api:shop#errors/item_not_found -> api:shop/cart\n');
    expect(_codesOf(root, _cartApi), ['cart_empty', 'item_not_found']);
    expect(_codesOf(root, shopApi), ['doc_exists']);
    expect(
      readDoc(root, _cartApi),
      contains('`item_not_found` is raised when a line names a missing item.'),
    );
    final shop = readDoc(root, shopApi);
    expect(shop, isNot(contains('is raised when')));
    expect(shop, contains('A plan refuses with `item_not_found` too.'));
  });

  test(
    'a row lands in a table a block heading follows with no blank line',
    () async {
      final root = await _project({
        shopApi: _errors('Shop', ['item_not_found']),
        _cartApi: _errors('Cart', [
          'cart_empty',
        ], after: '### Notes\nCart notes.\n'),
      });
      _apply(root, 'api:shop#errors/item_not_found -> api:shop/cart\n');
      expect(
        readDoc(root, _cartApi),
        contains('${_row('cart_empty')}${_row('item_not_found')}'),
      );
    },
  );

  test('shared row key moves every row', () async {
    final root = await _project({
      shopApi: _errors('Shop', ['doc_exists', 'item_not_found', 'doc_exists']),
      _cartApi: _errors('Cart', ['cart_empty']),
    });
    _apply(root, 'api:shop#errors/doc_exists -> api:shop/cart\n');
    expect(_codesOf(root, _cartApi), [
      'cart_empty',
      'doc_exists',
      'doc_exists',
    ]);
    expect(_codesOf(root, shopApi), ['item_not_found']);
  });

  test('missing key is item_not_found', () async {
    final root = await _project({
      shopApi: _errors('Shop', ['doc_exists']),
      _cartApi: _errors('Cart', ['cart_empty']),
    });
    expect(
      _refusal(root, 'api:shop#errors/nope -> api:shop/cart\n'),
      isA<WriteFault>()
          .having((f) => f.code, 'code', WriteFaultCode.itemNotFound)
          .having((f) => f.message, 'message', '$shopApi holds no errors/nope'),
    );
  });

  test('taken key in the destination is argument_invalid', () async {
    final root = await _project({
      shopApi: _errors('Shop', ['doc_exists', 'item_not_found']),
      _cartApi: _errors('Cart', ['item_not_found']),
    });
    expect(
      _refusal(root, 'api:shop#errors/item_not_found -> api:shop/cart\n'),
      isA<IndexFault>()
          .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
          .having(
            (f) => f.message,
            'message',
            '$_cartApi already holds errors/item_not_found',
          ),
    );
  });

  test('destination with no section of the key is argument_invalid', () async {
    final root = await _project({shopApi: _shopApiText});
    expect(
      _refusal(root, 'api:shop#operations/additem -> rulebook:shop/cart\n'),
      isA<IndexFault>()
          .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
          .having(
            (f) => f.message,
            'message',
            '$cartDomain has no operations section for operations/additem',
          ),
    );
  });

  test('keyed address with an empty section key or key is refused', () {
    for (final text in [
      'api:shop#operations/ keep',
      'api:shop#/additem keep',
    ]) {
      expect(
        () => parseMovePlan('$text\n', path: 'plan.txt'),
        throwsA(
          isA<IndexFault>().having(
            (f) => f.message,
            'message',
            'plan.txt:1: ${text.split(' ').first} names no <section key>/<key>',
          ),
        ),
        reason: text,
      );
    }
  });

  test('section of two tables gives no row units', () async {
    final index = await nestedIndexWith({
      'docs/$shopApi':
          '# Shop API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
          '| cart/add_item/check_stock | `addItem` |\n\n'
          '| FR | Operation |\n|----|-----------|\n'
          '| cart/drop_item/check | `dropItem` |\n\n'
          '## Operations\n### `addItem`\nAdds an item.\n',
    });
    List<KeyedUnit> unitsAt(String docPath) {
      final doc = index.at(docPath)!;
      return keyedUnitsOf(index.contentOf(doc), index.typeOf(doc)!);
    }

    expect(
      [for (final unit in unitsAt(shopApi)) '${unit.sectionKey}/${unit.key}'],
      ['operations/additem'],
    );
    expect(
      [
        for (final unit in unitsAt(shopDomain))
          '${unit.sectionKey}/${unit.key}',
      ],
      ['entities/Order'],
    );
  });

  test('keep lines naming every block and row reorder the blocks', () async {
    final root = await _project({shopApi: _shopApiText});
    _apply(
      root,
      'api:shop#operations/dropitem keep\n'
      'api:shop#fr_trace/cart/add_item/check_stock keep\n'
      'api:shop#operations/additem keep\n',
    );
    final shop = readDoc(root, shopApi);
    expect(
      shop.indexOf('### `dropItem`'),
      lessThan(shop.indexOf('### `addItem`')),
    );
    expect(shop, contains('Adds an item; see [drop](#dropitem).'));
    expect(_isDraft(root, shopApi), isFalse);
  });

  test(
    'keep lines naming only the items of a doc with rows keep its order',
    () async {
      final root = await _project({
        shopDomain:
            '# Shop domain\n\n## Entities\n| Entity | Kind |\n|---|---|\n'
            '| Order | root |\n\n## Invariants\n'
            '- **INV-1** One holds.\n- **INV-2** Two holds.\n- **INV-3** Three holds.\n',
      });
      final before = readDoc(root, shopDomain);
      _apply(
        root,
        'rulebook:shop#INV-3 keep\nrulebook:shop#INV-1 keep\nrulebook:shop#INV-2 keep\n',
      );
      expect(readDoc(root, shopDomain), before);
    },
  );

  test('a block landing on a slug another section holds takes the slug and both links follow', () async {
    final root = await _project({
      shopApi: _shopApiText,
      _cartApi:
          '$_cartApiText\n## Compatibility\n### `dropItem`\nThe old drop stays.\n',
      cartDomain:
          '# Cart domain\n\n## Invariants\n'
          '- **INV-1** See [old](API.md#dropitem) and [new](../API.md#dropitem).\n',
    });
    _apply(root, 'api:shop#operations/dropitem -> api:shop/cart\n');
    expect(
      readDoc(root, cartDomain),
      contains('See [old](API.md#dropitem-1) and [new](API.md#dropitem).'),
    );
  });

  test('a block with a repeat sibling moves and the sibling left keeps its links', () async {
    final root = await _project({
      shopApi:
          '# Shop API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
          '| cart/add_item/check_stock | `addItem` |\n\n'
          '## Operations\n### `addItem`\nSee [a](#dropitem) and [b](#dropitem-1).\n\n'
          '### `dropItem`\nFirst drop.\n\n### `dropItem`\nSecond drop.\n',
      _cartApi: _cartApiText,
    });
    _apply(root, 'api:shop#operations/dropitem -> api:shop/cart\n');
    final shop = readDoc(root, shopApi);
    expect(
      shop,
      contains('See [a](f01_cart/API.md#dropitem) and [b](#dropitem).'),
    );
    expect(shop, contains('Second drop.'));
    expect(readDoc(root, _cartApi), contains('First drop.'));
  });

  test('a destination section of two tables takes no row', () async {
    final root = await _project({
      shopApi: _errors('Shop', ['item_not_found']),
      _cartApi:
          '${_errors('Cart', ['cart_empty'])}\n$_catalogHead${_row('cart_full')}',
    });
    expect(
      _refusal(root, 'api:shop#errors/item_not_found -> api:shop/cart\n'),
      isA<IndexFault>().having(
        (f) => f.message,
        'message',
        '$_cartApi holds two or more tables in its errors section, '
            'so it takes no row errors/item_not_found',
      ),
    );
  });

  test('a row key holding a space cannot be named in a plan line', () {
    expect(
      () => parseMovePlan(
        'glossary:terms#terms/Grounding count keep\n',
        path: 'plan.txt',
      ),
      throwsA(
        isA<IndexFault>()
            .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
            .having((f) => f.message, 'message', startsWith('plan.txt:1: ')),
      ),
    );
  });

  test('a destination with no section of the key gains it at its template place', () async {
    final root = await _project({
      shopApi: _shopApiText,
      _cartApi:
          '# Cart API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
          '| add_item/check_stock | `listItems` |\n\n'
          '## Compatibility\nNo breaking change.\n',
    });
    _apply(root, 'api:shop#operations/dropitem -> api:shop/cart\n');
    final cart = readDoc(root, _cartApi);
    expect(cart, contains('## Operations\n\n### `dropItem`\n'));
    expect(
      cart.indexOf('## Operations'),
      lessThan(cart.indexOf('## Compatibility')),
    );
  });

  test(
    'a doc that only links a moved block keeps its approval with a new stamp',
    () async {
      final root = await _project({
        shopApi: _shopApiText,
        _cartApi: _cartApiText,
        cartDomain:
            '# Cart domain\n\n## Invariants\n'
            '- **INV-1** A cart drops lines; see [drop](../API.md#dropitem).\n',
      });
      final approved = _approvedOf(root, cartDomain);
      expect(approved, isNotNull);
      _apply(root, 'api:shop#operations/dropitem -> api:shop/cart\n');
      expect(_isDraft(root, cartDomain), isFalse);
      expect(_approvedOf(root, cartDomain), allOf(isNotNull, isNot(approved)));
    },
  );

  test('a link in the destination to a block landing there takes an empty path', () async {
    final root = await _project({
      shopApi: _shopApiText,
      _cartApi:
          '# Cart API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
          '| add_item/check_stock | `listItems` |\n\n'
          '## Operations\n### `listItems`\nLists items; see [drop](../API.md#dropitem).\n',
    });
    _apply(root, 'api:shop#operations/dropitem -> api:shop/cart\n');
    expect(
      readDoc(root, _cartApi),
      contains('Lists items; see [drop](#dropitem).'),
    );
  });
}
