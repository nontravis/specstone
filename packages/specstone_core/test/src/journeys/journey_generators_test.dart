import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/journeys/journey_generators.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/generator_kinds.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/index_fixture.dart';

const _journeyType = '''
id: journey
description: A walk through the stories.
path: prds/journeys/{slug}/JOURNEY.md
generators: [journey_flow, scenario_copy]
sections:
  - id: flow
    header: Flow
  - id: steps
    header: Steps
''';

const _journeyPath = 'prds/journeys/onboarding/JOURNEY.md';
const _story = 'login/email_login';

String _journeyText(List<String> stepLines) =>
    '# Onboarding\n\n## Flow\n\n## Steps\n${stepLines.join('\n')}\n';

typedef _Fixture = ({DocIndex index, MergedDocType type, Doc doc});

Future<_Fixture> _open(
  List<String> stepLines, {
  Map<String, String> extra = const {},
}) async {
  final session = openSession(
    await writeCheckProject(
      extra: {
        '.specstone/templates/journey.yaml': _journeyType,
        'docs/$_journeyPath': _journeyText(stepLines),
        ...extra,
      },
    ),
  );
  addTearDown(session.close);
  final index = session.index;
  return (
    index: index,
    type: index.set.lookup(journeyTypeId)!,
    doc: Doc.parse(_journeyText(stepLines)),
  );
}

List<GeneratedBlock> _flow(_Fixture f) =>
    journeyFlowBlocks(f.doc, f.type, f.index);

List<GeneratedBlock> _copy(_Fixture f) =>
    scenarioCopyBlocks(f.doc, f.type, f.index);

int _below(GeneratedBlock block) => (block.place as BelowBodyLine).index;

