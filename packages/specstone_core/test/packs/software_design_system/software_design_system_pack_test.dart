// Test names stay one literal so `specstone check` finds them by exact text.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/setup_migration/upgrade_plan.dart';
import 'package:specstone_core/src/shipped_generators.dart'
    show shippedGenerators;
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/models/migration_step.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shared_entry.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/no_generators.dart';
import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/sentence_case.dart';
import '../../helpers/shared_lines.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/software_design_system.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';
import '../../helpers/yaml_key_line.dart';

const _root = 'specs/design_system';

/// Each doc type but `component` and `component_group` with its path and its
/// sections: id and sentence-case header, all required.
const _plainDocTypes = <String, (String, List<(String, String)>)>{
  'guidelines': (
    '$_root/GUIDELINES.md',
    [('reading_order', 'Reading order'), ('hard_rules', 'Hard rules')],
  ),
  'discovery': (
    '$_root/DISCOVERY.md',
    [
      ('finding_a_component', 'Finding a component'),
      ('component_catalog', 'Component catalog'),
    ],
  ),
  'setup': ('$_root/SETUP.md', [('install_contract', 'Install contract')]),
  'icon': (
    '$_root/ICON.md',
    [('icon_set', 'Icon set'), ('sizes', 'Sizes'), ('naming', 'Naming')],
  ),
  'accessibility': (
    '$_root/ACCESSIBILITY.md',
    [('accessibility_bar', 'Accessibility bar')],
  ),
  'content': ('$_root/CONTENT.md', [('writing_rules', 'Writing rules')]),
  'contributing': (
    '$_root/CONTRIBUTING.md',
    [('definition_of_done', 'Definition of done')],
  ),
  'tokens': ('$_root/foundations/TOKENS.md', [('token_list', 'Token list')]),
  'color': ('$_root/foundations/COLOR.md', [('color_roles', 'Color roles')]),
  'typography': (
    '$_root/foundations/TYPOGRAPHY.md',
    [('type_scale', 'Type scale')],
  ),
  'spacing': (
    '$_root/foundations/SPACING.md',
    [('spacing_scale', 'Spacing scale')],
  ),
  'elevation': (
    '$_root/foundations/ELEVATION.md',
    [('elevation_levels', 'Elevation levels')],
  ),
  'shape': ('$_root/foundations/SHAPE.md', [('shapes', 'Shapes')]),
  'motion': (
    '$_root/foundations/MOTION.md',
    [('durations', 'Durations'), ('easings', 'Easings')],
  ),
  'theme': (
    '$_root/foundations/THEME.md',
    [('themes', 'Themes'), ('token_mapping', 'Token mapping')],
  ),
  'layout': (
    '$_root/composition/LAYOUTS.md',
    [('layouts', 'Layouts'), ('grids', 'Grids')],
  ),
  'ui_pattern': (
    '$_root/composition/patterns/{slug}.md',
    [
      ('purpose', 'Purpose'),
      ('components_used', 'Components used'),
      ('composition', 'Composition'),
    ],
  ),
};

/// The ids of the shared lines each guide prints, in print order: the
/// `prd-core` lines that reach every doc type, then the pack's own lines.
const _sharedLineIds = <String>[
  ...everyTypeSharedLineIds,
  'serve_library_builders',
  'library_spec_scope',
  'library_code_detail_home',
];

PackManifest _manifest() => PackManifest.parse(
  utf8.decode(shippedPackFiles['software-design-system/pack.yaml']!),
  file: 'packs/software-design-system/pack.yaml',
);

Future<MergedSet> _resolve(List<String> packs) async {
  final project = await writeTree({
    '.specstone/config.yaml': shippedPinsConfig(packs),
  });
  final home = await writeTree({});
  return TemplateResolver().resolve(
    workingDirectory: project,
    homeDirectory: home,
  );
}

