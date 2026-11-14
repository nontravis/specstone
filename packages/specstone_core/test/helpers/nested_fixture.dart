// The file contents are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:test/test.dart';

import 'check_fixture.dart';
import 'index_fixture.dart';

/// The DocPath of the top feature `shop`.
const shopFeature = 'prds/features/f02_shop/FEATURE.md';

/// The DocPath of the sub-feature `shop/cart`.
const cartFeature = 'prds/features/f02_shop/f01_cart/FEATURE.md';

/// The DocPath of the sub-feature `shop/pay`.
const payFeature = 'prds/features/f02_shop/f02_pay/FEATURE.md';

/// The DocPath of the story `shop/cart/add_item`.
const cartAdd = 'prds/features/f02_shop/f01_cart/us01_add_item/USER_STORY.md';

/// The DocPath of the FR `shop/cart/add_item/check_stock`.
const cartAddFr =
    'prds/features/f02_shop/f01_cart/us01_add_item/fr01_check_stock.md';

/// The DocPath of the story `shop/cart/drop_item`.
const cartDrop = 'prds/features/f02_shop/f01_cart/us02_drop_item/USER_STORY.md';

/// The DocPath of the story `shop/pay/card`.
const payCard = 'prds/features/f02_shop/f02_pay/us01_card/USER_STORY.md';

/// The DocPath of the story `shop/pay/refund`.
const payRefund = 'prds/features/f02_shop/f02_pay/us02_refund/USER_STORY.md';

/// The DocPath of the record of the sub-feature `shop/cart`.
const cartRecord = 'specs/f02_shop/f01_cart/IMPLEMENTATION.md';

/// The DocPath of the record of the sub-feature `shop/pay`.
const payRecord = 'specs/f02_shop/f02_pay/IMPLEMENTATION.md';

/// The records of `shop/cart` and `shop/pay`, keyed by path from the project
/// root: every story `implemented` but `refund`, which is [refund].
///
/// A test adds them as `extra`; the nested project holds no record itself.
Map<String, String> nestedRecords({String refund = 'planned'}) => {
  'docs/$cartRecord':
      "---\nstatuses:\n  - 'add_item:implemented'\n"
      "  - 'add_item/check_stock:implemented'\n  - 'drop_item:implemented'\n"
      "implements:\n  - 'add_item:app/lib/shop.dart:Shop'\n"
      "  - 'add_item/check_stock:app/lib/shop.dart:Shop'\n"
      '---\n\n# Cart implementation\n',
  'docs/$payRecord':
      "---\nstatuses:\n  - 'card:implemented'\n  - 'refund:$refund'\n"
      "implements:\n  - 'card:app/lib/shop.dart:Shop'\n"
      '---\n\n# Pay implementation\n',
};

/// The DocPath of the domain doc of `shop`.
const shopDomain = 'specs/f02_shop/DOMAIN.md';

/// The DocPath of the architecture doc of `shop`.
const shopArchitecture = 'specs/f02_shop/ARCHITECTURE.md';

/// The DocPath of the API doc of `shop`.
const shopApi = 'specs/f02_shop/API.md';

/// The DocPath of the domain doc of `shop/cart`.
const cartDomain = 'specs/f02_shop/f01_cart/DOMAIN.md';

/// The statement of the FR `shop/cart/add_item/check_stock`.
const checkStockStatement =
    'The system shall refuse an item that is out of stock.';

String _scenario(String title) =>
    '### Scenario 1 — [happy] $title\n- **Given** a shopper\n'
    '- **When** the shopper acts\n- **Then** the shopper sees the result';

String _feature(String title) =>
    '---\nvision:\n  - PV-01\ngoals:\n  - PG-01\n---\n\n# $title\n\n'
    '## Problem\nShoppers need it.\n\n## Benefit hypothesis\nMore orders.\n\n'
    '## Success measures\nOrders per week.\n\n## Current alternatives\nPhone orders.\n\n'
    '## Feature flow\nBrowse, then buy.\n\n## Out-of-scope\n- Gift cards — not planned\n';

