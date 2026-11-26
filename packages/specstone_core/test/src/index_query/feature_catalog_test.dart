import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/feature_catalog.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/generator_kinds.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _featuresDoc = 'prds/FEATURES.md';
const _tableHeader = '| Feature | What it does | Status | Stories | Serves |';
const _groupTableHeader = '| Group | Features | Status | Stories |';
const _groupedRecordPath =
    '.specstone/records/{slug}/f{nn}_{slug}/IMPLEMENTATION.md';
const _dash = '—';

/// The files of one feature at [dir] under `prds/features/`, with a story per
/// name of [stories].
Map<String, String> _feature(
  String dir,
  String title, {
  String front = '',
  List<String> stories = const [],
  String? text,
}) => {
  'docs/prds/features/$dir/FEATURE.md':
      text ??
      '${front.isEmpty ? '' : '---\n$front---\n\n'}'
          '# $title\n\n## Problem\nNeed it.\n',
  for (var n = 0; n < stories.length; n++)
    'docs/prds/features/$dir/us0${n + 1}_${stories[n]}/USER_STORY.md':
        '# Agent uses ${stories[n]}\n\n## Use Case\nUse it.\n',
};

/// The record of the feature at [dir] in [target], or the one unnamed target.
Map<String, String> _record(
  String dir,
  List<String> entries, {
  String? target,
}) => {
  '.specstone/records/${target == null ? '' : '$target/'}$dir/IMPLEMENTATION.md':
      '---\nstatuses:\n${[for (final e in entries) '  - "$e"\n'].join()}'
      '---\n\n# Record\n',
};

/// The template layers that put the feature and its stories under [levels]
/// group folders.
Map<String, String> _groupedLayers({
  int levels = 1,
  Map<String, String> extra = const {},
}) {
  final groups = List.filled(levels, '{slug}/').join();
  return {
    '.specstone/templates/feature.yaml':
        'path: prds/features/${groups}f{nn}_{slug}/FEATURE.md\n',
    '.specstone/templates/user_story.yaml':
        'path: prds/features/${groups}f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md\n',
    ...extra,
  };
}

/// The files of one grouped feature at [dir], with a story per entry of
/// [stories] that writes its status.
Map<String, String> _groupedFeature(
  String dir,
  String title,
  Map<String, String> stories,
) => {
  'docs/prds/features/$dir/FEATURE.md': '# $title\n\n## Problem\nNeed it.\n',
  for (final (n, MapEntry(:key, :value)) in stories.entries.indexed)
    'docs/prds/features/$dir/us0${n + 1}_$key/USER_STORY.md':
        '---\nstatus: $value\n---\n\n# Agent uses $key\n\n'
        '## Use Case\nUse it.\n',
};

Future<DocIndex> _open(
  Map<String, String> files, {
  List<String> targets = const [],
  List<String> packs = const ['prd-core', 'software-tech'],
}) async {
  final named = [for (final t in targets) '  $t:\n    code_root: ${t}_lib\n'];
  final root = await writeTree({
    '.specstone/config.yaml': targets.isEmpty
        ? shippedPinsConfig(packs)
        : '${shippedPinsConfig(packs)}targets:\n${named.join()}',
    for (final t in targets) '${t}_lib/.keep': '',
    ...files,
  });
  final session = openSession(root);
  addTearDown(session.close);
  return session.index;
}

/// The lines of [text] after the summary line, its blank line, and the two
/// header lines of the table.
List<String> _rows(String text) => text.split('\n').skip(4).toList();

/// The cells of the table [row], split on each `|` not written `\|`.
List<String> _cells(String row) {
  final parts = row.split(RegExp(r'(?<!\\)\|')).map((c) => c.trim()).toList();
  return parts.sublist(1, parts.length - 1);
}

String _text(DocIndex index) => featureCatalogText(index, _featuresDoc);

/// A project layer of the shipped `group_features` type that renames its doc
/// file to `AREA.md`.
const Map<String, String> _areaLayer = {
  '.specstone/templates/group_features.yaml': 'file: AREA.md\n',
};

