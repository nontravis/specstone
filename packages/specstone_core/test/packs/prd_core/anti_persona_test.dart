import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType anti;
  setUpAll(() async {
    anti = prdCoreDocType(await resolvePrdCore(), 'anti_persona');
  });

  test('f03/us06/fr01: anti_persona sits at '
      'prds/personas/{slug}/ANTI_PERSONA.md with its fields, status values, '
      'and eight sections', () {
    expect(anti.path, 'prds/personas/{slug}/ANTI_PERSONA.md');
    expect(anti.parent, isNull);
    expectOwnFields(anti, const [
      FieldSpec(
        'anti_type',
        FieldType.enumType,
        required: true,
        enumValues: ['misuser', 'non-target'],
      ),
      FieldSpec(
        'basis',
        FieldType.enumType,
        required: true,
        enumValues: ['proto', 'qualitative', 'statistical'],
      ),
      FieldSpec('reviewed', FieldType.date),
    ]);
    expectStatusValues(anti, ['assumed', 'validated', 'retired']);
    expectSections(anti, const [
      SectionSpec('snapshot', 'Snapshot', required: true),
      SectionSpec('goal', 'Goal', required: true),
      SectionSpec('sources', 'Sources', required: true),
      SectionSpec('motivations', 'Motivations'),
      SectionSpec('actions', 'Actions'),
      SectionSpec('tools', 'Tools'),
      SectionSpec('needs', 'Needs'),
      SectionSpec('consequences', 'Consequences'),
    ]);
  });

  test('f03/us06/fr02, f03/us06/fr02/e02, f03/us06/fr03, f03/us06/fr03/e01, '
      'f03/us06/fr03/e04: titled # <archetype title>, no NASA list', () {
    expectGuideShape(anti, title: '# <archetype title>');
    expectNoNasaLint(anti);
  });

  test('f03/us06/fr02: the guide splits misuser from non-target', () {
    expect(
      anti.description,
      allOf(contains('misuser'), contains('non-target')),
    );
    for (final id in const [
      'motivations',
      'actions',
      'tools',
      'needs',
      'consequences',
    ]) {
      expect(sectionOf(anti, id).description, contains('misuser'), reason: id);
    }
  });

  test('f03/us06/fr01: the status field gives the retired meaning', () {
    expect(
      fieldOf(anti, 'status').description,
      contains(
        'no longer a group the product designs for; kept because older docs '
        'cite it',
      ),
    );
  });
}
