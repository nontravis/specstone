import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType gnfr;
  setUpAll(() async {
    gnfr = prdCoreDocType(await resolvePrdCore(), 'gnfr');
  });

  test('gnfr sits at prds/GNFR.md with no parent and the nine '
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

  test('the 29 NASA words on the Statement '
      'lines of each category, and the NASA handbook', () {
    expectNasaLint(
      gnfr,
      sections: const [
        'performance',
        'security',
        'reliability',
        'maintainability',
        'interface',
        'environment',
        'safety',
        'operability',
        'design_standards',
      ],
      linePrefix: '- **Statement:**',
    );
  });

  test('no starter template holds a listed word', () {
    expectTemplatesFreeOfListedWords(gnfr);
  });

  test('gnfr joins implement and design, sets bundle_refs, and marks no '
      'query section', () {
    expect(gnfr.bundleRefs, isTrue);
    expect(gnfr.bundle, ['implement', 'design']);
    expect(gnfr.sections.where((s) => s.query != null), isEmpty);
  });
}