/// Three grouped features: two in `kitchen`, one in `garden`.
Map<String, String> _kitchenAndGarden({bool area = false}) => {
  ..._groupedLayers(extra: area ? _areaLayer : const {}),
  ..._groupedFeature('kitchen/f01_recipes', 'Recipes', {
    'cook': 'implemented',
    'bake': 'implemented',
  }),
  ..._groupedFeature('kitchen/f02_menus', 'Menus', {'plan': 'planned'}),
  ..._groupedFeature('garden/f03_beds', 'Beds', {'dig': 'implemented'}),
};

/// Two features under `form`, one in each of its two child groups.
Map<String, String> _formGroups() => {
  ..._groupedLayers(levels: 2),
  ..._groupedFeature('form/input/f01_text', 'Text', {'type': 'implemented'}),
  ..._groupedFeature('form/choice/f02_pick', 'Pick', {'tap': 'planned'}),
};

String _groupText(DocIndex index, String folder) =>
    groupFeatureCatalogText(index, 'prds/features/$folder/FEATURES.md');

CompanionDocs _companionsOf(DocIndex index) => featureCatalogCompanions(
  _featuresDoc,
  index.set.lookup('features')!,
  index,
);

void main() {
  group('feature_catalog', () {
    test('a nested feature gets no row and its stories count toward its top '
        'feature', () async {
      final index = await _open({
        ..._feature('f01_shop', 'Shop', stories: ['greet']),
        ..._feature('f01_shop/f01_cart', 'Cart', stories: ['add', 'remove']),
        ..._feature('f01_shop/f02_pay', 'Pay', stories: ['charge']),
        ..._record('f01_shop', ['greet:implemented']),
        ..._record('f01_shop/f01_cart', ['add:implemented', 'remove:planned']),
      });

      final text = _text(index);

      expect(text.split('\n').first, '1 features · 4 stories · 1 planned');
      expect(_rows(text), hasLength(1));
      expect(_cells(_rows(text).single), [
        '[Shop](features/f01_shop/FEATURE.md)',
        _dash,
        'planned',
        '2/4',
        _dash,
      ]);
    });

    test('skipped and deprecated stories leave the summary count and the '
        'stories cell', () async {
      final index = await _open({
        ..._feature(
          'f01_shop',
          'Shop',
          stories: ['greet', 'add', 'drop', 'old'],
        ),
        ..._record('f01_shop', [
          'greet:implemented',
          'add:planned',
          'drop:skipped',
          'old:deprecated',
        ]),
      });

      final text = _text(index);

      expect(text.split('\n').first, '1 features · 2 stories · 1 planned');
      expect(_cells(_rows(text).single)[3], '1/2');
    });

    test('the status counts run in the order implemented, planned, skipped, '
        'deprecated', () async {
      final index = await _open({
        ..._feature('f01_a', 'A', stories: ['x']),
        ..._feature('f02_b', 'B', stories: ['x']),
        ..._feature('f03_c', 'C'),
        ..._feature('f04_d', 'D', stories: ['x']),
        ..._feature('f05_e', 'E', stories: ['x']),
        ..._record('f01_a', ['x:implemented']),
        ..._record('f02_b', ['x:implemented']),
        ..._record('f04_d', [':skipped:not here']),
        ..._record('f05_e', ['x:deprecated']),
      });

      expect(
        _text(index).split('\n').first,
        '5 features · 2 stories · '
        '2 implemented, 1 planned, 1 skipped, 1 deprecated',
      );
    });

    test('a status no top feature computes leaves the counts', () async {
      final index = await _open({
        ..._feature('f01_a', 'A', stories: ['x']),
        ..._feature('f02_b', 'B', stories: ['x']),
        ..._record('f01_a', ['x:implemented']),
      });

      expect(
        _text(index).split('\n').first,
        '2 features · 2 stories · 1 implemented, 1 planned',
      );
    });

    test('a top feature with no summary shows a dash in the what it does '
        'cell', () async {
      final index = await _open(_feature('f01_a', 'A'));

      expect(_cells(_rows(_text(index)).single)[1], _dash);
    });

    test('a top feature with a string summary shows it', () async {
      final index = await _open(
        _feature('f01_a', 'A', front: 'summary: Sells things.\n'),
      );

      expect(_cells(_rows(_text(index)).single)[1], 'Sells things.');
    });

    for (final summary in ['[a, b]', '42', 'true', '{k: v}', '""', '"  "']) {
      test('the summary $summary shows a dash in the what it does '
          'cell', () async {
        final index = await _open(
          _feature('f01_a', 'A', front: 'summary: $summary\n'),
        );

        expect(_cells(_rows(_text(index)).single)[1], _dash);
      });
    }

    test('a blank line between summary lines and outer spaces give one '
        'trimmed space', () async {
      for (final summary in [r'"  One\n\ntwo.  "', r'"One\ntwo."']) {
        final index = await _open(
          _feature('f01_a', 'A', front: 'summary: $summary\n'),
        );

        final rows = _rows(_text(index));

        expect(rows, hasLength(1), reason: summary);
        expect(_cells(rows.single)[1], 'One two.', reason: summary);
      }
    });

    test('a top feature serves its vision values then its goals values, or a '
        'dash with neither', () async {
      final index = await _open({
        ..._feature(
          'f01_a',
          'A',
          front: 'goals:\n  - PG-01\nvision:\n  - PV-02\n',
        ),
        ..._feature('f02_b', 'B'),
      });

      final rows = _rows(_text(index));

      expect(_cells(rows[0])[4], 'PV-02, PG-01');
      expect(_cells(rows[1])[4], _dash);
    });

    for (final (label, source) in [
      ('no title line', '## Problem\nNeed it.\n'),
      ('a title line with no text', '# \n\n## Problem\nNeed it.\n'),
    ]) {
      test('a top feature with $label gets its row linked by its '
          'name', () async {
        final index = await _open(_feature('f04_pay', '', text: source));

        final catalog = _text(index);

        expect(catalog.split('\n').first, startsWith('1 features'));
        expect(
          _cells(_rows(catalog).single)[0],
          '[pay](features/f04_pay/FEATURE.md)',
        );
      });
    }

    test('a draft top feature and a skipped one each get a row, with no draft '
        'mark', () async {
      final index = await _open({
        ..._feature('f01_a', 'A', front: 'draft: true\n', stories: ['x']),
        ..._feature('f02_b', 'B', stories: ['x']),
        ..._record('f02_b', [':skipped:not built']),
      });

      final text = _text(index);
      final rows = _rows(text);

      expect(text.split('\n').first, startsWith('2 features'));
      expect(rows, hasLength(2));
      expect(_cells(rows[0])[0], '[A](features/f01_a/FEATURE.md)');
      expect(_cells(rows[1])[2], 'skipped');
    });

    test(
      'a tree with no feature doc gives the zero line and no table',
      () async {
        for (final targets in [
          <String>[],
          ['flutter', 'jaspr'],
          ['flutter'],
        ]) {
          final index = await _open({}, targets: targets);

          expect(
            _text(index),
            '0 features · 0 stories',
            reason: 'targets $targets',
          );
        }
      },
    );

    test('a pipe in a title or a summary is escaped and the row keeps five '
        'columns', () async {
      final index = await _open(
        _feature(
          'f01_a',
          'Read | write docs',
          front: 'summary: "Reads | writes."\n',
        ),
      );

      final row = _rows(_text(index)).single;

      expect(row, contains(r'[Read \| write docs]'));
      expect(row, contains(r'Reads \| writes.'));
      expect(_cells(row), hasLength(5));
    });

    test('an already escaped pipe in a summary stays one escape', () async {
      final index = await _open(
        _feature('f01_a', 'A', front: 'summary: "Reads \\\\| writes."\n'),
      );

      final row = _rows(_text(index)).single;

      expect(row, contains(r'Reads \| writes.'));
      expect(row, isNot(contains(r'\\|')));
      expect(_cells(row), hasLength(5));
    });

    test('a pipe after an escaped backslash in a summary is escaped', () async {
      final index = await _open(
        _feature('f01_a', 'A', front: 'summary: "Reads \\\\\\\\| writes."\n'),
      );

      final row = _rows(_text(index)).single;

      expect(row, contains(r'Reads \\\| writes.'));
      expect(_cells(row), hasLength(5));
    });

    test('top features keep the order of the index', () async {
      final index = await _open({
        ..._feature('f02_b', 'B'),
        ..._feature('f01_a', 'A'),
      });

      expect(
        [for (final r in _rows(_text(index))) _cells(r)[0]],
        ['[A](features/f01_a/FEATURE.md)', '[B](features/f02_b/FEATURE.md)'],
      );
    });

    test(
      'with no record doc type each status reads the written status',
      () async {
        final root = {
          ..._feature('f01_a', 'A'),
          'docs/prds/features/f01_a/us01_x/USER_STORY.md': '---\nstatus: implemented\n---\n\n# Agent uses x\n\n## Use Case\nUse it.\n',
        };
        final index = await _open(root, packs: ['prd-core']);

        final text = _text(index);

        expect(
          text.split('\n').first,
          '1 features · 1 stories · 1 implemented',
        );
        expect(_cells(_rows(text).single).sublist(2, 4), [
          'implemented',
          '1/1',
        ]);
      },
    );

    group('with two code targets', () {
      Map<String, String> shop() => {
        ..._feature('f01_shop', 'Shop', stories: ['greet', 'add']),
        ..._record('f01_shop', [
          'greet:implemented',
          'add:implemented',
        ], target: 'flutter'),
        ..._record('f01_shop', ['greet:implemented'], target: 'jaspr'),
      };

      test('status and stories give one part per target and the summary line '
          'one part per target', () async {
        final index = await _open(shop(), targets: ['flutter', 'jaspr']);

        final text = _text(index);

        expect(
          text.split('\n').first,
          '1 features · flutter: 2 stories, 1 implemented · '
          'jaspr: 2 stories, 1 planned',
        );
        expect(_cells(_rows(text).single).sublist(2, 4), [
          'flutter: implemented, jaspr: planned',
          'flutter: 2/2, jaspr: 1/2',
        ]);
      });

      test('the parts follow the order of targets', () async {
        final index = await _open(shop(), targets: ['jaspr', 'flutter']);

        final text = _text(index);

        expect(
          text.split('\n').first,
          '1 features · jaspr: 2 stories, 1 planned · '
          'flutter: 2 stories, 1 implemented',
        );
        expect(_cells(_rows(text).single)[3], 'jaspr: 1/2, flutter: 2/2');
      });
    });

    group('grouped layout', () {
      test('two group folders give a four-column table, one row per folder in '
          'tree order', () async {
        final index = await _open(
          {
            ..._groupedLayers(),
            ..._groupedFeature('kitchen/f01_recipes', 'Recipes', {
              'cook': 'implemented',
            }),
            ..._groupedFeature('kitchen/f02_menus', 'Menus', {
              'plan': 'planned',
            }),
            ..._groupedFeature('garden/f03_beds', 'Beds', {
              'dig': 'implemented',
            }),
          },
          packs: ['prd-core'],
        );

        final lines = _text(index).split('\n');

        expect(
          lines.first,
          '3 features · 3 stories · 2 implemented, 1 planned',
        );
        expect(lines[1], isEmpty);
        expect(lines[2], _groupTableHeader);
        expect(lines[3], '|---|---|---|---|');
        expect(
          [for (final row in lines.skip(4)) _cells(row)[0]],
          [
            '[garden](features/garden/FEATURES.md)',
            '[kitchen](features/kitchen/FEATURES.md)',
          ],
        );
      });

      test('a group row counts its features, their status counts, and their '
          'stories', () async {
        final index = await _open(
          {
            ..._groupedLayers(),
            ..._groupedFeature('kitchen/f01_recipes', 'Recipes', {
              'cook': 'implemented',
              'bake': 'implemented',
            }),
            ..._groupedFeature('kitchen/f02_menus', 'Menus', {
              'plan': 'planned',
            }),
          },
          packs: ['prd-core'],
        );

        final row = _cells(_rows(_text(index)).single);

        expect(row.sublist(1), ['2', '1 implemented, 1 planned', '2/3']);
      });

      test('with two levels the features doc lists only the first-level '
          'groups', () async {
        final index = await _open(
          {
            ..._groupedLayers(levels: 2),
            ..._groupedFeature('form/input/f01_text', 'Text', {
              'type': 'implemented',
            }),
            ..._groupedFeature('form/choice/f02_pick', 'Pick', {
              'tap': 'planned',
            }),
          },
          packs: ['prd-core'],
        );

        final rows = _rows(_text(index));

        expect(rows, hasLength(1));
        expect(_cells(rows.single), [
          '[form](features/form/FEATURES.md)',
          '2',
          '1 implemented, 1 planned',
          '1/2',
        ]);
      });

      test("a grouped project with two targets gives each target's status "
          'counts and stories in its group row', () async {
        final index = await _open(
          {
            ..._groupedLayers(
              extra: {
                '.specstone/templates/implementation.yaml':
                    'path: $_groupedRecordPath\n',
              },
            ),
            ..._feature('kitchen/f01_recipes', 'Recipes', stories: ['a', 'b']),
            ..._feature('kitchen/f02_menus', 'Menus', stories: ['c']),
            ..._record('kitchen/f01_recipes', [
              'a:implemented',
              'b:implemented',
            ], target: 'flutter'),
            ..._record('kitchen/f01_recipes', [
              'a:implemented',
            ], target: 'jaspr'),
          },
          targets: ['flutter', 'jaspr'],
        );

        final row = _cells(_rows(_text(index)).single);

        expect(row.sublist(1), [
          '2',
          'flutter: 1 implemented, 1 planned · jaspr: 2 planned',
          'flutter: 2/3, jaspr: 1/3',
        ]);
      });

      test('an ungrouped project keeps the feature table', () async {
        final index = await _open(_feature('f01_a', 'A'));

        expect(_text(index).split('\n')[2], _tableHeader);
      });
    });

    group('featureCatalogBlocks', () {
      test('returns one block at the top of the features section', () async {
        final index = await _open(_feature('f01_a', 'A'));
        final type = index.set.lookup('features')!;

        final blocks = featureCatalogBlocks(
          Doc.parse(''),
          _featuresDoc,
          type,
          index,
        );

        expect(blocks, hasLength(1));
        expect(blocks.single.kind, featureCatalogKind);
        expect(blocks.single.sectionId, 'features');
        expect(blocks.single.place, isA<SectionTop>());
        expect(blocks.single.text, _text(index));
      });

      test('the table opens under the summary line and a blank line', () async {
        final index = await _open(_feature('f01_a', 'A'));

        final lines = _text(index).split('\n');

        expect(lines[1], isEmpty);
        expect(lines[2], _tableHeader);
        expect(lines[3], '|---|---|---|---|---|');
      });

      test(
        'links reach the feature from the folder of the features doc',
        () async {
          final index = await _open(_feature('f01_a', 'A'));

          expect(
            featureCatalogText(index, 'prds/deep/FEATURES.md'),
            contains('[A](../features/f01_a/FEATURE.md)'),
          );
        },
      );
    });
  });

  group('group_feature_catalog', () {
    test('a one-level group doc lists its own top features in the five-column '
        'table', () async {
      final index = await _open(_kitchenAndGarden(), packs: ['prd-core']);

      final text = _groupText(index, 'kitchen');

      expect(text.split('\n')[2], _tableHeader);
      expect(
        [for (final row in _rows(text)) _cells(row)[0]],
        ['[Recipes](f01_recipes/FEATURE.md)', '[Menus](f02_menus/FEATURE.md)'],
      );
    });

    test("a group doc's summary line counts only its group's features and "
        'stories', () async {
      final index = await _open(_kitchenAndGarden(), packs: ['prd-core']);

      expect(
        _groupText(index, 'kitchen').split('\n').first,
        '2 features · 3 stories · 1 implemented, 1 planned',
      );
    });

    test('a first-level group doc of a two-level layout lists its child '
        'groups as group rows', () async {
      final index = await _open(_formGroups(), packs: ['prd-core']);

      final text = _groupText(index, 'form');

      expect(text.split('\n')[2], _groupTableHeader);
      expect(
        [for (final row in _rows(text)) _cells(row)[0]],
        ['[choice](choice/FEATURES.md)', '[input](input/FEATURES.md)'],
      );
    });

    test(
      'a second-level group doc lists the top features of its folder',
      () async {
        final index = await _open(_formGroups(), packs: ['prd-core']);

        final text = _groupText(index, 'form/input');

        expect(text.split('\n')[2], _tableHeader);
        expect(
          [for (final row in _rows(text)) _cells(row)[0]],
          ['[Text](f01_text/FEATURE.md)'],
        );
      },
    );

    test('groupFeatureCatalogBlocks returns one block at the top of the '
        'features section', () async {
      final index = await _open(_kitchenAndGarden(), packs: ['prd-core']);
      final type = index.set.lookup('features')!;
      const docPath = 'prds/features/kitchen/FEATURES.md';

      final blocks = groupFeatureCatalogBlocks(
        Doc.parse(''),
        docPath,
        type,
        index,
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.kind, groupFeatureCatalogKind);
      expect(blocks.single.sectionId, 'features');
      expect(blocks.single.place, isA<SectionTop>());
      expect(blocks.single.text, groupFeatureCatalogText(index, docPath));
    });

    test('group docs in the index leave the features top features', () async {
      final index = await _open(
        {
          ..._groupedLayers(),
          ..._groupedFeature('kitchen/f01_recipes', 'Recipes', {
            'cook': 'implemented',
          }),
          'docs/prds/features/kitchen/FEATURES.md':
              '# kitchen features\n\n## Features\n',
        },
        packs: ['prd-core'],
      );

      expect(
        index.docs.where((doc) => doc.docTypeId == 'group_features'),
        hasLength(1),
      );
      expect(
        index.docs
            .where((doc) => doc.docTypeId == 'feature')
            .map(index.parentOf),
        [null],
      );
      expect(_text(index).split('\n').first, startsWith('1 features'));
    });
  });

  group('feature catalog companions', () {
    test('the companion list holds one group doc per group folder at every '
        'level', () async {
      final index = await _open(_formGroups(), packs: ['prd-core']);

      final companions = _companionsOf(index);

      expect(companions.docTypeId, 'group_features');
      expect(
        [for (final doc in companions.docs) doc.docPath],
        [
          'prds/features/form/FEATURES.md',
          'prds/features/form/choice/FEATURES.md',
          'prds/features/form/input/FEATURES.md',
        ],
      );
    });

    test('a group folder with no top feature gets no companion', () async {
      final index = await _open(
        {
          ..._kitchenAndGarden(),
          'docs/prds/features/empty/NOTES.md': '# Notes\n',
        },
        packs: ['prd-core'],
      );

      expect(
        [for (final doc in _companionsOf(index).docs) doc.docPath],
        [
          'prds/features/garden/FEATURES.md',
          'prds/features/kitchen/FEATURES.md',
        ],
      );
    });

    test("a companion's seed text holds the title line and one header per "
        'section', () async {
      final index = await _open(_formGroups(), packs: ['prd-core']);

      final seed = _companionsOf(index).docs.first.seedText;

      expect(seed, '# form features\n\n## Features\n');
    });

    test('an ungrouped project lists no companion', () async {
      final index = await _open(_feature('f01_a', 'A'), packs: ['prd-core']);

      expect(_companionsOf(index).docs, isEmpty);
    });

    test('a grouped project with no group doc type lists no companion '
        'and names no doc type', () async {
      final index = await _open(
        {
          ..._kitchenAndGarden(),
          '.specstone/templates/group_features.yaml':
              'generators:\n  remove: [group_feature_catalog]\n',
        },
        packs: ['prd-core'],
      );

      final companions = _companionsOf(index);

      expect(companions.docTypeId, isEmpty);
      expect(companions.docs, isEmpty);
    });

    test("a group row links the group doc by the group type's file", () async {
      final index = await _open(
        _kitchenAndGarden(area: true),
        packs: ['prd-core'],
      );

      expect(
        [for (final row in _rows(_text(index))) _cells(row)[0]],
        [
          '[garden](features/garden/AREA.md)',
          '[kitchen](features/kitchen/AREA.md)',
        ],
      );
    });
  });
}
