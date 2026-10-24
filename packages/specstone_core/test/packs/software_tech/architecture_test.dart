import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _says = <String, List<String>>{
  'component_diagram': ['Mermaid', 'title', 'technology', 'intent', 'protocol'],
  'components': [
    'Component',
    'Responsibility',
    'Tech',
    'Owns',
    'Code path',
    'diagram box',
  ],
  'interaction': ['one request and one reply', 'error scenario'],
  'deployment': ['tech stack', 'Why'],
  'rollout': [
    'Stage',
    'Scope',
    'Gate',
    'Rollback',
    'expand',
    'migrate',
    'contract',
  ],
  'observability': ['Signal', 'SLI', 'SLO target', 'Alert on', 'log channel'],
  'concerns': [
    'Integration',
    'Errors',
    'Auth',
    'Lifecycle',
    'Events',
    'Rollout',
    'Observability',
    'see <section or sibling doc>',
    'N/A — <reason>',
  ],
  'design_references': ['three', 'rationale'],
};

void main() {
  late MergedDocType architecture;
  setUpAll(() async {
    architecture = prdCoreDocType(await resolveSoftwareTech(), 'architecture');
  });

  test('f03/us07/fr01, f03/us07/fr01/e05, f03/us07/fr01/e06: architecture sits '
      'under specs/f{nn}_{slug}/ with parent feature, a required prefix covers '
      'list, and nine sections', () {
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
    ]);
    expect(
      fieldOf(architecture, 'covers').description,
      allOf(contains('longest prefix'), contains('project root')),
    );
    expectSections(architecture, const [
      SectionSpec('component_diagram', 'Component diagram', required: true),
      SectionSpec('components', 'Components', required: true),
      SectionSpec('interaction', 'Interaction'),
      SectionSpec('deployment', 'Deployment'),
      SectionSpec('rollout', 'Rollout'),
      SectionSpec('observability', 'Observability'),
      SectionSpec('concerns', 'Concerns', required: true),
      SectionSpec('design_references', 'Design references'),
      SectionSpec('open_questions', 'Open questions'),
    ]);
  });

  test('f03/us07/fr02, f03/us07/fr02/e01, f03/us07/fr02/e03, '
      'f03/us07/fr02/e04, f03/us07/fr02/e08: the architecture guide', () {
    expectSpecGuide(
      architecture,
      title: '# <Feature name> architecture',
      says: ['no code samples'],
    );
    expectSectionsSay(architecture, _says);
  });

  test('f03/us07/s2, f03/us07/fr02: the guide gives the title form, then each '
      'section header in section order', () {
    final guide = architecture.renderGuide();
    final title = guide.indexOf('# <Feature name> architecture');
    final at = [
      for (final s in architecture.sections)
        guide.indexOf('## ${s.header}\n\n'),
    ];
    expect(title, greaterThanOrEqualTo(0));
    expect(at, everyElement(greaterThan(title)));
    expect(at, orderedEquals(List.of(at)..sort()));
  });

  test('f03/us07/fr03: architecture caps 400 lines, bans no word, and cites '
      'its four sources', () {
    expectSpecLint(architecture);
  });
}
