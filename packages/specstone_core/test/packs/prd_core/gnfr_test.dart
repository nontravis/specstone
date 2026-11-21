import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/pattern_findings.dart';
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

  group('the trace entry', () {
    test('every category section holds trace_outside_field', () {
      for (final section in gnfr.sections) {
        expect(
          [for (final p in section.bannedPatterns!) p.id],
          contains('trace_outside_field'),
          reason: section.id,
        );
      }
    });

    test('a Statement line holding a scenario ID or a standard cite gives '
        'trace_outside_field, and the same text on another bullet gives '
        'none', () async {
      const statement =
          '- **Statement:** The system shall answer a sign-in within 2 s.';
      const stem =
          '- **Statement:** The system shall answer a sign-in within 2 s';
      const hits = <String>[
        '$stem, as `S2` asks.',
        '$stem per ISO 25010.',
        '$stem per NFR-P02.',
      ];
      Future<List<String>> flagged(List<String> lines) => bannedLines(
        check.edit(check.gnfrDoc, [(statement, lines.join('\n'))]),
        check.gnfrDoc,
        'trace_outside_field',
      );

      expect(await flagged(hits), hits);
      expect(await flagged([statement]), isEmpty);
      expect(
        await flagged([
          statement,
          '- **Rationale:** Users wait per ISO 25010 and S2.',
          '- **Traced from:** NFR-P02, S2, ISO 25010',
        ]),
        isEmpty,
      );
    });
  });
}
