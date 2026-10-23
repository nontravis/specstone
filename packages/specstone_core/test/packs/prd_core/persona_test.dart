import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType persona;
  setUpAll(() async {
    persona = prdCoreDocType(await resolvePrdCore(), 'persona');
  });

  test('f03/us06/fr01: persona sits at prds/personas/{slug}/PERSONA.md with '
      'its fields, status values, and fourteen sections', () {
    expect(persona.path, 'prds/personas/{slug}/PERSONA.md');
    expect(persona.parent, isNull);
    expectOwnFields(persona, const [
      FieldSpec('role', FieldType.string, required: true),
      FieldSpec(
        'priority',
        FieldType.enumType,
        required: true,
        enumValues: ['primary', 'secondary', 'served'],
      ),
      FieldSpec(
        'basis',
        FieldType.enumType,
        required: true,
        enumValues: ['proto', 'qualitative', 'statistical'],
      ),
      FieldSpec('share', FieldType.string),
      FieldSpec('reviewed', FieldType.date),
    ]);
    expectStatusValues(persona, ['assumed', 'validated', 'retired']);
    expectSections(persona, const [
      SectionSpec('snapshot', 'Snapshot', required: true),
      SectionSpec('jobs', 'Jobs to be done', required: true),
      SectionSpec('behaviors', 'Behaviors & skills', required: true),
      SectionSpec('context_of_use', 'Context of use', required: true),
      SectionSpec('pains', 'Pains', required: true),
      SectionSpec('triggers', 'Triggers', required: true),
      SectionSpec('barriers', 'Barriers', required: true),
      SectionSpec('alternatives', 'Current alternatives', required: true),
      SectionSpec('success', 'Success looks like', required: true),
      SectionSpec('vocabulary', 'Vocabulary', required: true),
      SectionSpec('sources', 'Sources', required: true),
      SectionSpec('decision_criteria', 'Decision criteria'),
      SectionSpec('channels', 'Channels & content habits'),
      SectionSpec('how_we_talk', 'How we talk to'),
    ]);
  });

  test('f03/us06/fr02, f03/us06/fr02/e02, f03/us06/fr03, f03/us06/fr03/e01, '
      'f03/us06/fr03/e04: titled # <archetype title>, no NASA list', () {
    expectGuideShape(persona, title: '# <archetype title>');
    expectNoNasaLint(persona);
  });

  test('f03/us06/fr01: share is written only for a statistical persona', () {
    expect(fieldOf(persona, 'share').description, contains('statistical'));
  });

  test('f03/us06/fr01: the status field gives the retired meaning', () {
    expect(
      fieldOf(persona, 'status').description,
      contains(
        'no longer a group the product designs for; kept because older docs '
        'cite it',
      ),
    );
  });
}
