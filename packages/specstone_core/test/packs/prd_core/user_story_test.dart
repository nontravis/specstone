import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
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

  test('the acceptance criteria description chains at most two extra '
      'outcomes and counts one Then per scenario', () {
    final acceptance = sectionOf(story, 'acceptance_criteria');

    expect(
      acceptance.description!.split('\n'),
      contains(
        'Chain at most two extra outcomes with And or But; more outcomes '
        'make a second scenario.',
      ),
    );
    expect(acceptance.description, isNot(contains('Chain extra outcomes')));
    expect(
      [for (final p in acceptance.itemCount!.prefixes) (p.linePrefix, p.count)],
      [('- **When**', 1), ('- **Then**', 1)],
    );
  });

  test('a scenario of two Then lines is prefix_count_mismatch, and And and '
      'But lines add none', () async {
    Future<List<String>> mismatches(String thenLines) async {
      final report = await check.checkOf(
        await check.writeCheckProject(
          extra: check.doc(
            check.loginStory,
            '- **Then** the Agent sees the home page',
            thenLines,
          ),
        ),
      );
      return [
        for (final f in report.findings)
          if (f.kind == FindingKind.prefixCountMismatch) f.path,
      ];
    }

    expect(
      await mismatches('- **Then** the Agent sees the home page'),
      isEmpty,
    );
    expect(
      await mismatches(
        '- **Then** the Agent sees the home page\n'
        '- **And** the Agent sees a greeting\n'
        '- **But** the Agent sees no banner',
      ),
      isEmpty,
    );
    expect(
      await mismatches(
        '- **Then** the Agent sees the home page\n'
        '- **Then** the Agent sees a greeting',
      ),
      [check.loginStory],
    );
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
