import 'package:specstone_core/src/index_query/get_docs.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/index_fixture.dart';
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
  });

  test("a journey's Name is its slug", () {
    expect(
      docNameOf('prds/journeys/first_project_to_html/JOURNEY.md', journey),
      'first_project_to_html',
    );
  });

  test('the description states no number a lint key holds', () {
    expect(sectionOf(journey, 'goal').description, isNot(contains('One line')));
  });

  test('goal carries its line cap', () {
    expect(sectionOf(journey, 'goal').maxLines, 1);
  });

  test('a journey titled in words keeps its slug as its Name, and get reads '
      'it by that Name', () async {
    final index = await indexWith({
      'docs/prds/journeys/first_project_to_html/JOURNEY.md':
          '# First project to HTML\n\n## Goal\nShip a page.\n\n## Flow\n\n'
          '## Steps\n### 1. Open the page\nstep: login/email_login S1\n',
    });

    expect(
      answerGet(index, ['journey:first_project_to_html']).text,
      startsWith(
        '==> first_project_to_html (journey) · '
        'prds/journeys/first_project_to_html/JOURNEY.md · base ',
      ),
    );
  });
}
