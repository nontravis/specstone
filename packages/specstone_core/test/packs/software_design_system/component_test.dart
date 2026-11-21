import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_design_system.dart';

const _groupDoc = 'specs/design_system/components/buttons/GROUP.md';
const _componentDoc =
    'specs/design_system/components/buttons/primary_button.md';
const _looseDoc = 'specs/design_system/components/loose_button.md';

const _requiredHeaders = [
  'Purpose',
  'When to use',
  'Props',
  'Examples',
  'Accessibility',
];

String _body({bool keyboard = false}) => [
  for (final header in _requiredHeaders.take(4))
    '## $header\n\nWrites one line.\n',
  if (keyboard) '## Keyboard\n\nPress Enter.\n',
  '## Accessibility\n\nMeets the bar.\n',
].join('\n');

String _component({
  String? lifecycle = 'stable',
  String? feature = 'login',
  String? body,
}) =>
    '---\n${lifecycle == null ? '' : 'lifecycle: $lifecycle\n'}'
    '${feature == null ? '' : 'feature: $feature\n'}---\n\n'
    '# Primary button\n\n${body ?? _body()}';

const _group = '# Buttons\n\n## Purpose\n\nGroups the buttons.\n';

Future<List<String>> _findings(
  String component, {
  FindingKind? kind,
  String doc = _componentDoc,
}) async {
  final project = await writeCheckProject(
    extra: {
      '.specstone/config.yaml': softwareDesignSystemConfig(),
      'docs/$_groupDoc': _group,
      'docs/$doc': component,
    },
  );
  return spots(await checkOf(project, docPath: doc), kind);
}

