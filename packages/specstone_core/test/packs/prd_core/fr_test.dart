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

  test('the 29 NASA words on '
      'the Statement section only, and the NASA handbook', () {
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
}
