import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/pattern_findings.dart';
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

  group('the interface and used-by lines', () {
    const topicPath = 'specs/topics/doc_model.md';

    Map<String, String> topicDoc(String section, String body) => {
      'docs/$topicPath':
          '---\ndraft: true\n---\n\n# Doc model\n\n## $section\n\n$body',
    };

    test('a ( after the pointer is signature_copy, and a ( inside the span, '
        'inside a later span, a fenced line, and a blank line pass', () async {
      const copied = '- `lib/a.dart:parse` (String) → Doc';
      const glued = '- `lib/a.dart:parse`(String)';
      expect(
        await bannedLines(
          topicDoc(
            'Interface',
            '- `lib/a.dart:parse(String)`\n'
                '- `lib/a.dart:parse` — see `lib/b.dart:read(Doc)`\n\n'
                '```text\n- `lib/a.dart:parse` (String)\n```\n',
          ),
          topicPath,
          'signature_copy',
        ),
        isEmpty,
      );
      expect(
        await bannedLines(
          topicDoc('Interface', '- `lib/a.dart:parse`\n$copied\n$glued\n'),
          topicPath,
          'signature_copy',
        ),
        [copied, glued],
      );
      expect(sectionOf(topic, 'interface').bannedPatterns!.map((p) => p.id), [
        'interface_pointer',
        'signature_copy',
      ]);
    });

    test('a Used by table of one row is item_count_out_of_range, and two rows '
        'pass', () async {
      const header = '| Feature | What it uses |\n|---|---|\n';
      Future<List<String>> counted(String rows) async {
        final report = await checkOf(
          await writeCheckProject(extra: topicDoc('Used by', '$header$rows')),
        );
        return spots(report, FindingKind.itemCountOutOfRange);
      }

      expect(await counted('| login | the rules |\n'), [
        endsWith(': item_count_out_of_range'),
      ]);
      expect(
        await counted('| login | the rules |\n| search | the rules |\n'),
        isEmpty,
      );
      expect(sectionOf(topic, 'used_by').itemCount!.min, 2);
    });
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
