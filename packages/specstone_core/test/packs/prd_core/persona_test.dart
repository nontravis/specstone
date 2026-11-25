import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/pattern_findings.dart';
import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType persona;
  setUpAll(() async {
    persona = prdCoreDocType(await resolvePrdCore(), 'persona');
  });

  test('persona sits at prds/personas/{slug}/PERSONA.md with '
      'its fields, status values, and fourteen sections', () {
    expect(persona.path, 'prds/personas/{slug}/PERSONA.md');
    expect(persona.parent, isNull);
    expectOwnFields(persona, const [
      FieldSpec('role', FieldType.string, required: true),
      FieldSpec(
        'priority',
        FieldType.enumType,
        required: true,
        enumValues: ['primary', 'secondary', 'served'],
      ),
      FieldSpec(
        'basis',
        FieldType.enumType,
        required: true,
        enumValues: ['proto', 'qualitative', 'statistical'],
      ),
      FieldSpec('share', FieldType.string),
      FieldSpec('reviewed', FieldType.date),
    ]);
    expectStatusValues(persona, ['assumed', 'validated', 'retired']);
    expectSections(persona, const [
      SectionSpec('snapshot', 'Snapshot', required: true),
      SectionSpec('jobs', 'Jobs to be done', required: true),
      SectionSpec('behaviors', 'Behaviors & skills', required: true),
      SectionSpec('context_of_use', 'Context of use', required: true),
      SectionSpec('pains', 'Pains', required: true),
      SectionSpec('triggers', 'Triggers', required: true),
      SectionSpec('barriers', 'Barriers', required: true),
      SectionSpec('alternatives', 'Current alternatives', required: true),
      SectionSpec('success', 'Success looks like', required: true),
      SectionSpec('vocabulary', 'Vocabulary', required: true),
      SectionSpec('sources', 'Sources', required: true),
      SectionSpec('decision_criteria', 'Decision criteria'),
      SectionSpec('channels', 'Channels & content habits'),
      SectionSpec('how_we_talk', 'How we talk to'),
    ]);
  });

  test('the description states no number a lint key holds', () {
    final snapshot = sectionOf(persona, 'snapshot');
    expect(snapshot.description, isNot(contains('2 to 4')));
    expect(snapshot.template, isNot(contains('2 to 4')));
    expect(sectionOf(persona, 'jobs').description, isNot(contains('3 to 4')));
    expect(
      sectionOf(persona, 'alternatives').description,
      isNot(contains('at least one')),
    );
  });

  test('alternatives carries its item floor', () {
    final items = sectionOf(persona, 'alternatives').itemCount!;
    expect((items.min, items.max), (1, null));
  });

  test('the description keeps the bound, the research trace, and the '
      'Vocabulary exception in one line', () {
    expect(
      persona.description!.split('\n'),
      contains(
        'Keep a bound in the item it limits; keep the research trace in '
        "`basis:` and the Sources section, out of a narrative section's "
        'prose; a Vocabulary item names its own source.',
      ),
    );
  });

  group('the required lines of a section', () {
    const path = 'prds/personas/buyer/PERSONA.md';

    Future<List<String>> missing(String header, List<String> lines) =>
        missingPatterns({
          'docs/$path':
              '---\nrole: Parent\npriority: primary\nbasis: proto\n---\n\n'
              '# Parents of kids\n\n## Snapshot\n\nA parent.\nOf two kids.\n\n'
              '## $header\n\n${lines.join('\n')}\n',
        }, path);

    const contextLines = {
      'setting_line': '- **Setting:** at home',
      'tools_line': '- **Tools or devices:** a phone',
      'frequency_line': '- **Frequency:** daily',
      'use_line': '- **Use:** chosen',
    };
    const barrierLines = {
      'anxiety_line': '- **Anxiety:** a lost account',
      'habit_line': '- **Habit:** a saved password',
    };
    const talkLines = {
      'voice_guide_line': '- **Voice guide:** [Voice](../../voice.md)',
      'tone_shift_line': '- **Tone shift:** calmer',
    };

    for (final MapEntry(key: header, value: lines) in {
      'Context of use': contextLines,
      'Barriers': barrierLines,
      'How we talk to': talkLines,
    }.entries) {
      test('$header holds all its lines with no finding, and misses each '
          'line by its own id', () async {
        expect(await missing(header, lines.values.toList()), isEmpty);
        for (final MapEntry(key: id) in lines.entries) {
          expect(
            await missing(header, [
              for (final MapEntry(key: other, :value) in lines.entries)
                if (other != id) value,
            ]),
            [id],
            reason: id,
          );
        }
      });
    }

    test(
      'a Voice guide line with no link, one whose link sits in a code span, '
      'and a line held in a fenced block, give the line as missing',
      () async {
        expect(
          await missing('How we talk to', [
            '- **Voice guide:** the brand guide',
            talkLines['tone_shift_line']!,
          ]),
          ['voice_guide_line'],
        );
        expect(
          await missing('How we talk to', [
            '- **Voice guide:** `[Voice](../../voice.md)`',
            talkLines['tone_shift_line']!,
          ]),
          ['voice_guide_line'],
        );
        expect(
          await missing('Barriers', ['```text', ...barrierLines.values, '```']),
          unorderedEquals(barrierLines.keys),
        );
      },
    );
  });

  test('four jobs and one alternative give no item_count finding', () async {
    const path = 'prds/personas/buyer/PERSONA.md';
    Future<List<Map<String, Object?>>> outOfRange(int jobs) async {
      final items = [for (var n = 1; n <= jobs; n++) '- Job $n.'].join('\n');
      final report = await check.checkOf(
        await check.writeCheckProject(
          extra: {
            'docs/$path':
                '---\nrole: Parent\npriority: primary\nbasis: proto\n---\n\n'
                '# Parents of kids\n\n'
                '## Snapshot\n\nA parent.\nOf two kids.\n\n'
                '## Jobs to be done\n\n$items\n\n'
                '## Current alternatives\n\n- Paper notes.\n',
          },
        ),
      );
      return [
        for (final f in report.findings)
          if (f.kind == FindingKind.itemCountOutOfRange && f.path == path)
            f.toJson(),
      ];
    }

    expect(await outOfRange(4), isEmpty);
    expect(await outOfRange(5), [
      allOf(containsPair('limit', 4), containsPair('actual', 5)),
    ]);
  });
}
