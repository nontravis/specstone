import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedDocType integration;
  setUpAll(() async {
    integration = prdCoreDocType(await resolveSoftwareTech(), 'integration');
  });

  test('f03/us07/fr01, f03/us07/fr01/e05, f03/us07/fr01/e06: integration '
      'sits under specs/f{nn}_{slug}/ with parent feature, the overrides and tasks fields, and '
      'four sections, events optional', () {
    expect(integration.path, 'specs/f{nn}_{slug}/INTEGRATION.md');
    expect(integration.parent, 'feature');
    expectOwnFields(integration, const [
      FieldSpec('overrides', FieldType.string, list: true),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
    expectSections(integration, const [
      SectionSpec('external_systems', 'External systems', required: true),
      SectionSpec('contract_per_system', 'Contract per system', required: true),
      SectionSpec('translation', 'Translation'),
      SectionSpec('events', 'Events'),
    ]);
  });
}
