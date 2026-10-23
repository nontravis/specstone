import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

const _templates = {
  'use_case':
      '- **As a** <Role> [who <situation>]\n'
      '- **I want to** <action>\n'
      '- **so that** <benefit>',
  'rules': '- **BR-01** — <rule>',
  'acceptance_criteria':
      '### Scenario 1 — [happy] <what differs>\n'
      '- **Given** <only the state the scenario needs>\n'
      '- **When** <one trigger>\n'
      '- **Then** <observed outcome>\n'
      '\n'
      '### Scenario 2 — [error] <what differs> (BR-01)\n'
      '- **Given** <only the state the scenario needs>\n'
      '- **When** <one trigger>\n'
      '- **Then** <what the person sees or what the system refuses>',
  'open_questions': '- <question>',
};

void main() {
  late MergedDocType story;
  setUpAll(() async {
    story = prdCoreDocType(await resolvePrdCore(), 'user_story');
  });

  test('f03/us06/fr01: user_story sits under its feature folder with parent '
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

  test('f03/us06/fr02, f03/us06/fr02/e02, f03/us06/fr03, f03/us06/fr03/e01, '
      'f03/us06/fr03/e04: titled # <Name>, no NASA list', () {
    expectGuideShape(story, title: '# <Name>');
    expectNoNasaLint(story);
  });

  test('f03/us06/s2, f03/us06/fr02: the guide gives the title form, then '
      'each section header in order', () {
    final guide = story.renderGuide();
    expect(guide, startsWith(story.description!.trimRight()));
    final at = [
      '## Use Case',
      '## Rules',
      '## Acceptance Criteria',
      '## Open questions',
    ].map(guide.indexOf).toList();
    expect(at, everyElement(greaterThan(guide.indexOf('# <Name>'))));
    expect(at, orderedEquals(List.of(at)..sort()));
  });

  test('f03/us06/fr02: the templates hold the story form', () {
    for (final MapEntry(:key, :value) in _templates.entries) {
      expect(sectionOf(story, key).template, value, reason: key);
    }
    expect(
      sectionOf(story, 'rules').description,
      contains('two or more rules'),
    );
  });
}
