import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

const _templates = {
  'flow':
      '```mermaid\n'
      'flowchart LR\n'
      '  <Step1> --> <Step2> --> <Step3>\n'
      '```',
  'out_of_scope': '- <thing> — <owning feature | not planned>',
  'success_measures': '- <behavior change> — <target> by <date>',
};

void main() {
  late MergedDocType feature;
  setUpAll(() async {
    feature = prdCoreDocType(await resolvePrdCore(), 'feature');
  });

  test('f03/us06/fr01: feature sits at prds/features/f{nn}_{slug}/FEATURE.md '
      'with no parent, its fields, and ten sections', () {
    expect(feature.path, 'prds/features/f{nn}_{slug}/FEATURE.md');
    expect(feature.parent, isNull);
    expectOwnFields(feature, const [
      FieldSpec('vision', FieldType.string, list: true),
      FieldSpec('goals', FieldType.string, list: true),
      FieldSpec('persona', FieldType.docRef, list: true, docTypes: ['persona']),
      FieldSpec('system', FieldType.string),
    ]);
    expectSections(feature, const [
      SectionSpec('problem', 'Problem', required: true),
      SectionSpec('benefit_hypothesis', 'Benefit hypothesis', required: true),
      SectionSpec('success_measures', 'Success measures', required: true),
      SectionSpec(
        'current_alternatives',
        'Current alternatives',
        required: true,
      ),
      SectionSpec('flow', 'Feature flow', required: true),
      SectionSpec('out_of_scope', 'Out-of-scope', required: true),
      SectionSpec('appetite', 'Appetite'),
      SectionSpec('assumptions', 'Assumptions & rabbit holes'),
      SectionSpec('open_questions', 'Open questions'),
      SectionSpec('faq', 'FAQ'),
    ]);
  });

  test('f03/us06/fr01: the feature file writes no status entry', () {
    expect(
      shippedLayer('feature').fields.map((f) => f.id),
      isNot(contains('status')),
    );
    expectStatusValues(feature, ['planned', 'implemented', 'deprecated']);
  });

  test('f03/us06/fr02, f03/us06/fr02/e02, f03/us06/fr03, f03/us06/fr03/e01, '
      'f03/us06/fr03/e04: titled # <Name>, no NASA list', () {
    expectGuideShape(feature, title: '# <Name>');
    expectNoNasaLint(feature);
    expectSources(feature, [
      (
        'Bryar & Carr, PR/FAQ Instructions & Template',
        'https://workingbackwards.com/resources/working-backwards-pr-faq/',
      ),
      (
        'SAFe Fellow blog, Crafting Clarity: Feature Templates (2024)',
        'https://framework.scaledagile.com/blog/crafting-clarity-using-feature-templates-to-shape-and-communicate-intent/',
      ),
      (
        'Shape Up, Write the Pitch',
        'https://basecamp.com/shapeup/1.5-chapter-06',
      ),
      (
        'Marty Cagan, Assessing Product Opportunities',
        'https://www.svpg.com/assessing-product-opportunities/',
      ),
    ]);
  });

  test('f03/us06/fr02: the templates hold the flow sketch and the line '
      'forms', () {
    for (final MapEntry(:key, :value) in _templates.entries) {
      expect(sectionOf(feature, key).template, value, reason: key);
    }
  });

  test('f03/us06/fr02: the flow guide ends with the Mermaid quoting '
      'sentence', () {
    expect(
      sectionOf(feature, 'flow').description,
      endsWith('\n$mermaidQuoteSentence'),
    );
  });

  test('f03/us06/fr02: Out-of-scope carries no line cap', () {
    expect(sectionOf(feature, 'out_of_scope').maxLines, isNull);
  });

  test('f03/us06/fr01: feature joins no bundle and marks problem and '
      'out_of_scope query', () async {
    final feature = prdCoreDocType(await resolvePrdCore(), 'feature');
    expect(feature.bundle, isNull);
    expect(
      [
        for (final s in feature.sections)
          if (s.query == true) s.id,
      ],
      ['problem', 'out_of_scope'],
    );
  });
}
