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

  test('concerns and design_references describe their items without a line '
      'count', () {
    List<String> linesOf(String id) =>
        sectionOf(architecture, id).description?.split('\n') ?? const [];
    expect(
      linesOf('concerns'),
      contains(
        'Cover Integration, Errors, Auth, Lifecycle, Events, Rollout, and '
        'Observability, one item each.',
      ),
    );
    expect(
      linesOf('design_references'),
      contains(
        'List each design or ADR whose decisions this doc still states.',
      ),
    );
  });

  test('each concern message quotes its guide line as written', () {
    final concerns = sectionOf(architecture, 'concerns');
    final entries = concerns.requiredPatterns!;
    expect(entries, hasLength(7));
    for (final entry in entries) {
      final quoted = entry.message.split('guide line: ').last;
      expect(concerns.description, contains('$quoted.'), reason: entry.id);
    }
  });
}
