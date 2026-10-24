import 'package:specstone_core/src/templates/doc_type_layer.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';
import '../../helpers/software_tech.dart';

const _says = <String, List<String>>{
  'scope': ['covers'],
  'used_by': ['Feature', 'What it uses'],
  'rules': ['one sentence', 'diff', 'timeout 10 s'],
  'interface': ['path:Symbol', 'signature'],
  'model': ['data shape'],
  'examples': ['example'],
};

void main() {
  late MergedDocType topic;
  setUpAll(() async {
    topic = prdCoreDocType(await resolveSoftwareTech(), 'topic');
  });

  test('f03/us07/fr01, f03/us07/fr01/e06: topic sits at specs/topics/{slug}.md '
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
    ]);
    expect(
      fieldOf(topic, 'covers').description,
      allOf(contains('longest prefix'), contains('project root')),
    );
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

  test('f03/us07/fr02, f03/us07/fr02/e02, f03/us07/fr02/e03, '
      'f03/us07/fr02/e04, f03/us07/fr02/e05, f03/us07/fr02/e06: the topic '
      'guide', () {
    expectSpecGuide(
      topic,
      title: '# <Topic name>',
      says: [
        'rule set writes Rules',
        'component writes Interface',
        'both writes both',
      ],
    );
    expectSectionsSay(topic, _says);
  });

  test('f03/us07/fr03, f03/us07/fr03/e01: topic caps 400 lines, bans no '
      'word, and cites its four sources', () {
    expectSpecLint(topic);
  });
}
