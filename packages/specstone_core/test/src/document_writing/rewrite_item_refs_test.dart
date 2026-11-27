// Each test name states one behavior on one line.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/document_writing/item_mentions.dart'
    show itemMentions;
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_item.dart'
    show ItemLanding, numberByPosition, planItemLandings;
import 'package:specstone_core/src/document_writing/rewrite_item_refs.dart'
    show planItemRefs;
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, fingerprintFor, spots;
import '../../helpers/nested_fixture.dart';
import '../../helpers/no_generators.dart';
import '../../helpers/write_fixture.dart';

const _payDomain = 'specs/f02_shop/f02_pay/DOMAIN.md';
const _couponFeature = 'prds/features/f02_shop/f01_cart/f01_coupon/FEATURE.md';
const _couponDomain = 'specs/f02_shop/f01_cart/f01_coupon/DOMAIN.md';
const _because = 'carts expire after 7 days, because a cart holds stock';
const _fingerprint = '3f9a1c0b7e2d';

/// Plans the item [address] names into the cart domain, numbered by
/// position, as a move plan's item line is.
List<ItemLanding> _landingsToCart(WriteSession session, String address) =>
    numberByPosition(
      session.index,
      planItemLandings(session, [
        address,
      ], destination: session.target('rulebook:shop/cart')),
    ).landings;

String _domain(List<String> items, {String frontmatter = ''}) =>
    '$frontmatter# Domain\n\n## Invariants\n\n${items.join('\n')}\n';

String _inv(int number, [String text = 'holds.']) =>
    '- **INV-$number** Rule $number $text';

/// The twelve rules a target doc holds so a landing item takes `INV-13`.
final List<String> _twelve = [for (var n = 1; n <= 12; n++) _inv(n)];

Future<Directory> _project({
  List<String> shop = const [],
  List<String> cart = const [],
  List<String> pay = const [],
  Map<String, String> extra = const {},
}) => writeNestedProject(
  extra: {
    'docs/$shopDomain': _domain(shop.isEmpty ? [_inv(1), _inv(3)] : shop),
    'docs/$cartDomain': _domain(cart.isEmpty ? [_inv(1)] : cart),
    'docs/$_payDomain': _domain(pay.isEmpty ? [_inv(1)] : pay),
    ...extra,
  },
);

ReadAnswer _move(
  Directory root,
  List<String> addresses, {
  bool dryRun = false,
}) => writeIn(
  root,
  (session) => answerMove(
    session,
    addresses,
    under: 'rulebook:shop/cart',
    dryRun: dryRun,
    generators: noGenerators,
  ),
);

/// The doc text after its frontmatter, which carries the move's marks.
String _body(Directory root, String docPath) => readDoc(
  root,
  docPath,
).replaceFirst(RegExp(r'^---\n.*?\n---\n\n', dotAll: true), '');

String _codeText(Directory root, String path) =>
    File('${root.path}/$path').readAsStringSync();

/// The one-based line of the first line of [text] holding [needle].
int _lineOf(String text, String needle) =>
    text.split('\n').indexWhere((line) => line.contains(needle)) + 1;

const _toCart = '../f01_cart/DOMAIN.md#invariants';

const _dropStockFr =
    'prds/features/f02_shop/f01_cart/us01_add_item/fr02_drop_stock.md';
const _checkStock = 'fr:shop/cart/add_item/check_stock';

/// The path from the shop domain to the folder of the `add_item` FRs.
const _toAddItem = '../../prds/features/f02_shop/f01_cart/us01_add_item';

/// An FR whose edge cases are Case 1 to [count], its rationale [rationale].
String _frOf(int count, {String rationale = 'Stock is finite.'}) =>
    '---\ntraced_from:\n  - S1\nverify_method: test\n---\n\n'
    '# Requirement\n\n## Statement\n$checkStockStatement\n\n'
    '## Edge cases\n'
    '${[for (var n = 1; n <= count; n++) '$n. E0$n — Case $n → refused.'].join('\n')}\n\n'
    '## Rationale\n$rationale\n\n'
    '## Verification\nTest: a case is refused.\n';

/// The `mentions` lines of [answer].
List<String> _mentionLinesOf(ReadAnswer answer) => [
  for (final line in answer.text.split('\n'))
    if (line.startsWith('mentions ')) line,
];

/// Moves the edge case [id] of `check_stock` into `drop_stock`.
ReadAnswer _moveEdgeCase(Directory root, String id) => writeIn(
  root,
  (session) => answerMove(
    session,
    ['$_checkStock#$id'],
    under: 'fr:shop/cart/add_item/drop_stock',
    generators: noGenerators,
  ),
);

