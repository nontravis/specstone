import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedDocType techStack;
  setUpAll(() async {
    techStack = prdCoreDocType(await resolveSoftwareTech(), 'tech_stack');
  });

  test('tech_stack sits at specs/TECH_STACK.md with no parent, '
      'the code field, and four sections', () {
    expect(techStack.path, 'specs/TECH_STACK.md');
    expect(techStack.parent, isNull);
    expectOwnFields(techStack, const [
      FieldSpec('code', FieldType.string, list: true),
      FieldSpec('tasks', FieldType.taskRef, list: true),
    ]);
    expectSections(techStack, const [
      SectionSpec('stack', 'Stack', required: true),
      SectionSpec('constraints', 'Constraints'),
      SectionSpec('naming', 'Naming', required: true),
      SectionSpec('avoid', 'Avoid'),
    ]);
  });

  test('tech_stack joins implement and design', () async {
    final set = await resolveSoftwareTech();
    expect(set.lookup('tech_stack')!.bundle, ['implement', 'design']);
  });
}