String _story(String title, String scenario) =>
    '---\ngoals:\n  - PG-01\n---\n\n# $title\n\n## Use Case\n'
    '- **As a** Agent who shops\n- **I want to** act\n- **so that** I finish an order\n\n'
    '## Acceptance Criteria\n\n${_scenario(scenario)}\n';

String _domain(String title) =>
    '# $title domain\n\n## Entities\n| Entity | Kind | Identity | Owns | Notes |\n'
    '|--------|------|----------|------|-------|\n| Order | Aggregate root | id | lines | — |\n\n'
    '## Invariants\n- **INV-1** An order holds at least one line.\n';

/// Returns the docs of the nested project, keyed by path from the project root.
///
/// Holds `shop` with the sub-features `cart` and `pay`, two stories each, and
/// the layer that sets `max_depth: 3` on `feature`. The stories carry no status;
/// [nestedRecords] holds it.
Map<String, String> nestedFiles() => {
  '.specstone/templates/feature.yaml': 'max_depth: 3\n',
  'app/lib/shop.dart': 'class Shop {}\n',
  'docs/$shopFeature': _feature('Shop'),
  'docs/$cartFeature': _feature('Cart'),
  'docs/$payFeature': _feature('Pay'),
  'docs/$cartAdd': _story('Agent adds an item', 'Add an item'),
  'docs/$cartAddFr':
      '---\ntraced_from:\n  - S1\nverify_method: test\n'
      'confirmed:\n  - S1 ${fingerprintFor(_scenario('Add an item'))}\n---\n\n'
      '# Check the stock\n\n## Statement\n$checkStockStatement\n\n'
      '## Edge cases\n1. E01 — A sold-out item → refused.\n\n## Rationale\nStock is finite.\n\n'
      '## Verification\nTest: a sold-out item is refused.\n',
  'docs/$cartDrop': _story('Agent drops an item', 'Drop an item'),
  'docs/$payCard': _story('Agent pays by card', 'Pay by card'),
  'docs/$payRefund': _story('Agent asks a refund', 'Ask a refund'),
  'docs/$shopDomain': _domain('Shop'),
  'docs/$cartDomain': _domain('Cart'),
  'docs/$shopArchitecture':
      '---\ncovers:\n  - app/lib/\n---\n\n# Shop architecture\n\n'
      '## Component diagram\nOne box.\n\n## Components\n'
      '| Component | Responsibility |\n|---|---|\n| Shop | Sells items |\n\n'
      '## Concerns\n- Integration: N/A — no outside call\n- Errors: see Components\n'
      '- Auth: N/A — one local user\n- Lifecycle: N/A — no states\n- Events: N/A — no events\n'
      '- Rollout: N/A — one release\n- Observability: N/A — no telemetry\n',
  'docs/$shopApi':
      '---\nconfirmed:\n  - cart/add_item/check_stock ${fingerprintFor(checkStockStatement)}\n---\n\n'
      '# Shop API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
      '| cart/add_item/check_stock | `addItem` |\n\n'
      '## Operations\n### addItem\nAdds an item for the story '
      '[add item](../../prds/features/f02_shop/f01_cart/us01_add_item/USER_STORY.md).\n',
};

/// Writes the check fixture and the nested docs under a new temp folder.
///
/// A key in [extra] replaces or adds a file; a path in [without] drops one.
Future<Directory> writeNestedProject({
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) => writeCheckProject(extra: {...nestedFiles(), ...extra}, without: without);

/// Opens a session on the nested project with [extra] files and returns its
/// index; `addTearDown` closes the session.
Future<DocIndex> nestedIndexWith([Map<String, String> extra = const {}]) async {
  final session = openSession(await writeNestedProject(extra: extra));
  addTearDown(session.close);
  return session.index;
}
