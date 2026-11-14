import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType persona;
  setUpAll(() async {
    persona = prdCoreDocType(await resolvePrdCore(), 'persona');
  });

  test('persona sits at prds/personas/{slug}/PERSONA.md with '
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
      'titled # <archetype title>, no NASA list', () {
    expectGuideShape(persona, title: '# <archetype title>');
    expectNoNasaLint(persona);
    expectSources(persona, [
      (
        'Kim Goodwin, Perfecting Your Personas (Cooper Journal, 2001; Wayback)',
        'https://web.archive.org/web/20101229102055/http://www.cooper.com/journal/2001/08/perfecting_your_personas.html',
      ),
      (
        'NN/g, 3 Persona Types (2020)',
        'https://www.nngroup.com/articles/persona-types/',
      ),
      (
        'NN/g, Personas Make Users Memorable (2025)',
        'https://www.nngroup.com/articles/persona/',
      ),
      (
        '18F Methods, Personas card (archived repo)',
        'https://github.com/18F/methods/blob/main/_methods/personas.md',
      ),
    ]);
  });

  test('share is written only for a statistical persona', () {
    expect(fieldOf(persona, 'share').description, contains('statistical'));
  });

  test('the status field gives the retired meaning', () {
    expect(
      fieldOf(persona, 'status').description,
      contains(
        'no longer a group the product designs for; kept because older docs '
        'cite it',
      ),
    );
  });

  test('Write the shipped writing guides '
      'E07: the guide states the item shape: rule per ID, bound, '
      'mechanics, and trace', () {
    expectItemShape(
      persona,
      'Write one rule per ID; in a section with no IDs, one '
      'rule per item, with mechanics left to the spec docs.\n'
      'Keep a bound in the item it limits, and the research '
      'trace in `basis:` and the Sources section, never in the '
      'prose.',
    );
  });
}
