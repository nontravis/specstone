import 'dart:convert';

import 'package:specstone_core/src/document_writing/new_doc.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/software_design_system.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/write_fixture.dart';

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

const _audienceSentence =
    "These docs serve the team that builds the library, not the library's "
    'consumers.';

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
    test('ships at 1.0.0, extends software-tech, and carries exactly the '
        'nineteen doc type files', () {
      final bytes = shippedPackFiles['software-design-system/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/software-design-system/pack.yaml',
      );
      expect(manifest.name, 'software-design-system');
      expect(manifest.version.toString(), '1.0.0');
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
    test('a project that lists the three packs holds fourteen, fifteen, and '
        'nineteen doc types', () {
      expect(prdCoreIds, hasLength(14));
      expect(softwareTechIds, hasLength(15));
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
        expectSections(prdCoreDocType(set, id), [
          for (final (sectionId, header) in sections)
            SectionSpec(sectionId, header, required: true),
        ]);
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

    test('every guide intro says the docs serve the team that builds the '
        'library', () {
      for (final id in softwareDesignSystemIds) {
        expect(
          prdCoreDocType(set, id).description,
          contains(_audienceSentence),
          reason: id,
        );
      }
    });

    test('contributing sets export false and no other doc type sets it', () {
      expect(prdCoreDocType(set, 'contributing').export, isFalse);
      expect(prdCoreDocType(set, 'contributing').exported, isFalse);
      for (final id in softwareDesignSystemIds.where(
        (i) => i != 'contributing',
      )) {
        expect(prdCoreDocType(set, id).export, isNull, reason: id);
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

  group('guides', () {
    List<String> linesOf(String id) =>
        prdCoreDocType(set, id).description!.split('\n');

    test('the guidelines description holds each guidelines statement on one '
        'line', () {
      const structure =
          'Shared code structure, such as a component base class, stays in '
          'the `software-tech` spec docs.';
      const hardRule =
          'GUIDELINES holds each hard rule, such as "no raw colors", and the '
          "project's own lint verifies the code against it.";
      const statements = [structure, hardRule];
      for (final statement in statements) {
        expect(
          linesOf('guidelines').where((l) => l == statement),
          hasLength(1),
        );
      }
    });

    test('the setup description holds the install-page statement on one '
        'line', () {
      expect(
        linesOf('setup').where(
          (l) =>
              l ==
              "The install contract is the source of the skill's install page.",
        ),
        hasLength(1),
      );
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

    test('tokens holds one required section, token_list, and no per-target '
        'key', () {
      final tokens = prdCoreDocType(set, 'tokens');
      expect(tokens.sections.map((s) => s.id), ['token_list']);
      expect(tokens.sections.single.required, isTrue);
      expect(tokens.isPerTarget, isFalse);
    });

    test('the new command writes a motion doc whose headers are Durations '
        'then Easings', () async {
      final root = await writeTree({
        '.specstone/config.yaml': softwareDesignSystemConfig(),
        'docs/.keep': '',
      });

      final answer = writeIn(root, (s) => answerNew(s, docTypeId: 'motion'));

      const path = 'specs/design_system/foundations/MOTION.md';
      expect(answer.text, startsWith('==> motion (motion) · $path <=='));
      final headers = [
        for (final line in readDoc(root, path).split('\n'))
          if (line.startsWith('## ')) line,
      ];
      expect(headers, ['## Durations', '## Easings']);
    });

    test('a new motion doc is a skeleton with Durations then Easings', () {
      final text = skeletonOf(prdCoreDocType(set, 'motion'), 'motion');
      expect(text, contains('## Durations'));
      expect(text, contains('## Easings'));
      expect(
        text.indexOf('## Durations'),
        lessThan(text.indexOf('## Easings')),
      );
    });
  });
}
