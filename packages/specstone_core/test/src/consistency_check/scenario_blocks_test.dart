import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

List<BodyLine> _body(String text, {Set<int> fenced = const {}}) => [
  for (final (i, line) in text.split('\n').indexed)
    (text: line, line: i + 1, fenced: fenced.contains(i)),
];

void main() {
  group('scenarioBlocksIn', () {
    test('f04/us04/fr01: keys each block S<N> from its heading to the next '
        '### outside fences, the first of a repeated number winning', () {
      final blocks = scenarioBlocksIn(
        _body(
          'intro\n'
          '### Scenario 1 — one\n'
          '- a\n'
          '```\n'
          '### Scenario 7 — inside a fence\n'
          '```\n'
          '\n'
          '### Scenario 2 — two\n'
          '- b\n'
          '### Scenario 1 — again\n'
          '- c\n'
          '### Notes\n'
          'x',
          fenced: {3, 4, 5},
        ),
      );

      expect(blocks.keys, ['S1', 'S2']);
      expect(
        blocks['S1'],
        '### Scenario 1 — one\n- a\n```\n### Scenario 7 — inside a fence\n```',
      );
      expect(blocks['S2'], '### Scenario 2 — two\n- b');
    });

    test('f04/us04/fr01: Scenario 1 does not match Scenario 10', () {
      final blocks = scenarioBlocksIn(
        _body('### Scenario 10 — ten\n- a\n### Scenario 1 — one\n- b'),
      );

      expect(blocks['S1'], '### Scenario 1 — one\n- b');
      expect(blocks['S10'], '### Scenario 10 — ten\n- a');
    });
  });

  group('headingBlocksOf', () {
    test('f04/us04/fr01: a ### block whose heading does not match closes the '
        'block above and opens none', () {
      final blocks = headingBlocksOf(
        _body('### A — a\n- 1\n### other\n- 2\n### B — b\n- 3'),
        RegExp(r'^### (\S+) — '),
        (match) => match.group(1)!,
      );

      expect([for (final b in blocks) b.key], ['A', 'B']);
      expect(
        [for (final l in blocks.first.lines) l.text],
        ['### A — a', '- 1'],
      );
    });
  });

  group('storyScenarioBlocks', () {
    test(
      'f04/us04/fr01: reads the acceptance_criteria section of a story',
      () async {
        final session = openSession(await writeCheckProject());
        addTearDown(session.close);
        final index = session.index;
        final story = index.docs.singleWhere((d) => d.docPath == loginStory);

        expect(storyScenarioBlocks(index, story), {
          'S1': loginScenario1,
          'S2': loginScenario2,
        });
      },
    );

    test('f04/us04/fr01: a story whose header is spelled in another case '
        'still reads, as CheckContext matches headers', () async {
      final session = openSession(
        await writeCheckProject(
          extra: edit(loginStory, [
            ('## Acceptance Criteria\n', '## Acceptance criteria\n'),
          ]),
        ),
      );
      addTearDown(session.close);
      final index = session.index;
      final story = index.docs.singleWhere((d) => d.docPath == loginStory);

      expect(storyScenarioBlocks(index, story).keys, ['S1', 'S2']);
    });

    test('f04/us04/fr01: a doc with no acceptance_criteria section has no '
        'blocks', () async {
      final session = openSession(await writeCheckProject());
      addTearDown(session.close);
      final index = session.index;
      final feature = index.docs.singleWhere((d) => d.docPath == loginFeature);

      expect(storyScenarioBlocks(index, feature), isEmpty);
    });
  });
}
