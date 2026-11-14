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

  test('the diagram guide ends with the Mermaid quoting '
      'sentence', () {
    expect(
      sectionOf(features, 'diagram').description,
      endsWith('\n$mermaidQuoteSentence'),
    );
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

  test('f03/us06/fr02, f03/us06/fr02/e01, f03/us06/fr03, '
      'f03/us06/fr03/e01, f03/us06/fr03/e04: titled # System map, a short '
      'English guide, 400 lines, no NASA list', () {
    expectGuideShape(features, title: '# System map');
    expectNoNasaLint(features);
    expectSources(features, []);
  });

  test('the templates hold the diagram and the Systems '
      'table', () {
    for (final MapEntry(:key, :value) in _templates.entries) {
      expect(sectionOf(features, key).template, value, reason: key);
    }
  });

  test('Write the shipped writing guides '
      'E07: the guide states the item shape: rule per ID, bound, '
      'mechanics, and trace', () {
    expectItemShape(
      features,
      'Write one rule per ID; in a section with no IDs, one '
      'rule per item, with mechanics left to the spec docs.\n'
      'Keep a bound in the rule it limits, never in the '
      'diagram or a row.',
    );
  });
}