void main() {
  late MergedSet set;

  setUpAll(() async => set = await resolveSoftwareDesignSystem());

  group('manifest', () {
    test('ships at 1.7.1 over software-tech with its nineteen doc types', () {
      final bytes = shippedPackFiles['software-design-system/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/software-design-system/pack.yaml',
      );
      expect(manifest.name, 'software-design-system');
      expect(manifest.version.toString(), '1.7.1');
      expect(manifest.extendsPack, 'software-tech');
      expect(
        shippedPackFiles.keys.where(
          (k) => k.startsWith('software-design-system/'),
        ),
        unorderedEquals([
          'software-design-system/pack.yaml',
          for (final id in softwareDesignSystemIds)
            'software-design-system/$id.yaml',
        ]),
      );
    });

    test('ships one mark_retrim entry from 1.5.0 on every section of its nineteen doc types', () async {
      final migrations = _manifest().migrations;
      expect(migrations.map((m) => m.from.toString()), ['1.5.0']);
      final mark = migrations.single.steps.single as MarkRetrim;
      expect(mark.docTypes, [...softwareDesignSystemIds]..sort());
      expect(mark.sections.toSet(), {
        for (final id in softwareDesignSystemIds)
          for (final section in set.lookup(id)!.sections)
            // D7: source_of_truth is optional and new at 1.7.0, so no mark.
            if (section.id != 'source_of_truth') section.id,
      });

      final versions = shippedPackVersions();
      final project = await writeTree({
        '.specstone/config.yaml':
            'packs:\n'
            '  prd-core: ${versions['prd-core']}\n'
            '  software-tech: ${versions['software-tech']}\n'
            '  software-design-system: 1.5.0\n',
        'docs/$_root/foundations/COLOR.md':
            '# Color\n\n## Color roles\n\n'
            '- **Primary** marks the one main action.\n',
      });
      final plan = planUpgradeRun(
        project,
        templates: TemplateResolver(),
        homeDirectory: await writeTree({}),
        generators: shippedGenerators(),
      );

      expect(plan.lists.toJson()['steps'], [
        {
          'from': '1.5.0',
          'step': 'mark_retrim',
          'paths': ['$_root/foundations/COLOR.md'],
        },
      ]);
      expect(
        plan.rewrites
            .singleWhere(
              (rewrite) => rewrite.path == 'docs/$_root/foundations/COLOR.md',
            )
            .text,
        startsWith('---\nretrim:\n  - color_roles\n---\n'),
      );
    });

    test('a project pinned at 1.7.0 upgrades to 1.7.1 with no step and no doc rewrite', () async {
      final versions = shippedPackVersions();
      final project = await writeTree({
        '.specstone/config.yaml':
            'packs:\n'
            '  prd-core: ${versions['prd-core']}\n'
            '  software-tech: ${versions['software-tech']}\n'
            '  software-design-system: 1.7.0\n',
        'docs/$_root/foundations/COLOR.md':
            '# Color\n\n## Color roles\n\n'
            '- **Primary** marks the one main action.\n',
      });
      final plan = planUpgradeRun(
        project,
        templates: TemplateResolver(),
        homeDirectory: await writeTree({}),
        generators: shippedGenerators(),
      );

      expect(plan.header, contains('software-design-system 1.7.0 -> 1.7.1'));
      expect(plan.lists.toJson()['steps'], isEmpty);
      expect(
        plan.rewrites.where((rewrite) => rewrite.path.startsWith('docs/')),
        isEmpty,
      );
    });

    test('ships the shared lines serve_library_builders, library_spec_scope, and library_code_detail_home, naming nineteen doc types, and no shared field', () {
      final shared = _manifest().shared;
      expect(
        [for (final l in shared.lines) (l.id, l.disabled)],
        [
          ('serve_library_builders', false),
          ('library_spec_scope', false),
          ('library_code_detail_home', false),
        ],
      );
      for (final line in shared.lines) {
        expect(line.forDocTypes, softwareDesignSystemIds, reason: line.id);
      }
      expect(shared.fields, isEmpty);
    });

    test('the first shared line serves the builders of any design system on every guide', () {
      const text =
          'These docs serve the team that builds the design system, not the code that uses it.';
      final first = _manifest().shared.lines.first;
      expect(first.id, 'serve_library_builders');
      expect(first.text, text);
      for (final id in softwareDesignSystemIds) {
        expect(
          prdCoreDocType(set, id).renderGuide(),
          contains(text),
          reason: id,
        );
      }
    });

    test("library_spec_scope and library_code_detail_home hold the text of software-tech's spec_scope and code_detail_home", () {
      final tech = {
        for (final l in PackManifest.parse(
          utf8.decode(shippedPackFiles['software-tech/pack.yaml']!),
          file: 'packs/software-tech/pack.yaml',
        ).shared.lines)
          l.id: l.text,
      };
      final library = {for (final l in _manifest().shared.lines) l.id: l.text};
      expect(library['library_spec_scope'], tech['spec_scope']);
      expect(library['library_code_detail_home'], tech['code_detail_home']);
    });

    test('shares token_value once, over six doc types and seven sections', () {
      final patterns = _manifest().shared.patterns;
      expect(patterns.map((p) => (p.id, p.kind)), [
        ('token_value', SharedPatternKind.banned),
        ('link_item', SharedPatternKind.banned),
      ]);
      final tokenValue = patterns.singleWhere((p) => p.id == 'token_value');
      expect(tokenValue.forDocTypes, [
        'color',
        'elevation',
        'motion',
        'shape',
        'spacing',
        'typography',
      ]);
      expect(tokenValue.sections, [
        'color_roles',
        'type_scale',
        'spacing_scale',
        'elevation_levels',
        'shapes',
        'durations',
        'easings',
      ]);
      expect(tokenValue.scope, PatternScope.all);
    });

    // D12.
    test('reading_order and components_used take link_item by pattern_ref from one shared source that reaches no doc type', () {
      final source = _manifest().shared.patterns.singleWhere(
        (p) => p.id == 'link_item',
      );
      expect(source.pattern, isNotNull);
      expect(source.patternRef, isNull);
      expect(source.forDocTypes, isNull);
      expect(source.sections, isNull);
      for (final (docTypeId, sectionId) in [
        ('guidelines', 'reading_order'),
        ('ui_pattern', 'components_used'),
      ]) {
        final file = loadYaml(
          utf8.decode(
            shippedPackFiles['software-design-system/$docTypeId.yaml']!,
          ),
        ) as YamlMap;
        final section = (file['sections'] as YamlList).singleWhere(
          (s) => (s as YamlMap)['id'] == sectionId,
        ) as YamlMap;
        final entry =
            ((section['lint'] as YamlMap)['banned_patterns'] as YamlList)
                    .singleWhere((e) => (e as YamlMap)['id'] == 'link_item')
                as YamlMap;
        expect(entry['pattern_ref'], 'link_item', reason: docTypeId);
        expect(entry.containsKey('pattern'), isFalse, reason: docTypeId);
        expect(entry['message'], isNotNull, reason: docTypeId);
      }
    });

    test('the pack writes no layer over a prd-core or software-tech doc '
        'type', () {
      for (final id in [...prdCoreIds, ...softwareTechIds]) {
        expect(
          shippedPackFiles.containsKey('software-design-system/$id.yaml'),
          isFalse,
          reason: id,
        );
        expect(
          prdCoreDocType(set, id).pack,
          isNot('software-design-system'),
          reason: id,
        );
      }
    });
  });

  group('merged set', () {
    test('a project that lists the three packs holds each prd-core type, ten '
        'software-tech types, and nineteen design-system types', () {
      expect(softwareTechIds, hasLength(10));
      expect(softwareDesignSystemIds, hasLength(19));
      expect(
        set.docTypes.map((d) => d.id).toList(),
        [...prdCoreIds, ...softwareTechIds, ...softwareDesignSystemIds]..sort(),
      );
      for (final id in softwareDesignSystemIds) {
        expect(prdCoreDocType(set, id).pack, 'software-design-system');
      }
    });

    test('a project that lists prd-core and software-tech alone holds no '
        'design-system doc type', () async {
      final without = await resolveSoftwareTech();
      for (final id in softwareDesignSystemIds) {
        expect(without.lookup(id), isNull, reason: id);
      }
    });

    test('a project that lists the pack without software-tech is '
        'extends_target_unknown, exit status 78', () async {
      await expectLater(
        _resolve(['prd-core', 'software-design-system']),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsTargetUnknown)
              .having((f) => f.exitStatus, 'exitStatus', 78),
        ),
      );
    });
  });

  group('doc types', () {
    test('each doc type loads at its path, component with the parent '
        'component_group and every other with none', () {
      expect(
        prdCoreDocType(set, 'component_group').path,
        '$_root/components/{slug}/GROUP.md',
      );
      expect(
        prdCoreDocType(set, 'component').path,
        '$_root/components/{slug}/{slug}.md',
      );
      for (final MapEntry(key: id, value: (path, _))
          in _plainDocTypes.entries) {
        expect(prdCoreDocType(set, id).path, path, reason: id);
      }
      for (final id in softwareDesignSystemIds) {
        expect(
          prdCoreDocType(set, id).parent,
          id == 'component' ? 'component_group' : isNull,
          reason: id,
        );
      }
      expect(
        [..._plainDocTypes.keys, 'component', 'component_group']..sort(),
        softwareDesignSystemIds,
      );
    });

    test('each plain doc type holds the sections of its row, required, in '
        'order, with its header the id in sentence case', () {
      for (final MapEntry(key: id, value: (_, sections))
          in _plainDocTypes.entries) {
        // D7: tokens also holds the optional source_of_truth section.
        expect(
          [
            for (final s in prdCoreDocType(set, id).sections)
              if (id != 'tokens' || s.required)
                (s.id, s.header, s.prefixId, s.required),
          ],
          [
            for (final (sectionId, header) in sections)
              (sectionId, header, null, true),
          ],
          reason: id,
        );
      }
      expect(
        sectionOf(prdCoreDocType(set, 'ui_pattern'), 'purpose').summary,
        isTrue,
      );
    });

    test('no doc type sets per_target', () {
      for (final id in softwareDesignSystemIds) {
        expect(prdCoreDocType(set, id).isPerTarget, isFalse, reason: id);
      }
    });

    test('every doc type but component carries the built-in fields alone', () {
      for (final id in softwareDesignSystemIds.where((i) => i != 'component')) {
        expectOwnFields(prdCoreDocType(set, id), const []);
      }
    });

    test('every path starts with the design-system folder, so none overlaps '
        'a software-tech or prd-core path', () {
      final others = [
        for (final d in set.docTypes)
          if (d.pack != 'software-design-system') ...d.paths,
      ];
      for (final id in softwareDesignSystemIds) {
        final path = prdCoreDocType(set, id).path!;
        expect(path, startsWith('$_root/'), reason: id);
        expect(others, isNot(contains(path)), reason: id);
      }
    });

    test('each guide prints the prd-core lines, then serve_library_builders, '
        'and no software-tech line', () {
      for (final id in softwareDesignSystemIds) {
        final type = prdCoreDocType(set, id);
        expect(type.sharedLines.map((l) => l.id), _sharedLineIds, reason: id);
        final guide = type.renderGuide();
        for (final line in type.sharedLines) {
          expect(guide, contains(line.text), reason: id);
        }
      }
    });

    test('with software-design-system listed, every software-tech doc type but implementation still prints spec_scope and code_detail_home', () {
      for (final id in softwareTechIds.where((id) => id != 'implementation')) {
        final ids = prdCoreDocType(set, id).sharedLines.map((l) => l.id);
        expect(
          ids,
          containsAll(['spec_scope', 'code_detail_home']),
          reason: id,
        );
      }
    });

    test('no description restates a shared line that reaches its doc '
        'type', () {
      for (final id in softwareDesignSystemIds) {
        final type = prdCoreDocType(set, id);
        for (final description in descriptionsOf(type)) {
          for (final line in type.sharedLines) {
            expect(description ?? '', isNot(contains(line.text)), reason: id);
          }
        }
      }
    });

    test('no description or template holds a YAML key line', () {
      for (final id in softwareDesignSystemIds) {
        final type = prdCoreDocType(set, id);
        final texts = [
          ...descriptionsOf(type),
          for (final section in type.sections) section.template,
        ];
        for (final text in texts) {
          expectNoYamlKeyLine(text, reason: id);
        }
      }
    });

    test('discovery lists the component_catalog generator and no other doc '
        'type lists one', () {
      expect(prdCoreDocType(set, 'discovery').listedGenerators, [
        'component_catalog',
      ]);
      for (final id in softwareDesignSystemIds.where((i) => i != 'discovery')) {
        expect(prdCoreDocType(set, id).listedGenerators, isEmpty, reason: id);
      }
    });
  });

  group('lint entries', () {
    const draft = '---\ndraft: true\n---\n\n';
    const foundations = [
      'color',
      'typography',
      'spacing',
      'elevation',
      'shape',
      'motion',
    ];

    Future<List<String>> flagged(String docPath, String id, String body) =>
        bannedLines(
          {
            '.specstone/config.yaml': softwareDesignSystemConfig(),
            'docs/$docPath': '$draft# Doc\n\n$body',
          },
          docPath,
          id,
        );

    test('each doc type with no {slug} path holds its title in the title key '
        'and its description states none; the three placeholder-titled types '
        'set no title', () {
      const placeholderTitled = {'component_group', 'component', 'ui_pattern'};
      const named = {'icon': 'Icons', 'layout': 'Layouts', 'theme': 'Themes'};
      for (final id in softwareDesignSystemIds) {
        final type = prdCoreDocType(set, id);
        if (placeholderTitled.contains(id)) {
          expect(type.title, isNull, reason: id);
        } else {
          expect(type.title, named[id] ?? sentenceCase(id), reason: id);
        }
      }
    });

    test('every doc type titles with no number, so each sets '
        'lint.title_no_number', () {
      for (final id in softwareDesignSystemIds) {
        expect(prdCoreDocType(set, id).lint.titleNoNumber, isTrue, reason: id);
      }
    });

    test('a doc title holding a digit is title_numbered', () async {
      const path = '$_root/foundations/COLOR.md';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            '.specstone/config.yaml': softwareDesignSystemConfig(),
            'docs/$path': '$draft# Color 2\n\n## Color roles\n\nOne row.\n',
          },
        ),
        docPath: path,
      );
      expect([
        for (final f in report.findings)
          if (f.kind == FindingKind.titleNumbered) f.textLine,
      ], hasLength(1));
    });

    const valueLines = [
      '| primary | brand | #1A73E8 |',
      '| short | a short hex | #fa0 |',
      '| alpha | hex with alpha | #1A73E8cc |',
      '| gap | 16px |',
      '| body | 1.5rem |',
      '| em | 2em |',
      '| fast | 200ms |',
      '| slow | .2s |',
      '| half | 50% |',
      '| point | 12pt |',
      '| density | 8dp and 14sp |',
      'Set the role to #1A73E8 here.',
    ];
    const tokenLines = [
      '| primary | brand actions | [color-primary](TOKENS.md#color-primary) |',
      '| fade | fades in | [fade-in](TOKENS.md#fade-in) |',
      '| bad | a bad link | [bad](TOKENS.md#bad) |',
      '| space-md | a medium gap | [space-md](TOKENS.md#space-md) |',
      '- A role named `color-primary` in the second step.',
      'Use the roles in order of weight.',
    ];

    test('each foundation section flags a hex color or a unit value, and a '
        'token name, a link to a token row, a fenced line, and a blank line '
        'give none', () async {
      for (final id in foundations) {
        final (path, sections) = _plainDocTypes[id]!;
        for (final (_, header) in sections) {
          final lines = await flagged(
            path,
            'token_value',
            '## $header\n\n${tokenLines.join('\n')}\n\n'
                '```\n#1A73E8\n16px\n```\n\n${valueLines.join('\n')}\n',
          );
          expect(lines, valueLines, reason: '$id $header');
        }
      }
    });

    test('a value in one section is flagged and the other section of the '
        'doc stays clean', () async {
      final lines = await flagged(
        '$_root/foundations/MOTION.md',
        'token_value',
        '## Durations\n\n| fast | `200ms` |\n\n## Easings\n\n| calm | ease |\n',
      );
      expect(lines, ['| fast | `200ms` |']);
    });

    test('the message reads the guide line', () {
      for (final id in foundations) {
        final type = prdCoreDocType(set, id);
        for (final section in type.sections) {
          final entry = section.bannedPatterns!.singleWhere(
            (e) => e.id == 'token_value',
          );
          expect(
            entry.message,
            'token value in a foundation doc; guide line: it links the '
            'tokens doc and writes no token value',
            reason: '$id ${section.id}',
          );
        }
      }
    });

    const nonLinkItems = [
      '- Tokens first',
      '* Color after it',
      '+ `tokens` and more',
      '1. Typography next',
      '2) Spacing last',
    ];
    const linkItems = [
      '- [Tokens](foundations/TOKENS.md)',
      '1. [Color](foundations/COLOR.md)',
      '| [Color](foundations/COLOR.md) | the roles |',
      '  and a wrapped line of the item above',
    ];

    test('a reading-order or components-used item with no leading link is '
        'link_item, and a linked item, a table line, a wrapped line, a '
        'fenced line, and a blank line give none', () async {
      final body = '\n${linkItems.join('\n')}\n\n```\n- Fenced item\n```\n\n';
      final reading = await flagged(
        '$_root/GUIDELINES.md',
        'link_item',
        '## Reading order\n$body${nonLinkItems.join('\n')}\n\n'
            '## Hard rules\n\n- No raw colors.\n',
      );
      expect(reading, nonLinkItems);
      final used = await flagged(
        '$_root/composition/patterns/forms.md',
        'link_item',
        '## Purpose\n\n- Lists no link here.\n\n'
            '## Components used\n$body${nonLinkItems.join('\n')}\n\n'
            '## Composition\n\n- Stacks them.\n',
      );
      expect(used, nonLinkItems);
    });
  });

  group('guides', () {
    test('the guidelines guide words its hard rules and its code rule for the design system', () {
      final guidelines = prdCoreDocType(set, 'guidelines');
      final rules = sectionOf(guidelines, 'hard_rules').description;
      expect(
        guidelines.description,
        contains("the design system's hard rules"),
      );
      expect(
        guidelines.description,
        isNot(contains("the library's hard rules")),
      );
      expect(rules, contains('code using the design system'));
      expect(rules, isNot(contains("the library's code")));
    });

    test('the accessibility and component guides word the accessibility bar for the design system', () {
      expect(
        prdCoreDocType(set, 'accessibility').description,
        contains('the design-system-wide accessibility bar'),
      );
      expect(
        sectionOf(
          prdCoreDocType(set, 'component'),
          'accessibility',
        ).description,
        contains('the design-system-wide accessibility bar'),
      );
    });

    test(
      'the component guide words its any-language rule for the design system',
      () {
        expect(
          prdCoreDocType(set, 'component').description,
          contains('serves the design system in any language'),
        );
      },
    );

    test('no guide line of the pack names a library or its consumers', () {
      final words = RegExp(r'\blibrar|\bconsumer', caseSensitive: false);
      for (final id in softwareDesignSystemIds) {
        expect(
          prdCoreDocType(set, id).renderGuide(),
          isNot(contains(words)),
          reason: id,
        );
      }
    });

    test('the setup guide describes the setup of code that uses the design system under its kept header', () {
      final setup = prdCoreDocType(set, 'setup');
      expect(
        setup.description,
        'The setup doc: the setup contract of code using the design system.\n'
        "The install contract is what a skill's install steps follow.",
      );
      final section = sectionOf(setup, 'install_contract');
      expect(
        section.description,
        'State how code using the design system sets it up and what it gives, in steps a reader repeats.',
      );
      expect(section.header, 'Install contract');
    });

    test('a doc that breaks a hard rule gets no check finding, since no rule '
        'reads the library code', () async {
      const guidelines =
          '# Guidelines\n\n## Reading order\n\nOpen tokens first.\n\n'
          '## Hard rules\n\n- No raw colors.\n';
      const doc = 'docs/$_root/GUIDELINES.md';
      final clean = await writeCheckProject(
        extra: {
          '.specstone/config.yaml': softwareDesignSystemConfig(),
          doc: guidelines,
        },
      );
      final broken = await writeCheckProject(
        extra: {
          '.specstone/config.yaml': softwareDesignSystemConfig(),
          doc: guidelines,
          'app/lib/button.dart': 'const color = 0xFF112233;\n',
        },
      );

      final before = [
        for (final f in (await checkOf(clean)).findings) f.textLine,
      ];
      final after = [
        for (final f in (await checkOf(broken)).findings) f.textLine,
      ];

      expect(after, before);
      expect(
        after.where((spot) => spot.contains('app/lib/button.dart')),
        isEmpty,
      );
    });

    test('foundation guides hold no token literal', () {
      const foundations = [
        'color',
        'typography',
        'spacing',
        'elevation',
        'shape',
        'motion',
      ];
      final literal = RegExp(r'#[0-9a-fA-F]{3,8}\b|\d');
      // Intros may say "no token value"; a section must never ask for one.
      final valueAsk = RegExp(r'\bvalues?\b', caseSensitive: false);
      for (final id in foundations) {
        final docType = prdCoreDocType(set, id);
        final intro = docType.description ?? '';
        expect(intro, isNot(contains(literal)), reason: id);
        for (final section in docType.sections) {
          final text = section.description ?? '';
          expect(text, isNot(contains(literal)), reason: id);
          expect(text, isNot(contains(valueAsk)), reason: id);
        }
      }
    });

    test('tokens holds an optional source_of_truth section before its '
        'required token_list', () {
      final tokens = prdCoreDocType(set, 'tokens');
      expect(tokens.sections.map((s) => s.id), [
        'source_of_truth',
        'token_list',
      ]);
      expect(tokens.sections.map((s) => s.required), [isFalse, isTrue]);
      expect(tokens.isPerTarget, isFalse);
    });

    test('the tokens and theme guides tell a cell to cite the source symbol '
        'when source_of_truth is written', () {
      final hexColor = RegExp(r'#[0-9a-fA-F]{3,8}\b');
      const citeLine =
          'in a code span, not the value; with none, write the value.';
      for (final id in ['tokens', 'theme']) {
        final guide = prdCoreDocType(set, id).renderGuide();
        expect(guide, contains('Source of truth section'), reason: id);
        expect(guide, contains(citeLine), reason: id);
        expect(guide, isNot(contains(hexColor)), reason: id);
      }
    });

    test('the new command writes a motion doc whose headers are Durations '
        'then Easings', () async {
      final root = await writeTree({
        '.specstone/config.yaml': softwareDesignSystemConfig(),
        'docs/.keep': '',
      });

      final answer = writeIn(
        root,
        (s) => answerNew(s, docTypeId: 'motion', generators: noGenerators),
      );

      const path = 'specs/design_system/foundations/MOTION.md';
      expect(answer.text, startsWith('==> motion (motion) · $path <=='));
      final headers = [
        for (final line in readDoc(root, path).split('\n'))
          if (line.startsWith('## ')) line,
      ];
      expect(headers, ['## Durations', '## Easings']);
    });
  });
}
