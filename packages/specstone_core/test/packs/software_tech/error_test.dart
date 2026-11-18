import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedDocType error;
  setUpAll(() async {
    error = prdCoreDocType(await resolveSoftwareTech(), 'error');
  });

  test('error sits under '
      'specs/f{nn}_{slug}/ with parent feature, the overrides and tasks '
      'fields, and four sections', () {
    expect(error.path, 'specs/f{nn}_{slug}/ERROR.md');
    expect(error.parent, 'feature');
    expectOwnFields(error, const [
      FieldSpec('overrides', FieldType.string, list: true),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
    expectSections(error, const [
      SectionSpec('error_envelope', 'Error envelope'),
      SectionSpec('error_catalog', 'Error catalog', required: true),
      SectionSpec('retry_policy', 'Retry policy', required: true),
      SectionSpec('fallback', 'Fallback'),
    ]);
  });

  test('error_catalog caps its two prose columns at one sentence each', () {
    final caps = sectionOf(error, 'error_catalog').maxSentences!;
    expect(
      [for (final c in caps) (c.count, c.column)],
      [(1, 'Triggered by'), (1, 'Client guidance')],
    );
  });
}
