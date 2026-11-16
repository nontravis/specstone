import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

const _templates = {
  'name':
      '- **Human:** <Human-readable project name>\n'
      '- **Code:** `<snake_case_code_name>`',
  'vision':
      '### PV-01 — <short name>\n'
      '> en: <one sentence of 15 words or fewer>\n'
      '- **Why:** <one sentence>\n'
      '- **Problem:** <one sentence>\n'
      '- **Audience:** <one sentence>',
  'roles': '- `<RoleName>` — <one-line definition>',
  'out_of_scope': '- <thing the project will NOT do>',
  'glossary': '- **<Term>** — <one-line definition tying to a concrete entity>',
};

void main() {
  late MergedDocType project;
  setUpAll(() async {
    project = prdCoreDocType(await resolvePrdCore(), 'project');
  });

  test('project sits at prds/PROJECT.md with no parent, an '
      'owner field, and five sections', () {
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
      SectionSpec('glossary', 'Domain glossary'),
    ]);
  });

  test('project holds no goals section', () {
    expect(project.sections.map((s) => s.id), isNot(contains('goals')));
  });

  test('the status field gives the three meanings', () {
    expect(
      fieldOf(project, 'status').description,
      allOf(
        contains('no feature is in use'),
        contains('at least one feature is in use'),
        contains('still usable and being retired'),
      ),
    );
  });

  test('f03/us06/fr02, f03/us06/fr02/e01, f03/us06/fr03, '
      'f03/us06/fr03/e01, f03/us06/fr03/e04: titled # Project context, '
      'a short English guide, 400 lines, no NASA list', () {
    expectGuideShape(project, title: '# Project context');
    expectNoNasaLint(project);
    expectSources(project, []);
  });

  test('the templates carry the quote line and the '
      'English labels', () {
    for (final MapEntry(:key, :value) in _templates.entries) {
      expect(sectionOf(project, key).template, value, reason: key);
    }
  });

  test('project sets bundle_refs', () async {
    final project = prdCoreDocType(await resolvePrdCore(), 'project');
    expect(project.bundleRefs, isTrue);
  });

  test('project joins every bundle mode and marks roles, '
      'out_of_scope, and glossary query', () async {
    final project = prdCoreDocType(await resolvePrdCore(), 'project');
    expect(project.bundle, ['query', 'implement', 'design']);
    expect(
      [
        for (final s in project.sections)
          if (s.query == true) s.id,
      ],
      ['roles', 'out_of_scope', 'glossary'],
    );
  });

  test('Write the shipped writing guides '
      'E07: the guide states the item shape: rule per ID, bound, '
      'mechanics, and trace', () {
    expectItemShape(
      project,
      'Write one rule per `PV-*` ID, '
      'and leave mechanics to the spec docs.',
    );
  });

  test('the guides keep measured numbers out of PROJECT and ask for a '
      'general Problem and a linked measurement', () {
    expectItemShape(
      project,
      "PROJECT holds no measured number; a vision's evidence goes to the "
      'Baseline of the measurement of a goal that serves it.',
    );
    expect(
      sectionOf(project, 'vision').description,
      contains('with Problem in general words.'),
    );
  });
}
