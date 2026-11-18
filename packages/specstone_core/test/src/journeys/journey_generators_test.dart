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

const _journeyPath = 'prds/journeys/onboarding/JOURNEY.md';
const _story = 'login/email_login';

/// The login story, from the journey's folder.
const _ownStory = '../../features/f01_login/us01_email_login/USER_STORY.md';

/// The sign-out story's acceptance criteria, from the journey's folder.
const _signOut =
    '../../features/f01_login/us02_sign_out/USER_STORY.md#acceptance-criteria';

String _journeyText(List<String> stepLines) =>
    '# Onboarding\n\n## Flow\n\n## Steps\n${stepLines.join('\n')}\n';

typedef _Fixture = ({DocIndex index, MergedDocType type, Doc doc});

Future<_Fixture> _open(
  List<String> stepLines, {
  Map<String, String> extra = const {},
}) async {
  final session = openSession(
    await writeCheckProject(
      extra: {'docs/$_journeyPath': _journeyText(stepLines), ...extra},
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
    journeyFlowBlocks(f.doc, _journeyPath, f.type, f.index);

List<GeneratedBlock> _copy(_Fixture f) =>
    scenarioCopyBlocks(f.doc, _journeyPath, f.type, f.index);

/// The login story with [tail] after the Then line of its Scenario 1.
Map<String, String> _thenHolds(String tail) => edit(loginStory, [
  (
    '- **Then** the Agent sees the home page',
    '- **Then** the Agent sees the home page $tail',
  ),
]);

/// The copy of Scenario 1 for a journey whose step names it, the story's Then
/// line ending in [tail].
Future<String> _copiedThen(String tail) async {
  final f = await _open([
    '### 1. Start',
    'step: $_story S1',
  ], extra: _thenHolds(tail));
  return _copy(f).single.text.split('\n').last;
}

int _below(GeneratedBlock block) => (block.place as BelowBodyLine).index;

void main() {
  group('journey_flow', () {
    test('steps 1 to 5 and 3x after 2 draw six nodes and '
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

    test('a " in a heading is written #quot;', () async {
      final f = await _open(['### 1. Say "hi"']);

      expect(_flow(f).single.text, contains('  s1["1. Say #quot;hi#quot;"]'));
    });

    test('a journey with no step draws flowchart TD alone', () async {
      final f = await _open(['Nothing yet.']);

      expect(_flow(f).single.text, '```mermaid\nflowchart TD\n```');
    });

    test('a step naming no scenario is still drawn', () async {
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
    });

    test('a step whose after: names no step above has no '
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

    test('a step that follows an unresolved-after step '
        'gets its edge', () async {
      final f = await _open([
        '### 1. Start',
        '### 2. Next',
        'step: $_story S1',
        'after: 7',
        '### 3. Last',
      ]);

      final text = _flow(f).single.text;

      expect(text, contains('  s2 --> s3'));
      expect(text, isNot(contains('s1 --> s2')));
    });
  });

  group('scenario_copy', () {
    test(
      'a resolving step gets its scenario lines after '
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

    test('a Then line that wraps onto a second line is '
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

    test('S9 of a two-scenario story gets no block', () async {
      final f = await _open(['### 1. Start', 'step: $_story S9']);

      expect(_copy(f), isEmpty);
    });

    test('two steps naming one scenario get a block each', () async {
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
    });

    test('S1 copies Scenario 1, not Scenario 10', () async {
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

    test('a step naming no story gets no block', () async {
      final f = await _open(['### 1. Start', 'step: no/such_story S1']);

      expect(_copy(f), isEmpty);
    });

    test('a relative link takes the path from the '
        "journey's folder, its text and fragment kept", () async {
      expect(
        await _copiedThen(
          '[sign out](../us02_sign_out/USER_STORY.md#acceptance-criteria)',
        ),
        '- **Then** the Agent sees the home page [sign out]($_signOut)',
      );
    });

    test("a fragment-only link takes the story's path "
        'before the fragment', () async {
      expect(
        await _copiedThen('[rules](#rules)'),
        '- **Then** the Agent sees the home page [rules]($_ownStory#rules)',
      );
    });

    test('a link that leaves the docs root still reaches '
        'its file, and a definition moves too', () async {
      final f = await _open(
        ['### 1. Start', 'step: $_story S1'],
        extra: _thenHolds(
          '[code](../../../../../lib/a.dart) and [spec][s]\n\n'
          '[s]: <../FEATURE.md>',
        ),
      );

      final text = _copy(f).single.text;

      expect(text, contains('[code](../../../../lib/a.dart)'));
      expect(text, endsWith('[s]: <../../features/f01_login/FEATURE.md>'));
    });

    test('a folder link and a docs-root link reach from '
        "the journey's folder what they reach from the story", () async {
      expect(
        await _copiedThen('[out](../us02_sign_out/) [docs](../../../../)'),
        '- **Then** the Agent sees the home page '
        '[out](../../features/f01_login/us02_sign_out/) [docs](../../../)',
      );
    });

    test('a web address, another scheme, and a rooted '
        'path are copied as written', () async {
      const tail =
          '[web](https://example.com/a.md#x) [mail](mailto:a@example.com) '
          '[root](/docs/a.md)';

      expect(
        await _copiedThen(tail),
        '- **Then** the Agent sees the home page $tail',
      );
    });

    test('a path in a code span is copied as '
        'written', () async {
      const tail =
          '`../us02_sign_out/USER_STORY.md` and `[x](../us02_sign_out/a.md)`';

      expect(
        await _copiedThen(tail),
        '- **Then** the Agent sees the home page $tail',
      );
    });
  });

  group('step scenarios', () {
    test('scenarioCopyOf drops the heading line', () {
      expect(scenarioCopyOf('### Scenario 1 — x\n- a\n- b'), '- a\n- b');
      expect(scenarioCopyOf('### Scenario 1 — x'), '');
    });

    test('a table row right under the heading is copied in the layout', () {
      expect(
        scenarioCopyOf(
          '### Scenario 1 — x\n| a   | b  |\n|-----|----|\n| 1 | 2 |',
        ),
        '| a | b |\n|---|---|\n| 1 | 2 |',
      );
    });

    test('blank lines under the heading are left out', () {
      expect(scenarioCopyOf('### Scenario 1 — x\n\n\n- a\n- b'), '- a\n- b');
    });

    test('a padded table is copied in the format layout', () {
      const block =
          '### Scenario 1 — x\n\n'
          '| a   | b  |\n'
          '|-----|----|\n'
          '| one | 2  |  \n'
          '- c  ';

      expect(scenarioCopyOf(block), '| a | b |\n|---|---|\n| one | 2 |\n- c');
      expect(scenarioCopyOf(block), isNot(contains('  \n')));
      expect(scenarioCopyOf(block), isNot(endsWith(' ')));
    });

    test('stepsOfIndexed reads the steps of an indexed journey', () async {
      final f = await _open(['### 1. Start', 'step: $_story S1']);
      final journey = f.index.docs.singleWhere(
        (d) => d.docPath == _journeyPath,
      );

      final steps = stepsOfIndexed(f.index, journey);

      expect([for (final s in steps.steps) s.number], ['1']);
      expect(steps.steps.single.target?.label, '$_story#S1');
    });

    test('storyNamed finds a story by name and no other doc', () async {
      final f = await _open(['### 1. Start']);

      expect(storyNamed(f.index, _story)?.docPath, loginStory);
      expect(storyNamed(f.index, 'no/such_story'), isNull);
      expect(storyNamed(f.index, 'onboarding'), isNull);
    });
  });

  group('journeyGenerators', () {
    test('registers the journey kinds', () {
      expect(journeyGenerators().kinds, {'journey_flow', 'scenario_copy'});
    });

    test('the kinds the template loader accepts are the journey kinds and '
        'feature_catalog', () {
      expect(shippedGeneratorKinds, {
        'journey_flow',
        'scenario_copy',
        'feature_catalog',
      });
    });
  });
}
