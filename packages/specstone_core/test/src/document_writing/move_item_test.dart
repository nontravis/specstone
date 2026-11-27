// Each test name states one behavior on one line.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/document_writing/item_landing.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/document_writing/move_item.dart';
import 'package:specstone_core/src/document_writing/move_journal.dart'
    show MoveJournal;
import 'package:specstone_core/src/document_writing/move_plan.dart'
    show parseMovePlan;
import 'package:specstone_core/src/document_writing/move_plan_engine.dart';
import 'package:specstone_core/src/document_writing/move_plan_judge.dart'
    show judgeMovePlan;
import 'package:specstone_core/src/document_writing/write_fault.dart';
import 'package:specstone_core/src/document_writing/write_session.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/render_fault.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' show checkOf, fingerprintFor;
import '../../helpers/nested_fixture.dart';
import '../../helpers/no_generators.dart';
import '../../helpers/override_link_fixture.dart'
    show domainDoc, overrideFiles, rootAddress, rootFingerprint;
import '../../helpers/rulebook_fixture.dart';
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

/// The config that reads the per-edge-case rows the row projects hold.
String _edgeCaseConfig() =>
    '${shippedPinsConfig()}verification_coverage: edge_case\n';

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
  String under = 'rulebook:shop/cart',
  String? codeTarget,
}) => writeIn(
  root,
  (session) =>
      _planIn(session, addresses, under: under, codeTarget: codeTarget),
);