void main() {
  test('renumbered edge case links and ranges follow the new id', () async {
    const check = '$_toAddItem/fr01_check_stock.md#edge-cases';
    const drop = '$_toAddItem/fr02_drop_stock.md#edge-cases';
    final root = await _project(
      shop: [
        _inv(1, 'as [E03]($check) gives.'),
        _inv(3, 'as [E01]($check) to [E04]($check) give.'),
      ],
      extra: {
        'docs/$cartAddFr': _frOf(4, rationale: 'See [E04](#edge-cases).'),
        'docs/$_dropStockFr': _frOf(1),
      },
    );
    _moveEdgeCase(root, 'E02');
    expect(
      _body(root, shopDomain),
      _domain([
        _inv(1, 'as [E02]($check) gives.'),
        _inv(
          3,
          'as [E01]($check), [E02]($drop), [E02]($check) to [E03]($check) give.',
        ),
      ]),
    );
    expect(readDoc(root, cartAddFr), contains('See [E03](#edge-cases).\n'));
  });

  test('sure bare mention of a moved item becomes an item link', () async {
    const toCart = '../f01_cart/DOMAIN.md#invariants';
    final root = await _project(
      shop: [_inv(3), _inv(4, 'follows INV-3 of this doc.')],
      cart: _twelve,
      pay: [
        _inv(
          1,
          'follows [rulebook:shop](../DOMAIN.md) INV-3 and `rulebook:shop` INV-3.',
        ),
      ],
    );
    final answer = _move(root, ['rulebook:shop#INV-3']);
    expect(
      _body(root, shopDomain),
      _domain([
        _inv(4, 'follows [INV-13](f01_cart/DOMAIN.md#invariants) of this doc.'),
      ]),
    );
    expect(
      _body(root, _payDomain),
      _domain([
        _inv(
          1,
          'follows [rulebook:shop](../DOMAIN.md) [INV-13]($toCart) '
          'and `rulebook:shop` [INV-13]($toCart).',
        ),
      ]),
    );
    expect(answer.json['mentions'], isEmpty);
  });

  test("a bare ID the rewrite leaves on a renumbered edge case's own line prints a mentions line", () async {
    final root = await _project(
      extra: {
        'docs/$cartAddFr': _frOf(3)
            .replaceFirst('3. E03 — Case 3', '3. E03 — Case 3, as E03 reads'),
        'docs/$_dropStockFr': _frOf(1),
      },
    );
    final answer = _moveEdgeCase(root, 'E02');
    final check = readDoc(root, cartAddFr);
    expect(check, contains('2. E02 — Case 3, as E03 reads'));
    expect(_mentionLinesOf(answer), [
      'mentions $cartAddFr:${_lineOf(check, 'as E03 reads')} E03',
    ]);
  });

  test('a bare ID inside a moved item that names a source edge case renumbered in place becomes an item link to its new number', () async {
    final root = await _project(
      extra: {
        'docs/$cartAddFr': _frOf(3)
            .replaceFirst('Case 1 →', 'Case 1, before E03 →'),
        'docs/$_dropStockFr': _frOf(1),
      },
    );
    final answer = _moveEdgeCase(root, 'E01');
    expect(
      readDoc(root, _dropStockFr),
      contains(
        '2. E02 — Case 1, before [E02](fr01_check_stock.md#edge-cases) → refused.',
      ),
    );
    expect(_mentionLinesOf(answer), isEmpty);
  });

  test('bare id in a code span stays a mentions line', () async {
    final root = await _project(
      pay: [_inv(1, 'cites `$_checkStock#E02` and `$_checkStock#E03`.')],
      extra: {'docs/$cartAddFr': _frOf(3), 'docs/$_dropStockFr': _frOf(1)},
    );
    final payBefore = readDoc(root, _payDomain);
    final answer = _moveEdgeCase(root, 'E02');
    final line = _lineOf(payBefore, 'cites');
    expect(
      answer.text,
      allOf(
        contains('mentions $_payDomain:$line $_checkStock#E02\n'),
        contains('mentions $_payDomain:$line $_checkStock#E03\n'),
      ),
    );
    expect(readDoc(root, _payDomain), payBefore);
  });

  test("a bare ID inside a moved item that names an item that stays, or one the call renumbers, becomes an item link to that item's place", () async {
    final root = await _project(
      shop: [_inv(3, 'as INV-4 gives, and see INV-7.'), _inv(4), _inv(7)],
      cart: _twelve.take(7).toList(),
    );
    final answer = _move(root, ['rulebook:shop#INV-3', 'rulebook:shop#INV-7']);
    expect(
      _body(root, cartDomain),
      _domain([
        ..._twelve.take(7),
        '- **INV-8** Rule 3 as [INV-4](../DOMAIN.md#invariants) gives, and see [INV-9](#invariants).',
        '- **INV-9** Rule 7 holds.',
      ]),
    );
    expect(answer.json['mentions'], isEmpty);
  });

  group('an item link that names a moved item follows it', () {
    test('a link from another doc names the target doc and keeps its anchor and ID', () async {
      final root = await _project(
        pay: [_inv(1, 'follows [INV-3](../DOMAIN.md#invariants).')],
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, _payDomain),
        _domain([_inv(1, 'follows [INV-3]($_toCart).')]),
      );
    });

    test('a link takes the new ID of an item that was renumbered', () async {
      final root = await _project(
        cart: _twelve,
        pay: [_inv(1, 'follows [INV-3](../DOMAIN.md#invariants).')],
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, _payDomain),
        _domain([_inv(1, 'follows [INV-13]($_toCart).')]),
      );
    });

    test('a link in the source doc reaches the target doc and a link inside the moved item to an item that stays reaches the source doc', () async {
      final root = await _project(
        shop: [
          _inv(3, 'holds, with [INV-4](#invariants).'),
          _inv(4, 'holds, after [INV-3](#invariants).'),
        ],
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, shopDomain),
        _domain([
          _inv(4, 'holds, after [INV-3](f01_cart/DOMAIN.md#invariants).'),
        ]),
      );
      expect(
        _body(root, cartDomain),
        _domain([
          _inv(1),
          _inv(3, 'holds, with [INV-4](../DOMAIN.md#invariants).'),
        ]),
      );
    });

    test('a link in the target doc to the moved item becomes a link into its own doc', () async {
      final root = await _project(
        cart: _twelve.take(2).toList()
          ..add(_inv(5, 'follows [INV-3](../DOMAIN.md#invariants).')),
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, cartDomain),
        _domain([
          _inv(1),
          _inv(2),
          _inv(5, 'follows [INV-3](#invariants).'),
          _inv(3),
        ]),
      );
    });

    test('a link inside a moved item to another moved item stays a link into the target doc, with the new ID', () async {
      final root = await _project(
        shop: [_inv(3, 'holds, with [INV-7](#invariants).'), _inv(7), _inv(8)],
        cart: _twelve,
      );
      _move(root, ['rulebook:shop#INV-3', 'rulebook:shop#INV-7']);
      expect(
        _body(root, cartDomain),
        _domain([
          ..._twelve,
          '- **INV-13** Rule 3 holds, with [INV-14](#invariants).',
          '- **INV-14** Rule 7 holds.',
        ]),
      );
    });

    test('a link inside a moved item to a third doc is rebased to reach it from the target doc', () async {
      final root = await _project(
        shop: [
          _inv(
            3,
            'holds, see [pay](f02_pay/DOMAIN.md#invariants) and '
            '[INV-1](f02_pay/DOMAIN.md#invariants).',
          ),
        ],
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, cartDomain),
        _domain([
          _inv(1),
          _inv(
            3,
            'holds, see [pay](../f02_pay/DOMAIN.md#invariants) and '
            '[INV-1](../f02_pay/DOMAIN.md#invariants).',
          ),
        ]),
      );
    });

    test('a reference-style link and its definition follow the item', () async {
      final root = await _project(
        cart: _twelve,
        pay: [
          _inv(1, 'follows [INV-3][r].'),
          '',
          '[r]: ../DOMAIN.md#invariants',
        ],
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, _payDomain),
        _domain([_inv(1, 'follows [INV-13][r].'), '', '[r]: $_toCart']),
      );
    });

    test('a definition that serves a moved and a kept item stays and is listed', () async {
      final root = await _project(
        pay: [
          _inv(1, 'follows [INV-3][r] and [INV-1][r].'),
          '',
          '[r]: ../DOMAIN.md#invariants',
        ],
      );
      final payBefore = readDoc(root, _payDomain);
      final answer = _move(root, ['rulebook:shop#INV-3']);
      expect(readDoc(root, _payDomain), payBefore);
      expect(
        answer.text,
        contains(
          'mentions $_payDomain:${_lineOf(payBefore, '[r]:')} [r]: ../DOMAIN.md#invariants\n',
        ),
      );

      final sharedRoot = await _project(
        pay: [
          _inv(1, 'follows [INV-3][r] and see [the rules][r].'),
          '',
          '[r]: ../DOMAIN.md#invariants',
        ],
      );
      final sharedBefore = readDoc(sharedRoot, _payDomain);
      final sharedAnswer = _move(sharedRoot, ['rulebook:shop#INV-3']);
      expect(readDoc(sharedRoot, _payDomain), sharedBefore);
      expect(
        sharedAnswer.text,
        contains(
          'mentions $_payDomain:${_lineOf(sharedBefore, '[r]:')} [r]: ../DOMAIN.md#invariants\n',
        ),
        reason: 'a definition shared by an item link and another link',
      );
    });

    test('a reference-style link inside a moved item becomes an inline link that resolves from the target doc', () async {
      final root = await _project(
        shop: [
          _inv(3, 'holds, see [pay][p].'),
          '',
          '[p]: f02_pay/DOMAIN.md#invariants',
        ],
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, cartDomain),
        contains('holds, see [pay](../f02_pay/DOMAIN.md#invariants).'),
      );
    });

    test('a ./ link inside a moved item that resolves the same from the target doc keeps its spelling, item link and plain link alike', () async {
      final root = await _project(
        shop: [_inv(1), _inv(4)],
        pay: [
          _inv(
            5,
            'with [INV-4](./../DOMAIN.md#invariants), '
            '[shop](./../DOMAIN.md) and [rules](./../DOMAIN.md#invariants).',
          ),
        ],
      );
      writeIn(
        root,
        (session) => answerMove(
          session,
          ['rulebook:shop/pay#INV-5'],
          under: 'rulebook:shop/cart',
          generators: noGenerators,
        ),
      );
      expect(
        _body(root, cartDomain),
        contains(
          'with [INV-4](./../DOMAIN.md#invariants), '
          '[shop](./../DOMAIN.md) and [rules](./../DOMAIN.md#invariants).',
        ),
      );
    });

    test('a definition the move leaves unused is removed, one another link still uses stays', () async {
      final text = _inv(3, 'holds, see [pay][p].');
      final root = await _project(
        shop: [text, '', '[p]: f02_pay/DOMAIN.md#invariants'],
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(_body(root, shopDomain), isNot(contains('[p]:')));
      final shared = await _project(
        shop: [
          text,
          _inv(4, 'holds, see [pay][p].'),
          '',
          '[p]: f02_pay/DOMAIN.md#invariants',
        ],
      );
      _move(shared, ['rulebook:shop#INV-3']);
      expect(
        _body(shared, shopDomain),
        contains('[p]: f02_pay/DOMAIN.md#invariants'),
      );
    });

    test('a reference listed from inside a moved item is placed in the target doc, on its own line', () async {
      const text = 'holds, see [pay][p].';
      final root = await _project(
        shop: [
          _inv(3, text),
          _inv(4, text),
          '',
          '[p]: f02_pay/DOMAIN.md#invariants "Pay"',
        ],
      );
      final answer = _move(root, ['rulebook:shop#INV-4']);
      final cart = readDoc(root, cartDomain);
      expect(
        answer.text.split('\n').where((line) => line.startsWith('mentions ')),
        ['mentions $cartDomain:${_lineOf(cart, '[pay][p]')} [pay][p]'],
      );
    });

    test('a reference-style link inside a moved item whose destination resolves the same from the target doc becomes an inline link with that destination', () async {
      final root = await _project(
        pay: [
          _inv(1),
          _inv(5, 'holds, see [shop][s].'),
          '',
          '[s]: ../DOMAIN.md#invariants',
        ],
      );
      writeIn(
        root,
        (session) => answerMove(
          session,
          ['rulebook:shop/pay#INV-5'],
          under: 'rulebook:shop/cart',
          generators: noGenerators,
        ),
      );
      expect(
        _body(root, cartDomain),
        contains('holds, see [shop](../DOMAIN.md#invariants).'),
      );
      expect(_body(root, _payDomain), isNot(contains('[s]:')));
    });

    test('a reference-style link inside a moved item whose path stays as written, or whose destination is a web address, becomes an inline link with that destination', () async {
      final root = await _project(
        pay: [
          _inv(1),
          _inv(5, 'holds, see [odd][o] and [site][w].'),
          '',
          '[o]: ../a%2Fb.md',
          '[w]: https://example.com/rules',
        ],
      );
      writeIn(
        root,
        (session) => answerMove(
          session,
          ['rulebook:shop/pay#INV-5'],
          under: 'rulebook:shop/cart',
          generators: noGenerators,
        ),
      );
      expect(
        _body(root, cartDomain),
        contains(
          'holds, see [odd](../a%2Fb.md) and [site](https://example.com/rules).',
        ),
      );
    });

    test('a ./ link inside an item moved to a doc in the same folder keeps every byte, and a reference-style one becomes an inline link with the same destination', () async {
      final root = await _project(
        shop: [
          _inv(1),
          _inv(
            3,
            'with [INV-1](./f01_cart/DOMAIN.md#invariants), '
            '[cart](./f01_cart/DOMAIN.md) and [rules][r].',
          ),
          '',
          '[r]: ./f01_cart/DOMAIN.md#invariants',
        ],
        extra: {
          '.specstone/templates/api.yaml':
              'sections:\n  - id: invariants\n    header: Invariants\n'
              '    prefix_id: INV-\n',
        },
      );
      writeIn(
        root,
        (session) => answerMove(
          session,
          ['rulebook:shop#INV-3'],
          under: 'api:shop',
          generators: noGenerators,
        ),
      );
      expect(
        _body(root, shopApi),
        contains(
          'with [INV-1](./f01_cart/DOMAIN.md#invariants), '
          '[cart](./f01_cart/DOMAIN.md) and '
          '[rules](./f01_cart/DOMAIN.md#invariants).',
        ),
      );
    });

    test('a reference-style link left in the source doc whose definition moves with an item becomes an inline link, and a definition the move leaves unused is removed from the target doc', () async {
      List<String> shop(String moved) => [
        '### INV-5 — Cart expiry',
        '- A cart expires$moved.',
        '',
        '[p]: f02_pay/DOMAIN.md#invariants',
        '',
        '### INV-6 — Other',
        '- Stays, see [pay][p].',
      ];
      final root = await _project(shop: shop(', see [pay][p]'));
      _move(root, ['rulebook:shop#INV-5']);
      expect(
        _body(root, shopDomain),
        contains('- Stays, see [pay](f02_pay/DOMAIN.md#invariants).'),
      );
      expect(
        _body(root, cartDomain),
        contains('[p]: ../f02_pay/DOMAIN.md#invariants'),
      );
      final unused = await _project(shop: shop(''));
      _move(unused, ['rulebook:shop#INV-5']);
      expect(
        _body(unused, shopDomain),
        contains('- Stays, see [pay](f02_pay/DOMAIN.md#invariants).'),
      );
      expect(_body(unused, cartDomain), isNot(contains('[p]:')));
    });

    test('a reference-style item link inside a moved item whose definition stays becomes an inline link, and the definition left unused is removed', () async {
      final root = await _project(
        shop: [_inv(1), _inv(3, 'follows [INV-1][r].'), '', '[r]: #invariants'],
      );
      final answer = _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, cartDomain),
        _domain([
          _inv(1),
          _inv(3, 'follows [INV-1](../DOMAIN.md#invariants).'),
        ]),
      );
      expect(_body(root, shopDomain), _domain([_inv(1)]));
      expect(answer.text, isNot(contains('[r]:')));
    });

    test('a reference-style item link left in the source doc whose definition moves with an item becomes an inline link', () async {
      final root = await _project(
        shop: [
          '### INV-1 — First',
          '- Holds.',
          '',
          '### INV-5 — Cart expiry',
          '- A cart expires.',
          '',
          '[r]: #invariants',
          '',
          '### INV-6 — Other',
          '- Stays, see [INV-1][r].',
        ],
      );
      _move(root, ['rulebook:shop#INV-5']);
      expect(
        _body(root, shopDomain),
        contains('- Stays, see [INV-1](#invariants).'),
      );
      expect(_body(root, cartDomain), isNot(contains('[r]:')));
    });

    test('an indented definition of a renumbered item takes the new ID at its label', () async {
      final root = await _project(
        cart: _twelve,
        pay: [
          _inv(1, 'follows [INV-3][].'),
          '',
          '  [INV-3]: ../DOMAIN.md#invariants',
        ],
      );
      _move(root, ['rulebook:shop#INV-3']);
      final pay = _body(root, _payDomain);
      expect(pay, contains('follows [INV-13][].'));
      expect(pay, contains('  [INV-13]: $_toCart\n'));
    });

    test('a definition the move leaves unused is removed at its own line, a code line of the same text kept', () async {
      const definition = '[p]: f02_pay/DOMAIN.md#invariants';
      final root = await _project(
        shop: [
          _inv(3, 'holds, see [pay][p].'),
          '',
          '```',
          definition,
          '```',
          '',
          definition,
        ],
      );
      _move(root, ['rulebook:shop#INV-3']);
      final shop = _body(root, shopDomain);
      expect(shop, contains('```\n$definition\n```'));
      expect(definition.allMatches(shop), hasLength(1));
    });

    test('a listed definition in a doc the move leaves unwritten is placed on its file line, though a layout would shift it', () async {
      final root = await _project(
        extra: {
          'docs/$_payDomain':
              '# Domain\n\n## Invariants\n'
              '${_inv(1, 'follows [INV-3][r] and [INV-1][r].')}\n\n'
              '[r]: ../DOMAIN.md#invariants\n',
        },
      );
      final payBefore = readDoc(root, _payDomain);
      final answer = _move(root, ['rulebook:shop#INV-3']);
      expect(readDoc(root, _payDomain), payBefore);
      expect(
        answer.text,
        contains(
          'mentions $_payDomain:${_lineOf(payBefore, '[r]:')} [r]: ../DOMAIN.md#invariants\n',
        ),
      );
    });

    test('a reference-style link inside a moved item finds its definition by the label fold markdown reads', () async {
      final root = await _project(
        shop: [
          _inv(3, 'holds, see [pay][MAẞE].'),
          '',
          '[masse]: f02_pay/DOMAIN.md#invariants',
        ],
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, cartDomain),
        contains('holds, see [pay](../f02_pay/DOMAIN.md#invariants).'),
      );
    });

    test('a range of reference-style item links inside a moved item is listed as it reads after the write', () async {
      final root = await _project(
        shop: [
          _inv(1),
          _inv(2),
          _inv(3, 'Covers [INV-1][a] to [INV-2][b].'),
          '',
          '[a]: #invariants',
          '[b]: #invariants',
        ],
      );
      final answer = _move(root, ['rulebook:shop#INV-3']);
      const written =
          '[INV-1](../DOMAIN.md#invariants) to [INV-2](../DOMAIN.md#invariants)';
      final cart = readDoc(root, cartDomain);
      expect(cart, contains('Covers $written.'));
      expect(
        answer.text.split('\n').where((line) => line.startsWith('mentions ')),
        ['mentions $cartDomain:${_lineOf(cart, 'Covers')} $written'],
      );
    });

    test('a range of reference-style item links stays and is listed', () async {
      final root = await _project(
        shop: [_inv(2), _inv(3), _inv(4), _inv(5)],
        pay: [
          _inv(1, 'Covers [INV-2][a] to [INV-5][b].'),
          '',
          '[a]: ../DOMAIN.md#invariants',
          '[b]: ../DOMAIN.md#invariants',
        ],
      );
      final payBefore = readDoc(root, _payDomain);
      final answer = _move(root, ['rulebook:shop#INV-3']);
      expect(readDoc(root, _payDomain), payBefore);
      expect(
        answer.text,
        contains(
          'mentions $_payDomain:${_lineOf(payBefore, 'Covers')} '
          '[INV-2][a] to [INV-5][b]\n',
        ),
      );
    });

    test(
      'the mentions of a plan made once equal those of a fresh one',
      () async {
        final root = await _project(
          shop: [_inv(3), _inv(4, 'follows INV-3 of this doc.')],
        );
        writeIn(root, (session) {
          final landings = _landingsToCart(session, 'rulebook:shop#INV-3');
          final refs = planItemRefs(session, landings);
          expect(
            itemMentions(session, landings, refs: refs),
            itemMentions(session, landings),
          );
        });
      },
    );

    test('a rewritten typed doc is laid out as format lays it out', () async {
      final root = await _project(
        extra: {
          'docs/$_payDomain':
              '# Domain\n\n\n\n## Invariants\n\n\n'
              '- **INV-1** Rule 1 follows [INV-3](../DOMAIN.md#invariants).\n\n\n',
        },
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, _payDomain),
        _domain([_inv(1, 'follows [INV-3]($_toCart).')]),
      );
    });

    test('a link keeps the title written after its destination', () async {
      final root = await _project(
        pay: [_inv(1, 'follows [INV-3](../DOMAIN.md#invariants "the rule").')],
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, _payDomain),
        _domain([_inv(1, 'follows [INV-3]($_toCart "the rule").')]),
      );
    });

    test(
      'a doc with CRLF line ends keeps them and takes the new link',
      () async {
        final root = await _project(
          pay: [_inv(1, 'follows [INV-3](../DOMAIN.md#invariants).')],
        );
        final crlf = readDoc(root, _payDomain).replaceAll('\n', '\r\n');
        docFile(root, _payDomain).writeAsStringSync(crlf);
        _move(root, ['rulebook:shop#INV-3']);
        final pay = readDoc(root, _payDomain);
        expect(pay, contains('follows [INV-3]($_toCart).\r\n'));
        expect(pay.replaceAll('\r\n', ''), isNot(contains('\n')));
      },
    );

    test('an edit refuses a doc that changed since the plan', () async {
      final root = await _project(
        pay: [_inv(1, 'follows [INV-3](../DOMAIN.md#invariants).')],
      );
      writeIn(root, (session) {
        final edits = planItemRefs(
          session,
          _landingsToCart(session, 'rulebook:shop#INV-3'),
        ).edits;
        expect(
          () => edits[_payDomain]!('# Domain\n\nA late edit.\n'),
          throwsA(
            isA<RenderFault>().having(
              (fault) => fault.message,
              'message',
              'cannot write $_payDomain: changed since the move was planned',
            ),
          ),
        );
      });
    });

    test('a section link whose text is no item ID keeps its text', () async {
      final root = await _project(
        pay: [_inv(1, 'see the [invariants](../DOMAIN.md#invariants).')],
      );
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, _payDomain),
        _domain([_inv(1, 'see the [invariants](../DOMAIN.md#invariants).')]),
      );
    });

    test('a link that names an item that stays keeps its text', () async {
      final root = await _project(
        pay: [_inv(1, 'follows [INV-1](../DOMAIN.md#invariants).')],
      );
      final before = _body(root, _payDomain);
      _move(root, ['rulebook:shop#INV-3']);
      expect(_body(root, _payDomain), before);
    });
  });

  group('a range that holds a moved item', () {
    const prose = 'Covers [INV-2](#invariants) to [INV-5](#invariants).';

    List<String> shop(String text) => [
      _inv(2),
      _inv(3),
      _inv(4),
      _inv(5),
      _inv(6, text),
    ];

    test('splits into the links and ranges that name the same items', () async {
      final root = await _project(shop: shop(prose));
      _move(root, ['rulebook:shop#INV-3']);
      expect(
        _body(root, shopDomain),
        _domain([
          _inv(2),
          _inv(4),
          _inv(5),
          _inv(
            6,
            'Covers [INV-2](#invariants), [INV-3](f01_cart/DOMAIN.md#invariants), '
            '[INV-4](#invariants) to [INV-5](#invariants).',
          ),
        ]),
      );
    });

    test('keeps its text when none of its items moved', () async {
      final root = await _project(
        shop: [..._twelve.take(5), _inv(6, prose), _inv(9)],
      );
      _move(root, ['rulebook:shop#INV-9']);
      expect(
        _body(root, shopDomain),
        _domain([..._twelve.take(5), _inv(6, prose)]),
      );
    });

    test(
      'a range and the same link alone on one line each get their own edit',
      () async {
        final root = await _project(
          shop: shop(
            '[INV-2](#invariants) to [INV-4](#invariants) and [INV-3](#invariants).',
          ),
        );
        _move(root, ['rulebook:shop#INV-3']);
        expect(
          _body(root, shopDomain),
          contains(
            '[INV-2](#invariants), [INV-3](f01_cart/DOMAIN.md#invariants), '
            '[INV-4](#invariants) and [INV-3](f01_cart/DOMAIN.md#invariants).',
          ),
        );
      },
    );

    test(
      'a range whose end links carry titles splits and keeps each title',
      () async {
        final root = await _project(
          shop: shop(
            'Covers [INV-2](#invariants "a") to [INV-5](#invariants "b").',
          ),
        );
        _move(root, ['rulebook:shop#INV-3']);
        expect(
          _body(root, shopDomain),
          contains(
            'Covers [INV-2](#invariants "a"), '
            '[INV-3](f01_cart/DOMAIN.md#invariants), '
            '[INV-4](#invariants) to [INV-5](#invariants "b").',
          ),
        );
      },
    );

    test(
      'a range of two moved items keeps one range into the target doc',
      () async {
        final root = await _project(
          shop: shop('[INV-3](#invariants) to [INV-4](#invariants).'),
        );
        _move(root, ['rulebook:shop#INV-3', 'rulebook:shop#INV-4']);
        expect(
          _body(root, shopDomain),
          contains(
            '[INV-3](f01_cart/DOMAIN.md#invariants) to '
            '[INV-4](f01_cart/DOMAIN.md#invariants).',
          ),
        );
      },
    );
  });

  group('references that are no item link', () {
    test('an override line and its overrides entry name the target doc and the new ID, the fingerprint kept', () async {
      final root = await _project(
        shop: [_inv(1), _inv(3)],
        cart: _twelve,
        extra: {
          'docs/$_couponFeature': '# Coupon\n',
          'docs/$_couponDomain': _domain(
            [
              _inv(5),
              '- Overrides: [INV-3](../../DOMAIN.md#invariants) — $_because',
            ],
            frontmatter:
                '---\noverrides:\n  - rulebook:shop#INV-3 $_fingerprint\n---\n\n',
          ),
        },
      );
      _move(root, ['rulebook:shop#INV-3']);
      final coupon = readDoc(root, _couponDomain);
      expect(
        coupon,
        contains(
          '- Overrides: [INV-13](../DOMAIN.md#invariants) — $_because\n',
        ),
      );
      expect(
        coupon,
        contains('overrides:\n  - rulebook:shop/cart#INV-13 $_fingerprint\n'),
      );
      expect(coupon, isNot(contains('rulebook:shop#INV-3')));
    });

    test('an overrides entry that matched a renumbered item takes the landed fingerprint and checks clean, while a stale one keeps its value and stays suspect', () async {
      Future<List<Map<String, Object>>> suspects(Directory root) async => [
        for (final finding in (await checkOf(
          root,
          docPath: _couponDomain,
        )).findings)
          if (finding.kind == FindingKind.suspect) finding.toJson(),
      ];
      Future<Directory> coupon(String fingerprint) => _project(
        shop: [_inv(1), _inv(3)],
        cart: _twelve,
        extra: {
          'docs/$_couponFeature': '# Coupon\n',
          'docs/$_couponDomain': _domain(
            [
              _inv(5),
              '- Overrides: [INV-3](../../DOMAIN.md#invariants) — $_because',
            ],
            frontmatter:
                '---\noverrides:\n  - rulebook:shop#INV-3 $fingerprint\n---\n\n',
          ),
        },
      );

      final matched = await coupon(fingerprintFor(_inv(3)));
      expect(await suspects(matched), isEmpty);
      _move(matched, ['rulebook:shop#INV-3']);
      expect(
        readDoc(matched, _couponDomain),
        contains(
          'overrides:\n  - rulebook:shop/cart#INV-13 '
          '${fingerprintFor(_inv(13).replaceFirst('Rule 13', 'Rule 3'))}\n',
        ),
      );
      expect(await suspects(matched), isEmpty);

      final stale = await coupon(_fingerprint);
      expect(await suspects(stale), hasLength(1));
      _move(stale, ['rulebook:shop#INV-3']);
      expect(
        readDoc(stale, _couponDomain),
        contains('overrides:\n  - rulebook:shop/cart#INV-13 $_fingerprint\n'),
      );
      expect(
        [
          for (final suspect in await suspects(stale))
            (suspect['link'], suspect['recorded']),
        ],
        [('rulebook:shop/cart#INV-13', _fingerprint)],
      );
    });

    test(
      'a dry run of a renumbering move stamps no overrides fingerprint',
      () async {
        final root = await _project(
          shop: [_inv(1), _inv(3)],
          cart: _twelve,
          extra: {
            'docs/$_couponFeature': '# Coupon\n',
            'docs/$_couponDomain': _domain(
              [
                _inv(5),
                '- Overrides: [INV-3](../../DOMAIN.md#invariants) — $_because',
              ],
              frontmatter:
                  '---\noverrides:\n  - rulebook:shop#INV-3 '
                  '${fingerprintFor(_inv(3))}\n---\n\n',
            ),
          },
        );
        final before = readDoc(root, _couponDomain);
        _move(root, ['rulebook:shop#INV-3'], dryRun: true);
        expect(readDoc(root, _couponDomain), before);
      },
    );

    test('a confirmed entry that names no item keeps its text', () async {
      final root = await _project();
      final before = readDoc(root, cartAddFr);
      _move(root, ['rulebook:shop#INV-3']);
      expect(readDoc(root, cartAddFr), before);
    });

    test('a task ref of the moved item leaves the source and joins the target under the new ID', () async {
      final root = await _project(
        shop: [_inv(3), _inv(4)],
        cart: _twelve,
        extra: {
          'docs/$shopDomain': _domain(
            [_inv(3), _inv(4)],
            frontmatter: '---\ntasks:\n  - INV-3:ENG-42\n  - INV-4:ENG-43\n  - ENG-44\n---\n\n',
          ),
        },
      );
      _move(root, ['rulebook:shop#INV-3']);
      final shop = readDoc(root, shopDomain);
      expect(shop, contains('tasks:\n  - INV-4:ENG-43\n  - ENG-44\n'));
      expect(shop, isNot(contains('ENG-42')));
      expect(
        readDoc(root, cartDomain),
        contains('tasks:\n  - INV-13:ENG-42\n'),
      );
    });

    test('a doc the rewrite changes, but no source or target, keeps its approval and passes check', () async {
      final root = await _project(
        pay: [_inv(1, 'follows [INV-3](../DOMAIN.md#invariants).')],
      );
      final approvedBefore = RegExp(
        r'^approved: "([^"]+)"$',
        multiLine: true,
      ).firstMatch(readDoc(root, _payDomain))?.group(1);
      _move(root, ['rulebook:shop#INV-3']);
      final pay = readDoc(root, _payDomain);
      expect(pay, isNot(contains('draft: true')));
      expect(pay, contains('approved: "'));
      expect(approvedBefore, isNotNull);
      expect(
        spots(await checkOf(root), FindingKind.approvalStale),
        isNot(contains(_payDomain)),
      );
    });
  });

  group('a bare ID', () {
    const mention = 'mentions ';

    test('a doc address with the ID in a code comment and in an agent file prints a mentions line and keeps the file bytes', () async {
      const code = '// Enforces `rulebook:shop#INV-3`.\n';
      const agent = 'Read `rulebook:shop#INV-3` first.\n';
      final root = await _project(
        extra: {'app/lib/cart.dart': code, 'CLAUDE.md': agent},
      );
      final answer = _move(root, ['rulebook:shop#INV-3']);
      expect(_codeText(root, 'app/lib/cart.dart'), code);
      expect(_codeText(root, 'CLAUDE.md'), agent);
      expect(
        answer.text,
        allOf(
          contains('${mention}CLAUDE.md:1 rulebook:shop#INV-3\n'),
          contains('${mention}app/lib/cart.dart:1 rulebook:shop#INV-3\n'),
        ),
      );
    });

    test('a bare ID in another doc with no doc address right before it prints no mentions line', () async {
      final root = await _project(
        pay: [_inv(1, 'see INV-3 of `rulebook:shop`.')],
      );
      final answer = _move(root, ['rulebook:shop#INV-3']);
      expect(answer.text, isNot(contains(_payDomain)));
      expect(answer.json['mentions'], isEmpty);
    });

    test('a doc address with the ID inside a moved item prints the same one mentions line when the call renumbers the item', () async {
      final root = await _project(
        shop: [_inv(3, 'see `rulebook:shop#INV-7`.'), _inv(7)],
        cart: _twelve,
      );
      final answer = _move(root, [
        'rulebook:shop#INV-3',
        'rulebook:shop#INV-7',
      ]);
      final line = _lineOf(readDoc(root, cartDomain), 'see `rulebook:shop');
      expect(answer.text.split('\n').where((l) => l.startsWith(mention)), [
        '$mention$cartDomain:$line rulebook:shop#INV-7',
      ]);
      expect(answer.json['mentions'], hasLength(1));
    });

    test('a bare ID inside a moved item that names a co-moved item keeping its ID prints none, while the address form prints one', () async {
      final root = await _project(
        shop: [_inv(3, 'see INV-7 and `rulebook:shop#INV-7`.'), _inv(7)],
      );
      final answer = _move(root, [
        'rulebook:shop#INV-3',
        'rulebook:shop#INV-7',
      ]);
      final line = _lineOf(readDoc(root, cartDomain), 'see INV-7');
      expect(answer.text.split('\n').where((l) => l.startsWith(mention)), [
        '$mention$cartDomain:$line rulebook:shop#INV-7',
      ]);
    });

    test('an ID after a link whose doc type lacks its prefix is judged in the doc that holds it', () async {
      final root = await _project(
        shop: [_inv(3), _inv(4, 'follows [api:shop](API.md) INV-3 here.')],
        pay: [_inv(1, 'follows [api:shop](../API.md) INV-3 here.')],
      );
      final payBefore = readDoc(root, _payDomain);
      final answer = _move(root, ['rulebook:shop#INV-3']);
      expect(
        readDoc(root, shopDomain),
        contains(
          'follows [api:shop](API.md) '
          '[INV-3](f01_cart/DOMAIN.md#invariants) here.',
        ),
      );
      expect(readDoc(root, _payDomain), payBefore);
      expect(answer.json['mentions'], isEmpty);
    });

    test('a dry run prints the mentions lines a real move prints and writes no file', () async {
      final pay = [_inv(1, 'cites `rulebook:shop#INV-3`.')];
      final twin = await _project(pay: pay);
      final written = _move(twin, ['rulebook:shop#INV-3']);
      final root = await _project(pay: pay);
      final before = readDoc(root, _payDomain);
      final answer = _move(root, ['rulebook:shop#INV-3'], dryRun: true);
      expect(answer.json['mentions'], written.json['mentions']);
      expect(
        answer.text,
        contains(
          '$mention$_payDomain:${_lineOf(before, 'cites')} rulebook:shop#INV-3\n',
        ),
      );
      expect(answer.text, endsWith('dry run: nothing moved\n'));
      expect(readDoc(root, _payDomain), before);
    });
  });
}
