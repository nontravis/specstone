import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedDocType api;
  setUpAll(() async {
    api = prdCoreDocType(await resolveSoftwareTech(), 'api');
  });

  test('f03/us07/fr01, f03/us07/fr01/e06: api sits under '
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
}
