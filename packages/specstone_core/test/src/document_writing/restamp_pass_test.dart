// The test names are plan text kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/finding.dart'
    show FindingKind;
import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/doc_model/doc_type_matcher.dart';
import 'package:specstone_core/src/document_writing/approval.dart';
import 'package:specstone_core/src/document_writing/move_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/rendering/line_ending.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart'
    show checkOf, checkProjectFiles, docTypeMatcherOf, fingerprintFor;
import '../../helpers/nested_fixture.dart';
import '../../helpers/shipped_pins.dart' show shippedStatusesOutside;
import '../../helpers/write_fixture.dart'
    show getDoc, readDoc, treeBytes, writeIn;

const _dropLink = '../us02_drop_item/USER_STORY.md';
const _matrix = '\n## Verification matrix\n\n';
const _soldOutCase = '1. E01 — A sold-out item → refused.';
const _keepStockFr =
    'prds/features/f02_shop/f01_cart/us02_drop_item/fr01_keep_stock.md';
const _cartDomainOverride =
    '- Overrides: [INV-1](../DOMAIN.md#invariants) — a cart order holds one item, because carts are small';

String _scenario(String title, {String given = 'a shopper'}) =>
    '### Scenario 1 — [happy] $title\n- **Given** $given\n'
    '- **When** the shopper acts\n- **Then** the shopper sees the result';

String _story(String title, String scenario) =>
    '---\ngoals:\n  - PG-01\n---\n\n# $title\n\n## Use Case\n'
    '- **As a** Agent who shops\n- **I want to** act\n- **so that** I finish an order\n\n'
    '## Acceptance Criteria\n\n$scenario\n';

String _fr(
  String title, {
  required String scenario,
  List<String> edgeCases = const [_soldOutCase],
  String statement = checkStockStatement,
}) =>
    '---\ntraced_from:\n  - S1\nverify_method: test\n'
    'confirmed:\n  - S1 ${fingerprintFor(scenario)}\n---\n\n'
    '# $title\n\n## Statement\n$statement\n\n'
    '## Edge cases\n${edgeCases.join('\n')}\n\n## Rationale\nStock is finite.\n\n'
    '## Verification\nTest: a sold-out item is refused.\n';

String _domain(String title, List<String> invariants, {String? overrides}) =>
    '${overrides == null ? '' : '---\noverrides:\n  - $overrides\n---\n\n'}'
    '# $title domain\n\n## Entities\n| Entity | Kind | Identity | Owns | Notes |\n'
    '|--------|------|----------|------|-------|\n| Order | Aggregate root | id | lines | — |\n\n'
    '## Invariants\n${invariants.join('\n')}\n';

String _record(String record, List<String> rows) =>
    '${nestedRecords()[record]}$_matrix${rows.join('\n')}\n';

String _row(String item, String edgeCase, String literal, String fingerprint) =>
    '- $item $edgeCase: `$literal` $fingerprint';

/// The `link` key of each `suspect` finding of the whole check of [root].
Future<List<Object?>> _suspects(Directory root) async => [
  for (final finding in (await checkOf(root)).findings)
    if (finding.kind == FindingKind.suspect) finding.keys['link'],
];

/// Expects the doc at [docPath] to be no draft and stamped with the approval
/// hash of its written text.
void _expectApprovedAgain(Directory root, String docPath) {
  final text = toLf(readDoc(root, docPath));
  final fields = ApprovalFields.of(Doc.parse(text));
  final match = docTypeMatcherOf({...checkProjectFiles(), ...nestedFiles()})
      .match(docPath);
  expect(fields.isDraft, isFalse);
  expect(
    fields.approvedValue,
    approvalHashOf(
      text,
      (match as MatchedDocType).docType,
      statusesOutside: shippedStatusesOutside,
    ),
  );
}

ReadAnswer _reorderDrop(Directory root, {bool dryRun = false}) => writeIn(
  root,
  (session) => answerReorder(
    session,
    'user_story:shop/cart/drop_item',
    place: '1',
    dryRun: dryRun,
  ),
);

