import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType reference;
  setUpAll(() async {
    reference = prdCoreDocType(await resolvePrdCore(), 'reference');
  });

  test('reference sits at prds/references/{slug}/REFERENCE.md '
      'with its fields, status values, and two sections', () {
    expect(reference.path, 'prds/references/{slug}/REFERENCE.md');
    expect(reference.parent, isNull);
    expectOwnFields(reference, const [
      FieldSpec('source', FieldType.string, required: true),
      FieldSpec('files', FieldType.string, list: true, required: true),
    ]);
    expectStatusValues(reference, ['current', 'superseded']);
    expectSections(reference, const [
      SectionSpec('summary', 'Summary', required: true),
      SectionSpec('key_terms', 'Key terms'),
    ]);
  });

  group('the summary fact locator', () {
    const path = 'prds/references/court/REFERENCE.md';

    Future<List<String>> flagged(List<String> lines) => bannedLines(
      {
        'docs/$path':
            '---\nsource: Court\nfiles:\n  - court.pdf\n---\n\n# Court\n\n'
            '## Summary\n\n${lines.join('\n')}\n',
      },
      path,
      'fact_locator',
    );

    test('a bullet ending in a parenthesized page or section gives no '
        'finding', () async {
      expect(
        await flagged([
          '- The court holds the ruling (p. 12)',
          '- The court holds the ruling (section 4.2).',
          '- The court holds the ruling (`court.pdf`, p. 3)',
        ]),
        isEmpty,
      );
    });

    test('a bullet with no tail, an empty tail, or the tail mid-line gives '
        'fact_locator', () async {
      const loose = [
        '- The court holds the ruling',
        '- The court holds the ruling ()',
        '- The court holds the ruling (p. 12) in full',
        '* The court holds the ruling',
      ];

      expect(await flagged(loose), loose);
    });

    test('a wrapped line, a blank line, a table line, and a fenced line give '
        'no finding', () async {
      expect(
        await flagged([
          '- The court holds the ruling (p. 12)',
          '  and states its reason.',
          '',
          '| Fact | Page |',
          '```text',
          '- A fenced fact',
          '```',
        ]),
        isEmpty,
      );
    });
  });
}
