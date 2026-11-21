// The test titles are plan values kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/index_query/bundle.dart';
import 'package:specstone_core/src/index_query/bundle_join.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/refs.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/skill_doc_fixture.dart';

const _reviewer = 'specs/agents/reviewer.md';
const _other = 'specs/agents/other.md';
const _review = 'specs/skills/review.md';

/// An agent doc whose `feature` field names [features].
Map<String, String> _agent(String slug, List<String> features) => {
  'docs/specs/agents/$slug.md':
      '---\nfeature:\n${[for (final f in features) '  - $f\n'].join()}---\n\n'
      '# $slug\n\n## Role\n\nReviews a diff.\n',
};

Map<String, String> _skill(String slug, List<String> features) => {
  'docs/specs/skills/$slug.md':
      '---\nfeature:\n${[for (final f in features) '  - $f\n'].join()}---\n\n'
      '# $slug\n\n## Purpose\n\nReviews a diff.\n',
};

Future<DocIndex> _index(Map<String, String> docs) =>
    nestedIndexWith({'.specstone/config.yaml': skillPinsConfig(), ...docs});

Bundle _design(DocIndex index, List<String> targets, {bool summary = false}) =>
    pickBundle(
      index,
      targets,
      BundleMode.design,
      noProject: false,
      summary: summary,
    );

Map<String, String> _anchors(Bundle bundle) => {
  for (final MapEntry(:key, :value) in bundle.linkedDocs.entries)
    key: value.anchorPath,
};

