import 'dart:convert';

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/merged_set.dart';
import 'package:specstone_core/src/templates/pack_manifest.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_fault.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/agent_skills.dart';
import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/software_tech.dart';
import '../../helpers/temp_tree.dart';

const _skillDoc = 'specs/skills/review.md';
const _skillFolder = '.claude/skills/review/';
const _skillFile = '${_skillFolder}SKILL.md';

/// A skill doc whose `covers:` and body the caller picks.
String _skillText({
  String covers = '  - $_skillFolder\n',
  String body =
      '## Purpose\n\nReviews a diff.\n\n'
      '## When to use\n\n- A diff to review.\n\n'
      '## Boundaries\n\n- Never edits the diff.\n\n'
      '## Acceptance\n\n- A diff with one fault: the report names it.\n',
}) =>
    '---\n${covers.isEmpty ? '' : 'covers:\n$covers'}---\n\n# Review\n\n$body';

Future<List<String>> _skillFindings(
  String text, {
  FindingKind? kind,
  List<String> packs = const ['prd-core', 'software-tech', 'agent-skills'],
  Map<String, String> extra = const {},
}) async {
  final project = await writeCheckProject(
    extra: {
      '.specstone/config.yaml': shippedPinsConfig(packs),
      'docs/$_skillDoc': text,
      _skillFile: '# Review\n',
      ...extra,
    },
  );
  return spots(await checkOf(project, docPath: _skillDoc), kind);
}

