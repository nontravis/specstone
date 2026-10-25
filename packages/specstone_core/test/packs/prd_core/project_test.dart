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
  'goals':
      '### PG-01 — <short name>\n'
      '**Serves:** PV-01\n'
      '**Statement:** <goal statement>\n'
      '**Metric:** <numeric target with unit>\n'
      '**By:** <date or milestone>',
  'roles': '- `<RoleName>` — <one-line definition>',
  'out_of_scope': '- <thing the project will NOT do>',
  'glossary': '- **<Term>** — <one-line definition tying to a concrete entity>',
};

void main() {
  late MergedDocType project;
  setUpAll(() async {
    project = prdCoreDocType(await resolvePrdCore(), 'project');
  });

  test('f03/us06/fr01: project sits at prds/PROJECT.md with no parent, an '
      'owner field, and six sections', () {
    expect(project.path, 'prds/PROJECT.md');
    expect(project.parent, isNull);
    expectOwnFields(project, const [
      FieldSpec('owner', FieldType.string, required: true),
    ]);
    expectStatusValues(project, ['planned', 'implemented', 'deprecated']);
    expectSections(project, const [
      SectionSpec('name', 'Project name', required: true),
      SectionSpec('vision', 'Project vision', prefixId: 'PV-', required: true),
      SectionSpec('goals', 'Project goals', prefixId: 'PG-'),
      SectionSpec('roles', 'Role', required: true),
      SectionSpec('out_of_scope', 'Out-of-scope', required: true),
      SectionSpec('glossary', 'Domain glossary'),
    ]);
  });

  test('f03/us06/fr01: the status field gives the three meanings', () {
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
  });

  test('f03/us06/fr02/e04: the templates carry the quote line and the '
      'English labels', () {
    for (final MapEntry(:key, :value) in _templates.entries) {
      expect(sectionOf(project, key).template, value, reason: key);
    }
  });

  test('f03/us06/fr01: project joins every bundle mode and marks roles, '
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
}
