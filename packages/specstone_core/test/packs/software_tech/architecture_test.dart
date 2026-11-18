import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
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
      SectionSpec('concerns', 'Concerns', required: true),
      SectionSpec('design_references', 'Design references'),
      SectionSpec('open_questions', 'Open questions'),
    ]);
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
