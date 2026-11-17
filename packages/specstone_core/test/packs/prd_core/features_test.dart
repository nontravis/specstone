import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType features;
  setUpAll(() async {
    features = prdCoreDocType(await resolvePrdCore(), 'features');
  });

  test('features sits at prds/FEATURES.md with no parent, no '
      'own field, and two sections', () {
    expect(features.path, 'prds/FEATURES.md');
    expect(features.parent, isNull);
    expectOwnFields(features, const []);
    expectStatusValues(features, ['planned', 'implemented', 'deprecated']);
    expectSections(features, const [
      SectionSpec('diagram', 'System interaction diagram', required: true),
      SectionSpec('systems', 'Systems', required: true),
    ]);
  });
}
