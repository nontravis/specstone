import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

const _prefixes = {
  'performance': 'NFR-P',
  'security': 'NFR-Sec',
  'reliability': 'NFR-R',
  'maintainability': 'NFR-M',
  'interface': 'NFR-I',
  'environment': 'NFR-E',
  'safety': 'NFR-Sa',
  'operability': 'NFR-O',
  'design_standards': 'NFR-DS',
};

/// The F3P-D18 block every category template holds, with its prefix.
String _block(String prefix) =>
    '### ${prefix}01 — <name>\n'
    '- **Statement:** The <product> shall <verb> <object> '
    '<value ± tolerance> <condition>.\n'
    '- **Rationale:** <reason and assumptions>\n'
    '- **Traced from:** <PG id, stakeholder expectation, standard, or '
    'self-derived>\n'
    '- **Verification:** <test | analysis | inspection | demonstration>; '
    '<pass criteria>; <level>\n'
    '- **Owner:** <name, or blank for the PROJECT owner>\n'
    '- **TBR:** <value, why, close action, who, by when; or none>';

void main() {
  late MergedDocType gnfr;
  setUpAll(() async {
    gnfr = prdCoreDocType(await resolvePrdCore(), 'gnfr');
  });

  test('f03/us06/fr01: gnfr sits at prds/GNFR.md with no parent and the nine '
      'categories in order', () {
    expect(gnfr.path, 'prds/GNFR.md');
    expect(gnfr.parent, isNull);
    expectOwnFields(gnfr, const []);
    expectStatusValues(gnfr, ['planned', 'implemented', 'deprecated']);
    expectSections(gnfr, const [
      SectionSpec(
        'performance',
        'Performance',
        prefixId: 'NFR-P',
        required: true,
      ),
      SectionSpec('security', 'Security', prefixId: 'NFR-Sec', required: true),
      SectionSpec(
        'reliability',
        'Reliability',
        prefixId: 'NFR-R',
        required: true,
      ),
      SectionSpec(
        'maintainability',
        'Maintainability',
        prefixId: 'NFR-M',
        required: true,
      ),
      SectionSpec('interface', 'Interface', prefixId: 'NFR-I', required: true),
      SectionSpec(
        'environment',
        'Environment',
        prefixId: 'NFR-E',
        required: true,
      ),
      SectionSpec('safety', 'Safety', prefixId: 'NFR-Sa', required: true),
      SectionSpec(
        'operability',
        'Operability',
        prefixId: 'NFR-O',
        required: true,
      ),
      SectionSpec(
        'design_standards',
        'Design standards',
        prefixId: 'NFR-DS',
        required: true,
      ),
    ]);
  });

  test('f03/us06/fr02, f03/us06/fr02/e01, f03/us06/fr02/e03, '
      'f03/us06/fr03/e04: titled # Project-wide non-functional requirements, '
      'naming the -ly and -ize words', () {
    expectGuideShape(gnfr, title: '# Project-wide non-functional requirements');
    expect(gnfr.description, allOf(contains('-ly'), contains('-ize')));
  });

  test('f03/us06/fr03, f03/us06/fr03/e02: the 29 NASA words at doc level and '
      'the NASA handbook', () {
    expectNasaLint(gnfr);
  });

  test('f03/us06/fr02: each category template is one NFR block with its '
      'prefix', () {
    for (final MapEntry(:key, :value) in _prefixes.entries) {
      expect(sectionOf(gnfr, key).template, _block(value), reason: key);
    }
  });

  test('f03/us06/fr02: Maintainability reads industry-neutral', () {
    expect(
      sectionOf(gnfr, 'maintainability').description,
      contains('cost and time to change, inspect, and repair'),
    );
  });

  test('f03/us06/fr03: no starter template holds a listed word', () {
    expectTemplatesFreeOfListedWords(gnfr);
  });
}
