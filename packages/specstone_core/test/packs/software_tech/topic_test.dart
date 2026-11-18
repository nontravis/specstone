import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

void main() {
  late MergedDocType topic;
  setUpAll(() async {
    topic = prdCoreDocType(await resolveSoftwareTech(), 'topic');
  });

  test('topic sits at specs/topics/{slug}.md '
      'with no parent, a required prefix covers list, and eight sections', () {
    expect(topic.path, 'specs/topics/{slug}.md');
    expect(topic.parent, isNull);
    expectOwnFields(topic, const [
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
    expectSections(topic, const [
      SectionSpec('purpose', 'Purpose', required: true),
      SectionSpec('scope', 'Scope', required: true),
      SectionSpec('used_by', 'Used by', required: true),
      SectionSpec('rules', 'Rules', prefixId: 'RULE-'),
      SectionSpec('interface', 'Interface'),
      SectionSpec('model', 'Model'),
      SectionSpec('examples', 'Examples'),
      SectionSpec('open_questions', 'Open questions'),
    ]);
  });

  test('the description states no number a lint key holds', () {
    final purpose = sectionOf(topic, 'purpose');
    expect(purpose.description, isNot(contains('one paragraph')));
    expect(
      sectionOf(topic, 'rules').description,
      isNot(contains('one sentence')),
    );
  });

  test('purpose carries its item cap', () {
    final items = sectionOf(topic, 'purpose').itemCount!;
    expect((items.min, items.max), (null, 1));
  });

  test('the topic description says a rule set writes Rules, a component '
      'writes Interface, and both writes both', () {
    expect(
      topic.description,
      contains(
        'A rule set writes Rules, a component writes Interface, and a topic '
        'that is both writes both; no field names the kind.',
      ),
    );
  });
}