ReadAnswer _renameDrop(Directory root) => writeIn(
  root,
  (session) => answerRename(
    session,
    'user_story:shop/cart/drop_item',
    slug: 'remove_item',
  ),
);

ReadAnswer _moveAddUnderPay(Directory root) => writeIn(
  root,
  (session) =>
      answerMove(session, ['user_story:shop/cart/add_item'], under: 'shop/pay'),
);

void main() {
  group('a reorder', () {
    const soldOut =
        '1. E01 — A sold-out item, as [drop]($_dropLink) shows → refused.';
    const missing =
        '2. E02 — A missing item, as [drop]($_dropLink) shows → refused.';
    String reordered(String text) =>
        text.replaceAll('us02_drop_item', 'us01_drop_item');
    final stale = fingerprintFor('2. E02 — An old text → refused.');

    Future<Directory> rowProject() => writeNestedProject(
      extra: {
        'docs/$cartAddFr': _fr(
          'Check the stock',
          scenario: _scenario('Add an item'),
          edgeCases: [soldOut, missing],
        ),
        ...nestedRecords(),
        cartRecord: _record(cartRecord, [
          _row(
            'add_item/check_stock',
            'E01',
            'refuses a sold-out item',
            fingerprintFor(soldOut),
          ),
          _row('add_item/check_stock', 'E02', 'refuses a missing item', stale),
        ]),
      },
    );

    test('a reorder re-stamps a matched row whose edge case link it rewrites and leaves a stale row as written', () async {
      final root = await rowProject();
      final before = readDoc(root, cartRecord);
      _reorderDrop(root);
      expect(
        readDoc(root, cartRecord),
        before.replaceFirst(
          fingerprintFor(soldOut),
          fingerprintFor(reordered(soldOut)),
        ),
      );
      expect(await _suspects(root), ['add_item/check_stock#E02']);
    });

    test('a reorder re-stamps a matched confirmed and overrides entry whose block link it rewrites, and stamps the approval hash again', () async {
      final scenario = _scenario(
        'Add an item',
        given: 'a shopper, as [drop]($_dropLink) shows',
      );
      const shopRule =
          '- **INV-1** An order holds at least one line, as [add](../../prds/features/f02_shop/f01_cart/us01_add_item/USER_STORY.md) shows.';
      final root = await writeNestedProject(
        extra: {
          'docs/$cartAdd': _story('Agent adds an item', scenario),
          'docs/$cartAddFr': _fr('Check the stock', scenario: scenario),
          'docs/$shopDomain': _domain('Shop', [shopRule]),
          'docs/$cartDomain': _domain('Cart', [
            '- **INV-1** An order holds at least one line.',
            _cartDomainOverride,
          ], overrides: 'domain:shop#INV-1 ${fingerprintFor(shopRule)}'),
        },
      );
      _reorderDrop(root);
      const movedFr =
          'prds/features/f02_shop/f01_cart/us02_add_item/fr01_check_stock.md';
      expect(
        readDoc(root, movedFr),
        contains('  - S1 ${fingerprintFor(reordered(scenario))}\n'),
      );
      expect(
        readDoc(root, cartDomain),
        contains(
          '  - domain:shop#INV-1 '
          '${fingerprintFor(shopRule.replaceFirst('us01_add_item', 'us02_add_item'))}\n',
        ),
      );
      _expectApprovedAgain(root, movedFr);
      _expectApprovedAgain(root, cartDomain);
      expect(await _suspects(root), isEmpty);
    });

    test('a reorder dry run names a record changed by stamping alone and writes nothing', () async {
      final root = await rowProject();
      Map<String, List<int>> files() => {
        for (final MapEntry(:key, :value) in treeBytes(root).entries)
          if (!key.contains('.specstone/index.sqlite')) key: value,
      };
      // A first session lays down the index and its ignore file.
      getDoc(root, 'user_story:shop/cart/drop_item');
      final before = files();
      final answer = _reorderDrop(root, dryRun: true);
      expect(answer.text, contains('rewrites $cartRecord\n'));
      expect(answer.json['rewritten'], contains(cartRecord));
      expect(files(), before);
      expect(await _suspects(root), ['add_item/check_stock#E02']);
    });

    test('an entry the pass never judged keeps its bytes, and the matched entry sharing its fingerprint takes the new one', () async {
      final scenario = _scenario(
        'Add an item',
        given: 'a shopper, as [drop]($_dropLink) shows',
      );
      final recorded = fingerprintFor(scenario);
      final root = await writeNestedProject(
        extra: {
          'docs/$cartAdd': _story('Agent adds an item', scenario),
          'docs/$cartAddFr': _fr('Check the stock', scenario: scenario)
              .replaceFirst(
                '  - S1 $recorded\n',
                '  - S1 $recorded\n  - S2 $recorded\n',
              ),
        },
      );
      _reorderDrop(root);
      const movedFr =
          'prds/features/f02_shop/f01_cart/us02_add_item/fr01_check_stock.md';
      expect(
        readDoc(root, movedFr),
        contains(
          'confirmed:\n  - S1 ${fingerprintFor(reordered(scenario))}\n'
          '  - S2 $recorded\n',
        ),
      );
      expect(await _suspects(root), isEmpty);
    });
  });

  group('a doc move', () {
    test(
      'a moved doc whose tracked block keeps its text keeps every entry byte',
      () async {
        final root = await writeNestedProject();
        final confirmed = RegExp(r'confirmed:\n(?:  - .*\n)+');
        final before = confirmed.firstMatch(readDoc(root, cartAddFr))![0];
        _moveAddUnderPay(root);
        const movedFr =
            'prds/features/f02_shop/f02_pay/us03_add_item/fr01_check_stock.md';
        expect(confirmed.firstMatch(readDoc(root, movedFr))![0], before);
        expect(await _suspects(root), isEmpty);
      },
    );

    test('two entries sharing a recorded fingerprint whose blocks part keep their values', () async {
      const sharedCase = '1. E01 — See [cart](../FEATURE.md) → refused.';
      final shared = fingerprintFor(sharedCase);
      final root = await writeNestedProject(
        extra: {
          'docs/$cartAddFr': _fr(
            'Check the stock',
            scenario: _scenario('Add an item'),
            edgeCases: [sharedCase],
          ),
          'docs/$_keepStockFr': _fr(
            'Keep the stock',
            scenario: _scenario('Drop an item'),
            edgeCases: [sharedCase],
          ),
          ...nestedRecords(),
          cartRecord: _record(cartRecord, [
            _row('add_item/check_stock', 'E01', 'refuses an item', shared),
            _row('drop_item/keep_stock', 'E01', 'refuses an item', shared),
          ]),
        },
      );
      _moveAddUnderPay(root);
      expect(
        readDoc(root, cartRecord),
        contains(
          '${_row('drop_item/keep_stock', 'E01', 'refuses an item', shared)}\n',
        ),
      );
      expect(
        readDoc(root, payRecord),
        contains(
          '${_row('add_item/check_stock', 'E01', 'refuses an item', shared)}\n',
        ),
      );
      expect(await _suspects(root), ['add_item/check_stock#E01']);
    });

    test('a story move re-stamps a carried row and a trace entry whose block link it rewrites', () async {
      final scenario = _scenario(
        'Add an item',
        given: 'a shopper, as [drop]($_dropLink) shows',
      );
      const soldOut =
          '1. E01 — A sold-out item, as [cart](../FEATURE.md) shows → refused.';
      final root = await writeNestedProject(
        extra: {
          'docs/$cartAdd': _story('Agent adds an item', scenario),
          'docs/$cartAddFr': _fr(
            'Check the stock',
            scenario: scenario,
            edgeCases: [soldOut],
          ),
          ...nestedRecords(),
          cartRecord: _record(cartRecord, [
            _row(
              'add_item/check_stock',
              'E01',
              'refuses a sold-out item',
              fingerprintFor(soldOut),
            ),
          ]),
        },
      );
      _moveAddUnderPay(root);
      const movedFr =
          'prds/features/f02_shop/f02_pay/us03_add_item/fr01_check_stock.md';
      final movedScenario = scenario.replaceFirst(
        _dropLink,
        '../../f01_cart/us02_drop_item/USER_STORY.md',
      );
      final movedCase = soldOut.replaceFirst(
        '../FEATURE.md',
        '../../f01_cart/FEATURE.md',
      );
      expect(
        readDoc(root, payRecord),
        contains(
          '${_row('add_item/check_stock', 'E01', 'refuses a sold-out item', fingerprintFor(movedCase))}\n',
        ),
      );
      expect(
        readDoc(root, movedFr),
        contains('  - S1 ${fingerprintFor(movedScenario)}\n'),
      );
      expect(await _suspects(root), isEmpty);
    });

    test('an FR move re-stamps its own rows and traces whose block link it rewrites', () async {
      final scenario = _scenario(
        'Add an item',
        given: 'a shopper, as [stock](fr01_check_stock.md) shows',
      );
      const soldOut =
          '1. E01 — A sold-out item, as [add](USER_STORY.md) shows → refused.';
      final root = await writeNestedProject(
        extra: {
          'docs/$cartAdd': _story('Agent adds an item', scenario),
          'docs/$cartAddFr': _fr(
            'Check the stock',
            scenario: scenario,
            edgeCases: [soldOut],
          ),
          ...nestedRecords(),
          cartRecord: _record(cartRecord, [
            _row(
              'add_item/check_stock',
              'E01',
              'refuses a sold-out item',
              fingerprintFor(soldOut),
            ),
          ]),
        },
      );
      writeIn(
        root,
        (session) => answerMove(session, [
          'fr:shop/cart/add_item/check_stock',
        ], under: 'shop/cart/drop_item'),
      );
      const movedFr =
          'prds/features/f02_shop/f01_cart/us02_drop_item/fr01_check_stock.md';
      final movedScenario = scenario.replaceFirst(
        'fr01_check_stock.md',
        '../us02_drop_item/fr01_check_stock.md',
      );
      final movedCase = soldOut.replaceFirst(
        '(USER_STORY.md)',
        '(../us01_add_item/USER_STORY.md)',
      );
      expect(
        readDoc(root, movedFr),
        contains(
          '  - shop/cart/add_item#S1 ${fingerprintFor(movedScenario)}\n',
        ),
      );
      expect(
        readDoc(root, cartRecord),
        contains(
          '${_row('drop_item/check_stock', 'E01', 'refuses a sold-out item', fingerprintFor(movedCase))}\n',
        ),
      );
      expect(await _suspects(root), isEmpty);
    });

    test(
      'a feature move re-stamps a trace whose scenario link it rewrites',
      () async {
        final scenario = _scenario(
          'Add an item',
          given: 'a shopper, as [pay](../../f02_pay/FEATURE.md) shows',
        );
        final root = await writeNestedProject(
          extra: {
            'docs/$cartAdd': _story('Agent adds an item', scenario),
            'docs/$cartAddFr': _fr('Check the stock', scenario: scenario),
          },
        );
        writeIn(
          root,
          (session) => answerMove(
            session,
            ['feature:shop/cart'],
            under: null,
            top: true,
          ),
        );
        const movedFr =
            'prds/features/f03_cart/us01_add_item/fr01_check_stock.md';
        final movedScenario = scenario.replaceFirst(
          '../../f02_pay/FEATURE.md',
          '../../f02_shop/f02_pay/FEATURE.md',
        );
        expect(
          readDoc(root, movedFr),
          contains('  - S1 ${fingerprintFor(movedScenario)}\n'),
        );
        expect(await _suspects(root), isEmpty);
      },
    );
  });

  group('a rename', () {
    String renamed(String text) => text.replaceAll('drop_item', 'remove_item');

    test('a rename re-stamps a row whose edge case holds the renamed name in a code span or a mermaid node', () async {
      const spanCase =
          '1. E01 — A sold-out item, as `shop/cart/drop_item` shows → refused.';
      const nodeCase =
          '2. E02 — A missing item → refused.\n'
          '   ```mermaid\n   flowchart LR\n     N[shop/cart/drop_item E01]\n   ```';
      final root = await writeNestedProject(
        extra: {
          'docs/$cartAddFr': _fr(
            'Check the stock',
            scenario: _scenario('Add an item'),
            edgeCases: [spanCase, nodeCase],
          ),
          ...nestedRecords(),
          cartRecord: _record(cartRecord, [
            _row(
              'add_item/check_stock',
              'E01',
              'refuses a sold-out item',
              fingerprintFor(spanCase),
            ),
            _row(
              'add_item/check_stock',
              'E02',
              'refuses a missing item',
              fingerprintFor(nodeCase),
            ),
          ]),
        },
      );
      _renameDrop(root);
      final record = readDoc(root, cartRecord);
      expect(
        record,
        contains(
          '${_row('add_item/check_stock', 'E01', 'refuses a sold-out item', fingerprintFor(renamed(spanCase)))}\n',
        ),
      );
      expect(
        record,
        contains(
          '${_row('add_item/check_stock', 'E02', 'refuses a missing item', fingerprintFor(renamed(nodeCase)))}\n',
        ),
      );
      expect(await _suspects(root), isEmpty);
    });

    test('a rename leaves a row alone when its edge case text is untouched', () async {
      final kept = fingerprintFor(_soldOutCase);
      final root = await writeNestedProject(
        extra: {
          ...nestedRecords(),
          cartRecord: _record(cartRecord, [
            _row(
              'add_item/check_stock',
              'E01',
              'refuses a sold-out item',
              kept,
            ),
          ]),
        },
      );
      writeIn(
        root,
        (session) => answerRename(
          session,
          'user_story:shop/cart/add_item',
          slug: 'put_item',
        ),
      );
      expect(
        readDoc(root, cartRecord),
        endsWith(
          '$_matrix${_row('put_item/check_stock', 'E01', 'refuses a sold-out item', kept)}\n',
        ),
      );
      expect(await _suspects(root), isEmpty);
    });

    test('a rename re-stamps a confirmed entry whose scenario link it rewrites and an overrides entry whose item link it rewrites', () async {
      final scenario = _scenario(
        'Add an item',
        given: 'a shopper, as [drop]($_dropLink) shows',
      );
      const shopRule =
          '- **INV-1** An order holds at least one line, as [drop](../../prds/features/f02_shop/f01_cart/us02_drop_item/USER_STORY.md) shows.';
      const statement =
          'The system shall refuse an item that is out of stock, as [drop](../us02_drop_item/USER_STORY.md) shows.';
      final stale = fingerprintFor('The system shall refuse nothing.');
      final root = await writeNestedProject(
        extra: {
          'docs/$cartAdd': _story('Agent adds an item', scenario),
          'docs/$cartAddFr': _fr(
            'Check the stock',
            scenario: scenario,
            statement: statement,
          ),
          'docs/$shopDomain': _domain('Shop', [shopRule]),
          'docs/$cartDomain': _domain('Cart', [
            '- **INV-1** An order holds at least one line.',
            _cartDomainOverride,
          ], overrides: 'domain:shop#INV-1 ${fingerprintFor(shopRule)}'),
          'docs/$shopApi': nestedFiles()['docs/$shopApi']!.replaceFirst(
            fingerprintFor(checkStockStatement),
            stale,
          ),
        },
      );
      _renameDrop(root);
      expect(
        readDoc(root, cartAddFr),
        contains('  - S1 ${fingerprintFor(renamed(scenario))}\n'),
      );
      expect(
        readDoc(root, cartDomain),
        contains(
          '  - domain:shop#INV-1 ${fingerprintFor(renamed(shopRule))}\n',
        ),
      );
      expect(
        readDoc(root, shopApi),
        contains('  - cart/add_item/check_stock $stale\n'),
      );
      expect(await _suspects(root), ['cart/add_item/check_stock']);
    });
  });
}
