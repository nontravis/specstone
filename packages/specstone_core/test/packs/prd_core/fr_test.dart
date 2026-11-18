import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType fr;
  setUpAll(() async {
    fr = prdCoreDocType(await resolvePrdCore(), 'fr');
  });

  test('fr sits under its story folder with parent user_story, '
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
      FieldSpec('confirmed', FieldType.string, list: true),
    ]);
    expectStatusValues(fr, ['planned', 'implemented', 'deprecated']);
    expectSections(fr, const [
      SectionSpec('statement', 'Statement', required: true),
      SectionSpec('input_output', 'Input / Output'),
      SectionSpec('behavior', 'Behavior'),
      SectionSpec('edge_cases', 'Edge cases', prefixId: 'E', required: true),
      SectionSpec('rationale', 'Rationale', required: true),
      SectionSpec('verification', 'Verification', required: true),
      SectionSpec('tbr', 'TBR'),
    ]);
  });

  test('fr lints the 29 NASA words on Statement only, and the handbook', () {
    expectNasaLint(
      fr,
      sections: ['statement'],
      otherWords: {
        'tbr': ['TBD'],
      },
    );
  });

  test('no starter template holds a listed word', () {
    expectTemplatesFreeOfListedWords(fr);
  });

  test('the description states no number a lint key holds', () {
    expect(fr.description, isNot(contains('Statement as one sentence')));
  });

  test('fr marks statement summary', () {
    expect(
      [
        for (final s in fr.sections)
          if (s.summary == true) s.id,
      ],
      ['statement'],
    );
  });

  test('the description states the item shape and that edge cases exercise'
      ' each Statement clause', () {
    final description = fr.description!;

    expect(
      description,
      contains(
        'Write the Statement with one "shall", stated positively, with a '
        'quantified value kept in it, such as `within 2 s`.',
      ),
    );
    expect(
      description,
      contains(
        'Write one Edge cases item per case; a case the system does not '
        'handle goes there too, with what happens then.',
      ),
    );
    expect(description, contains('leave mechanics to the spec docs'));
    expect(
      description,
      contains(
        'Keep the trace in `traced_from` alone, never in the Statement or an '
        'edge case.',
      ),
    );
    expect(
      description,
      contains(
        'Exercise each Statement clause and each Input or Output row with an '
        'edge case, or with a scenario the FR traces.',
      ),
    );
  });

  test('the verification description and template show one Pass criteria'
      ' line and name no test file', () {
    final verification = sectionOf(fr, 'verification');
    final template = verification.template!;

    expect(
      verification.description,
      contains(
        'Write a long Verification as one `- **Pass criteria:**` line with '
        'one nested bullet per condition.',
      ),
    );
    expect(verification.description, contains('Name no test file here'));
    expect(
      RegExp(r'\*\*Pass criteria:\*\*').allMatches(template),
      hasLength(1),
    );
    expect(
      template,
      isNot(matches(RegExp(r'_test\.|\.test\.|\.spec\.|\btests?/'))),
    );
  });

  test('the edge cases template shows the several-trigger shape and the'
      ' description names it', () {
    final edgeCases = sectionOf(fr, 'edge_cases');

    expect(
      edgeCases.template,
      contains(
        '2. E02 — <lead> → <response>\n'
        '   <more response, one sentence per line, with no blank line>\n'
        '   - <trigger>\n'
        '   - <trigger>',
      ),
    );
    expect(
      edgeCases.description,
      contains(
        'For several triggers, keep the `→` in the lead and join the '
        'response as indented lines, with no blank line.',
      ),
    );
    expect(
      edgeCases.description,
      contains('List the triggers as nested items.'),
    );
  });
}
