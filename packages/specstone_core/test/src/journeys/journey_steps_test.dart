import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:test/test.dart';

JourneySteps _read(List<String> lines, {Set<String> blockKinds = const {}}) =>
    readJourneySteps(lines.join('\n'), blockKinds: blockKinds);

List<String> _numbers(JourneySteps steps) => [
  for (final step in steps.steps) step.number,
];

List<String> _pathNumbers(JourneySteps steps, List<int> path) => [
  for (final i in path) steps.steps[i].number,
];

void main() {
  group('constants', () {
    test('f10/us01/fr02: the journey ids and generated kinds', () {
      expect(journeyTypeId, 'journey');
      expect(flowSectionId, 'flow');
      expect(stepsSectionId, 'steps');
      expect(journeyFlowKind, 'journey_flow');
      expect(scenarioCopyKind, 'scenario_copy');
    });
  });

  group('paths', () {
    test('f10/us01/fr02/e01: steps 1 to 5 and 3x after 2 give the paths '
        '5 and 3x', () {
      final steps = _read([
        '### 1. Start',
        '### 2. Next',
        '### 3. Third',
        '### 4. Fourth',
        '### 5. Fifth',
        '### 3x. Branch',
        'step: a/b S1',
        'after: 2',
      ]);

      expect(steps.paths, [
        [0, 1, 2, 3, 4],
        [0, 1, 5],
      ]);
      expect(steps.edges.last, (1, 5));
      expect(steps.edges, [(0, 1), (1, 2), (2, 3), (3, 4), (1, 5)]);
      expect(steps.offPathIndexes, isEmpty);
    });

    test('f10/us01/fr02/e02: 3x written before 4 makes 4 follow 3x', () {
      final steps = _read([
        '### 1. One',
        '### 2. Two',
        '### 3. Three',
        '### 3x. Branch',
        'step: a/b S1',
        'after: 2',
        '### 4. Four',
        '### 5. Five',
      ]);

      expect(steps.followedIndex(4), 3);
      expect(steps.paths.map((p) => _pathNumbers(steps, p).last), ['3', '5']);
    });

    test('f10/us01/fr02/e03: an after: naming the step directly above is the '
        'same as none', () {
      final withAfter = _read([
        '### 1. A',
        '### 2. B',
        'step: a/b S1',
        'after: 1',
      ]);
      final without = _read(['### 1. A', '### 2. B']);

      expect(withAfter.followedIndex(1), 0);
      expect(withAfter.paths, without.paths);
      expect(withAfter.edges, without.edges);
      expect(withAfter.unresolvedAfterIndexes, isEmpty);
    });

    test('f10/us01/fr02/e05: an after: naming no step, or a step below, is '
        'unresolved and its step is on no path', () {
      final none = _read(['### 1. A', '### 2. B', 'step: a/b S1', 'after: 7']);
      expect(none.unresolvedAfterIndexes, [1]);
      expect(none.offPathIndexes, [1]);
      expect(none.paths, [
        [0],
      ]);
      expect(none.followedIndex(1), isNull);

      final below = _read([
        '### 1. A',
        '### 3x. Branch',
        'step: a/b S1',
        'after: 4',
        '### 4. D',
      ]);
      expect(below.unresolvedAfterIndexes, [1]);
      expect(below.offPathIndexes, [1, 2]);
      expect(below.paths, [
        [0],
      ]);
    });

    test('f10/us01/fr02/e05: a step below an off-path step with no after: is '
        'off path too', () {
      final steps = _read([
        '### 1. A',
        '### 2. B',
        'step: a/b S1',
        'after: 9',
        '### 3. C',
      ]);

      expect(steps.offPathIndexes, [1, 2]);
      expect(steps.unresolvedAfterIndexes, [1]);
      expect(steps.edges, isEmpty);
    });

    test('f10/us01/fr02/e08: a second ### 3. heading is a duplicate, and an '
        'after: 3 below it follows the first step 3', () {
      final steps = _read([
        '### 1. A',
        '### 3. First three',
        '### 3. Second three',
        '### 4. Four',
        'step: a/b S1',
        'after: 3',
      ]);

      expect(steps.duplicateIndexes, [2]);
      expect(steps.followedIndex(3), 1);
      expect(steps.unresolvedAfterIndexes, isEmpty);
    });

    test('f10/us01/fr02/e05: an after: on the first step names no step above '
        'it', () {
      final steps = _read(['### 1. A', 'step: a/b S1', 'after: 1', '### 2. B']);

      expect(steps.unresolvedAfterIndexes, [0]);
      expect(steps.paths, [
        [0, 1],
      ]);
    });

    test('f10/us01/fr02: one step gives one path and no step gives none', () {
      final one = _read(['### 1. Only']);
      expect(one.paths, [
        [0],
      ]);
      expect(one.followedIndex(0), isNull);
      expect(one.edges, isEmpty);

      final none = _read(['just text', '']);
      expect(none.steps, isEmpty);
      expect(none.paths, isEmpty);
      expect(none.offPathIndexes, isEmpty);
    });

    test('f10/us01/fr02: text above the first heading is no step', () {
      final steps = _read(['step: a/b S1', 'after: 1', '### 1. A']);

      expect(_numbers(steps), ['1']);
      expect(steps.steps.single.stepValue, isNull);
      expect(steps.steps.single.headingIndex, 2);
    });
  });

  group('step lines', () {
    test('f10/us01/fr02/e04: step: setup_migration/set_up_new_project S1 reads '
        'as that story and Scenario 1', () {
      final step = _read([
        '### 1. Set up',
        'step: setup_migration/set_up_new_project S1',
      ]).steps.single;

      expect(step.target!.identity, 'setup_migration/set_up_new_project');
      expect(step.target!.scenario, 1);
      expect(step.target!.label, 'setup_migration/set_up_new_project#S1');
      expect(step.target!.scenarioLabel, 'S1');
      expect(step.number, '1');
      expect(step.heading, 'Set up');
      expect(step.headingIndex, 0);
      expect(step.stepIndex, 1);
    });

    test('f10/us01/fr02/e06: a value that does not read as <story identity> '
        'S<N> gives no target', () {
      expect(readStepTarget('login'), isNull);
      expect(readStepTarget('login/email_login'), isNull);
      expect(readStepTarget('Login/email S1'), isNull);
      expect(readStepTarget('login/ S1'), isNull);
      expect(readStepTarget('login S'), isNull);
      expect(readStepTarget('login S99999999999999999999'), isNull);
      expect(readStepTarget('login/email S2')!.label, 'login/email#S2');
    });

    test(
      'f10/us01/fr02/e07: free text in a step is kept and read by nothing',
      () {
        final steps = _read([
          '### 1. A',
          'Some prose about the step.',
          '- a bullet',
          'step: a/b S1',
          'more prose with step: inside',
          'after: 1',
          '### 2. B',
          'step: a/b S2',
          'after: 1',
        ]);

        expect(steps.steps[0].stepIndex, 3);
        expect(steps.steps[0].afterIndex, 5);
        expect(steps.steps[1].afterIndex, 8);
        expect(steps.paths, [
          [0, 1],
        ]);
      },
    );

    test('f10/us01/fr02: a heading with no step: line has no stepValue and no '
        'target', () {
      final step = _read(['### 1. A', 'after: 1']).steps.single;

      expect(step.stepValue, isNull);
      expect(step.stepIndex, isNull);
      expect(step.target, isNull);
      expect(step.afterValue, isNull);
      expect(step.anchorIndex, 0);
    });

    test('f10/us01/fr02: anchorIndex is after, then step, then heading', () {
      final steps = _read(['### 1. A', 'step: a/b S1', 'after: 1']).steps;
      expect(steps.single.anchorIndex, 1 + 1);

      final stepOnly = _read(['### 1. A', 'step: a/b S1']).steps.single;
      expect(stepOnly.anchorIndex, 1);
    });

    test('f10/us01/fr02: two spaces before S1 do not read, a trailing space '
        'does', () {
      final two = _read(['### 1. A', 'step: a/b  S1']).steps.single;
      expect(two.target, isNull);
      expect(two.stepValue, 'a/b  S1');

      final trailing = _read(['### 1. A', 'step: a/b S1 ']).steps.single;
      expect(trailing.stepValue, 'a/b S1');
      expect(trailing.target!.label, 'a/b#S1');
    });

    test('f10/us01/fr02: the after: below the step: line is the branch', () {
      final steps = _read(['### 1. A', 'after: 9', 'step: a/b S1', 'after: 1'])
          .steps;

      expect(steps.single.afterIndex, 3);
      expect(steps.single.afterValue, '1');
    });
  });

  group('skipped lines', () {
    test('f10/us01/fr02: a ### 1. line in a code fence is no step', () {
      final steps = _read(['### 1. A', '```', '### 2. B', '```', '### 3. C']);

      expect(_numbers(steps), ['1', '3']);
    });

    test('f10/us01/fr02: a step: line in a code fence is not read', () {
      final steps = _read(['### 1. A', '```', 'step: a/b S1', '```']);

      expect(steps.steps.single.stepValue, isNull);
    });

    test('f10/us01/fr02: the lines of a scenario_copy block are skipped', () {
      final lines = [
        '### 1. A',
        'step: a/b S1',
        '<!-- specstone:generated scenario_copy (do not edit) -->',
        '### 9. Inside',
        'step: x/y S2',
        'after: 1',
        '<!-- specstone:generated end -->',
        '### 2. B',
      ];

      final skipped = _read(lines, blockKinds: {scenarioCopyKind});
      expect(_numbers(skipped), ['1', '2']);
      expect(skipped.steps.first.stepValue, 'a/b S1');
      expect(skipped.steps.first.afterValue, isNull);

      final read = _read(lines);
      expect(_numbers(read), ['1', '9', '2']);
    });

    test('f10/us01/fr02: a steps body led by --- skips a pasted block between '
        'two --- lines', () {
      final lines = [
        '---',
        '### 1. A',
        'step: a/b S1',
        '<!-- specstone:generated scenario_copy (do not edit) -->',
        '### 9. Inside',
        'step: x/y S2',
        'after: 1',
        '<!-- specstone:generated end -->',
        '---',
        '### 2. B',
      ];

      final steps = _read(lines, blockKinds: {scenarioCopyKind});

      expect(_numbers(steps), ['1', '2']);
      expect(steps.steps.first.afterValue, isNull);
    });
  });
}
