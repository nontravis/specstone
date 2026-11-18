import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType story;
  setUpAll(() async {
    story = prdCoreDocType(await resolvePrdCore(), 'user_story');
  });

  test('user_story sits under its feature folder with parent '
      'feature, its fields, and four sections', () {
    expect(
      story.path,
      'prds/features/f{nn}_{slug}/us{nn}_{slug}/USER_STORY.md',
    );
    expect(story.parent, 'feature');
    expectOwnFields(story, const [
      FieldSpec('vision', FieldType.string, list: true),
      FieldSpec('goals', FieldType.string, list: true),
      FieldSpec('persona', FieldType.docRef, list: true, docTypes: ['persona']),
    ]);
    expectStatusValues(story, ['planned', 'implemented', 'deprecated']);
    expectSections(story, const [
      SectionSpec('use_case', 'Use Case', required: true),
      SectionSpec('rules', 'Rules', prefixId: 'BR-'),
      SectionSpec('acceptance_criteria', 'Acceptance Criteria', required: true),
      SectionSpec('open_questions', 'Open questions'),
    ]);
  });

  test('the description states no number a lint key holds', () {
    final acceptance = sectionOf(story, 'acceptance_criteria');
    expect(story.description, isNot(contains('more than 6 scenarios')));
    for (final id in ['vision', 'goals']) {
      expect(
        fieldOf(story, id).description,
        isNot(contains('at least one ID')),
        reason: id,
      );
    }
    expect(
      sectionOf(story, 'rules').description,
      isNot(contains('two or more rules')),
    );
    expect(acceptance.description, isNot(contains('3 to 5 steps')));
    expect(acceptance.description, isNot(contains('use one When')));
    expect(acceptance.description, isNot(contains('at least one `[error]`')));
    expect(acceptance.template, isNot(contains('one trigger')));
  });

  test('rules carries its item floor', () {
    final items = sectionOf(story, 'rules').itemCount!;
    expect((items.min, items.max), (2, null));
  });

  test('user_story marks use_case and rules summary', () {
    expect(
      [
        for (final s in story.sections)
          if (s.summary == true) s.id,
      ],
      ['use_case', 'rules'],
    );
  });
}
