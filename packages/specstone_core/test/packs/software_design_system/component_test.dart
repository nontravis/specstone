import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_design_system.dart';

const _groupDoc = 'specs/design_system/components/buttons/GROUP.md';
const _componentDoc =
    'specs/design_system/components/buttons/primary_button.md';
const _looseDoc = 'specs/design_system/components/loose_button.md';

const _sectionHeaders = [
  'Purpose',
  'When to use',
  'Anatomy',
  'Variants',
  'States',
  'Props',
  'Tokens',
  'Do',
  "Don't",
  'Examples',
  'Accessibility',
];

String _body({bool keyboard = false}) => [
  for (final header in _sectionHeaders.take(10))
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
      expect(fieldOf(component, 'lifecycle').export, isNull);
      expect(fieldOf(component, 'feature').export, isFalse);
      expect(fieldOf(component, 'design_source').export, isFalse);
    });

    test('carries the twelve sections in order, keyboard alone optional', () {
      expectSections(component, [
        for (final header in _sectionHeaders.take(10))
          SectionSpec(
            header == "Don't"
                ? 'dont'
                : header.toLowerCase().replaceAll(' ', '_'),
            header,
            required: true,
          ),
        const SectionSpec('keyboard', 'Keyboard'),
        const SectionSpec('accessibility', 'Accessibility', required: true),
      ]);
      expect(sectionOf(component, 'purpose').summary, isTrue);
      expect(component.sections, hasLength(12));
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
      expect(lines, contains(startsWith('These docs serve the team that')));
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
