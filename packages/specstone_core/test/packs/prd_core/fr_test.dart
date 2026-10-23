import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

const _templates = <String, String>{
  'statement': requirementStatementTemplate,
  'input_output':
      '**Input**\n'
      '| Field   | Type   | Required | Notes         |\n'
      '| ------- | ------ | -------- | ------------- |\n'
      '| <field> | <type> | <yes/no> | <constraints> |\n'
      '\n'
      '**Output**\n'
      '| Field   | Type   | Notes              |\n'
      '| ------- | ------ | ------------------ |\n'
      '| <field> | <type> | <semantics, units> |',
  'behavior':
      '```mermaid\n'
      'flowchart TD\n'
      '  A[<step>] --> B{<decision>}\n'
      '  B -- <branch> --> C[<outcome>]\n'
      '```',
  'edge_cases': '1. E01 — <trigger> → <response>',
  'rationale':
      '<reason, assumptions, related requirements, design constraints>',
  'verification': verificationTemplate,
  'tbr': tbrTemplate,
};

void main() {
  late MergedDocType fr;
  setUpAll(() async {
    fr = prdCoreDocType(await resolvePrdCore(), 'fr');
  });

  test('f03/us06/fr01: fr sits under its story folder with parent user_story, '
      'its fields, and seven sections', () {
    expect(
      fr.path,
      'prds/features/f{nn}_{slug}/us{nn}_{slug}/fr{nn}_{slug}.md',
    );
    expect(fr.parent, 'user_story');
    expectOwnFields(fr, const [
      FieldSpec('traced_from', FieldType.string, list: true, required: true),
      FieldSpec(
        'verify_method',
        FieldType.enumType,
        required: true,
        enumValues: ['test', 'analysis', 'inspection', 'demonstration'],
      ),
      FieldSpec('owner', FieldType.string),
    ]);
    expectStatusValues(fr, ['planned', 'implemented', 'deprecated']);
    expectSections(fr, const [
      SectionSpec('statement', 'Statement', required: true),
      SectionSpec('input_output', 'Input / Output'),
      SectionSpec('behavior', 'Behavior'),
      SectionSpec('edge_cases', 'Edge cases', required: true),
      SectionSpec('rationale', 'Rationale', required: true),
      SectionSpec('verification', 'Verification', required: true),
      SectionSpec('tbr', 'TBR'),
    ]);
  });

  test('f03/us06/fr02, f03/us06/fr02/e02, f03/us06/fr02/e03, '
      'f03/us06/fr03/e04: titled # <Name>, naming the -ly and -ize words', () {
    expectGuideShape(fr, title: '# <Name>');
    expect(fr.description, allOf(contains('-ly'), contains('-ize')));
  });

  test('f03/us06/s4, f03/us06/fr03, f03/us06/fr03/e02: the 29 NASA words at '
      'doc level and the NASA handbook', () {
    expectNasaLint(fr);
  });

  test('f03/us06/fr02: the templates hold the requirement forms, free of the '
      'listed words', () {
    for (final MapEntry(:key, :value) in _templates.entries) {
      expect(sectionOf(fr, key).template, value, reason: key);
    }
    expectTemplatesFreeOfListedWords(fr);
  });

  test('f03/us06/fr02: Edge cases asks for detect, report, handle, and '
      'recover', () {
    expect(
      sectionOf(fr, 'edge_cases').description,
      allOf(
        contains('detect'),
        contains('report'),
        contains('handle'),
        contains('recover'),
      ),
    );
  });
}
