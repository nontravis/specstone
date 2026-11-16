// Each test name states one behavior on one line.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/document_writing/item_landing.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show MoveJournal;
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/nested_fixture.dart';
import '../../helpers/override_link_fixture.dart'
    show domainDoc, overrideFiles, rootAddress, rootFingerprint;
import '../../helpers/shipped_pins.dart';
import '../../helpers/write_fixture.dart';

const _payDomain = 'specs/f02_shop/f02_pay/DOMAIN.md';
const _couponFeature = 'prds/features/f02_shop/f01_cart/f01_coupon/FEATURE.md';
const _couponDomain = 'specs/f02_shop/f01_cart/f01_coupon/DOMAIN.md';
const _notes = 'specs/f02_shop/notes.md';
const _because = 'carts expire after 7 days, because a cart holds stock';

/// A coupon sub-feature of cart whose rule overrides one of cart's.
final Map<String, String> _couponWithOverride = {
  'docs/$_couponFeature': '# Coupon\n',
  'docs/$_couponDomain': _domain([
    _inv(5),
    '- Overrides: [INV-2](../DOMAIN.md#invariants) — $_because',
  ]),
};

String _domain(List<String> items) =>
    '# Domain\n\n## Invariants\n\n${items.join('\n')}\n';

String _inv(int number) => '- **INV-$number** Rule $number holds.';

Future<Directory> _project({
  List<String> shop = const [],
  List<String> cart = const [],
  List<String> pay = const [],
  Map<String, String> extra = const {},
}) => writeNestedProject(
  extra: {
    if (shop.isNotEmpty) 'docs/$shopDomain': _domain(shop),
    if (cart.isNotEmpty) 'docs/$cartDomain': _domain(cart),
    'docs/$_payDomain': _domain(pay.isEmpty ? [_inv(1)] : pay),
    ...extra,
  },
);

List<ItemLanding> _plan(
  Directory root,
  List<String> addresses, {
  String under = 'domain:shop/cart',
  String? codeTarget,
}) => writeIn(
  root,
  (session) =>
      planItemMove(session, addresses, under: under, codeTarget: codeTarget),
);

/// Every doc of [root] as bytes, so a test shows a refusal wrote none.
Map<String, List<int>> _docs(Directory root) => {
  for (final entry in treeBytes(root).entries)
    if (entry.key.startsWith('docs/')) entry.key: entry.value,
};

/// Plans [addresses] and returns the fault it raised, asserting no doc
/// changed.
Future<Object> _refusal(
  List<String> addresses, {
  List<String> shop = const [],
  List<String> cart = const [],
  List<String> pay = const [],
  Map<String, String> extra = const {},
  String under = 'domain:shop/cart',
}) async {
  final root = await _project(
    shop: shop.isEmpty ? [_inv(1), _inv(2), _inv(3)] : shop,
    cart: cart.isEmpty ? [_inv(1)] : cart,
    pay: pay,
    extra: extra,
  );
  final before = _docs(root);
  try {
    _plan(root, addresses, under: under);
  } on Object catch (fault) {
    expect(_docs(root), before, reason: 'a refused plan writes no doc');
    return fault;
  }
  return fail('no fault raised');
}

