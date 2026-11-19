import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/marketing.dart';
import '../../helpers/personal_branding.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/software_design_system.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';
import '../../helpers/yaml_key_line.dart';

const _voiceDoc = 'specs/marketing/VOICE.md';
const _personStatement =
    "The docs hold the stable facts; the person's own skills write the "
    'content outside the docs.';
const _learningStatement = 'A learning edits the doc it corrects.';

/// The `prd-core` shared line ids that reach every doc type, in print order.
const _prdCoreLineIds = [
  'one_rule_per_item',
  'cite_at_item_end',
  'one_example',
  'condition_first',
  'cite_by_link',
];
const _allSixPacks = [
  'prd-core',
  'software-tech',
  'software-design-system',
  'agent-skills',
  'marketing',
  'personal-branding',
];

/// One expected personal-branding doc type: its path and sections.
final class _DocTypeSpec {
  const new(this.path, this.sections);

  final String path;
  final List<SectionSpec> sections;
}

const _docTypes = <String, _DocTypeSpec>{
  'story': _DocTypeSpec('specs/marketing/STORY.md', [
    SectionSpec('story', 'Story'),
    SectionSpec('values', 'Values'),
  ]),
  'proof': _DocTypeSpec('specs/marketing/PROOF.md', [
    SectionSpec('results', 'Results'),
    SectionSpec('testimonials', 'Testimonials'),
    SectionSpec('credentials', 'Credentials'),
  ]),
  'offer': _DocTypeSpec('specs/marketing/OFFER.md', [
    SectionSpec('ladder', 'Ladder'),
  ]),
  'relationships': _DocTypeSpec('specs/marketing/RELATIONSHIPS.md', [
    SectionSpec('people', 'People'),
    SectionSpec('groups', 'Groups'),
  ]),
};

Future<MergedSet> _resolve(List<String> packs) =>
    resolvePersonalBranding(packs);

PackManifest _manifest() => PackManifest.parse(
  utf8.decode(shippedPackFiles['personal-branding/pack.yaml']!),
  file: 'packs/personal-branding/pack.yaml',
);

/// The description of [type], its declared fields, and its sections.
List<String?> _descriptionsOf(MergedDocType type) => [
  type.description,
  for (final field in type.fields)
    if (!field.isBuiltIn) field.description,
  for (final section in type.sections) section.description,
];

/// Expects [type]'s guide to print the shared lines of [ids], in that order.
void _expectSharedLines(MergedDocType type, List<String> ids) {
  expect(type.sharedLines.map((l) => l.id), ids, reason: type.id);
  final guide = type.renderGuide();
  for (final line in type.sharedLines) {
    expect(guide, contains(line.text), reason: type.id);
  }
}