void main() {
  group('component_group', () {
    late MergedDocType group;

    setUpAll(() async {
      group = prdCoreDocType(
        await resolveSoftwareDesignSystem(),
        'component_group',
      );
    });

    test('loads at its path with no parent, the built-in fields, and one '
        'required purpose section that summarizes', () {
      expect(group.pack, 'software-design-system');
      expect(group.path, 'specs/design_system/components/{slug}/GROUP.md');
      expect(group.parent, isNull);
      expectOwnFields(group, const []);
      expectSections(group, const [
        SectionSpec('purpose', 'Purpose', required: true),
      ]);
      expect(sectionOf(group, 'purpose').summary, isTrue);
    });
  });

  group('component', () {
    late MergedDocType component;

    setUpAll(() async {
      component = prdCoreDocType(
        await resolveSoftwareDesignSystem(),
        'component',
      );
    });

    test('loads at its path under the component_group parent', () {
      expect(component.pack, 'software-design-system');
      expect(component.path, 'specs/design_system/components/{slug}/{slug}.md');
      expect(component.parent, 'component_group');
      expect(component.isPerTarget, isFalse);
    });

    test('carries the lifecycle, feature, and design_source fields', () {
      expectOwnFields(component, const [
        FieldSpec(
          'lifecycle',
          FieldType.enumType,
          required: true,
          enumValues: ['beta', 'stable', 'deprecated'],
        ),
        FieldSpec(
          'feature',
          FieldType.docRef,
          required: true,
          docTypes: ['feature'],
        ),
        FieldSpec('design_source', FieldType.sourceRef, list: true),
      ]);
    });

    test('the component guide lists its sections in the read order', () {
      expect(component.sections.map((s) => s.header), [
        'Purpose',
        'When to use',
        'Anatomy',
        'Variants',
        'States',
        'Props',
        'Examples',
        'Keyboard',
        'Accessibility',
      ]);
      expect(sectionOf(component, 'purpose').summary, isTrue);
    });

    test('only anatomy, variants, states, and keyboard are optional', () {
      final optional = [
        for (final section in component.sections)
          if (!section.required) section.id,
      ];
      expect(optional, ['anatomy', 'variants', 'states', 'keyboard']);
      expect(component.sections, hasLength(9));
    });

    test('the description holds the intro and one line for each component '
        'rule', () {
      final lines = component.description!.split('\n');
      const noCode =
          'The component doc holds no code, so it serves the library in any '
          'language.';
      const rulePhrases = [
        noCode,
        'The Agent writes Props by hand.',
        'Examples state each scenario as prop values, never as code.',
      ];
      for (final phrase in rulePhrases) {
        expect(
          lines.where((l) => l.startsWith(phrase)),
          hasLength(1),
          reason: phrase,
        );
      }
      expect(
        lines.singleWhere((l) => l.startsWith('The Agent writes Props')),
        contains('Specstone never generates props from it.'),
      );
    });

    test("the when-to-use section folds in the Do and Don't points", () {
      expect(
        sectionOf(component, 'when_to_use').description,
        contains("Fold the Do and Don't points into this section."),
      );
    });

    test('the props section names the five language-neutral types', () {
      expect(
        sectionOf(component, 'props').description,
        allOf(
          contains('`text`'),
          contains('`number`'),
          contains('`boolean`'),
          contains('`choice`'),
          contains('`on-tap`'),
        ),
      );
    });
  });

  group('component props lint', () {
    const rowsOutside = [
      '| size | integer | 3 |',
      '| label | string | |',
      '| onPressed | callback | |',
      '| mode | `enum` | |',
      '| gap | text, number | |',
    ];
    const rowsInside = [
      '| Prop | Type | Notes |',
      '|---|---|---|',
      '| :--- | :---: | ---: |',
      '| label | text | the caption |',
      '| count | number | |',
      '| busy | boolean | |',
      '| size | `choice` | small or large |',
      '| tap | on-tap | |',
      '| Type | text | a prop named Type |',
    ];

    Future<List<String>> flaggedProps(String body) => bannedLines(
      {
        '.specstone/config.yaml': softwareDesignSystemConfig(),
        'docs/$_groupDoc': _group,
        'docs/$_componentDoc': _component(body: body),
      },
      _componentDoc,
      'prop_type_value',
    );

    test('a type cell outside the five is prop_type_value, and a type of '
        'the five, the header and separator rows, a prose line, a fenced '
        'row, and a blank line give none', () async {
      final lines = await flaggedProps(
        '## Props\n\nProps hold one row per prop.\n\n'
        '${rowsInside.join('\n')}\n\n```\n| fenced | integer |\n```\n\n'
        '${rowsOutside.join('\n')}\n',
      );
      expect(lines, rowsOutside);
    });

    test('a table row of another section gives none', () async {
      final lines = await flaggedProps(
        '## Purpose\n\n| a | integer |\n\n## Props\n\n| label | text |\n\n'
        '## Examples\n\n| Scenario | Values |\n| default | label: Save |\n',
      );
      expect(lines, isEmpty);
    });

    test('a Prop, Description, Type table flags its type column, since the '
        'guide names the second column', () async {
      final lines = await flaggedProps(
        '## Props\n\n| Prop | Description | Type |\n|---|---|---|\n'
        '| label | the caption | text |\n',
      );
      expect(lines, [
        '| Prop | Description | Type |',
        '| label | the caption | text |',
      ]);
      final component = prdCoreDocType(
        await resolveSoftwareDesignSystem(),
        'component',
      );
      expect(
        component.renderGuide(),
        contains(
          'Write one row per prop, its type one of `text`, `number`, '
          '`boolean`, `choice`, and `on-tap` in the second column.',
        ),
      );
    });

    test('the message reads the guide line', () async {
      final component = prdCoreDocType(
        await resolveSoftwareDesignSystem(),
        'component',
      );
      final entry = sectionOf(
        component,
        'props',
      ).bannedPatterns!.singleWhere((e) => e.id == 'prop_type_value');
      expect(
        entry.message,
        'prop type is not text, number, boolean, choice, or on-tap; guide '
        'line: Write one row per prop, its type one of `text`, `number`, '
        '`boolean`, `choice`, and `on-tap` in the second column.',
      );
    });
  });

  group('component doc check', () {
    test('a complete component in its group, with or without Keyboard, gives '
        'no finding', () async {
      expect(await _findings(_component()), isEmpty);
      expect(await _findings(_component(body: _body(keyboard: true))), isEmpty);
    });

    test('a component with no feature is required_field_missing', () async {
      expect(
        await _findings(
          _component(feature: null),
          kind: FindingKind.requiredFieldMissing,
        ),
        ['$_componentDoc:1: required_field_missing'],
      );
    });

    test('a component with no Purpose section is required_section_missing '
        'for it', () async {
      final body = _body().replaceFirst(
        '## Purpose\n\nWrites one line.\n\n',
        '',
      );
      expect(body, isNot(contains('## Purpose')));

      final findings = await _findings(
        _component(body: body),
        kind: FindingKind.requiredSectionMissing,
      );

      expect(findings, ['$_componentDoc:1: required_section_missing']);
    });

    test('a feature that names no feature doc is doc_ref_unresolved', () async {
      expect(
        await _findings(
          _component(feature: 'checkout'),
          kind: FindingKind.docRefUnresolved,
        ),
        ['$_componentDoc:4: doc_ref_unresolved'],
      );
    });

    test('a lifecycle outside beta, stable, and deprecated is the enum '
        'fault', () async {
      expect(
        await _findings(
          _component(lifecycle: 'retired'),
          kind: FindingKind.fieldValueMismatch,
        ),
        ['$_componentDoc:3: field_value_mismatch'],
      );
    });

    test('a component outside a component group folder is untyped', () async {
      expect(
        await _findings(
          _component(),
          doc: _looseDoc,
          kind: FindingKind.untypedDoc,
        ),
        ['$_looseDoc:1: untyped_doc'],
      );
    });
  });
}