void main() {
  group('landing an item keeps or renumbers its ID', () {
    test('an ID the target does not hold stays', () async {
      final root = await _project(shop: [_inv(1), _inv(2), _inv(3)]);
      final landings = _plan(root, ['domain:shop#INV-3']);
      expect(landings, hasLength(1));
      final landing = landings.single;
      expect(landing.from.doc.docPath, shopDomain);
      expect(landing.from.id, 'INV-3');
      expect(landing.to.docPath, cartDomain);
      expect(landing.sectionKey, 'invariants');
      expect(landing.newId, 'INV-3');
    });

    test('an ID the target holds takes one past its highest', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [_inv(1), _inv(3), _inv(12)],
      );
      final landing = _plan(root, ['domain:shop#INV-3']).single;
      expect(landing.from.id, 'INV-3');
      expect(landing.newId, 'INV-13');
    });

    test('an ID only a generated block of the target holds stays', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [
          _inv(1),
          '',
          '<!-- specstone:generated scenario_copy (do not edit) -->',
          _inv(3),
          '<!-- specstone:generated end -->',
        ],
        extra: {
          '.specstone/templates/domain.yaml': 'generators: [scenario_copy]\n',
        },
      );
      final landing = _plan(root, ['domain:shop#INV-3']).single;
      expect(landing.newId, 'INV-3');
    });

    test('two clashing items of one doc count after each other', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [_inv(1), _inv(2), _inv(12)],
      );
      final landings = _plan(root, ['domain:shop#INV-1', 'domain:shop#INV-2']);
      expect([for (final l in landings) l.newId], ['INV-13', 'INV-14']);
    });

    test('items of two source docs that both clash count after the first one '
        'landed', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
        pay: [_inv(1)],
      );
      final landings = _plan(root, [
        'domain:shop#INV-1',
        'domain:shop/pay#INV-1',
      ]);
      expect(
        [for (final l in landings) l.from.doc.docPath],
        [shopDomain, _payDomain],
      );
      expect([for (final l in landings) l.newId], ['INV-13', 'INV-14']);
    });

    test(
      'an item that keeps its ID counts toward the next free number',
      () async {
        final root = await _project(
          shop: [_inv(1), _inv(2), _inv(7)],
          cart: [_inv(1), _inv(2)],
        );
        final landings = _plan(root, [
          'domain:shop#INV-7',
          'domain:shop#INV-1',
        ]);
        expect([for (final l in landings) l.newId], ['INV-7', 'INV-8']);
      },
    );

    test(
      'a lettered ID of the target takes a number before the new one',
      () async {
        final root = await _project(
          shop: [_inv(1), _inv(2)],
          cart: [_inv(1), _inv(7), '- **INV-6a** A lettered rule holds.'],
        );
        expect(_plan(root, ['domain:shop#INV-1']).single.newId, 'INV-9');
      },
    );

    test('a target doc that lacks the section still gets a landing', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2)],
        extra: {
          'docs/$cartDomain':
              '# Cart domain\n\n## Entities\n| Entity | Kind | Identity | Owns | Notes |\n'
              '|--------|------|----------|------|-------|\n| Cart | Aggregate root | id | lines | — |\n',
        },
      );
      final landing = _plan(root, ['domain:shop#INV-2']).single;
      expect(landing.sectionKey, 'invariants');
      expect(landing.newId, 'INV-2');
    });
  });

  group('the targets a call names', () {
    test(
      'an item already in the target doc stays and the others move',
      () async {
        final root = await _project(shop: [_inv(1), _inv(2), _inv(3)]);
        final landings = _plan(root, [
          'domain:shop/cart#INV-1',
          'domain:shop#INV-3',
        ]);
        expect([for (final l in landings) l.from.id], ['INV-3']);
      },
    );

    test('every item already in the target doc plans no landing', () async {
      final root = await _project();
      expect(_plan(root, ['domain:shop/cart#INV-1']), isEmpty);
    });

    test('an item named twice, in two address forms, lands once', () async {
      final root = await _project(shop: [_inv(1), _inv(2), _inv(3)]);
      final landings = _plan(root, [
        'domain:shop#INV-3',
        '$shopDomain#INV-3',
        'domain:shop#INV-3',
      ]);
      expect(landings, hasLength(1));
    });

    test('a doc address read as a suffix names its doc', () async {
      final root = await _project(shop: [_inv(1), _inv(2), _inv(3)]);
      final landing = _plan(root, [
        'domain:shop#INV-2',
      ], under: 'domain:cart').single;
      expect(landing.to.docPath, cartDomain);
    });

    test('items from several docs land in the order given', () async {
      final root = await _project(shop: [_inv(5)], pay: [_inv(6)]);
      final landings = _plan(root, [
        'domain:shop/pay#INV-6',
        'domain:shop#INV-5',
      ]);
      expect([for (final l in landings) l.from.id], ['INV-6', 'INV-5']);
    });
  });

  group('a refused target refuses the call and writes no doc', () {
    test(
      'an ID its doc lacks is item_not_found, naming the doc and the ID',
      () async {
        final fault = await _refusal(['domain:shop#INV-99']);
        expect(fault, isA<WriteFault>());
        final write = fault as WriteFault;
        expect(write.code, WriteFaultCode.itemNotFound);
        expect(write.exitStatus, 64);
        expect(write.message, '$shopDomain holds no INV-99');
      },
    );

    test('the second of two targets missing refuses both', () async {
      final fault = await _refusal(['domain:shop#INV-3', 'domain:shop#INV-99']);
      expect((fault as WriteFault).code, WriteFaultCode.itemNotFound);
      expect(fault.message, '$shopDomain holds no INV-99');
    });

    test('a doc that carries no such name is doc_not_found', () async {
      final fault = await _refusal(['domain:nothing#INV-3']);
      expect((fault as IndexFault).code, IndexFaultCode.docNotFound);
      expect(fault.exitStatus, 64);
    });

    test('an --under that names no doc is doc_not_found', () async {
      final fault = await _refusal([
        'domain:shop#INV-3',
      ], under: 'domain:nothing');
      expect((fault as IndexFault).code, IndexFaultCode.docNotFound);
    });

    test('an address that names 2 or more docs is argument_invalid with each candidate', () async {
      final fault = await _refusal(
        ['domain:shop/pay#INV-1'],
        extra: {
          'docs/prds/features/f02_shop/f03_pay/FEATURE.md': '# Pay\n',
          'docs/specs/f02_shop/f03_pay/DOMAIN.md': _domain([_inv(1)]),
        },
      );
      expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(fault.exitStatus, 64);
      expect(fault.message, contains(_payDomain));
      expect(fault.message, contains('specs/f02_shop/f03_pay/DOMAIN.md'));
    });

    test('a target doc type with no section of that key and prefix is argument_invalid', () async {
      final fault = await _refusal(['domain:shop#INV-3'], under: 'api:shop');
      expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(fault.exitStatus, 64);
      expect(
        fault.message,
        '$shopApi has no invariants section for INV- items',
      );
    });

    test('an untyped file as the source is untyped_target', () async {
      final fault = await _refusal(
        ['$_notes#INV-3'],
        extra: {'docs/$_notes': '# Notes\n\n## Invariants\n\n${_inv(3)}\n'},
      );
      expect((fault as IndexFault).code, IndexFaultCode.untypedTarget);
      expect(fault.exitStatus, 64);
    });

    test('an untyped file as --under is untyped_target', () async {
      final fault = await _refusal(
        ['domain:shop#INV-3'],
        extra: {'docs/$_notes': '# Notes\n'},
        under: _notes,
      );
      expect((fault as IndexFault).code, IndexFaultCode.untypedTarget);
    });

    test(
      'a path that holds # and names no doc splits at its first #',
      () async {
        final fault = await _refusal(
          ['prds/notes#draft.md#INV-3'],
          extra: {'docs/prds/notes#draft.md': '# Notes\n'},
        );
        expect((fault as IndexFault).code, IndexFaultCode.docNotFound);
        expect(fault.message, contains('prds/notes'));
      },
    );
  });

  group('the override chain a move must keep', () {
    test('a doc whose Overrides line links the item must hold the target in its chain', () async {
      final fault = await _refusal(
        ['domain:shop#INV-3'],
        pay: [
          _inv(1),
          '- Overrides: [INV-3](../DOMAIN.md#invariants) — $_because',
        ],
      );
      expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(fault.exitStatus, 64);
      expect(
        fault.message,
        '$_payDomain overrides $shopDomain#INV-3; $cartDomain sits outside its chain',
      );
    });

    test('the same holds when the overriding doc is the target doc', () async {
      final fault = await _refusal(
        ['domain:shop#INV-3'],
        cart: [
          _inv(1),
          '- Overrides: [INV-3](../DOMAIN.md#invariants) — $_because',
        ],
      );
      expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(
        fault.message,
        '$cartDomain overrides $shopDomain#INV-3; $cartDomain sits outside its chain',
      );
    });

    test('an Overrides line on another item leaves the move allowed', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        pay: [
          _inv(1),
          '- Overrides: [INV-3](../DOMAIN.md#invariants) — $_because',
        ],
      );
      expect(_plan(root, ['domain:shop#INV-2']).single.newId, 'INV-2');
    });

    test('an item whose own Overrides line links an item outside the target chain is argument_invalid, naming it', () async {
      final fault = await _refusal(
        ['domain:shop/cart/coupon#INV-5'],
        cart: [_inv(1), _inv(2)],
        extra: _couponWithOverride,
        under: 'domain:shop/pay',
      );
      expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(fault.exitStatus, 64);
      expect(
        fault.message,
        '$_couponDomain#INV-5 overrides $cartDomain#INV-2, outside the chain of $_payDomain',
      );
    });

    test('the same holds when the target doc holds the overridden item', () async {
      final fault = await _refusal(
        ['domain:shop/cart/coupon#INV-5'],
        cart: [_inv(1), _inv(2)],
        extra: _couponWithOverride,
      );
      expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(
        fault.message,
        '$_couponDomain#INV-5 overrides $cartDomain#INV-2, outside the chain of $cartDomain',
      );
    });

    test('an own Overrides line that the target chain holds leaves the move allowed', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2)],
        cart: [_inv(1)],
        extra: {
          'docs/$_couponFeature': '# Coupon\n',
          'docs/$_couponDomain': _domain([
            _inv(5),
            '- Overrides: [INV-2](../../DOMAIN.md#invariants) — $_because',
          ]),
        },
      );
      final landing = _plan(root, ['domain:shop/cart/coupon#INV-5']).single;
      expect(landing.newId, 'INV-5');
    });
  });

  group('the call as the move command reads it', () {
    Future<Object> refused(
      List<String> addresses, {
      String? under,
      String? codeTarget,
      Map<String, String> extra = const {},
    }) async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        extra: extra,
      );
      final before = _docs(root);
      try {
        writeIn(
          root,
          (s) => answerMove(s, addresses, under: under, codeTarget: codeTarget),
        );
      } on Object catch (fault) {
        expect(_docs(root), before);
        return fault;
      }
      return fail('no fault raised');
    }

    test(
      'an item beside a story target is argument_invalid, naming one kind',
      () async {
        final fault = await refused([
          'domain:shop#INV-3',
          'user_story:shop/cart/add_item',
        ], under: 'shop/cart');
        expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
        expect(fault.exitStatus, 64);
        expect(
          fault.message,
          'move takes item targets or doc targets, not both',
        );
      },
    );

    test('an item beside a spec doc is doc_type_not_movable, before the mixed test', () async {
      final fault = await refused([
        'domain:shop#INV-3',
        'domain:shop',
      ], under: 'domain:shop/cart');
      expect((fault as WriteFault).code, WriteFaultCode.docTypeNotMovable);
      expect(
        fault.message,
        'domain docs cannot move; move takes a user_story, an fr, an nf, '
        'or a feature',
      );
    });

    test(
      'an item target that names no doc is doc_not_found, even with --top',
      () async {
        final root = await _project(shop: [_inv(1)]);
        expect(
          () => writeIn(
            root,
            (s) =>
                answerMove(s, const ['nowhere#INV-1'], under: null, top: true),
          ),
          throwsA(
            isA<IndexFault>().having(
              (f) => f.code,
              'code',
              IndexFaultCode.docNotFound,
            ),
          ),
        );
      },
    );

    test(
      'item targets with no --under are argument_missing with the item message',
      () async {
        final fault = await refused(['domain:shop#INV-3']);
        expect((fault as IndexFault).code, IndexFaultCode.argumentMissing);
        expect(fault.exitStatus, 64);
        expect(
          fault.message,
          'move needs --under <doc address> for item targets',
        );
      },
    );

    test('a story target given --target is argument_invalid', () async {
      final fault = await refused(
        ['user_story:shop/cart/add_item'],
        under: 'shop/pay',
        codeTarget: 'server',
      );
      expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(fault.exitStatus, 64);
      expect(fault.message, 'move takes --target only with item targets');
    });

    test('an FR target given --target is argument_invalid', () async {
      final fault = await refused(
        ['fr:shop/cart/add_item/check_stock'],
        under: 'shop/pay/refund',
        codeTarget: 'server',
      );
      expect(
        (fault as IndexFault).message,
        'move takes --target only with item targets',
      );
    });

    test('a #<section key> that reads as no item ID stays a doc target and is argument_invalid', () async {
      final fault = await refused([
        'domain:shop#invariants',
      ], under: 'domain:shop/cart');
      expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(fault.exitStatus, 64);
      expect(fault.message, contains('takes no #<section key>'));
    });

    test(
      'only a suffix that reads whole as an item ID names an item',
      () async {
        final root = await _project(shop: [_inv(1), _inv(2), _inv(3)]);
        writeIn(root, (session) {
          final index = session.index;
          expect(isItemAddress(index, 'domain:shop#INV-3'), isTrue);
          expect(isItemAddress(index, 'domain:shop#INV-99'), isTrue);
          expect(isItemAddress(index, 'domain:shop#invariants'), isFalse);
          expect(isItemAddress(index, 'domain:shop#INV-3a'), isFalse);
          expect(isItemAddress(index, 'domain:shop#INV-3 x'), isFalse);
          expect(isItemAddress(index, 'domain:shop#'), isFalse);
        });
      },
    );

    test(
      'a path that holds # and names a doc is a doc target, not an item',
      () async {
        final fault = await refused(
          ['prds/notes#draft.md'],
          under: 'shop/pay',
          extra: {'docs/prds/notes#draft.md': '# Notes\n'},
        );
        expect((fault as IndexFault).code, IndexFaultCode.untypedTarget);
        expect(
          fault.message,
          startsWith('prds/notes#draft.md has no doc type'),
        );
      },
    );
  });

  group('--target keeps each address to one code target', () {
    Future<Directory> twoTargets() {
      String doc(String target, int n) => _domain([_inv(1), _inv(n)]);
      return writeNestedProject(
        without: {
          'docs/$shopDomain',
          'docs/$cartDomain',
          'docs/$shopArchitecture',
          'docs/$shopApi',
        },
        extra: {
          '.specstone/config.yaml':
              '${shippedPinsConfig()}targets:\n'
              '  app:\n    code_root: app_lib\n'
              '  server:\n    code_root: server_lib\n',
          'app_lib/.keep': '',
          'server_lib/.keep': '',
          for (final target in ['app', 'server']) ...{
            'docs/specs/$target/f02_shop/DOMAIN.md': doc(target, 3),
            'docs/specs/$target/f02_shop/f01_cart/DOMAIN.md': _domain([
              _inv(1),
            ]),
          },
        },
      );
    }

    test('an address resolves inside the named target', () async {
      final root = await twoTargets();
      final landing = _plan(root, [
        'domain:shop#INV-3',
      ], codeTarget: 'server').single;
      expect(landing.from.doc.docPath, 'specs/server/f02_shop/DOMAIN.md');
      expect(landing.to.docPath, 'specs/server/f02_shop/f01_cart/DOMAIN.md');
    });

    test('an address that names a doc of each target is argument_invalid with each candidate', () async {
      final root = await twoTargets();
      Object? fault;
      try {
        _plan(root, ['domain:shop#INV-3']);
      } on IndexFault catch (caught) {
        fault = caught;
      }
      expect((fault! as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(
        (fault as IndexFault).message,
        allOf(
          contains('specs/app/f02_shop/DOMAIN.md'),
          contains('specs/server/f02_shop/DOMAIN.md'),
        ),
      );
    });

    test('a --target the project does not hold is argument_invalid', () async {
      final root = await twoTargets();
      Object? fault;
      try {
        _plan(root, ['domain:shop#INV-3'], codeTarget: 'nothing');
      } on IndexFault catch (caught) {
        fault = caught;
      }
      expect((fault! as IndexFault).code, IndexFaultCode.argumentInvalid);
    });
  });

  group('an item move writes', () {
    // The doc text after its frontmatter, which carries the move's marks.
    String bodyOf(Directory root, String docPath) => readDoc(
      root,
      docPath,
    ).replaceFirst(RegExp(r'^---\n.*?\n---\n\n', dotAll: true), '');

    ReadAnswer move(
      Directory root,
      List<String> addresses, {
      bool dryRun = false,
    }) => writeIn(
      root,
      (session) => answerMove(
        session,
        addresses,
        under: 'domain:shop/cart',
        dryRun: dryRun,
      ),
    );

    test('the item with its nested items lands last in the target section and the source keeps the gap', () async {
      final root = await _project(
        shop: [
          '- **INV-3** Rule 3 holds.',
          '  - **Enforcer:** Cart',
          '  - **Consistency:** immediate',
          _inv(4),
        ],
        cart: [_inv(1)],
      );
      final answer = move(root, ['domain:shop#INV-3']);
      expect(
        bodyOf(root, cartDomain),
        _domain([
          _inv(1),
          '- **INV-3** Rule 3 holds.',
          '  - **Enforcer:** Cart',
          '  - **Consistency:** immediate',
        ]),
      );
      expect(bodyOf(root, shopDomain), _domain([_inv(4)]));
      expect(
        answer.text,
        'moved $shopDomain#INV-3 to $cartDomain#INV-3\n'
        'rewrote $shopDomain\n'
        'rewrote $cartDomain\n',
      );
    });

    test('several items land in the order given', () async {
      final root = await _project(
        shop: [_inv(5), _inv(6), _inv(7)],
        cart: [_inv(1)],
      );
      final answer = move(root, ['domain:shop#INV-7', 'domain:shop#INV-5']);
      expect(bodyOf(root, cartDomain), _domain([_inv(1), _inv(7), _inv(5)]));
      expect(bodyOf(root, shopDomain), _domain([_inv(6)]));
      expect(
        answer.text,
        startsWith(
          'moved $shopDomain#INV-7 to $cartDomain#INV-7\n'
          'moved $shopDomain#INV-5 to $cartDomain#INV-5\n',
        ),
      );
    });

    test(
      'a target doc that lacks the section gains it at its template place',
      () async {
        final root = await _project(
          shop: [_inv(1), _inv(2)],
          extra: {
            'docs/$cartDomain':
                '# Cart domain\n\n## Entities\n\nA cart holds lines.\n\n'
                '## Known limits\n\n- A cart holds one coupon.\n',
          },
        );
        move(root, ['domain:shop#INV-2']);
        expect(
          bodyOf(root, cartDomain),
          '# Cart domain\n\n## Entities\n\nA cart holds lines.\n\n'
          '## Invariants\n\n${_inv(2)}\n\n'
          '## Known limits\n\n- A cart holds one coupon.\n',
        );
      },
    );

    test('a clashing ID takes the next free number and the reply and the text name it', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
      );
      final answer = move(root, ['domain:shop#INV-3']);
      expect(
        readDoc(root, cartDomain),
        contains('\n- **INV-13** Rule 3 holds.\n'),
      );
      expect(
        answer.text,
        'moved $shopDomain#INV-3 to $cartDomain#INV-13\n'
        'renumbered $cartDomain INV-3 to INV-13\n'
        'rewrote $shopDomain\n'
        'rewrote $cartDomain\n',
      );
    });

    test('two clashing items count after each other', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
      );
      final answer = move(root, ['domain:shop#INV-1', 'domain:shop#INV-2']);
      expect(
        answer.text,
        startsWith(
          'moved $shopDomain#INV-1 to $cartDomain#INV-13\n'
          'moved $shopDomain#INV-2 to $cartDomain#INV-14\n'
          'renumbered $cartDomain INV-1 to INV-13\n'
          'renumbered $cartDomain INV-2 to INV-14\n',
        ),
      );
    });

    test('a one-slug span naming a moved item is no stale mention, a prefixed '
        'one is', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
        extra: {
          'docs/specs/f03_ledger/DOMAIN.md': _domain([_inv(1), _inv(2)]),
          'app/lib/note.dart': '// `ledger#INV-2` and `domain:ledger#INV-2`\n',
        },
      );
      final json = move(root, ['domain:ledger#INV-2']).json;
      expect(json['mentions'], [
        {
          'path': 'app/lib/note.dart',
          'line': 1,
          'mention': 'domain:ledger#INV-2',
        },
      ]);
    });

    test('--json holds moved, renumbered, rewritten, and mentions', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
      );
      final json = move(root, ['domain:shop#INV-3']).json;
      expect(json, {
        'moved': [
          {'from': '$shopDomain#INV-3', 'to': '$cartDomain#INV-13'},
        ],
        'renumbered': [
          {'doc': cartDomain, 'from': 'INV-3', 'to': 'INV-13'},
        ],
        'rewritten': [shopDomain, cartDomain],
        'mentions': <Object?>[],
      });
    });

    test('a dry run prints moves, renumbers, rewrites, and the closing line, and writes no file', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
      );
      final before = _docs(root);
      final answer = move(root, ['domain:shop#INV-3'], dryRun: true);
      expect(
        answer.text,
        'moves $shopDomain#INV-3 to $cartDomain#INV-13\n'
        'renumbers $cartDomain INV-3 to INV-13\n'
        'rewrites $shopDomain\n'
        'rewrites $cartDomain\n'
        'dry run: nothing moved\n',
      );
      expect(answer.json['dryRun'], isTrue);
      expect(answer.json['renumbered'], [
        {'doc': cartDomain, 'from': 'INV-3', 'to': 'INV-13'},
      ]);
      expect(_docs(root), before);
      expect(
        File('${root.path}/${MoveJournal.journalPath}').existsSync(),
        isFalse,
        reason: 'a dry run writes no journal',
      );
    });

    test(
      'every item already in the target doc changes nothing and replies empty',
      () async {
        final root = await _project();
        final before = _docs(root);
        final answer = move(root, ['domain:shop/cart#INV-1']);
        expect(answer.text, isEmpty);
        expect(answer.json['moved'], isEmpty);
        expect(answer.json['renumbered'], isEmpty);
        expect(_docs(root), before);
      },
    );

    test('an approved source doc and an approved target doc both become drafts and keep their approved value', () async {
      final root = await _project(shop: [_inv(1), _inv(2)], cart: [_inv(1)]);
      String approvedOf(String docPath) => RegExp(
        r'^approved: "([^"]+)"$',
        multiLine: true,
      ).firstMatch(readDoc(root, docPath))!.group(1)!;
      final shopApproved = approvedOf(shopDomain);
      final cartApproved = approvedOf(cartDomain);
      final pay = readDoc(root, _payDomain);
      move(root, ['domain:shop#INV-2']);
      for (final (docPath, approved) in [
        (shopDomain, shopApproved),
        (cartDomain, cartApproved),
      ]) {
        final text = readDoc(root, docPath);
        expect(text, contains('draft: true\n'));
        expect(text, contains('approved: "$approved"\n'));
      }
      expect(readDoc(root, _payDomain), pay);
    });

    group('the Overrides line a moved item carries', () {
      const entry = '$rootAddress ';
      final entryLine = '$entry$rootFingerprint';
      const overrideLine =
          '- Overrides: [INV-3](../DOMAIN.md#invariants) — $_because';
      const landedLine =
          '- Overrides: [INV-3](../../DOMAIN.md#invariants) — $_because';

      Future<Directory> project({
        List<String> shop = const [],
        List<String> cartEntries = const [],
      }) => writeNestedProject(
        extra: overrideFiles(
          extra: {
            'docs/$shopDomain': domainDoc(
              shop.isEmpty ? [_inv(5), overrideLine] : shop,
              entries: [entryLine],
            ),
            'docs/$cartDomain': domainDoc([_inv(1)], entries: cartEntries),
          },
        ),
      );

      test('lands right after the item with its link rebased, and its entry leaves the source for the target', () async {
        final root = await project();
        move(root, ['domain:shop#INV-5']);
        final cart = readDoc(root, cartDomain);
        expect(cart, contains('\n${_inv(5)}\n$landedLine\n'));
        expect(cart, contains('overrides:\n  - $entryLine\n'));
        final shop = readDoc(root, shopDomain);
        expect(shop, isNot(contains('Overrides:')));
        expect(shop, isNot(contains('overrides:')));
        expect(shop, isNot(contains(rootAddress)));
      });

      test('an Overrides line that stays in the source keeps the entry and the target takes a copy', () async {
        final root = await project(
          shop: [_inv(5), overrideLine, _inv(6), overrideLine],
        );
        move(root, ['domain:shop#INV-5']);
        expect(
          readDoc(root, shopDomain),
          contains('overrides:\n  - $entryLine\n'),
        );
        expect(
          readDoc(root, shopDomain),
          contains('\n${_inv(6)}\n$overrideLine\n'),
        );
        expect(
          readDoc(root, cartDomain),
          contains('overrides:\n  - $entryLine\n'),
        );
      });

      test('a target that already holds an entry for the item keeps that one entry', () async {
        final root = await project(cartEntries: [entryLine]);
        move(root, ['domain:shop#INV-5']);
        final cart = readDoc(root, cartDomain);
        expect(
          RegExp(RegExp.escape(rootAddress)).allMatches(cart),
          hasLength(1),
        );
        expect(readDoc(root, shopDomain), isNot(contains(rootAddress)));
      });

      test('a heading item moves as its whole block, its Overrides line and entry with it', () async {
        final root = await project(
          shop: [
            '### INV-5 — Cart expiry',
            '- A cart expires.',
            overrideLine,
            '- A last bullet.',
            '',
            '### INV-6 — Other',
            '- Stays.',
          ],
        );
        move(root, ['domain:shop#INV-5']);
        expect(
          bodyOf(root, cartDomain),
          contains(
            '${_inv(1)}\n\n### INV-5 — Cart expiry\n\n- A cart expires.\n'
            '$landedLine\n- A last bullet.\n',
          ),
        );
        expect(
          readDoc(root, cartDomain),
          contains('overrides:\n  - $entryLine\n'),
        );
        final shop = bodyOf(root, shopDomain);
        expect(shop, contains('### INV-6 — Other\n\n- Stays.\n'));
        expect(shop, isNot(contains('INV-5')));
        expect(shop, isNot(contains('Overrides:')));
        expect(readDoc(root, shopDomain), isNot(contains(rootAddress)));
      });
    });

    test('a landing keeps the CRLF line ends of both docs', () async {
      final root = await _project(shop: [_inv(1), _inv(2)], cart: [_inv(9)]);
      for (final docPath in [shopDomain, cartDomain]) {
        final text = readDoc(root, docPath);
        docFile(root, docPath).writeAsStringSync(text.replaceAll('\n', '\r\n'));
      }
      move(root, ['domain:shop#INV-2']);
      for (final docPath in [shopDomain, cartDomain]) {
        final text = readDoc(root, docPath);
        expect(text, contains('\r\n'));
        expect(text.replaceAll('\r\n', ''), isNot(contains('\n')));
      }
      expect(
        readDoc(root, cartDomain),
        endsWith(
          '# Domain\r\n\r\n## Invariants\r\n\r\n${_inv(9)}\r\n${_inv(2)}\r\n',
        ),
      );
    });

    test('an edit refuses a doc that changed since the plan', () async {
      final root = await _project(shop: [_inv(1), _inv(2)], cart: [_inv(9)]);
      writeIn(root, (session) {
        final edits = itemLandingEdits(
          session,
          planItemMove(session, [
            'domain:shop#INV-2',
          ], under: 'domain:shop/cart'),
        );
        for (final docPath in [shopDomain, cartDomain]) {
          expect(
            () => edits[docPath]!('# Domain\n\nA late edit.\n'),
            throwsA(
              isA<RenderFault>().having(
                (fault) => fault.message,
                'message',
                'cannot write $docPath: changed since the move was planned',
              ),
            ),
          );
        }
      });
    });

    group('the source layout around the gap', () {
      Future<Directory> project() => _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [_inv(9)],
        extra: {
          'docs/$shopDomain':
              '# Domain\n\n## Invariants\n\n${_inv(1)}\n${_inv(2)}\n${_inv(3)}\n\n'
              '## Known limits\n\n- A cart holds one coupon.\n',
        },
      );

      const tail = '\n## Known limits\n\n- A cart holds one coupon.\n';

      test('the last item of a section leaves one blank line before the next section', () async {
        final root = await project();
        move(root, ['domain:shop#INV-3']);
        expect(
          bodyOf(root, shopDomain),
          '# Domain\n\n## Invariants\n\n${_inv(1)}\n${_inv(2)}\n$tail',
        );
      });

      test(
        'the first item of a section leaves one blank line after the header',
        () async {
          final root = await project();
          move(root, ['domain:shop#INV-1']);
          expect(
            bodyOf(root, shopDomain),
            '# Domain\n\n## Invariants\n\n${_inv(2)}\n${_inv(3)}\n$tail',
          );
        },
      );

      test('every item of a section leaves its header and one blank line before the next', () async {
        final root = await project();
        move(root, [
          'domain:shop#INV-1',
          'domain:shop#INV-2',
          'domain:shop#INV-3',
        ]);
        expect(bodyOf(root, shopDomain), '# Domain\n\n## Invariants\n$tail');
      });
    });
  });
}
