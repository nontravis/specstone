import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType nf;
  setUpAll(() async {
    nf = prdCoreDocType(await resolvePrdCore(), 'nf');
  });

  test('nf sits under its story folder with parent user_story, '
      'its fields, and four sections', () {
    expect(
      nf.path,
      'prds/features/f{nn}_{slug}/us{nn}_{slug}/nf{nn}_{slug}.md',
    );
    expect(nf.parent, 'user_story');
    expectOwnFields(nf, const [
      FieldSpec(
        'kind',
        FieldType.enumType,
        required: true,
        enumValues: ['tighten', 'relax', 'add'],
      ),
      FieldSpec('overrides', FieldType.string),
      FieldSpec('traced_from', FieldType.string, list: true),
      FieldSpec(
        'verify_method',
        FieldType.enumType,
        required: true,
        enumValues: ['test', 'analysis', 'inspection', 'demonstration'],
      ),
      FieldSpec('owner', FieldType.string),
      FieldSpec('confirmed', FieldType.string, list: true),
    ]);
    expectStatusValues(nf, ['planned', 'implemented', 'deprecated']);
    expectSections(nf, const [
      SectionSpec('statement', 'Statement', required: true),
      SectionSpec('rationale', 'Rationale', required: true),
      SectionSpec('verification', 'Verification', required: true),
      SectionSpec('tbr', 'TBR'),
    ]);
  });

  test('nf lints the 29 NASA words on '
      'the Statement section only, and the NASA handbook', () {
    expectNasaLint(nf, sections: ['statement']);
  });

  test('no starter template holds a listed word', () {
    expectTemplatesFreeOfListedWords(nf);
  });

  test('nf marks statement summary', () {
    expect(
      [
        for (final s in nf.sections)
          if (s.summary == true) s.id,
      ],
      ['statement'],
    );
  });
}
