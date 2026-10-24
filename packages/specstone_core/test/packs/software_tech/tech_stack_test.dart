import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _says = <String, List<String>>{
  'stack': [
    'Slot',
    'Choice',
    'Version',
    'Why',
    'Language',
    'Architecture',
    'API protocol',
    'Storage',
    'Auth / Identity',
    'Frontend framework',
    'Repo layout',
    'Primary dependencies',
    'Testing',
    'Target platform',
    'pointing at the architecture docs',
  ],
  'constraints': ['license', 'no network'],
  'naming': ['naming', 'five'],
  'avoid': ['What', 'Why'],
};

void main() {
  late MergedDocType techStack;
  setUpAll(() async {
    techStack = prdCoreDocType(await resolveSoftwareTech(), 'tech_stack');
  });

  test('f03/us07/fr01: tech_stack sits at specs/TECH_STACK.md with no parent, '
      'no own field, and four sections', () {
    expect(techStack.path, 'specs/TECH_STACK.md');
    expect(techStack.parent, isNull);
    expectOwnFields(techStack, const []);
    expectSections(techStack, const [
      SectionSpec('stack', 'Stack', required: true),
      SectionSpec('constraints', 'Constraints'),
      SectionSpec('naming', 'Naming', required: true),
      SectionSpec('avoid', 'Avoid'),
    ]);
  });

  test('f03/us07/fr02, f03/us07/fr02/e02, f03/us07/fr02/e03, '
      'f03/us07/fr02/e04, f03/us07/fr02/e08: the tech_stack guide', () {
    expectSpecGuide(
      techStack,
      title: '# Tech stack',
      says: ['secret', 'performance and scale'],
    );
    expectSectionsSay(techStack, _says);
  });

  test('f03/us07/fr03: tech_stack caps 400 lines, bans no word, and cites '
      'its four sources', () {
    expectSpecLint(techStack);
  });
}
