import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedDocType api;
  setUpAll(() async {
    api = prdCoreDocType(await resolveSoftwareTech(), 'api');
  });

  test('api sits under '
      'specs/f{nn}_{slug}/ with parent feature, the confirmed field, and four '
      'sections', () {
    expect(api.path, 'specs/f{nn}_{slug}/API.md');
    expect(api.parent, 'feature');
    expectOwnFields(api, const [
      FieldSpec('confirmed', FieldType.string, list: true),
      FieldSpec('overrides', FieldType.string, list: true),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
    expectSections(api, const [
      SectionSpec('source_of_truth', 'Source-of-truth'),
      SectionSpec('fr_trace', 'FR trace', required: true),
      SectionSpec('operations', 'Operations', required: true),
      SectionSpec('compatibility', 'Compatibility'),
    ]);
  });
  test('the operations description states one heading shape, with no FR '
      'label', () {
    final description = api.sections
        .singleWhere((s) => s.id == 'operations')
        .description;

    expect(
      description,
      contains(
        'one `###` per operation, headed `` `<operation>` `` alone '
        'with no FR label',
      ),
    );
  });

  test('operations carry no response example lint', () {
    final operations = sectionOf(api, 'operations');

    expect(operations.requiredPatterns, isNull);
    expect(
      [for (final p in operations.bannedPatterns!) p.id],
      ['operation_heading'],
    );
    expect(
      operations.description?.split('\n'),
      contains(
        'Write a success and an error Response example, valid against the '
        'source of truth, only in a doc that holds that section.',
      ),
    );
  });

  test('the operations guide asks a code list per operation', () {
    expect(
      sectionOf(api, 'operations').description,
      allOf(
        contains('`**Errors:** <codes>; see <links>`'),
        contains('every code the operation returns as a code span'),
        contains('`**Errors:** none`'),
      ),
    );
  });

  test('an API.md or an ERROR.md over 50000 characters gets chars_over_limit, '
      'limit 50000', () async {
    const draft = '---\ndraft: true\n---\n\n';
    for (final (file, title) in [
      ('API.md', '# Login API\n'),
      ('ERROR.md', '# Login errors\n'),
    ]) {
      final docPath = 'docs/specs/f01_login/$file';
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            docPath:
                '$draft$title'
                '${'x' * (50001 - draft.length - title.length - 2)}',
          },
        ),
      );

      final json = report.findings
          .singleWhere((f) => f.kind == FindingKind.charsOverLimit)
          .toJson();
      expect(
        json,
        allOf(containsPair('limit', 50000), containsPair('actual', 50001)),
        reason: file,
      );
    }
  });
}
