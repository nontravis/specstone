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
const _skillFile = '.claude/skills/review/SKILL.md';

/// A skill doc whose `covers:` and body the caller picks.
String _skillText({
  String covers = '  - $_skillFile\n',
  String body = '## Sources\n\n- [Login API](../f01_login/API.md)\n',
}) =>
    '---\noutput: .claude/skills/review/\n'
    '${covers.isEmpty ? '' : 'covers:\n$covers'}---\n\n# Review\n\n$body';

Future<List<String>> _skillFindings(
  String text, {
  FindingKind? kind,
  List<String> packs = const ['prd-core', 'software-tech', 'agent-skills'],
}) async {
  final project = await writeCheckProject(
    extra: {
      '.specstone/config.yaml': shippedPinsConfig(packs),
      'docs/$_skillDoc': text,
      _skillFile: '# Review\n',
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

    test('carries the output, feature, and covers fields', () {
      final output = fieldOf(skill, 'output');
      expect(output.type, FieldType.string);
      expect(output.list, isFalse);
      expect(output.required, isTrue);

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

      for (final id in ['output', 'feature', 'covers']) {
        expect(fieldOf(skill, id).description, isNotEmpty, reason: id);
      }
    });

    test('carries purpose, when_to_use, and sources in order, sources alone '
        'required', () {
      expectSections(skill, const [
        SectionSpec('purpose', 'Purpose'),
        SectionSpec('when_to_use', 'When to use'),
        SectionSpec('sources', 'Sources', required: true),
      ]);
      expect(sectionOf(skill, 'purpose').summary, isTrue);
    });

    test('the description holds one line for each skill rule', () {
      final lines = skill.description!.split('\n');
      expect(lines.length, greaterThanOrEqualTo(5));
      expect(
        lines.where((l) => l.contains('Specstone installs and distributes')),
        hasLength(1),
      );
      expect(lines.where((l) => l.contains('`<output>/SKILL.md`')), isNotEmpty);
    });

    test('lists beside the prd-core doc types', () {
      expect(
        set.docTypes.map((d) => d.id).toList(),
        [...prdCoreIds, 'skill']..sort(),
      );
    });

    test('lists beside the doc types of software-tech', () async {
      final both = await resolveAgentSkills(extraPacks: ['software-tech']);
      expect(
        both.docTypes.map((d) => d.id).toList(),
        [...prdCoreIds, ...softwareTechIds, 'skill']..sort(),
      );
    });

    test('is absent from a project that lists prd-core alone', () async {
      expect((await resolvePrdCore()).lookup('skill'), isNull);
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

    test('a second covers entry gives no finding', () async {
      expect(
        await _skillFindings(
          _skillText(covers: '  - $_skillFile\n  - app/lib/login.dart\n'),
        ),
        isEmpty,
      );
    });

    test('a skill doc with only Sources gives no finding, and a Sources link '
        'to a doc of another pack is accepted', () async {
      expect(await _skillFindings(_skillText()), isEmpty);
    });
  });
}
