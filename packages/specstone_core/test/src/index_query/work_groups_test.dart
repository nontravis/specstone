// The test titles are row and edge case names kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/work_groups.dart';
import 'package:test/test.dart';

import '../../helpers/nested_fixture.dart';

/// Returns a story of about [tokens] est. tokens; [use] opens its use case.
String _paddedStory(String title, int tokens, {String use = ''}) =>
    '# $title\n\n## Use Case\n$use${'Pad words. ' * (tokens * 4 ~/ 11)}\n';

/// The docs of three stories of about 20,000 est. tokens each, `card`
/// linking `add_item`, so two fill a group and the third opens the next.
Map<String, String> _threeLargeStories() => {
  'docs/$cartAdd': _paddedStory('Agent adds an item', 20000),
  'docs/$cartDrop': _paddedStory('Agent drops an item', 20000),
  'docs/$payCard': _paddedStory(
    'Agent pays by card',
    20000,
    use: 'Pay for the [added item](../../f01_cart/us01_add_item/USER_STORY.md). ',
  ),
};

const _largeTargets = [
  'shop/pay/card',
  'shop/cart/add_item',
  'shop/cart/drop_item',
];

List<WorkGroup> _groups(
  DocIndex index,
  List<String> targets, [
  BundleMode mode = BundleMode.implement,
]) => pickWorkGroups(index, targets, mode, noProject: false).groups;

List<String> _addresses(WorkGroup group) => [
  for (final unit in group.units) unit.address,
];

/// Returns what a group holds, its targets as a set, so two runs compare.
Map<String, Object> _shapeOf(WorkGroup group) => {
  'number': group.number,
  'targets': group.targets.toSet(),
  'tokens': group.tokens,
  'units': [
    for (final unit in group.units)
      {'address': unit.address, 'docs': unit.docPaths, 'tokens': unit.tokens},
  ],
};

void main() {
  test('E04: two targets whose work units share a doc form one work unit, sized once, its address the story', () async {
    final groups = _groups(await nestedIndexWith(), [
      'shop/cart/add_item',
      'shop/cart/add_item/check_stock',
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.units, hasLength(1));
    expect(_addresses(groups.single), ['user_story:shop/cart/add_item']);
    expect(groups.single.units.single.docPaths, {cartAdd, cartAddFr});
  });

  test('work unit: a lone FR target in implement keeps the implement row, its work unit the FR alone', () async {
    final unit = _groups(await nestedIndexWith(), [
      'shop/cart/add_item/check_stock',
    ]).single.units.single;
    expect(unit.address, 'fr:shop/cart/add_item/check_stock');
    expect(unit.docPaths, {cartAddFr});
  });

  test('work unit: an FR target in design reads as its story, its address the story', () async {
    final unit = _groups(await nestedIndexWith(), [
      'shop/cart/add_item/check_stock',
    ], BundleMode.design).single.units.single;
    expect(unit.address, 'user_story:shop/cart/add_item');
    expect(unit.docPaths, {cartAdd, cartAddFr});
  });

  test(
    'E04: a feature and its story share no doc, so they stay two work units',
    () async {
      final groups = _groups(await nestedIndexWith(), [
        'shop/cart',
        'shop/cart/add_item',
      ], BundleMode.design);
      expect(groups, hasLength(1));
      expect(_addresses(groups.single), [
        'feature:shop/cart',
        'user_story:shop/cart/add_item',
      ]);
    },
  );

  test('E03: a work unit past the group budget alone forms a group of its own, whole', () async {
    final index = await nestedIndexWith({
      'docs/$cartAdd': _paddedStory('Agent adds an item', 60000),
    });
    final groups = _groups(index, [
      'shop/cart/add_item',
      'shop/cart/drop_item',
      'shop/pay/card',
    ]);
    expect(groups.map(_addresses), [
      ['user_story:shop/cart/add_item'],
      ['user_story:shop/cart/drop_item', 'user_story:shop/pay/card'],
    ]);
    expect(groups.first.tokens, greaterThan(workGroupBudget));
    expect(groups.first.units.single.docPaths, {cartAdd, cartAddFr});
  });

  test('groups: next-fit in docs-tree order, the link from card to add_item deciding no group (BR-02)', () async {
    final groups = _groups(
      await nestedIndexWith(_threeLargeStories()),
      _largeTargets,
    );
    expect(groups.map((group) => group.number), [1, 2]);
    expect(groups.map(_addresses), [
      ['user_story:shop/cart/add_item', 'user_story:shop/cart/drop_item'],
      ['user_story:shop/pay/card'],
    ]);
    expect(groups.map((group) => group.targets), [
      ['shop/cart/add_item', 'shop/cart/drop_item'],
      ['shop/pay/card'],
    ]);
    for (final group in groups) {
      expect(group.tokens, lessThanOrEqualTo(workGroupBudget));
    }
  });

  test(
    'group size: the chain docs above two work units of one group count once',
    () async {
      final index = await nestedIndexWith();
      final alone = _groups(index, ['shop/cart/add_item']).single;
      final chainAbove = alone.tokens - alone.units.single.tokens;
      expect(chainAbove, greaterThan(0));
      final both = _groups(index, [
        'shop/cart/add_item',
        'shop/cart/drop_item',
      ]).single;
      final [addItem, dropItem] = both.units;
      expect(both.tokens, addItem.tokens + dropItem.tokens + chainAbove);
    },
  );

  test('work unit, chain children: a nested feature is picked by --summary in design and by the top doc rule in implement, its unit itself and its spec docs', () async {
    final index = await nestedIndexWith();
    for (final mode in [BundleMode.design, BundleMode.implement]) {
      final unit = _groups(index, ['shop/cart'], mode).single.units.single;
      expect(unit.address, 'feature:shop/cart', reason: mode.wire);
      expect(unit.docPaths, {cartFeature, cartDomain}, reason: mode.wire);
    }
    final design = pickBundle(
      index,
      ['shop/cart'],
      BundleMode.design,
      noProject: false,
      picksWorkUnits: true,
    );
    expect(design.docPaths, {
      cartFeature,
      cartDomain,
      shopFeature,
      shopDomain,
      shopArchitecture,
      shopApi,
    });
    expect(design.summaryPaths, {cartAdd, cartAddFr, cartDrop});
    final implement = pickBundle(
      index,
      ['shop/cart'],
      BundleMode.implement,
      noProject: false,
      picksWorkUnits: true,
    );
    expect(implement.docPaths, {
      cartFeature,
      cartDomain,
      shopFeature,
      shopDomain,
      shopArchitecture,
      shopApi,
    });
    expect(implement.nameListTops, {cartFeature});
  });

  test(
    'the same targets in another order give the same groups on every run',
    () async {
      final index = await nestedIndexWith(_threeLargeStories());
      final first = _groups(index, _largeTargets).map(_shapeOf).toList();
      final again = _groups(index, _largeTargets.reversed.toList());
      expect(again.map(_shapeOf).toList(), first);
    },
  );
}
