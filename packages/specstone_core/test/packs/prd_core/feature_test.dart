// The placement lines are the pack's text, kept verbatim on one line each.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/prd_core.dart';

const _ownFields = <FieldSpec>[
  FieldSpec('vision', FieldType.string, list: true),
  FieldSpec('goals', FieldType.string, list: true),
  FieldSpec('persona', FieldType.docRef, list: true, docTypes: ['persona']),
  FieldSpec('system', FieldType.string),
  FieldSpec('depends_on', FieldType.docRef, list: true, docTypes: ['feature']),
];

const _templates = {
  'flow':
      '```mermaid\n'
      'flowchart LR\n'
      '  <Step1> --> <Step2> --> <Step3>\n'
      '```',
  'out_of_scope': '- <thing> — <owning feature | not planned>',
  'success_measures': '- <behavior change> — <target> by <date>',
};

const _placementLines = [
  'Place a new requirement by three questions, and state the answer to each when you propose its place:',
  '1. Does it use an entity, invariant, or rule an existing feature owns (in its domain doc, where the project has one)? No: a new top feature.',
  '2. Yes: how many stories does it yield? One: a new story in the deepest such feature that holds stories.',
  "3. Several: do those stories own entities or invariants the feature's other stories do not use? Yes: a new sub-feature under that feature. No: new stories in that feature.",
  'A sub-feature holds at least 2 stories or sub-features; a lone story never starts one.',
  'A feature that holds sub-features holds no story; a lone story whose only spec is such a parent goes to the sub-feature whose stories it is closest to, and the proposal says so.',
  'The parent keeps only what all its sub-features share.',
  "When `check` reports `chars_over_limit` or `lines_over_limit` on a feature's doc that a write has laid out, propose a sub-feature split by the same three questions; the Owner approves it.",
  'A feature of fewer than 4 stories takes no split, since a split needs at least 2 sub-features of at least 2 stories each and a feature holds stories or sub-features, never both; say why no split applies.',
  "`item_over_limit` takes no split, since a split never shrinks one item; the item takes its doc type's item shape instead.",
  'Cut no text to pass a size.',
];

const _dependsOnDescription =
    'Names the features this feature needs built first; each name must resolve to a feature.\n'
    'Leave it out when the feature depends on no other feature.';
const _workspaceLayer =
    'fields:\n  - id: depends_on\n    type: doc_ref\n    list: true\n    doc_types: [feature]\n'
    '    description: |-\n'
    '      Names the features this feature needs built first; each name must resolve to a feature.\n'
    '      Leave it out when the feature depends on no other feature.\n';

void main() {
  late MergedDocType feature;
  setUpAll(() async {
    feature = prdCoreDocType(await resolvePrdCore(), 'feature');
  });

  test('f03/us06/fr01: feature sits at prds/features/f{nn}_{slug}/FEATURE.md '
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

  test('template_packs/write_prd_docs_from_prd_core/ship_prd_core_pack: depends_on '
      'carries the description the workspace layer gave it', () {
    expect(fieldOf(feature, 'depends_on').description, _dependsOnDescription);
  });

  test(
    'template_packs/customize_shipped_doc_type/merge_layers_by_id E03, E04: a project '
    'layer that still declares depends_on merges into the one shipped field',
    () async {
      final merged = prdCoreDocType(
        await resolvePrdCore(templates: {'feature.yaml': _workspaceLayer}),
        'feature',
      );
      expectOwnFields(merged, _ownFields);
    },
  );

  test('f03/us06/fr01, sf-r5: feature carries max_depth 3', () {
    expect(feature.maxDepth, 3);
  });

  test(
    'f03/us06/fr02/e05, sf-r8: the feature description in guide feature ends '
    'with the placement questions',
    () {
      final lines = const LineSplitter().convert(feature.description!);
      expect(
        lines.sublist(lines.length - _placementLines.length),
        _placementLines,
      );
    },
  );

  test('f03/us03/fr05/e01: a project feature.yaml of max_depth 3 makes the '
      'nested FEATURE.md the feature shop/cart', () async {
    final session = openSession(await writeNestedProject());
    addTearDown(session.close);
    expect(session.index.at(cartFeature)!.name, 'shop/cart');
  });

  test('sf-r5: writeNestedProject without its feature.yaml still names '
      'shop/cart', () async {
    final session = openSession(
      await writeNestedProject(without: {'.specstone/templates/feature.yaml'}),
    );
    addTearDown(session.close);
    expect(session.index.at(cartFeature)!.name, 'shop/cart');
  });
}
