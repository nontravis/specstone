import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedDocType auth;
  setUpAll(() async {
    auth = prdCoreDocType(await resolveSoftwareTech(), 'auth');
  });

  test('auth sits under '
      'specs/f{nn}_{slug}/ with parent feature, the overrides and tasks '
      'fields, and eight sections', () {
    expect(auth.path, 'specs/f{nn}_{slug}/AUTH.md');
    expect(auth.parent, 'feature');
    expectOwnFields(auth, const [
      FieldSpec('overrides', FieldType.string, list: true),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
    expectSections(auth, const [
      SectionSpec('roles', 'Roles', required: true),
      SectionSpec('scopes', 'Scopes', required: true),
      SectionSpec('resource_matrix', 'Resource matrix', required: true),
      SectionSpec('conditions', 'Conditions'),
      SectionSpec('field_rules', 'Field rules'),
      SectionSpec('authentication_and_sessions', 'Authentication and sessions'),
      SectionSpec('enforcement', 'Enforcement', required: true),
      SectionSpec('audit', 'Audit', required: true),
    ]);
  });

  test('the description states no number a lint key holds', () {
    expect(
      sectionOf(auth, 'enforcement').description,
      isNot(contains('one line')),
    );
  });

  test('enforcement carries its line cap', () {
    expect(sectionOf(auth, 'enforcement').maxLines, 1);
  });

  test('a matrix with no Default: deny line gets default_deny, and the line '
      'in a bullet or after the table clears it', () async {
    const authPath = 'specs/f01_login/AUTH.md';
    const table = '| Resource | admin |\n|---|---|\n| session | yes |\n';
    Future<List<String>> missing(String body) => missingPatterns({
      'docs/$authPath':
          '---\ndraft: true\n---\n\n# Login auth\n\n'
          '## Resource matrix\n\n$body',
    }, authPath);

    expect(await missing(table), ['default_deny']);
    expect(await missing('$table\nDefault: deny\n'), isEmpty);
    expect(await missing('Default: deny\n\n$table'), isEmpty);
    expect(await missing('- Default: deny\n\n$table'), isEmpty);
    expect(await missing('$table\n```text\nDefault: deny\n```\n'), [
      'default_deny',
    ]);
    expect(
      sectionOf(auth, 'resource_matrix').requiredPatterns!.single.message,
      endsWith('guide line: Write the line "Default: deny"'),
    );
  });
}
