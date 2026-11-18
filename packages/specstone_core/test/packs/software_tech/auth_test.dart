import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

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
}
