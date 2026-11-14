import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType journey;
  setUpAll(() async {
    journey = prdCoreDocType(await resolvePrdCore(), 'journey');
  });

  test('journey has its path, no parent, two optional fields, '
      'three required sections, and its generators', () {
    expect(journey.path, 'prds/journeys/{slug}/JOURNEY.md');
    expect(journey.parent, isNull);
    expectOwnFields(journey, const [
      FieldSpec('persona', FieldType.docRef, list: true, docTypes: ['persona']),
      FieldSpec('confirmed', FieldType.string, list: true),
    ]);
    expectSections(journey, const [
      SectionSpec('goal', 'Goal', required: true),
      SectionSpec('flow', 'Flow', required: true),
      SectionSpec('steps', 'Steps', required: true),
    ]);
    expect(journey.generators, ['journey_flow', 'scenario_copy']);
    expect(journey.lint.maxLines, 400);
  });

  test('f10/us01/fr01/e01, f10/us01/s5: the guide opens with the sizing '
      'rule, then Goal, Flow, and Steps', () {
    final guide = journey.renderGuide();
    final rule = guide.indexOf('one goal of one persona');
    final branch = guide.indexOf('Branch only on outcomes the persona sees');
    final headers = ['## Goal', '## Flow', '## Steps'].map(guide.indexOf);
    expect(rule, isNonNegative);
    expect(branch, isNonNegative);
    expect(headers, everyElement(greaterThan(branch)));
    expect(headers.toList(), orderedEquals(List.of(headers)..sort()));
  });

  test("a journey's Name is its slug", () {
    expect(
      docNameOf('prds/journeys/first_project_to_html/JOURNEY.md', journey),
      'first_project_to_html',
    );
  });

  test('f03/us06/fr02, f03/us06/fr03, f03/us06/fr03/e01: titled # <the goal '
      'as the persona says it>, no NASA list', () {
    expectGuideShape(journey, title: '# <the goal as the persona says it>');
    expectNoNasaLint(journey);
    expectSources(journey, []);
  });

  test('Write the shipped writing guides '
      'E07: the guide states the item shape: rule per ID, bound, '
      'mechanics, and trace', () {
    expectItemShape(
      journey,
      'Write one rule per ID; in a section with no IDs, one '
      'rule per item, with mechanics left to the spec docs.\n'
      'Keep a bound in the step it limits, never in the prose.',
    );
  });
}
