import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/component_catalog.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/temp_tree.dart';

const _discoveryDoc = 'specs/design_system/DISCOVERY.md';
const _tableHeader = '| Component | Group | Purpose | Lifecycle | Doc |';
const _dash = '—';
const _primaryDoc = 'specs/design_system/components/buttons/primary_button.md';

const _discoveryType = '''
id: discovery
description: Where to find a component.
path: specs/design_system/DISCOVERY.md
generators: [component_catalog]
sections:
  - id: component_catalog
    header: Component catalog
''';

const _groupType = '''
id: component_group
description: One group of components.
path: specs/design_system/components/{slug}/GROUP.md
sections:
  - id: purpose
    header: Purpose
    summary: true
''';

const _componentType = '''
id: component
description: One component.
path: specs/design_system/components/{slug}/{slug}.md
parent: component_group
fields:
  - id: lifecycle
    type: enum
    enum: [beta, stable, deprecated]
sections:
  - id: purpose
    header: Purpose
    summary: true
''';

String _componentFile({String? lifecycle, String? purpose, String? title}) =>
    '${lifecycle == null ? '' : '---\nlifecycle: $lifecycle\n---\n\n'}'
    '# ${title ?? 'Component'}\n'
    '${purpose == null ? '' : '\n## Purpose\n$purpose\n'}';

/// The files of one component under the group [group].
Map<String, String> _component(
  String group,
  String name, {
  String? lifecycle = 'stable',
  String? purpose = 'Does a thing. Then more.',
}) => {
  'docs/specs/design_system/components/$group/GROUP.md':
      '# ${group.toUpperCase()}\n\n## Purpose\nGroups $group.\n',
  'docs/specs/design_system/components/$group/$name.md': _componentFile(
    lifecycle: lifecycle,
    purpose: purpose,
    title: name,
  ),
};

Future<DocIndex> _open(Map<String, String> files) async {
  final root = await writeTree({
    '.specstone/config.yaml': shippedPinsConfig(),
    '.specstone/templates/discovery.yaml': _discoveryType,
    '.specstone/templates/component_group.yaml': _groupType,
    '.specstone/templates/component.yaml': _componentType,
    'docs/$_discoveryDoc': '# Discovery\n\n## Component catalog\n',
    ...files,
  });
  final session = openSession(root);
  addTearDown(session.close);
  return session.index;
}

String _text(DocIndex index) => componentCatalogText(index, _discoveryDoc);

/// The rows of [text] below its two header lines.
List<String> _rows(String text) => text.split('\n').skip(2).toList();

/// The cells of the table [row], split on each `|` not written `\|`.
List<String> _cells(String row) {
  final parts = row.split(RegExp(r'(?<!\\)\|')).map((c) => c.trim()).toList();
  return parts.sublist(1, parts.length - 1);
}

void main() {
  group('component_catalog', () {
    test('two groups give one row per component, in tree order', () async {
      final index = await _open({
        ..._component('inputs', 'text_field'),
        ..._component('buttons', 'primary_button'),
      });

      final text = _text(index);
      final rows = _rows(text);

      expect(text.split('\n').first, _tableHeader);
      expect(rows, hasLength(2));
      expect(_cells(rows.first).take(2), ['buttons/primary_button', 'buttons']);
      expect(_cells(rows.last).take(2), ['inputs/text_field', 'inputs']);
    });

    test('a row holds the first sentence, the lifecycle, and a link relative '
        'to the discovery doc', () async {
      final index = await _open(_component('buttons', 'primary_button'));

      expect(_cells(_rows(_text(index)).single), [
        'buttons/primary_button',
        'buttons',
        'Does a thing.',
        'stable',
        '[$_primaryDoc](components/buttons/primary_button.md)',
      ]);
    });

    test('a component with no Purpose section reads a dash', () async {
      for (final purpose in [null, '']) {
        final index = await _open(
          _component('buttons', 'primary_button', purpose: purpose),
        );

        expect(
          _cells(_rows(_text(index)).single)[2],
          _dash,
          reason: '$purpose',
        );
      }
    });

    test('an already escaped pipe stays one escape', () async {
      final index = await _open(
        _component(
          'buttons',
          'primary_button',
          purpose: r'Picks a \| b for you. Next.',
        ),
      );

      final row = _rows(_text(index)).single;

      expect(_cells(row), hasLength(5));
      expect(_cells(row)[2], r'Picks a \| b for you.');
    });

    test('a pipe after an escaped backslash is escaped', () async {
      final index = await _open(
        _component(
          'buttons',
          'primary_button',
          purpose: r'Matches `a\\|b` here. Next.',
        ),
      );

      final row = _rows(_text(index)).single;

      expect(_cells(row), hasLength(5));
      expect(_cells(row)[2], r'Matches `a\\\|b` here.');
    });

    test('a component with no lifecycle reads a dash', () async {
      final index = await _open(
        _component('buttons', 'primary_button', lifecycle: null),
      );

      expect(_cells(_rows(_text(index)).single)[3], _dash);
    });

    test('a period and space inside a code span ends no sentence', () async {
      final index = await _open(
        _component(
          'buttons',
          'primary_button',
          purpose: 'Shows the `1. 2` step count. Wraps long text.',
        ),
      );

      expect(
        _cells(_rows(_text(index)).single)[2],
        'Shows the `1. 2` step count.',
      );
    });

    test(
      'a pipe in a cell is escaped and the row keeps five columns',
      () async {
        final index = await _open(
          _component(
            'buttons',
            'primary_button',
            purpose: 'Picks a | b for you. Next.',
          ),
        );

        final row = _rows(_text(index)).single;

        expect(_cells(row), hasLength(5));
        expect(_cells(row)[2], r'Picks a \| b for you.');
      },
    );

    test('no component gives the header rows alone', () async {
      final index = await _open({});

      expect(_text(index), '$_tableHeader\n|---|---|---|---|---|');
    });

    test(
      'the block sits at the top of the component_catalog section',
      () async {
        final index = await _open(_component('buttons', 'primary_button'));
        final type = index.set.lookup('discovery')!;

        final blocks = componentCatalogBlocks(
          Doc.parse('# Discovery\n'),
          _discoveryDoc,
          type,
          index,
        );

        expect(blocks, hasLength(1));
        expect(blocks.single.kind, componentCatalogKind);
        expect(blocks.single.sectionId, 'component_catalog');
        expect(blocks.single.place, isA<SectionTop>());
        expect(blocks.single.text, _text(index));
      },
    );
  });
}