void main() {
  group('agent-skills manifest', () {
    test('agent-skills ships at 1.0.0 and extends prd-core', () {
      final bytes = shippedPackFiles['agent-skills/pack.yaml'];
      expect(bytes, isNotNull);
      final manifest = PackManifest.parse(
        utf8.decode(bytes!),
        file: 'packs/agent-skills/pack.yaml',
      );
      expect(manifest.name, 'agent-skills');
      expect(manifest.version.toString(), '1.0.0');
      expect(manifest.extendsPack, 'prd-core');
    });

    test('agent-skills listed without prd-core is prd_core_missing', () async {
      final project = await writeTree({
        '.specstone/config.yaml': shippedPinsConfig(['agent-skills']),
      });
      final home = await writeTree({});
      expect(
        () => TemplateResolver().resolve(
          workingDirectory: project,
          homeDirectory: home,
        ),
        throwsA(
          isA<TemplateFault>().having(
            (f) => f.code,
            'code',
            FaultCode.prdCoreMissing,
          ),
        ),
      );
    });
  });

  group('skill doc type', () {
    late MergedSet set;
    late MergedDocType skill;

    setUpAll(() async {
      set = await resolveAgentSkills();
      skill = prdCoreDocType(set, 'skill');
    });

    test('loads from agent-skills at its path with no parent', () {
      expect(skill.pack, 'agent-skills');
      expect(skill.path, 'specs/skills/{slug}.md');
      expect(skill.parent, isNull);
    });

    test('the skill type carries covers and feature and no output', () {
      expect(skill.fields.map((f) => f.id), isNot(contains('output')));

      final feature = fieldOf(skill, 'feature');
      expect(feature.type, FieldType.docRef);
      expect(feature.list, isFalse);
      expect(feature.required, isFalse);
      expect(feature.docTypes, ['feature']);

      final covers = fieldOf(skill, 'covers');
      expect(covers.type, FieldType.outputRef);
      expect(covers.list, isTrue);
      expect(covers.pointer, PointerKind.prefix);
      expect(covers.root, PointerRoot.project);
      expect(covers.required, isTrue);

      for (final id in ['feature', 'covers']) {
        expect(fieldOf(skill, id).description, isNotEmpty, reason: id);
      }
    });

    test('the skill sections come in order with inputs alone optional', () {
      expectSections(skill, const [
        SectionSpec('purpose', 'Purpose', required: true),
        SectionSpec('when_to_use', 'When to use', required: true),
        SectionSpec('boundaries', 'Boundaries', required: true),
        SectionSpec('acceptance', 'Acceptance', required: true),
        SectionSpec('inputs', 'Inputs'),
      ]);
      expect(sectionOf(skill, 'purpose').summary, isTrue);
    });

    test('the description holds one line for each skill rule', () {
      final lines = skill.description!.split('\n');
      const rulePhrases = [
        'the spec of one skill a project builds for other projects to use',
        "The skill's own files hold its wording, steps, and host frontmatter",
        'read from the project root, never from a code root',
        'Specstone installs and distributes no project skill',
      ];
      for (final phrase in rulePhrases) {
        expect(
          lines.where((l) => l.contains(phrase)),
          hasLength(1),
          reason: phrase,
        );
      }
    });

    test(
      'the merged set lists skill and agent beside the other packs',
      () async {
        expect(
          set.docTypes.map((d) => d.id).toList(),
          [...prdCoreIds, 'skill', 'agent']..sort(),
        );
        expect(set.docTypes, hasLength(prdCoreIds.length + 2));

        final both = await resolveAgentSkills(extraPacks: ['software-tech']);
        expect(
          both.docTypes.map((d) => d.id).toList(),
          [...prdCoreIds, ...softwareTechIds, 'skill', 'agent']..sort(),
        );
        expect(
          both.docTypes,
          hasLength(prdCoreIds.length + softwareTechIds.length + 2),
        );
      },
    );

    test('is absent from a project that lists prd-core alone', () async {
      final prdOnly = await resolvePrdCore();
      expect(prdOnly.lookup('skill'), isNull);
      expect(prdOnly.lookup('agent'), isNull);
    });

    test(
      'a project layer writing root: code on covers resolves code',
      () async {
        final layered = await resolveAgentSkills(
          templates: const {
            'skill.yaml':
                'fields:\n  - {id: covers, type: output_ref, pointer: prefix, '
                'root: code}\n',
          },
        );
        expect(
          fieldOf(prdCoreDocType(layered, 'skill'), 'covers').root,
          PointerRoot.code,
        );
      },
    );
  });

  group('agent doc type', () {
    late MergedDocType agent;

    setUpAll(() async {
      agent = prdCoreDocType(await resolveAgentSkills(), 'agent');
    });

    test('the agent type loads at its path with covers and feature', () {
      expect(agent.pack, 'agent-skills');
      expect(agent.path, 'specs/agents/{slug}.md');
      expect(agent.parent, isNull);

      final feature = fieldOf(agent, 'feature');
      expect(feature.type, FieldType.docRef);
      expect(feature.required, isFalse);
      expect(feature.docTypes, ['feature']);

      final covers = fieldOf(agent, 'covers');
      expect(covers.type, FieldType.outputRef);
      expect(covers.list, isTrue);
      expect(covers.pointer, PointerKind.prefix);
      expect(covers.root, PointerRoot.project);
      expect(covers.required, isTrue);
      expect(agent.fields.map((f) => f.id), isNot(contains('output')));
    });

    test('the agent sections come in order and are all required', () {
      expectSections(agent, const [
        SectionSpec('role', 'Role', required: true),
        SectionSpec('dispatch_trigger', 'Dispatch trigger', required: true),
        SectionSpec('brief_inputs', 'Brief inputs', required: true),
        SectionSpec('report_shape', 'Report shape', required: true),
        SectionSpec('boundaries', 'Boundaries', required: true),
        SectionSpec('acceptance', 'Acceptance', required: true),
      ]);
      expect(sectionOf(agent, 'role').summary, isTrue);
    });
  });

  group('skill doc check', () {
    test('a skill doc with no covers is required_field_missing', () async {
      expect(
        await _skillFindings(
          _skillText(covers: ''),
          kind: FindingKind.requiredFieldMissing,
        ),
        ['$_skillDoc:1: required_field_missing'],
      );
    });

    test('one skill file or a second covers entry is tracked with no '
        'finding', () async {
      expect(
        await _skillFindings(_skillText(covers: '  - $_skillFile\n')),
        isEmpty,
      );
      expect(
        await _skillFindings(
          _skillText(covers: '  - $_skillFile\n  - app/lib/login.dart\n'),
        ),
        isEmpty,
      );
    });

    test('a skill doc without inputs gives no finding', () async {
      expect(await _skillFindings(_skillText()), isEmpty);
    });
  });
}
