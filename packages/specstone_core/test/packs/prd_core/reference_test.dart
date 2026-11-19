import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType reference;
  setUpAll(() async {
    reference = prdCoreDocType(await resolvePrdCore(), 'reference');
  });

  test('reference sits at prds/references/{slug}/REFERENCE.md '
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
}
