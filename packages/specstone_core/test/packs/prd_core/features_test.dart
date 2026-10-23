import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

const _templates = {
  'diagram':
      '```mermaid\n'
      'flowchart LR\n'
      '  <Actor> --> <System>\n'
      '  <System> --> <External>\n'
      '```',
  'systems':
      '| System | Description |\n'
      '|--------|-------------|\n'
      '| <System name> | <One-line description of the system.> |',
};

void main() {
  late MergedDocType features;
  setUpAll(() async {
    features = prdCoreDocType(await resolvePrdCore(), 'features');
  });

  test('f03/us06/fr01: features sits at prds/FEATURES.md with no parent, no '
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

  test('f03/us06/fr02, f03/us06/fr02/e01, f03/us06/fr03, '
      'f03/us06/fr03/e01, f03/us06/fr03/e04: titled # System map, a short '
      'English guide, 400 lines, no NASA list', () {
    expectGuideShape(features, title: '# System map');
    expectNoNasaLint(features);
  });

  test('f03/us06/fr02: the templates hold the diagram and the Systems '
      'table', () {
    for (final MapEntry(:key, :value) in _templates.entries) {
      expect(sectionOf(features, key).template, value, reason: key);
    }
  });
}