void main() {
  group('journey_flow', () {
    test('f10/us01/fr03/e01: steps 1 to 5 and 3x after 2 draw six nodes and '
        'five edges', () async {
      final f = await _open([
        '### 1. Start',
        '### 2. Next',
        '### 3. Third',
        '### 4. Fourth',
        '### 5. Fifth',
        '### 3x. Branch',
        'step: $_story S1',
        'after: 2',
      ]);

      final blocks = _flow(f);

      expect(blocks, hasLength(1));
      expect(blocks.single.kind, journeyFlowKind);
      expect(blocks.single.sectionId, flowSectionId);
      expect(blocks.single.place, isA<SectionTop>());
      expect(
        blocks.single.text,
        '```mermaid\n'
        'flowchart TD\n'
        '  s1["1. Start"]\n'
        '  s2["2. Next"]\n'
        '  s3["3. Third"]\n'
        '  s4["4. Fourth"]\n'
        '  s5["5. Fifth"]\n'
        '  s3x["3x. Branch"]\n'
        '  s1 --> s2\n'
        '  s2 --> s3\n'
        '  s3 --> s4\n'
        '  s4 --> s5\n'
        '  s2 --> s3x\n'
        '```',
      );
    });

    test('f10/us01/fr03/e02: a " in a heading is written #quot;', () async {
      final f = await _open(['### 1. Say "hi"']);

      expect(_flow(f).single.text, contains('  s1["1. Say #quot;hi#quot;"]'));
    });

    test(
      'f10/us01/fr03/e03: a journey with no step draws flowchart TD alone',
      () async {
        final f = await _open(['Nothing yet.']);

        expect(_flow(f).single.text, '```mermaid\nflowchart TD\n```');
      },
    );

    test(
      'f10/us01/fr03/e04: a step naming no scenario is still drawn',
      () async {
        final f = await _open([
          '### 1. Start',
          'step: $_story S9',
          '### 2. Next',
          'step: no/such_story S1',
          'after: 1',
        ]);

        expect(
          _flow(f).single.text,
          '```mermaid\nflowchart TD\n  s1["1. Start"]\n  s2["2. Next"]\n'
          '  s1 --> s2\n```',
        );
      },
    );

    test('f10/us01/fr03/e05: a step whose after: names no step above has no '
        'incoming edge', () async {
      final f = await _open([
        '### 1. Start',
        '### 2. Next',
        'step: $_story S1',
        'after: 7',
      ]);

      final text = _flow(f).single.text;

      expect(text, contains('  s2["2. Next"]'));
      expect(text, isNot(contains('-->')));
    });
  });

  group('scenario_copy', () {
    test(
      'f10/us01/fr04/e01: a resolving step gets its scenario lines after '
      'the heading, below its step: line; with after: below that line',
      () async {
        final f = await _open([
          '### 1. Start',
          'step: $_story S1',
          '### 2. Next',
          'step: $_story S2',
          'after: 1',
        ]);

        final blocks = _copy(f);

        expect(blocks, hasLength(2));
        for (final block in blocks) {
          expect(block.kind, scenarioCopyKind);
          expect(block.sectionId, stepsSectionId);
        }
        expect(_below(blocks[0]), 1);
        expect(
          blocks[0].text,
          '- **Given** an account\n- **When** the Agent signs in\n'
          '- **Then** the Agent sees the home page',
        );
        expect(_below(blocks[1]), 4);
        expect(blocks[1].text, startsWith('- **Given** an account\n'));
      },
    );

    test('f10/us01/fr04/e03: a Then line that wraps onto a second line is '
        'copied whole', () async {
      final f = await _open(
        ['### 1. Start', 'step: $_story S1'],
        extra: edit(loginStory, [
          (
            '- **Then** the Agent sees the home page',
            '- **Then** the Agent sees the home page\n  and a welcome note',
          ),
        ]),
      );

      expect(
        _copy(f).single.text,
        endsWith('the home page\n  and a welcome note'),
      );
    });

    test(
      'f10/us01/fr04/e05: S9 of a two-scenario story gets no block',
      () async {
        final f = await _open(['### 1. Start', 'step: $_story S9']);

        expect(_copy(f), isEmpty);
      },
    );

    test(
      'f10/us01/fr04/e06: two steps naming one scenario get a block each',
      () async {
        final f = await _open([
          '### 1. Start',
          'step: $_story S1',
          '### 2. Again',
          'step: $_story S1',
        ]);

        final blocks = _copy(f);

        expect(blocks, hasLength(2));
        expect(blocks[0].text, blocks[1].text);
        expect(_below(blocks[0]), 1);
        expect(_below(blocks[1]), 3);
      },
    );

    test('f10/us01/fr04: S1 copies Scenario 1, not Scenario 10', () async {
      final f = await _open(
        ['### 1. Start', 'step: $_story S1'],
        extra: edit(loginStory, [
          (
            '## Acceptance Criteria\n',
            '## Acceptance Criteria\n\n### Scenario 10 — [happy] Ten\n- ten\n',
          ),
        ]),
      );

      final block = scenarioBlockOf(f.index, const StepTarget(_story, 1));

      expect(block, startsWith('### Scenario 1 — [happy] Sign in'));
      expect(_copy(f).single.text, isNot(contains('ten')));
    });

    test('f10/us01/fr04: a step naming no story gets no block', () async {
      final f = await _open(['### 1. Start', 'step: no/such_story S1']);

      expect(_copy(f), isEmpty);
    });
  });

  group('step scenarios', () {
    test('f10/us01/fr04: scenarioCopyOf drops the heading line', () {
      expect(scenarioCopyOf('### Scenario 1 — x\n- a\n- b'), '- a\n- b');
      expect(scenarioCopyOf('### Scenario 1 — x'), '');
    });

    test(
      'f10/us01/fr03: stepsOfIndexed reads the steps of an indexed journey',
      () async {
        final f = await _open(['### 1. Start', 'step: $_story S1']);
        final journey = f.index.docs.singleWhere(
          (d) => d.docPath == _journeyPath,
        );

        final steps = stepsOfIndexed(f.index, journey);

        expect([for (final s in steps.steps) s.number], ['1']);
        expect(steps.steps.single.target?.label, '$_story#S1');
      },
    );

    test(
      'f10/us01/fr03: storyNamed finds a story by name and no other doc',
      () async {
        final f = await _open(['### 1. Start']);

        expect(storyNamed(f.index, _story)?.docPath, loginStory);
        expect(storyNamed(f.index, 'no/such_story'), isNull);
        expect(storyNamed(f.index, 'onboarding'), isNull);
      },
    );
  });

  group('journeyGenerators', () {
    test('f05/us03/fr01: registers exactly the kinds the template loader '
        'accepts', () {
      expect(journeyGenerators().kinds, shippedGeneratorKinds);
    });
  });
}
