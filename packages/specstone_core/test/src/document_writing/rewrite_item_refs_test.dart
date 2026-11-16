// Each test name states one behavior on one line.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_item.dart'
    show planItemMove;
import 'package:specstone_core/src/document_writing/rewrite_item_refs.dart'
    show itemMentions, itemRefEdits, planItemRefs;
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, spots;
import '../../helpers/nested_fixture.dart';
import '../../helpers/write_fixture.dart';

const _payDomain = 'specs/f02_shop/f02_pay/DOMAIN.md';
const _couponFeature = 'prds/features/f02_shop/f01_cart/f01_coupon/FEATURE.md';
const _couponDomain = 'specs/f02_shop/f01_cart/f01_coupon/DOMAIN.md';
const _because = 'carts expire after 7 days, because a cart holds stock';
const _fingerprint = '3f9a1c0b7e2d';

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
  (session) =>
      answerMove(session, addresses, under: 'domain:shop/cart', dryRun: dryRun),
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

void main() {
  group('an item link that names a moved item follows it', () {
    test('a link from another doc names the target doc and keeps its anchor and ID', () async {
      final root = await _project(
        pay: [_inv(1, 'follows [INV-3](../DOMAIN.md#invariants).')],
      );
      _move(root, ['domain:shop#INV-3']);
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
      _move(root, ['domain:shop#INV-3']);
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
      _move(root, ['domain:shop#INV-3']);
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
      _move(root, ['domain:shop#INV-3']);
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
      _move(root, ['domain:shop#INV-3', 'domain:shop#INV-7']);
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
      _move(root, ['domain:shop#INV-3']);
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
      _move(root, ['domain:shop#INV-3']);
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
      final answer = _move(root, ['domain:shop#INV-3']);
      expect(readDoc(root, _payDomain), payBefore);
      expect(
        answer.text,
        contains(
          'mentions $_payDomain:${_lineOf(payBefore, '[r]:')} [r]: ../DOMAIN.md#invariants\n',
        ),
      );
    });

    test('a link inside a moved item that resolves the same from the target doc keeps every byte', () async {
      final root = await _project(
        shop: [_inv(1), _inv(4)],
        pay: [_inv(5, 'holds, with [INV-4](./../DOMAIN.md#invariants).')],
      );
      writeIn(
        root,
        (session) => answerMove(session, [
          'domain:shop/pay#INV-5',
        ], under: 'domain:shop/cart'),
      );
      expect(
        _body(root, cartDomain),
        _domain([
          _inv(1),
          _inv(5, 'holds, with [INV-4](./../DOMAIN.md#invariants).'),
        ]),
      );
    });

    test('a definition shared by an item link and another link stays and is listed', () async {
      final root = await _project(
        pay: [
          _inv(1, 'follows [INV-3][r] and see [the rules][r].'),
          '',
          '[r]: ../DOMAIN.md#invariants',
        ],
      );
      final payBefore = readDoc(root, _payDomain);
      final answer = _move(root, ['domain:shop#INV-3']);
      expect(readDoc(root, _payDomain), payBefore);
      expect(
        answer.text,
        contains(
          'mentions $_payDomain:${_lineOf(payBefore, '[r]:')} [r]: ../DOMAIN.md#invariants\n',
        ),
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
      _move(root, ['domain:shop#INV-3']);
      expect(
        _body(root, cartDomain),
        contains('holds, see [pay](../f02_pay/DOMAIN.md#invariants).'),
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
      final answer = _move(root, ['domain:shop#INV-3']);
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
          final landings = planItemMove(session, [
            'domain:shop#INV-3',
          ], under: 'domain:shop/cart');
          final refs = planItemRefs(session, landings);
          expect(
            itemMentions(session, landings, refs: refs),
            itemMentions(session, landings),
          );
          expect(refs.edits.keys, itemRefEdits(session, landings).keys);
        });
      },
    );

    test('a link keeps the title written after its destination', () async {
      final root = await _project(
        pay: [_inv(1, 'follows [INV-3](../DOMAIN.md#invariants "the rule").')],
      );
      _move(root, ['domain:shop#INV-3']);
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
        _move(root, ['domain:shop#INV-3']);
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
        final edits = itemRefEdits(
          session,
          planItemMove(session, [
            'domain:shop#INV-3',
          ], under: 'domain:shop/cart'),
        );
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
      _move(root, ['domain:shop#INV-3']);
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
      _move(root, ['domain:shop#INV-3']);
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
      _move(root, ['domain:shop#INV-3']);
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
      _move(root, ['domain:shop#INV-9']);
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
        _move(root, ['domain:shop#INV-3']);
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
        _move(root, ['domain:shop#INV-3']);
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
        _move(root, ['domain:shop#INV-3', 'domain:shop#INV-4']);
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
                '---\noverrides:\n  - domain:shop#INV-3 $_fingerprint\n---\n\n',
          ),
        },
      );
      _move(root, ['domain:shop#INV-3']);
      final coupon = readDoc(root, _couponDomain);
      expect(
        coupon,
        contains(
          '- Overrides: [INV-13](../DOMAIN.md#invariants) — $_because\n',
        ),
      );
      expect(
        coupon,
        contains('overrides:\n  - domain:shop/cart#INV-13 $_fingerprint\n'),
      );
      expect(coupon, isNot(contains('domain:shop#INV-3')));
    });

    test('a confirmed entry that names no item keeps its text', () async {
      final root = await _project();
      final before = readDoc(root, cartAddFr);
      _move(root, ['domain:shop#INV-3']);
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
      _move(root, ['domain:shop#INV-3']);
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
      _move(root, ['domain:shop#INV-3']);
      final pay = readDoc(root, _payDomain);
      expect(pay, isNot(contains('draft: true')));
      expect(pay, contains('approved: "'));
      expect(approvedBefore, isNotNull);
      expect(
        spots(checkOf(root), FindingKind.approvalStale),
        isNot(contains(_payDomain)),
      );
    });
  });

  group('a bare ID is listed, never rewritten', () {
    const mention = 'mentions ';

    test('a bare ID in the source doc outside a link, and a doc address with the ID in another doc, print one mentions line each and keep every byte', () async {
      final root = await _project(
        shop: [_inv(3), _inv(4, 'follows INV-3 of this doc.')],
        pay: [_inv(1, 'cites `domain:shop#INV-3`.')],
      );
      final payBefore = readDoc(root, _payDomain);
      final answer = _move(root, ['domain:shop#INV-3']);
      expect(
        answer.text,
        contains(
          '$mention$shopDomain:${_lineOf(readDoc(root, shopDomain), 'follows INV-3')} INV-3\n',
        ),
      );
      expect(
        answer.text,
        contains(
          '$mention$_payDomain:${_lineOf(payBefore, 'cites')} domain:shop#INV-3\n',
        ),
      );
      expect(readDoc(root, _payDomain), payBefore);
      expect(readDoc(root, shopDomain), contains('follows INV-3 of this doc.'));
    });

    test('a doc address with the ID in a code comment and in an agent file prints a mentions line and keeps the file bytes', () async {
      const code = '// Enforces `domain:shop#INV-3`.\n';
      const agent = 'Read `domain:shop#INV-3` first.\n';
      final root = await _project(
        extra: {'app/lib/cart.dart': code, 'CLAUDE.md': agent},
      );
      final answer = _move(root, ['domain:shop#INV-3']);
      expect(_codeText(root, 'app/lib/cart.dart'), code);
      expect(_codeText(root, 'CLAUDE.md'), agent);
      expect(
        answer.text,
        allOf(
          contains('${mention}CLAUDE.md:1 domain:shop#INV-3\n'),
          contains('${mention}app/lib/cart.dart:1 domain:shop#INV-3\n'),
        ),
      );
    });

    test('a bare ID in another doc with no doc address right before it prints no mentions line', () async {
      final root = await _project(
        pay: [_inv(1, 'see INV-3 of `domain:shop`.')],
      );
      final answer = _move(root, ['domain:shop#INV-3']);
      expect(answer.text, isNot(contains(_payDomain)));
      expect(answer.json['mentions'], isEmpty);
    });

    test('a bare ID right after a doc address in another doc prints a mentions line', () async {
      final root = await _project(
        pay: [_inv(1, 'see `domain:shop` INV-3 here.')],
      );
      final payBefore = readDoc(root, _payDomain);
      final answer = _move(root, ['domain:shop#INV-3']);
      expect(
        answer.text,
        contains('$mention$_payDomain:${_lineOf(payBefore, 'see')} INV-3\n'),
      );
    });

    test('a bare ID inside a moved item that names an item that stays, or one the call renumbers, prints one mentions line', () async {
      final root = await _project(
        shop: [_inv(3, 'as INV-4 gives, and see INV-7.'), _inv(4), _inv(7)],
        cart: _twelve.take(7).toList(),
      );
      final answer = _move(root, ['domain:shop#INV-3', 'domain:shop#INV-7']);
      final line = _lineOf(readDoc(root, cartDomain), 'as INV-4');
      expect(
        answer.text,
        allOf(
          contains('$mention$cartDomain:$line INV-4\n'),
          contains('$mention$cartDomain:$line INV-7\n'),
        ),
      );
      expect(
        readDoc(root, cartDomain),
        contains('as INV-4 gives, and see INV-7.'),
      );
    });

    test('a bare ID inside a moved item that names a co-moved item keeping its ID prints none, while the address form prints one', () async {
      final root = await _project(
        shop: [_inv(3, 'see INV-7 and `domain:shop#INV-7`.'), _inv(7)],
      );
      final answer = _move(root, ['domain:shop#INV-3', 'domain:shop#INV-7']);
      final line = _lineOf(readDoc(root, cartDomain), 'see INV-7');
      expect(answer.text.split('\n').where((l) => l.startsWith(mention)), [
        '$mention$cartDomain:$line domain:shop#INV-7',
      ]);
    });

    test('a dry run prints the mentions lines a real move prints and writes no file', () async {
      final shop = [_inv(3), _inv(4, 'follows INV-3 of this doc.')];
      final twin = await _project(shop: shop);
      final written = _move(twin, ['domain:shop#INV-3']);
      final root = await _project(shop: shop);
      final before = readDoc(root, shopDomain);
      final answer = _move(root, ['domain:shop#INV-3'], dryRun: true);
      expect(answer.json['mentions'], written.json['mentions']);
      expect(
        answer.text,
        contains(
          '$mention$shopDomain:${_lineOf(readDoc(twin, shopDomain), 'follows INV-3')} INV-3\n',
        ),
      );
      expect(answer.text, endsWith('dry run: nothing moved\n'));
      expect(readDoc(root, shopDomain), before);
    });
  });
}