void main() {
  test(
    'a design bundle of a top doc joins a holder naming a doc of its subtree',
    () async {
      final index = await _index({
        ..._agent('reviewer', ['shop/cart']),
      });
      final b = _design(index, ['shop']);
      expect(_anchors(b), {_reviewer: cartFeature});
      expect(b.linkedDocs[_reviewer]!.direction, JoinDirection.inward);
      expect(b.docPaths, isNot(contains(_reviewer)));
    },
  );

  test("the second target's holder joins from its own top doc", () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/pay']),
    });
    final b = _design(index, ['shop/cart/add_item', 'shop/pay/card']);
    expect(_anchors(b), {_reviewer: payFeature});
  });

  test('a holder naming the doc above the top doc does not join', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart']),
      ..._agent('other', ['shop']),
    });
    final b = _design(index, ['shop/cart/add_item']);
    expect(_anchors(b), {_reviewer: cartFeature});
  });

  test('a holder naming a summary sub-feature does not join', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart']),
      ..._agent('other', ['shop']),
    });
    final b = _design(index, ['shop'], summary: true);
    expect(b.summaryPaths, contains(cartFeature));
    expect(_anchors(b), {_other: shopFeature});
  });

  test('a holder target joins its named doc outward in every mode', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart']),
    });
    for (final mode in BundleMode.values) {
      final b = pickBundle(index, ['agent:reviewer'], mode, noProject: false);
      expect(_anchors(b), {cartFeature: _reviewer}, reason: mode.wire);
      expect(
        b.linkedDocs[cartFeature]!.direction,
        JoinDirection.outward,
        reason: mode.wire,
      );
    }
  });

  test('a cross-target join of a summary doc', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart']),
    });
    final bundle = Bundle(BundleMode.design)
      ..summaryPaths.add(cartFeature)
      ..docPaths.addAll([shopFeature, _reviewer]);
    joinLinkedDocs(index, bundle, [
      const TargetPicks(
        topPath: shopFeature,
        wholePaths: {shopFeature},
        summaryPaths: {cartFeature},
        subtreePaths: {shopFeature},
      ),
      const TargetPicks(
        topPath: _reviewer,
        wholePaths: {_reviewer},
        summaryPaths: {},
        subtreePaths: {_reviewer},
        targetPath: _reviewer,
      ),
    ]);
    expect(bundle.linkedDocs, isEmpty);
    expect(bundle.docPaths, contains(cartFeature));
    expect(bundle.summaryOnly, isEmpty);
  });

  test('a doc one target prints in summary stays summary for the target that holds it', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart']),
    });
    final bundle = Bundle(BundleMode.design)
      ..summaryPaths.add(cartFeature)
      ..docPaths.add(_reviewer);
    joinLinkedDocs(index, bundle, [
      const TargetPicks(
        topPath: _reviewer,
        wholePaths: {_reviewer},
        summaryPaths: {cartFeature},
        subtreePaths: {_reviewer},
        targetPath: _reviewer,
      ),
    ]);
    expect(bundle.docPaths, isNot(contains(cartFeature)));
    expect(bundle.linkedDocs, isEmpty);
  });

  test('two holders naming one doc', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart']),
      ..._agent('other', ['shop/cart']),
    });
    final b = pickBundle(
      index,
      ['agent:reviewer', 'agent:other'],
      BundleMode.implement,
      noProject: false,
    );
    expect(b.linkedDocs.keys, [cartFeature]);
    expect(b.linkedDocs[cartFeature]!.anchorPath, _other);
    final inward = _design(index, ['shop']);
    expect(inward.linkedDocs.keys, [_other, _reviewer]);
  });

  test('a picked doc under a join', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart']),
    });
    final b = _design(index, ['shop', 'agent:reviewer']);
    expect(b.linkedDocs, isEmpty);
    expect(b.docPaths, containsAll([_reviewer, cartFeature]));
  });

  test('a joined doc joins nothing further', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart', 'shop/pay']),
    });
    final b = _design(index, ['shop/cart/add_item']);
    expect(b.linkedDocs.keys, [_reviewer]);
    expect(b.docPaths, isNot(contains(payFeature)));
  });

  test('a skill and an agent naming one doc join in tree order', () async {
    final index = await _index({
      ..._skill('review', ['shop/cart']),
      ..._agent('reviewer', ['shop/cart']),
    });
    final b = _design(index, ['shop/cart/add_item']);
    expect(b.linkedDocs.keys, [_reviewer, _review]);
  });

  test('a value outside the field doc_types joins nothing', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart/add_item']),
    });
    expect(_design(index, ['shop']).linkedDocs, isEmpty);
    expect(
      pickBundle(
        index,
        ['agent:reviewer'],
        BundleMode.implement,
        noProject: false,
      ).linkedDocs,
      isEmpty,
    );
  });

  for (final (label, docTypes) in [
    ('no doc_types', ''),
    ('an empty doc_types', '    doc_types: []\n'),
  ]) {
    test('a bundle_with field with $label joins nothing', () async {
      final index = await _index({
        '.specstone/templates/agent.yaml':
            'fields:\n  - id: about\n    type: doc_ref\n'
            '    bundle_with: true\n$docTypes',
        'docs/specs/agents/reviewer.md':
            '---\nabout:\n  - shop/cart/add_item\n---\n\n'
            '# reviewer\n\n## Role\n\nReviews a diff.\n',
      });
      final holder = index.at(_reviewer)!;
      final story = index.at(cartAdd)!;
      expect(linkedDocsOf(index, holder), isEmpty);
      expect(holdersNaming(index, story), isEmpty);
      expect(_design(index, ['shop/cart/add_item']).linkedDocs, isEmpty);
      expect(
        pickBundle(
          index,
          ['agent:reviewer'],
          BundleMode.implement,
          noProject: false,
        ).linkedDocs,
        isEmpty,
      );
    });
  }

  test('a doc_ref field with no bundle_with key joins nothing', () async {
    final index = await indexWith();
    final story = index.at(
      'prds/features/f01_login/us01_email_login/USER_STORY.md',
    )!;
    final persona = index.typeOf(story)!.fields.where((f) => f.id == 'persona');
    expect(persona.single.bundleWith, isNull);
    expect(linkedDocsOf(index, story), isEmpty);
    expect(_design(index, ['login']).linkedDocs, isEmpty);
  });

  test('--no-project keeps a join', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart']),
    });
    final b = pickBundle(index, ['shop'], BundleMode.design, noProject: true);
    expect(_anchors(b), {_reviewer: cartFeature});
  });

  test('a childless holder target prints its outward join, its bundle: docs, and no inward holder', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart']),
    });
    final b = pickBundle(
      index,
      ['agent:reviewer'],
      BundleMode.implement,
      noProject: false,
    );
    expect(b.docPaths, {_reviewer});
    expect(_anchors(b), {cartFeature: _reviewer});
    expect(b.joinedPaths, isNotEmpty);
  });

  test('holdersNaming lists the holders of a doc in tree order', () async {
    final index = await _index({
      ..._skill('review', ['shop/cart']),
      ..._agent('reviewer', ['shop/cart']),
      ..._agent('other', ['shop/pay']),
    });
    final cart = index.at(cartFeature)!;
    expect(holdersNaming(index, cart).map((d) => d.docPath), [
      _reviewer,
      _review,
    ]);
  });

  test('two targets of one feature join a holder once', () async {
    final index = await _index({
      ..._agent('reviewer', ['shop/cart']),
    });
    final b = _design(index, ['shop/cart/add_item', 'shop/cart/drop_item']);
    expect(b.linkedDocs.keys, [_reviewer]);
  });
}
