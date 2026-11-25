import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/prd_core.dart';

const _ownFields = <FieldSpec>[
  FieldSpec('summary', FieldType.string, required: true),
  FieldSpec('vision', FieldType.string, list: true),
  FieldSpec('goals', FieldType.string, list: true),
  FieldSpec('persona', FieldType.docRef, list: true, docTypes: ['persona']),
  FieldSpec('system', FieldType.string),
  FieldSpec('depends_on', FieldType.docRef, list: true, docTypes: ['feature']),
  FieldSpec('patterns', FieldType.string, list: true),
];

const _workspaceLayer =
    'fields:\n'
    '  - id: depends_on\n'
    '    type: doc_ref\n'
    '    list: true\n'
    '    doc_types: [feature]\n'
    '    description: Names the features this feature needs built first.\n';

void main() {
  late MergedDocType feature;
  setUpAll(() async {
    feature = prdCoreDocType(await resolvePrdCore(), 'feature');
  });

  test('feature sits at prds/features/f{nn}_{slug}/FEATURE.md '
      'with no parent, its fields, and ten sections', () {
    expect(feature.path, 'prds/features/f{nn}_{slug}/FEATURE.md');
    expect(feature.parent, isNull);
    expectOwnFields(feature, _ownFields);
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

  test('summary is a required string with its description and one-sentence '
      'caps', () {
    final summary = fieldOf(feature, 'summary');
    expect(summary.lint?.maxSentences, 1);
    expect(summary.lint?.maxSentenceWords, {'default': 15, 'ko': 10});
    expect(summary.lint?.maxSentenceChars, {
      'default': 60,
      'th': 60,
      'ja': 36,
      'zh': 27,
    });
  });

  test('the feature file writes no status entry', () {
    expect(
      shippedLayer('feature').fields.map((f) => f.id),
      isNot(contains('status')),
    );
    expectStatusValues(feature, ['planned', 'implemented', 'deprecated']);
  });

  test('Out-of-scope carries no section line cap', () {
    expect(sectionOf(feature, 'out_of_scope').maxLines, isNull);
  });

  test('out_of_scope carries its item line cap', () {
    expect(sectionOf(feature, 'out_of_scope').maxItemLines, 1);
  });

  test('feature joins no bundle and marks problem and '
      'out_of_scope query', () {
    expect(feature.bundle, isNull);
    expect(
      [
        for (final s in feature.sections)
          if (s.query == true) s.id,
      ],
      ['problem', 'out_of_scope'],
    );
  });

  test(
    'a project '
    'layer that still declares depends_on merges into the one shipped field',
    () async {
      final merged = prdCoreDocType(
        await resolvePrdCore(templates: {'feature.yaml': _workspaceLayer}),
        'feature',
      );
      expectOwnFields(merged, _ownFields);
    },
  );

  test('feature carries max_depth 3', () {
    expect(feature.maxDepth, 3);
  });

  test('a project feature.yaml that sets another cap gives the merged feature'
      ' that cap', () async {
    final merged = prdCoreDocType(
      await resolvePrdCore(templates: {'feature.yaml': 'max_depth: 2\n'}),
      'feature',
    );

    expect(merged.maxDepth, 2);
  });

  test('writeNestedProject without its feature.yaml still names '
      'shop/cart', () async {
    final session = openSession(
      await writeNestedProject(without: {'.specstone/templates/feature.yaml'}),
    );
    addTearDown(session.close);
    expect(session.index.at(cartFeature)!.name, 'shop/cart');
  });

  test('a one-sentence summary at the word cap gives no finding', () async {
    Future<List<String>> found(int words) async {
      final report = await check.checkOf(
        await check.writeCheckProject(
          extra: check.edit(check.loginFeature, [
            (
              'summary: Lets an agent sign in.',
              'summary: ${List.filled(words, 'abc').join(' ')}.',
            ),
          ]),
        ),
      );
      return [
        for (final f in report.findings)
          if (f.path == check.loginFeature) f.kind.wire,
      ];
    }

    expect(await found(15), isEmpty);
    expect(await found(16), contains('words_over_limit'));
  });
}
