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
      SectionSpec('retry_policy', 'Retry policy'),
      SectionSpec('fallback', 'Fallback'),
    ]);
  });

  test('the catalog names no implementing column', () {
    final text = sectionOf(error, 'error_catalog').description!;
    expect(text, isNot(contains('Implemented by')));
    expect(
      text,
      contains(
        'columns Code, Exit/HTTP, Category, Triggered by, Client guidance',
      ),
    );
    expect(text, contains('an optional Details column'));
  });

  test('the error and project_error catalogs name an optional Group column of '
      'slugs unique in the catalog', () async {
    final projectError = prdCoreDocType(
      await resolveSoftwareTech(),
      'project_error',
    );

    for (final type in [error, projectError]) {
      final description = sectionOf(type, 'error_catalog').description!;
      expect(
        description,
        allOf(
          contains(
            'Add an optional Group column, a slug naming codes that several '
            'operations return together, such as `template_fault`',
          ),
          contains('keep each slug unique in the catalog'),
          contains('an optional Details column'),
        ),
        reason: type.id,
      );
      expect(
        description.split('\n').length,
        lessThanOrEqualTo(5),
        reason: type.id,
      );
    }
  });

  test('retry policy is optional', () {
    final retry = sectionOf(error, 'retry_policy');
    expect(retry.required, isFalse);
    expect(retry.description, contains('only when some call retries'));
  });

  test('error_catalog caps its two prose columns at one sentence each', () {
    final caps = sectionOf(error, 'error_catalog').maxSentences!;
    expect(
      [for (final c in caps) (c.count, c.column)],
      [(1, 'Triggered by'), (1, 'Client guidance')],
    );
  });
}