/// Plans [addresses] under the doc [under] names, as the move plan of one
/// line per address judges them.
List<ItemLanding> _planIn(
  WriteSession session,
  List<String> addresses, {
  String under = 'rulebook:shop/cart',
  String? codeTarget,
}) => judgeMovePlan(
  session,
  parseMovePlan(
    [for (final address in addresses) '$address -> $under'].join('\n'),
    path: 'plan.txt',
  ),
  codeTarget: codeTarget,
).landings;

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
  String under = 'rulebook:shop/cart',
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
      final landings = _plan(root, ['rulebook:shop#INV-3']);
      expect(landings, hasLength(1));
      final landing = landings.single;
      expect(landing.from.doc.docPath, shopDomain);
      expect(landing.from.id, 'INV-3');
      expect(landing.to.docPath, cartDomain);
      expect(landing.sectionKey, 'invariants');
      expect(landing.newId, 'INV-3');
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
          rulebookLayerFile: '${rulebookLayer}generators: [scenario_copy]\n',
        },
      );
      final landing = _plan(root, ['rulebook:shop#INV-3']).single;
      expect(landing.newId, 'INV-3');
    });

    test('items of two source docs that both clash count after the first one '
        'landed', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
        pay: [_inv(1)],
      );
      final landings = _plan(root, [
        'rulebook:shop#INV-1',
        'rulebook:shop/pay#INV-1',
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
          'rulebook:shop#INV-7',
          'rulebook:shop#INV-1',
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
        expect(_plan(root, ['rulebook:shop#INV-1']).single.newId, 'INV-9');
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
      final landing = _plan(root, ['rulebook:shop#INV-2']).single;
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
          'rulebook:shop/cart#INV-1',
          'rulebook:shop#INV-3',
        ]);
        expect([for (final l in landings) l.from.id], ['INV-3']);
      },
    );

    test('an item named twice, in two address forms, lands once', () async {
      final root = await _project(shop: [_inv(1), _inv(2), _inv(3)]);
      final landings = _plan(root, [
        'rulebook:shop#INV-3',
        '$shopDomain#INV-3',
        'rulebook:shop#INV-3',
      ]);
      expect(landings, hasLength(1));
    });

    test('a doc address read as a suffix names its doc', () async {
      final root = await _project(shop: [_inv(1), _inv(2), _inv(3)]);
      final landing = _plan(root, [
        'rulebook:shop#INV-2',
      ], under: 'rulebook:cart').single;
      expect(landing.to.docPath, cartDomain);
    });

    test('items from several docs land in the order given', () async {
      final root = await _project(shop: [_inv(5)], pay: [_inv(6)]);
      final landings = _plan(root, [
        'rulebook:shop/pay#INV-6',
        'rulebook:shop#INV-5',
      ]);
      expect([for (final l in landings) l.from.id], ['INV-6', 'INV-5']);
    });
  });

  group('a refused target refuses the call and writes no doc', () {
    test(
      'an ID its doc lacks is item_not_found, naming the doc and the ID',
      () async {
        final fault = await _refusal(['rulebook:shop#INV-99']);
        expect(fault, isA<WriteFault>());
        final write = fault as WriteFault;
        expect(write.code, WriteFaultCode.itemNotFound);
        expect(write.exitStatus, 64);
        expect(write.message, '$shopDomain holds no INV-99');
      },
    );

    test('the second of two targets missing refuses both', () async {
      final fault = await _refusal([
        'rulebook:shop#INV-3',
        'rulebook:shop#INV-99',
      ]);
      expect((fault as WriteFault).code, WriteFaultCode.itemNotFound);
      expect(fault.message, '$shopDomain holds no INV-99');
    });

    test('a doc that carries no such name is doc_not_found', () async {
      final fault = await _refusal(['rulebook:nothing#INV-3']);
      expect((fault as IndexFault).code, IndexFaultCode.docNotFound);
      expect(fault.exitStatus, 64);
    });

    test('an address that names 2 or more docs is argument_invalid with each candidate', () async {
      final fault = await _refusal(
        ['rulebook:shop/pay#INV-1'],
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

    test(
      'one of several targets naming no doc refuses the whole call',
      () async {
        final fault = await _refusal([
          'rulebook:shop#INV-3',
          'rulebook:nothing#INV-1',
        ]);
        expect((fault as IndexFault).code, IndexFaultCode.docNotFound);
        expect(fault.exitStatus, 64);
      },
    );

    test('a target doc type with no section of that key and prefix is argument_invalid', () async {
      final fault = await _refusal(['rulebook:shop#INV-3'], under: 'api:shop');
      expect((fault as IndexFault).code, IndexFaultCode.argumentInvalid);
      expect(fault.exitStatus, 64);
      expect(
        fault.message,
        '$shopApi has no invariants section for INV- items',
      );
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

    test(
      'a rule moved alone while a staying title names it is refused',
      () async {
        String scenario(int n, String title) =>
            '### Scenario $n — [edge] Case $n$title\n\n'
            '- **Given** a cart\n- **When** the shopper acts\n'
            '- **Then** the shopper sees it';
        final story =
            '---\ngoals:\n  - PG-01\n---\n\n# Agent adds an item\n\n'
            '## Use Case\n\n- **As a** Agent who shops\n- **I want to** act\n'
            '- **so that** I finish an order\n\n'
            '## Rules\n\n- **BR-01** — Rule 1 holds.\n'
            '- **BR-02** — Rule 2 holds.\n\n'
            '## Acceptance Criteria\n\n${scenario(1, '')}\n\n'
            '${scenario(2, '')}\n\n${scenario(3, ' (BR-02)')}\n';
        for (final dryRun in [false, true]) {
          final root = await _project(extra: {'docs/$cartAdd': story});
          final before = _docs(root);
          Object? fault;
          try {
            writeIn(
              root,
              (session) => answerMove(
                session,
                const ['user_story:shop/cart/add_item#BR-02'],
                under: 'user_story:shop/cart/drop_item',
                dryRun: dryRun,
                generators: noGenerators,
              ),
            );
          } on IndexFault catch (caught) {
            fault = caught;
          }
          expect((fault! as IndexFault).code, IndexFaultCode.argumentInvalid);
          expect((fault as IndexFault).exitStatus, 64);
          expect(
            fault.message,
            'shop/cart/add_item#BR-02 is named by Scenario 3, which stays; '
            'move both in one call',
          );
          expect(_docs(root), before, reason: 'a refused move writes no doc');
        }
      },
    );
  });

  group('the override chain a move must keep', () {
    test('an Overrides line on another item leaves the move allowed', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        pay: [
          _inv(1),
          '- Overrides: [INV-3](../DOMAIN.md#invariants) — $_because',
        ],
      );
      expect(_plan(root, ['rulebook:shop#INV-2']).single.newId, 'INV-2');
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
      final landing = _plan(root, ['rulebook:shop/cart/coupon#INV-5']).single;
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
          (s) => answerMove(
            s,
            addresses,
            under: under,
            codeTarget: codeTarget,
            generators: noGenerators,
          ),
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
          'rulebook:shop#INV-3',
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
        'rulebook:shop#INV-3',
        'rulebook:shop',
      ], under: 'rulebook:shop/cart');
      expect((fault as WriteFault).code, WriteFaultCode.docTypeNotMovable);
      expect(
        fault.message,
        'rulebook docs cannot move; move takes a user_story, an fr, an nf, '
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
            (s) => answerMove(
              s,
              const ['nowhere#INV-1'],
              under: null,
              top: true,
              generators: noGenerators,
            ),
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

    test('a #<section key> that reads as no item ID stays a doc target and is argument_invalid', () async {
      final fault = await refused([
        'rulebook:shop#invariants',
      ], under: 'rulebook:shop/cart');
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
          expect(isItemAddress(index, 'rulebook:shop#INV-3'), isTrue);
          expect(isItemAddress(index, 'rulebook:shop#INV-99'), isTrue);
          expect(isItemAddress(index, 'rulebook:shop#invariants'), isFalse);
          expect(isItemAddress(index, 'rulebook:shop#INV-3a'), isFalse);
          expect(isItemAddress(index, 'rulebook:shop#INV-3 x'), isFalse);
          expect(isItemAddress(index, 'rulebook:shop#'), isFalse);
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
        'rulebook:shop#INV-3',
      ], codeTarget: 'server').single;
      expect(landing.from.doc.docPath, 'specs/server/f02_shop/DOMAIN.md');
      expect(landing.to.docPath, 'specs/server/f02_shop/f01_cart/DOMAIN.md');
    });

    test('a refusal over --target writes no doc', () async {
      final root = await twoTargets();
      final before = _docs(root);
      for (final codeTarget in [null, 'nothing']) {
        expect(
          () => writeIn(
            root,
            (s) => answerMove(
              s,
              const ['rulebook:shop#INV-3'],
              under: 'rulebook:shop/cart',
              codeTarget: codeTarget,
              generators: noGenerators,
            ),
          ),
          throwsA(
            isA<IndexFault>()
                .having((f) => f.code, 'code', IndexFaultCode.argumentInvalid)
                .having((f) => f.exitStatus, 'exitStatus', 64),
          ),
          reason: '$codeTarget',
        );
        expect(_docs(root), before, reason: '$codeTarget');
      }
      expect(
        File('${root.path}/${MoveJournal.journalPath}').existsSync(),
        isFalse,
      );
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
        under: 'rulebook:shop/cart',
        dryRun: dryRun,
        generators: noGenerators,
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
      final answer = move(root, ['rulebook:shop#INV-3']);
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

    test('a quoted heading item moves alone, and the quoted heading item after it stays with its ID', () async {
      final root = await _project(
        shop: [
          '> ### INV-5 — Cart expiry',
          '> A cart expires.',
          '',
          '> ### INV-6 — Other',
          '> Stays.',
        ],
        cart: [_inv(1)],
      );
      move(root, ['rulebook:shop#INV-5']);
      expect(
        bodyOf(root, shopDomain),
        _domain(['> ### INV-6 — Other', '> Stays.']),
      );
      expect(
        bodyOf(root, cartDomain),
        _domain([
          _inv(1),
          '',
          '> ### INV-5 — Cart expiry',
          '> A cart expires.',
        ]),
      );
    });

    test('several items land in the order given', () async {
      final root = await _project(
        shop: [_inv(5), _inv(6), _inv(7)],
        cart: [_inv(1)],
      );
      final answer = move(root, ['rulebook:shop#INV-7', 'rulebook:shop#INV-5']);
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
        move(root, ['rulebook:shop#INV-2']);
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
      final answer = move(root, ['rulebook:shop#INV-3']);
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

    test(
      'a table row written with outer pipes lands under a new number',
      () async {
        final root = await _project(
          shop: [
            '| ID | Rule |',
            '| --- | --- |',
            '| INV-1 | Rule 1 holds. |',
            '| INV-2 | Rule 2 holds. |',
            '| INV-3 | Rule 3 holds. |',
          ],
          cart: [for (var n = 1; n <= 12; n++) _inv(n)],
        );
        final answer = move(root, ['rulebook:shop#INV-3']);
        expect(
          readDoc(root, cartDomain),
          contains('\n| INV-13 | Rule 3 holds. |'),
        );
        expect(
          answer.text,
          startsWith('moved $shopDomain#INV-3 to $cartDomain#INV-13\n'),
        );
      },
    );

    test('two clashing items count after each other', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
      );
      final answer = move(root, ['rulebook:shop#INV-1', 'rulebook:shop#INV-2']);
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
          'app/lib/note.dart':
              '// `ledger#INV-2` and `rulebook:ledger#INV-2`\n',
        },
      );
      final json = move(root, ['rulebook:ledger#INV-2']).json;
      expect(json['mentions'], [
        {
          'path': 'app/lib/note.dart',
          'line': 1,
          'mention': 'rulebook:ledger#INV-2',
        },
      ]);
    });

    test('an ID right after an address becomes a link to the moved item, one outside every run is kept', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
        pay: [
          _inv(1),
          '- **INV-2** Pay holds `rulebook:shop` and then see INV-3.',
          '- **INV-4** Pay holds `rulebook:shop` INV-3 here.',
        ],
      );
      final json = move(root, ['rulebook:shop#INV-3']).json;
      expect(json['mentions'], isEmpty);
      final pay = readDoc(root, _payDomain);
      expect(pay, contains('and then see INV-3.\n'));
      expect(
        pay,
        contains(
          '`rulebook:shop` [INV-13](../f01_cart/DOMAIN.md#invariants) here.\n',
        ),
      );
    });

    test('a doc file of no doc type lists no mention, while a typed doc lists the same text', () async {
      const text =
          'Holds `rulebook:shop#INV-3` and [rulebook:shop](DOMAIN.md) INV-3.\n';
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
        pay: [_inv(1), '- **INV-2** Pay $text'],
        extra: {'docs/$_notes': '# Notes\n\n$text'},
      );
      final json = move(root, ['rulebook:shop#INV-3']).json;
      final mentions = json['mentions']! as List<Object?>;
      final paths = {for (final m in mentions) (m! as Map)['path']};
      expect(paths, contains(_payDomain));
      expect(paths, isNot(contains(_notes)));
    });

    test('a bare ID inside each of two items landing in one section becomes a link to the item that stays', () async {
      final root = await _project(
        shop: [
          '- **INV-1** Rule 1 holds, with INV-3.',
          '- **INV-2** Rule 2 holds, with INV-3.',
          _inv(3),
        ],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
      );
      final json = move(root, [
        'rulebook:shop#INV-1',
        'rulebook:shop#INV-2',
      ]).json;
      expect(json['mentions'], isEmpty);
      final cart = readDoc(root, cartDomain);
      for (final (id, rule) in [('INV-13', 1), ('INV-14', 2)]) {
        expect(
          cart,
          contains(
            '- **$id** Rule $rule holds, with '
            '[INV-3](../DOMAIN.md#invariants).\n',
          ),
        );
      }
    });

    test('--json holds moved, renumbered, rewritten, and mentions', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
      );
      final json = move(root, ['rulebook:shop#INV-3']).json;
      expect(json, {
        'moved': [
          {'from': '$shopDomain#INV-3', 'to': '$cartDomain#INV-13'},
        ],
        'renumbered': [
          {'path': cartDomain, 'from': 'INV-3', 'to': 'INV-13'},
        ],
        'rewritten': [shopDomain, cartDomain],
        'deleted': <Object?>[],
        'mentions': <Object?>[],
      });
    });

    test(
      'the reply prints a rewrote line for each other doc whose bytes changed',
      () async {
        final root = await _project(
          shop: [_inv(1), _inv(2), _inv(3)],
          pay: [
            _inv(1),
            '- **INV-2** Pay follows [INV-3](../DOMAIN.md#invariants).',
          ],
        );
        final answer = move(root, ['rulebook:shop#INV-3']);
        expect(
          answer.text,
          'moved $shopDomain#INV-3 to $cartDomain#INV-3\n'
          'rewrote $shopDomain\n'
          'rewrote $cartDomain\n'
          'rewrote $_payDomain\n',
        );
        expect(
          readDoc(root, _payDomain),
          contains('[INV-3](../f01_cart/DOMAIN.md#invariants)'),
        );
      },
    );

    test('a doc that links two moved items is rewritten once, both links in the one pass', () async {
      final root = await _project(
        shop: [for (var n = 1; n <= 7; n++) _inv(n)],
        pay: [
          _inv(1),
          '- **INV-2** Pay follows [INV-3](../DOMAIN.md#invariants) and [INV-7](../DOMAIN.md#invariants).',
        ],
      );
      final answer = move(root, ['rulebook:shop#INV-3', 'rulebook:shop#INV-7']);
      expect(answer.json['rewritten'], [shopDomain, cartDomain, _payDomain]);
      expect('rewrote $_payDomain\n'.allMatches(answer.text), hasLength(1));
      expect(
        readDoc(root, _payDomain),
        contains(
          '[INV-3](../f01_cart/DOMAIN.md#invariants) and '
          '[INV-7](../f01_cart/DOMAIN.md#invariants)',
        ),
      );
    });

    test('a dry run lists an item named twice once', () async {
      final root = await _project(shop: [_inv(1), _inv(2), _inv(3)]);
      final answer = move(root, [
        'rulebook:shop#INV-3',
        '$shopDomain#INV-3',
      ], dryRun: true);
      expect(
        answer.text,
        'moves $shopDomain#INV-3 to $cartDomain#INV-3\n'
        'rewrites $shopDomain\n'
        'rewrites $cartDomain\n'
        'dry run: nothing moved\n',
      );
    });

    test('a dry run prints moves, renumbers, rewrites, and the closing line, and writes no file', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [for (var n = 1; n <= 12; n++) _inv(n)],
      );
      final before = _docs(root);
      final answer = move(root, ['rulebook:shop#INV-3'], dryRun: true);
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
        {'path': cartDomain, 'from': 'INV-3', 'to': 'INV-13'},
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
        final answer = move(root, ['rulebook:shop/cart#INV-1']);
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
      move(root, ['rulebook:shop#INV-2']);
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
        move(root, ['rulebook:shop#INV-5']);
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
        move(root, ['rulebook:shop#INV-5']);
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
        move(root, ['rulebook:shop#INV-5']);
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
        move(root, ['rulebook:shop#INV-5']);
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
      move(root, ['rulebook:shop#INV-2']);
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
          _planIn(session, ['rulebook:shop#INV-2']),
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
        move(root, ['rulebook:shop#INV-3']);
        expect(
          bodyOf(root, shopDomain),
          '# Domain\n\n## Invariants\n\n${_inv(1)}\n${_inv(2)}\n$tail',
        );
      });

      test(
        'the first item of a section leaves one blank line after the header',
        () async {
          final root = await project();
          move(root, ['rulebook:shop#INV-1']);
          expect(
            bodyOf(root, shopDomain),
            '# Domain\n\n## Invariants\n\n${_inv(2)}\n${_inv(3)}\n$tail',
          );
        },
      );

      test('every item of a section leaves its header and one blank line before the next', () async {
        final root = await project();
        move(root, [
          'rulebook:shop#INV-1',
          'rulebook:shop#INV-2',
          'rulebook:shop#INV-3',
        ]);
        expect(bodyOf(root, shopDomain), '# Domain\n\n## Invariants\n$tail');
      });
    });
  });

  group('an edge case move rewrites the record rows that name it', () {
    const dropFr =
        'prds/features/f02_shop/f01_cart/us01_add_item/fr02_drop_stock.md';
    const chargeFr = 'prds/features/f02_shop/f02_pay/us01_card/fr01_charge.md';
    const matrix = '\n## Verification matrix\n\n';
    const soldOutRow = '- add_item/check_stock E01: `refuses a sold-out item`';
    const missingRow = '- add_item/check_stock E02: `refuses a missing item`';

    String fr(List<int> edgeCases) =>
        '---\ntraced_from:\n  - S1\nverify_method: test\n---\n\n'
        '# Requirement\n\n## Statement\n$checkStockStatement\n\n'
        '## Edge cases\n'
        '${[for (final n in edgeCases) '$n. E0$n — Case $n → refused.'].join('\n')}\n\n'
        '## Rationale\nStock is finite.\n\n'
        '## Verification\nTest: a case is refused.\n';

    Future<Directory> project() => writeNestedProject(
      extra: {
        '.specstone/config.yaml': _edgeCaseConfig(),
        ...nestedRecords(),
        'docs/$cartAddFr': fr([1, 2]),
        'docs/$dropFr': fr([1]),
        'docs/$chargeFr': fr([1]),
        cartRecord:
            '${nestedRecords()[cartRecord]}$matrix$soldOutRow\n$missingRow\n',
      },
    );

    ReadAnswer move(
      Directory root, {
      required String under,
      bool dryRun = false,
      String id = 'E01',
    }) => writeIn(
      root,
      (session) => answerMove(
        session,
        ['fr:shop/cart/add_item/check_stock#$id'],
        under: under,
        dryRun: dryRun,
        generators: noGenerators,
      ),
    );

    test('a row names the edge case at its target requirement and new number, and a row of an edge case that stays keeps its text', () async {
      final root = await project();
      move(root, under: 'fr:shop/cart/add_item/drop_stock', id: 'E02');
      expect(
        readDoc(root, cartRecord),
        endsWith(
          '$matrix$soldOutRow\n'
          '- add_item/drop_stock E02: `refuses a missing item`\n',
        ),
      );
    });

    test(
      'a row naming an edge case renumbered in place names its new number',
      () async {
        final root = await project();
        move(root, under: 'fr:shop/cart/add_item/drop_stock');
        expect(
          readDoc(root, cartRecord),
          endsWith(
            '$matrix- add_item/drop_stock E02: `refuses a sold-out item`\n'
            '- add_item/check_stock E01: `refuses a missing item`\n',
          ),
        );
      },
    );

    test('a plan that creates the landing FR carries a moved edge case row to the new feature record', () async {
      final root = await project();
      writeIn(
        root,
        (session) => answerPlanMove(
          session,
          parseMovePlan(
            'new feature --parent shop --slug gift\n'
            'new user_story --parent shop/gift --slug wrap\n'
            'new fr --parent shop/gift/wrap --slug pick_paper\n'
            'fr:shop/cart/add_item/check_stock#E01 -> fr:shop/gift/wrap/pick_paper\n',
            path: 'plan.txt',
          ),
          dryRun: false,
          generators: noGenerators,
        ),
      );
      expect(
        readDoc(root, '.specstone/records/f02_shop/f03_gift/IMPLEMENTATION.md'),
        endsWith('$matrix- wrap/pick_paper E03: `refuses a sold-out item`\n'),
      );
      expect(
        readDoc(root, cartRecord),
        endsWith(
          '$matrix- add_item/check_stock E01: `refuses a missing item`\n',
        ),
      );
    });

    test("a requirement of another feature takes the row into that feature's record, named relative to it", () async {
      final root = await project();
      move(root, under: 'fr:shop/pay/card/charge', id: 'E02');
      expect(readDoc(root, cartRecord), endsWith('$matrix$soldOutRow\n'));
      expect(
        readDoc(root, payRecord),
        endsWith('$matrix- card/charge E02: `refuses a missing item`\n'),
      );
    });

    test(
      'a dry run lists the record among the docs it rewrites and writes none',
      () async {
        final root = await project();
        final before = readDoc(root, cartRecord);
        final answer = move(
          root,
          under: 'fr:shop/cart/add_item/drop_stock',
          dryRun: true,
        );
        expect(answer.text, contains('rewrites $cartRecord\n'));
        expect(readDoc(root, cartRecord), before);
      },
    );

    group('a row stamped before the move', () {
      const landedCase = '2. E02 — Case 1 → refused.';
      const movedRow = '- add_item/check_stock E01: `refuses a sold-out item`';

      Future<Directory> stamped(
        String soldOutStamp, {
        bool holdsPayRecord = true,
      }) => writeNestedProject(
        extra: {
          '.specstone/config.yaml': _edgeCaseConfig(),
          ...nestedRecords()
            ..removeWhere((path, _) => !holdsPayRecord && path == payRecord),
          'docs/$cartAddFr': fr([1, 2]),
          'docs/$dropFr': fr([1]),
          'docs/$chargeFr': fr([1]),
          cartRecord:
              '${nestedRecords()[cartRecord]}$matrix'
              '$movedRow $soldOutStamp\n'
              '$missingRow ${fingerprintFor('2. E02 — Case 2 → refused.')}\n',
        },
      );

      Future<List<Object?>> unsettledLinks(Directory root) async => [
        for (final finding in (await checkOf(
          root,
          docPath: cartRecord,
        )).findings)
          if (finding.kind == FindingKind.suspect ||
              finding.kind == FindingKind.unconfirmed)
            finding.keys['link'],
      ];

      test(
        "a moved edge case's matched row is stamped from its landed block",
        () async {
          final root = await stamped(
            fingerprintFor('1. E01 — Case 1 → refused.'),
          );
          move(root, under: 'fr:shop/cart/add_item/drop_stock');
          expect(readDoc(root, dropFr), contains('$landedCase\n'));
          expect(
            readDoc(root, cartRecord),
            contains(
              '- add_item/drop_stock E02: `refuses a sold-out item` '
              '${fingerprintFor(landedCase)}\n',
            ),
          );
          expect(await unsettledLinks(root), isEmpty);
        },
      );

      test("a moved edge case's stale row is left as recorded", () async {
        final stale = fingerprintFor('1. E01 — An old text → refused.');
        final root = await stamped(stale);
        move(root, under: 'fr:shop/cart/add_item/drop_stock');
        expect(
          readDoc(root, cartRecord),
          contains(
            '- add_item/drop_stock E02: `refuses a sold-out item` $stale\n',
          ),
        );
        expect(await unsettledLinks(root), ['add_item/drop_stock#E02']);
      });

      test(
        'a row carried into a new record is stamped from its landed block',
        () async {
          final root = await stamped(
            fingerprintFor('1. E01 — Case 1 → refused.'),
            holdsPayRecord: false,
          );
          move(root, under: 'fr:shop/pay/card/charge');
          expect(readDoc(root, chargeFr), contains('$landedCase\n'));
          expect(
            readDoc(root, payRecord),
            contains(
              '- card/charge E02: `refuses a sold-out item` '
              '${fingerprintFor(landedCase)}\n',
            ),
          );
        },
      );
    });
  });

  group('an edge case move under fr or off leaves the record as written', () {
    const dropFr =
        'prds/features/f02_shop/f01_cart/us01_add_item/fr02_drop_stock.md';
    const matrix = '\n## Verification matrix\n\n';

    String contractOf(List<int> edgeCases) =>
        '## Statement\n\n$checkStockStatement\n\n## Edge cases\n\n'
        '${[for (final n in edgeCases) '$n. E0$n — Case $n → refused.'].join('\n')}\n';

    String fr(List<int> edgeCases) =>
        '---\ntraced_from:\n  - S1\nverify_method: test\n---\n\n'
        '# Requirement\n\n${contractOf(edgeCases)}\n'
        '## Rationale\n\nStock is finite.\n\n'
        '## Verification\n\nTest: a case is refused.\n';

    String frRow(String item, List<int> edgeCases) =>
        '- add_item/$item: `refuses a case` '
        '${fingerprintFor(contractOf(edgeCases))}';

    Future<Directory> project(String coverage, String rows) =>
        writeNestedProject(
          extra: {
            '.specstone/config.yaml':
                '${shippedPinsConfig()}verification_coverage: $coverage\n',
            ...nestedRecords(),
            'docs/$cartAddFr': fr([1, 2]),
            'docs/$dropFr': fr([1]),
            cartRecord: '${nestedRecords()[cartRecord]}$matrix$rows\n',
          },
        );

    void moveToDrop(Directory root) => writeIn(
      root,
      (session) => answerMove(
        session,
        ['fr:shop/cart/add_item/check_stock#E01'],
        under: 'fr:shop/cart/add_item/drop_stock',
        generators: noGenerators,
      ),
    );

    Future<List<Object?>> suspectLinks(Directory root) async => [
      for (final finding in (await checkOf(root, docPath: cartRecord)).findings)
        if (finding.kind == FindingKind.suspect) finding.keys['link'],
    ];

    test('leaves per-FR rows and stamps as written when an edge case moves under fr', () async {
      final rows =
          '${frRow('check_stock', [1, 2])}\n${frRow('drop_stock', [1])}';
      final root = await project('fr', rows);
      expect(await suspectLinks(root), isEmpty);
      moveToDrop(root);
      expect(readDoc(root, dropFr), contains('2. E02 — Case 1 → refused.\n'));
      expect(readDoc(root, cartRecord), endsWith('$matrix$rows\n'));
      expect(
        await suspectLinks(root),
        unorderedEquals(['add_item/check_stock', 'add_item/drop_stock']),
      );
    });

    test('leaves rows as written when an edge case moves under off', () async {
      const row = '- add_item/check_stock E01: `refuses a case`';
      final root = await project('false', row);
      moveToDrop(root);
      expect(readDoc(root, dropFr), contains('2. E02 — Case 1 → refused.\n'));
      expect(readDoc(root, cartRecord), endsWith('$matrix$row\n'));
    });
  });

  group('a refusal reads the same with --dry-run and writes no doc', () {
    String describe(Object fault) => switch (fault) {
      IndexFault(:final code, :final message, :final exitStatus) =>
        '${code.wire} $exitStatus: $message',
      WriteFault(:final code, :final message, :final exitStatus) =>
        '${code.wire} $exitStatus: $message',
      _ => fail('not a refusal: $fault'),
    };

    /// Runs the move with and without --dry-run on one project and returns
    /// the refusal, asserting both runs give it and no doc changed.
    Future<String> refusal(
      List<String> addresses, {
      String? under = 'rulebook:shop/cart',
      bool top = false,
      String? codeTarget,
      List<String> shop = const [],
      List<String> cart = const [],
      List<String> pay = const [],
      Map<String, String> extra = const {},
    }) async {
      final root = await _project(
        shop: shop.isEmpty ? [_inv(1), _inv(2), _inv(3)] : shop,
        cart: cart.isEmpty ? [_inv(1)] : cart,
        pay: pay,
        extra: extra,
      );
      final before = _docs(root);
      final described = <String>[];
      for (final dryRun in [false, true]) {
        try {
          writeIn(
            root,
            (s) => answerMove(
              s,
              addresses,
              under: under,
              top: top,
              codeTarget: codeTarget,
              dryRun: dryRun,
              generators: noGenerators,
            ),
          );
        } on Object catch (fault) {
          described.add(describe(fault));
          expect(_docs(root), before, reason: 'dryRun $dryRun writes no doc');
          continue;
        }
        fail('no fault raised, dryRun $dryRun');
      }
      expect(described.last, described.first);
      return described.first;
    }

    test('item targets with no --under, and --top in place of it, are refused alike', () async {
      expect(
        await refusal(['rulebook:shop#INV-3'], under: null),
        'argument_missing 64: move needs --under <doc address> for item targets',
      );
      final top = await refusal(
        ['rulebook:shop#INV-3'],
        under: null,
        top: true,
      );
      expect(top, startsWith('argument_invalid 64: '));
    });

    test('an Overrides line outside the target chain refuses the move alike', () async {
      expect(
        await refusal(
          ['rulebook:shop#INV-3'],
          pay: [
            _inv(1),
            '- Overrides: [INV-3](../DOMAIN.md#invariants) — $_because',
          ],
        ),
        'argument_invalid 64: $_payDomain overrides $shopDomain#INV-3; $cartDomain sits outside its chain',
      );
      expect(
        await refusal(
          ['rulebook:shop#INV-3'],
          cart: [
            _inv(1),
            '- Overrides: [INV-3](../DOMAIN.md#invariants) — $_because',
          ],
        ),
        'argument_invalid 64: $cartDomain overrides $shopDomain#INV-3; $cartDomain sits outside its chain',
      );
    });

    test('a moved item whose own Overrides line leaves the target chain refuses the move alike', () async {
      expect(
        await refusal(
          ['rulebook:shop/cart/coupon#INV-5'],
          cart: [_inv(1), _inv(2)],
          extra: _couponWithOverride,
          under: 'rulebook:shop/pay',
        ),
        'argument_invalid 64: $_couponDomain#INV-5 overrides $cartDomain#INV-2, outside the chain of $_payDomain',
      );
      expect(
        await refusal(
          ['rulebook:shop/cart/coupon#INV-5'],
          cart: [_inv(1), _inv(2)],
          extra: _couponWithOverride,
        ),
        'argument_invalid 64: $_couponDomain#INV-5 overrides $cartDomain#INV-2, outside the chain of $cartDomain',
      );
    });

    test(
      'an untyped file as the source or as --under is untyped_target alike',
      () async {
        final extra = {
          'docs/$_notes': '# Notes\n\n## Invariants\n\n${_inv(3)}\n',
        };
        final source = await refusal(['$_notes#INV-3'], extra: extra);
        expect(
          source,
          startsWith('untyped_target 64: $_notes has no doc type'),
        );
        final under = await refusal(
          ['rulebook:shop#INV-3'],
          extra: extra,
          under: _notes,
        );
        expect(under, startsWith('untyped_target 64: $_notes has no doc type'));
      },
    );

    test('a doc move of any kind given --target is refused alike', () async {
      final extra = {
        'docs/prds/features/f02_shop/f01_cart/us01_add_item/nf01_stock_time.md': '# Stock time\n\n## Statement\n\nThe system shall check stock within 1 s.\n',
      };
      for (final (target, under) in [
        ('user_story:shop/cart/add_item', 'shop/pay'),
        ('fr:shop/cart/add_item/check_stock', 'shop/pay/refund'),
        ('nf:shop/cart/add_item/stock_time', 'shop/pay/refund'),
        ('feature:shop/cart', 'shop'),
      ]) {
        expect(
          await refusal(
            [target],
            under: under,
            codeTarget: 'server',
            extra: extra,
          ),
          'argument_invalid 64: move takes --target only with item targets',
          reason: target,
        );
      }
    });

    test(
      'a suffix that reads as an item ID the doc lacks is item_not_found alike',
      () async {
        expect(
          await refusal(['rulebook:shop#phase2']),
          'item_not_found 64: $shopDomain holds no phase2',
        );
      },
    );

    test('a suffix that reads as no item ID makes the whole text a doc target, refused alike', () async {
      for (final target in [
        'rulebook:shop#invariants',
        'rulebook:shop#a#INV-3',
      ]) {
        expect(
          await refusal([target]),
          startsWith('argument_invalid 64: '),
          reason: target,
        );
      }
    });
  });

  group('position numbers and retired IDs', () {
    const dropFr =
        'prds/features/f02_shop/f01_cart/us01_add_item/fr02_drop_stock.md';
    const checkStock = 'fr:shop/cart/add_item/check_stock';

    /// An FR whose edge cases are Case 1 to [count], each at its position.
    String fr(int count) =>
        '---\ntraced_from:\n  - S1\nverify_method: test\n---\n\n'
        '# Requirement\n\n## Statement\n$checkStockStatement\n\n'
        '## Edge cases\n'
        '${[for (var n = 1; n <= count; n++) '$n. E0$n — Case $n → refused.'].join('\n')}\n\n'
        '## Rationale\nStock is finite.\n\n'
        '## Verification\nTest: a case is refused.\n';

    Future<Directory> project({required int source, required int target}) =>
        writeNestedProject(
          extra: {'docs/$cartAddFr': fr(source), 'docs/$dropFr': fr(target)},
        );

    List<String> edgeCasesOf(Directory root, String docPath) => [
      for (final line in readDoc(root, docPath).split('\n'))
        if (RegExp(r'^\d+\. E').hasMatch(line)) line,
    ];

    ReadAnswer move(Directory root, List<String> addresses) => writeIn(
      root,
      (session) => answerMove(
        session,
        addresses,
        under: 'fr:shop/cart/add_item/drop_stock',
        generators: noGenerators,
      ),
    );

    test('moved edge cases number from one in their new order', () async {
      final root = await project(source: 3, target: 0);
      final answer = move(root, ['$checkStock#E03', '$checkStock#E01']);
      expect(edgeCasesOf(root, dropFr), [
        '1. E01 — Case 3 → refused.',
        '2. E02 — Case 1 → refused.',
      ]);
      expect(
        answer.text,
        startsWith(
          'moved $cartAddFr#E03 to $dropFr#E01\n'
          'moved $cartAddFr#E01 to $dropFr#E02\n'
          'renumbered $dropFr E03 to E01\n'
          'renumbered $dropFr E01 to E02\n'
          'renumbered $cartAddFr E02 to E01\n',
        ),
      );
      expect(readDoc(root, cartAddFr), isNot(contains('retired_ids')));
    });

    test('source edge cases close the gap', () async {
      final root = await project(source: 3, target: 1);
      final answer = move(root, ['$checkStock#E02']);
      expect(edgeCasesOf(root, cartAddFr), [
        '1. E01 — Case 1 → refused.',
        '2. E02 — Case 3 → refused.',
      ]);
      expect(edgeCasesOf(root, dropFr), [
        '1. E01 — Case 1 → refused.',
        '2. E02 — Case 2 → refused.',
      ]);
      expect(answer.text, contains('renumbered $cartAddFr E03 to E02\n'));
    });

    test(
      'moved item whose id the target retired takes the next free number',
      () async {
        final root = await _project(
          shop: [_inv(1), _inv(2), _inv(3)],
          extra: {
            'docs/$cartDomain':
                '---\nretired_ids:\n  - INV-3\n---\n\n'
                '${_domain([_inv(1), _inv(12)])}',
          },
        );
        final landings = _plan(root, [
          'rulebook:shop#INV-3',
          'rulebook:shop#INV-1',
        ]);
        expect([for (final l in landings) l.newId], ['INV-13', 'INV-14']);
      },
    );

    test('rule leaving a doc is retired there', () async {
      final root = await _project(
        shop: [_inv(1), _inv(2), _inv(3)],
        cart: [_inv(1)],
      );
      writeIn(
        root,
        (session) => answerMove(
          session,
          ['rulebook:shop#INV-3'],
          under: 'rulebook:shop/cart',
          generators: noGenerators,
        ),
      );
      expect(readDoc(root, shopDomain), contains('retired_ids:\n  - INV-3\n'));
      expect(readDoc(root, cartDomain), isNot(contains('retired_ids')));
    });
  });
}
