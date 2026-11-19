import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType project;
  setUpAll(() async {
    project = prdCoreDocType(await resolvePrdCore(), 'project');
  });

  test('project sits at prds/PROJECT.md with no parent, an '
      'owner field, and four sections', () {
    expect(project.path, 'prds/PROJECT.md');
    expect(project.parent, isNull);
    expectOwnFields(project, const [
      FieldSpec('owner', FieldType.string, required: true),
    ]);
    expectStatusValues(project, ['planned', 'implemented', 'deprecated']);
    expectSections(project, const [
      SectionSpec('name', 'Project name', required: true),
      SectionSpec('vision', 'Project vision', prefixId: 'PV-', required: true),
      SectionSpec('roles', 'Role', required: true),
      SectionSpec('out_of_scope', 'Out-of-scope', required: true),
    ]);
  });

  test('the description states no number a lint key holds', () {
    final vision = sectionOf(project, 'vision');
    expect(sectionOf(project, 'name').description, isNot(contains('one line')));
    expect(vision.description, isNot(contains('15 words')));
    expect(vision.description, isNot(contains('one sentence each')));
    expect(vision.template, isNot(contains('15 words')));
    expect(vision.template, isNot(contains('one sentence')));
    final roles = sectionOf(project, 'roles');
    expect(roles.description, isNot(contains('one-line')));
    expect(roles.template, isNot(contains('one-line')));
  });

  test('name and roles carry their item line cap', () {
    for (final id in ['name', 'roles']) {
      expect(sectionOf(project, id).maxItemLines, 1, reason: id);
    }
  });

  test('the quote_words message states the cap alone', () {
    final quoteWords = sectionOf(
      project,
      'vision',
    ).bannedPatterns!.singleWhere((p) => p.id == 'quote_words');
    expect(quoteWords.message, 'quote over 15 words');
  });

  test('project sets bundle_refs, joins every bundle mode, and marks roles '
      'and out_of_scope query', () {
    expect(project.bundleRefs, isTrue);
    expect(project.bundle, ['query', 'implement', 'design']);
    expect(
      [
        for (final s in project.sections)
          if (s.query == true) s.id,
      ],
      ['roles', 'out_of_scope'],
    );
  });

  test('the vision template labels each entry line in English', () {
    final template = sectionOf(project, 'vision').template!;

    expect(
      template,
      allOf(
        contains('- **Why:** '),
        contains('- **Problem:** '),
        contains('- **Audience:** '),
      ),
    );
  });
}
