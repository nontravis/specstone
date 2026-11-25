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

  test('the tech_stack doc type holds its fixed title and its description '
      'states none', () {
    expect(techStack.title, 'Tech stack');
    expect(techStack.description, isNot(contains('Title it')));
  });

  test('the description states no number a lint key holds', () {
    expect(
      sectionOf(techStack, 'naming').description,
      isNot(contains('Rows may exceed five')),
    );
  });

  test('stack caps its Why column at one sentence', () {
    final caps = sectionOf(techStack, 'stack').maxSentences!;
    expect([for (final c in caps) (c.count, c.column)], [(1, 'Why')]);
  });

  test('tech_stack joins implement and design', () async {
    final set = await resolveSoftwareTech();
    expect(set.lookup('tech_stack')!.bundle, ['implement', 'design']);
  });

  test('stack links a decision doc when a Why needs more than one clause', () {
    final text = sectionOf(techStack, 'stack').description!;

    expect(
      text,
      contains(
        'keep the Why to one clause, linking a `decision` doc when it needs '
        'more',
      ),
    );
    expect(text.split('\n'), hasLength(5));
  });
}
