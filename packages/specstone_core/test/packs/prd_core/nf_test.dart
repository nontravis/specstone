import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

const _templates = <String, String>{
  'statement': requirementStatementTemplate,
  'rationale': '<reason; for kind relax, why the waiver is acceptable>',
  'verification': verificationTemplate,
  'tbr': tbrTemplate,
};

void main() {
  late MergedDocType nf;
  setUpAll(() async {
    nf = prdCoreDocType(await resolvePrdCore(), 'nf');
  });

  test('f03/us06/fr01: nf sits under its story folder with parent user_story, '
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

  test('f03/us06/fr02, f03/us06/fr02/e02, f03/us06/fr02/e03, '
      'f03/us06/fr03/e04: titled # <Name>, naming the -ly and -ize words', () {
    expectGuideShape(nf, title: '# <Name>');
    expect(nf.description, allOf(contains('-ly'), contains('-ize')));
  });

  test('f03/us06/s4, f03/us06/fr03, f03/us06/fr03/e02: the 29 NASA words on '
      'the Statement section only, and the NASA handbook', () {
    expectNasaLint(nf, sections: ['statement']);
  });

  test('f03/us06/fr02: the templates hold the requirement forms, free of the '
      'listed words', () {
    for (final MapEntry(:key, :value) in _templates.entries) {
      expect(sectionOf(nf, key).template, value, reason: key);
    }
    expectTemplatesFreeOfListedWords(nf);
  });

  test('f03/us06/fr01: kind names its three values', () {
    expect(
      fieldOf(nf, 'kind').description,
      allOf(contains('tighten'), contains('relax'), contains('add')),
    );
  });
}
