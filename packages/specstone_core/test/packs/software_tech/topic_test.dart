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
}