void main() {
  late MergedSet set;

  setUpAll(() async => set = await resolvePersonalBranding());

  group('manifest', () {
    test('personal-branding ships at 1.0.0 and extends marketing', () {
      final bytes = shippedPackFiles['personal-branding/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/personal-branding/pack.yaml',
      );
      expect(manifest.name, 'personal-branding');
      expect(manifest.version.toString(), '1.0.0');
      expect(manifest.extendsPack, 'marketing');
    });

    test('ships person_stable_facts, then person_learning_edits_doc, each '
        'naming the four doc types, and no shared field', () {
      final shared = _manifest().shared;
      expect(
        [for (final l in shared.lines) (l.id, l.text, l.disabled)],
        [
          ('person_stable_facts', _personStatement, false),
          ('person_learning_edits_doc', _learningStatement, false),
        ],
      );
      for (final line in shared.lines) {
        expect(line.forDocTypes, personalBrandingIds, reason: line.id);
      }
      expect(shared.fields, isEmpty);
    });

    test('the pack holds the manifest, the voice layer, and the doc type '
        'files of personalBrandingIds alone', () {
      expect(
        shippedPackFiles.keys.where((k) => k.startsWith('personal-branding/')),
        unorderedEquals([
          'personal-branding/pack.yaml',
          'personal-branding/voice.yaml',
          for (final id in personalBrandingIds) 'personal-branding/$id.yaml',
        ]),
      );
    });

    test('a project that lists the pack without marketing is '
        'extends_target_unknown naming the pack file and marketing', () async {
      await expectLater(
        _resolve(['prd-core', 'personal-branding']),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.extendsTargetUnknown)
              .having((f) => f.exitStatus, 'exitStatus', 78)
              .having(
                (f) => f.file,
                'file',
                'packs/personal-branding/pack.yaml',
              )
              .having((f) => f.message, 'message', contains('marketing')),
        ),
      );
    });

    test('a pin one version below fails as pack_pin_older naming the shipped '
        'version', () async {
      final project = await writeTree({
        '.specstone/config.yaml':
            'packs:\n  prd-core: ${shippedPackVersions()['prd-core']}\n'
            '  marketing: 1.0.0\n  personal-branding: 0.9.0\n',
      });
      final home = await writeTree({});
      expect(
        () => TemplateResolver().resolve(
          workingDirectory: project,
          homeDirectory: home,
        ),
        throwsA(
          isA<TemplateFault>()
              .having((f) => f.code, 'code', FaultCode.packPinOlder)
              .having((f) => f.message, 'message', contains('1.0.0')),
        ),
      );
    });
  });

  group('merged set', () {
    test('holds the prd-core, marketing, and personal-branding doc types', () {
      expect(personalBrandingIds, hasLength(4));
      expect(
        set.docTypes.map((d) => d.id).toList(),
        [...prdCoreIds, ...marketingIds, ...personalBrandingIds]..sort(),
      );
      for (final id in personalBrandingIds) {
        expect(prdCoreDocType(set, id).pack, 'personal-branding', reason: id);
      }
    });

    test('is absent from a project that lists marketing alone', () async {
      final without = await resolveMarketing();
      for (final id in personalBrandingIds) {
        expect(without.lookup(id), isNull, reason: id);
      }
    });

    test('a project that lists all six shipped packs resolves, each new doc '
        'type beside the design-system and skill doc types', () async {
      final all = await _resolve(_allSixPacks);
      expect(
        all.docTypes.map((d) => d.id).toList(),
        [
          ...prdCoreIds,
          ...softwareTechIds,
          ...softwareDesignSystemIds,
          'skill',
          ...marketingIds,
          ...personalBrandingIds,
        ]..sort(),
      );
      final others = [
        for (final d in all.docTypes)
          if (d.pack != 'personal-branding') ...d.paths,
      ];
      for (final id in personalBrandingIds) {
        expect(others, isNot(contains(prdCoreDocType(all, id).path)));
      }
    });
  });

  group('doc types', () {
    test('each loads at its path with no parent', () {
      expect([..._docTypes.keys]..sort(), personalBrandingIds);
      for (final MapEntry(key: id, value: spec) in _docTypes.entries) {
        final docType = prdCoreDocType(set, id);
        expect(docType.path, spec.path, reason: id);
        expect(docType.parent, isNull, reason: id);
      }
    });

    test('each holds the optional sections of its row, in order', () {
      for (final MapEntry(key: id, value: spec) in _docTypes.entries) {
        expectSections(prdCoreDocType(set, id), spec.sections);
      }
    });

    test('none sets per_target and each carries the built-in fields alone', () {
      for (final id in personalBrandingIds) {
        final docType = prdCoreDocType(set, id);
        expect(docType.isPerTarget, isFalse, reason: id);
        expectOwnFields(docType, const []);
      }
    });

    test('every path starts under specs/marketing/ and overlaps no other '
        'pack path', () {
      final others = [
        for (final d in set.docTypes)
          if (d.pack != 'personal-branding') ...d.paths,
      ];
      for (final id in personalBrandingIds) {
        final path = prdCoreDocType(set, id).path!;
        expect(path, startsWith('specs/marketing/'), reason: id);
        expect(others, isNot(contains(path)), reason: id);
      }
    });

    test('each guide prints the prd-core lines, then the two pack lines', () {
      for (final id in personalBrandingIds) {
        _expectSharedLines(prdCoreDocType(set, id), [
          ..._prdCoreLineIds,
          'person_stable_facts',
          'person_learning_edits_doc',
        ]);
      }
    });

    test('no description restates a shared line that reaches its doc '
        'type', () {
      for (final id in [...personalBrandingIds, 'voice']) {
        final type = prdCoreDocType(set, id);
        for (final description in _descriptionsOf(type)) {
          for (final line in type.sharedLines) {
            expect(description ?? '', isNot(contains(line.text)), reason: id);
          }
        }
      }
    });

    test('no description or template holds a YAML key line', () {
      for (final id in [...personalBrandingIds, 'voice']) {
        final type = prdCoreDocType(set, id);
        final texts = [
          ..._descriptionsOf(type),
          for (final section in type.sections) section.template,
        ];
        for (final text in texts) {
          expectNoYamlKeyLine(text, reason: id);
        }
      }
    });
  });

  group('voice layer', () {
    test('ends with the required writing_habits section after the marketing '
        'sections', () {
      final voice = prdCoreDocType(set, 'voice');
      expect(voice.pack, 'marketing');
      expectSections(voice, const [
        SectionSpec('tone', 'Tone'),
        SectionSpec('words', 'Words'),
        SectionSpec('writing_habits', 'Writing habits', required: true),
      ]);
    });

    test('keeps the marketing description and path', () async {
      final base = prdCoreDocType(await resolveMarketing(), 'voice');
      final layered = prdCoreDocType(set, 'voice');
      expect(layered.description, base.description);
      expect(layered.path, base.path);
    });

    test('the voice guide prints the prd-core lines, then both marketing '
        'lines', () {
      _expectSharedLines(prdCoreDocType(set, 'voice'), [
        ..._prdCoreLineIds,
        'stable_facts_and_plan',
        'learning_edits_doc',
      ]);
    });

    test('a project that lists marketing alone holds no writing_habits '
        'section', () async {
      final base = prdCoreDocType(await resolveMarketing(), 'voice');
      expect(base.sections.map((s) => s.id), ['tone', 'words']);
    });
  });

  group('check', () {
    test('a voice doc with no Writing habits section is '
        'required_section_missing', () async {
      final project = await writeCheckProject(
        extra: {
          '.specstone/config.yaml': shippedPinsConfig(personalBrandingPacks),
          'docs/$_voiceDoc': '# Voice\n\n## Tone\n\nPlain.\n',
        },
      );
      expect(
        spots(
          await checkOf(project, docPath: _voiceDoc),
          FindingKind.requiredSectionMissing,
        ),
        ['$_voiceDoc:1: required_section_missing'],
      );
    });
  });
}
