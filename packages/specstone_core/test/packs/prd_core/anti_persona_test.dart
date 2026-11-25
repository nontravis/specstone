import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType anti;
  setUpAll(() async {
    anti = prdCoreDocType(await resolvePrdCore(), 'anti_persona');
  });

  test('anti_persona sits at '
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
      SectionSpec('motivations', 'Motivations', required: true),
      SectionSpec('actions', 'Actions', required: true),
      SectionSpec('tools', 'Tools', required: true),
      SectionSpec('needs', 'Needs', required: true),
      SectionSpec('consequences', 'Consequences', required: true),
    ]);
  });
}
