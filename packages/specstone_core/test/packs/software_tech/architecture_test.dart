import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  const draft = '---\ndraft: true\n---\n\n';
  late MergedDocType architecture;
  setUpAll(() async {
    architecture = prdCoreDocType(await resolveSoftwareTech(), 'architecture');
  });

  test('architecture sits '
      'under specs/f{nn}_{slug}/ with parent feature, a required prefix covers '
      'list, and ten sections', () {
    expect(architecture.path, 'specs/f{nn}_{slug}/ARCHITECTURE.md');
    expect(architecture.parent, 'feature');
    expectOwnFields(architecture, const [
      FieldSpec(
        'covers',
        FieldType.outputRef,
        list: true,
        required: true,
        pointer: PointerKind.prefix,
      ),
      FieldSpec('overrides', FieldType.string, list: true),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
    expectSections(architecture, const [
      SectionSpec('component_diagram', 'Component diagram', required: true),
      SectionSpec('components', 'Components', required: true),
      SectionSpec('component_details', 'Component details'),
      SectionSpec('interaction', 'Interaction'),
      SectionSpec('deployment', 'Deployment'),
      SectionSpec('rollout', 'Rollout'),
      SectionSpec('observability', 'Observability'),
      SectionSpec('concerns', 'Concerns'),
      SectionSpec('design_references', 'Design references'),
      SectionSpec('open_questions', 'Open questions'),
    ]);
  });

  test('the section descriptions state no number a lint key holds', () {
    for (final id in ['components', 'component_details']) {
      expect(
        sectionOf(architecture, id).description,
        isNot(contains('one sentence')),
        reason: id,
      );
    }
    expect(
      sectionOf(architecture, 'design_references').description,
      isNot(contains('no count cap')),
    );
  });

  test('concerns is optional and keeps only the see ending rule', () {
    final concerns = sectionOf(architecture, 'concerns');

    expect(concerns.required, isFalse);
    expect(concerns.requiredPatterns, isNull);
    expect(
      [for (final p in concerns.bannedPatterns!) p.id],
      ['concern_ending'],
    );
    expect(concerns.maxItemLines, 1);
    expect(
      concerns.description?.split('\n'),
      allOf(
        contains(
          'Write one line per concern that applies, among Integration, '
          'Errors, Auth, Lifecycle, Events, Rollout, and Observability.',
        ),
        contains('End each line with `see <section or sibling doc>`.'),
        contains('Write no line for a concern that does not apply.'),
      ),
    );
  });

  test('an N/A concern line breaks the ending rule', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/specs/f01_login/ARCHITECTURE.md':
              '$draft# Login architecture\n\n## Concerns\n'
              '- Auth: N/A — no access rules\n',
        },
      ),
    );

    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.patternBanned,
    );
    expect(finding.path, 'specs/f01_login/ARCHITECTURE.md');
    expect(finding.toJson(), containsPair('pattern', 'concern_ending'));
  });

  test('a bullet under the components table is banned', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          'docs/specs/f01_login/ARCHITECTURE.md':
              '$draft# Login architecture\n\n## Components\n'
              '| Component | Responsibility |\n|---|---|\n'
              '| Gate | Checks the password |\n\n'
              '- Gate also logs each attempt\n',
        },
      ),
    );

    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.patternBanned,
    );
    expect(finding.path, 'specs/f01_login/ARCHITECTURE.md');
    expect(finding.toJson(), containsPair('line', 12));
  });

  test('design references cap their links', () {
    final references = sectionOf(architecture, 'design_references');

    expect(references.maxItemLines, 1);
    expect(references.itemCount!.max, 5);
    expect(
      references.description?.split('\n'),
      contains(
        'List each design or ADR whose decisions this doc still states, one '
        'link per line, with the decision IDs the doc still relies on and no '
        'summary.',
      ),
    );
  });

  test('components names four columns and no file list', () {
    final components = sectionOf(architecture, 'components');

    expect(
      components.description,
      allOf(
        contains('the columns Component, Responsibility, Tech, Owns.'),
        isNot(contains('Code path')),
        contains('Write no file, folder, or command list'),
      ),
    );
  });

  test('the component details guide asks for one ### Component subsection per '
      'component that needs more than its row', () {
    final details = sectionOf(architecture, 'component_details');

    expect(details.required, isFalse);
    expect(
      details.description,
      allOf(
        contains('only when a component needs more than its row'),
        contains('one `### <Component>` subsection per such component'),
        contains("headed with the row's Component cell"),
      ),
    );
  });
}
