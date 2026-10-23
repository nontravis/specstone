import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType reference;
  setUpAll(() async {
    reference = prdCoreDocType(await resolvePrdCore(), 'reference');
  });

  test('f03/us06/fr01: reference sits at prds/references/{slug}/REFERENCE.md '
      'with its fields, status values, and two sections', () {
    expect(reference.path, 'prds/references/{slug}/REFERENCE.md');
    expect(reference.parent, isNull);
    expectOwnFields(reference, const [
      FieldSpec('source', FieldType.string, required: true),
      FieldSpec('files', FieldType.string, list: true, required: true),
    ]);
    expectStatusValues(reference, ['current', 'superseded']);
    expectSections(reference, const [
      SectionSpec('summary', 'Summary', required: true),
      SectionSpec('key_terms', 'Key terms'),
    ]);
  });

  test('f03/us06/fr02, f03/us06/fr02/e02, f03/us06/fr03, f03/us06/fr03/e01, '
      'f03/us06/fr03/e04: titled # <Name>, no NASA list', () {
    expectGuideShape(reference, title: '# <Name>');
    expectNoNasaLint(reference);
  });

  test('f03/us06/fr01: superseded means a newer edition replaced it', () {
    expect(
      fieldOf(reference, 'status').description,
      contains('a newer edition replaced it'),
    );
  });
}
