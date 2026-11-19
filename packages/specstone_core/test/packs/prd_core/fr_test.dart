import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/prd_core.dart';

void main() {
  late MergedDocType fr;
  setUpAll(() async {
    fr = prdCoreDocType(await resolvePrdCore(), 'fr');
  });

  test('fr sits under its story folder with parent user_story, '
      'its fields, and seven sections', () {
    expect(
      fr.path,
      'prds/features/f{nn}_{slug}/us{nn}_{slug}/fr{nn}_{slug}.md',
    );
    expect(fr.parent, 'user_story');
    expectOwnFields(fr, const [
      FieldSpec('traced_from', FieldType.string, list: true, required: true),
      FieldSpec(
        'verify_method',
        FieldType.enumType,
        required: true,
        enumValues: ['test', 'analysis', 'inspection', 'demonstration'],
      ),
      FieldSpec('owner', FieldType.string),
      FieldSpec('confirmed', FieldType.string, list: true),
    ]);
    expectStatusValues(fr, ['planned', 'implemented', 'deprecated']);
    expectSections(fr, const [
      SectionSpec('statement', 'Statement', required: true),
      SectionSpec('input_output', 'Input / Output'),
      SectionSpec('behavior', 'Behavior'),
      SectionSpec('edge_cases', 'Edge cases', prefixId: 'E', required: true),
      SectionSpec('rationale', 'Rationale', required: true),
      SectionSpec('verification', 'Verification', required: true),
      SectionSpec('tbr', 'TBR'),
    ]);
  });

  test('fr lints the 29 NASA words on Statement only, and the handbook', () {
    expectNasaLint(
      fr,
      sections: ['statement'],
      otherWords: {
        'tbr': ['TBD'],
      },
    );
  });

  test('no starter template holds a listed word', () {
    expectTemplatesFreeOfListedWords(fr);
  });

  test('the description states no number a lint key holds', () {
    expect(fr.description, isNot(contains('Statement as one sentence')));
  });

  test('fr marks statement summary', () {
    expect(
      [
        for (final s in fr.sections)
          if (s.summary == true) s.id,
      ],
      ['statement'],
    );
  });

  test('the description states the item shape, the edge case lines, and the'
      ' split line', () {
    final description = fr.description!;

    expect(
      description,
      contains(
        'Write the Statement with one "shall" and its quantified value, such '
        'as `within 2 s`.',
      ),
    );
    expect(description, contains('leave mechanics to the spec docs'));
    expect(
      description,
      contains(
        'Keep the trace in `traced_from` alone, never in the Statement or an '
        'edge case.',
      ),
    );
    final positions = [
      for (final line in [..._edgeCaseLines, _splitLine])
        description.indexOf(line),
    ];
    expect(positions, everyElement(isNonNegative));
    expect(positions, orderedEquals([...positions]..sort()));
    for (final fragment in _droppedFragments) {
      expect(description, isNot(contains(fragment)), reason: fragment);
    }
    expect(_splitLine, isNot(matches(RegExp(r'\d'))));
  });

  test('the verification shows the short Pass criteria first and names no'
      ' test file', () {
    final verification = sectionOf(fr, 'verification');
    final template = verification.template!;
    final short = template.indexOf(
      '- **Pass criteria:** each edge case holds.\n- **Level:** <level>',
    );
    final long = template.indexOf(
      '- **Pass criteria:** each edge case holds.\n'
      '  - <a condition no edge case states>\n'
      '- **Level:** <level>',
    );

    expect(short, isZero);
    expect(long, greaterThan(short));
    expect(
      verification.description,
      contains(
        'Write `- **Pass criteria:** each edge case holds.`, with one nested '
        'bullet per condition no edge case states.',
      ),
    );
    expect(verification.description, contains('Name no test file here'));
    expect(
      template,
      isNot(matches(RegExp(r'_test\.|\.test\.|\.spec\.|\btests?/'))),
    );
  });

  test('the edge cases template shows the several-trigger shape and the'
      ' description names it', () {
    final edgeCases = sectionOf(fr, 'edge_cases');

    expect(
      edgeCases.template,
      contains(
        '2. E02 — <lead> → <response>\n'
        '   <more response, one sentence per line, with no blank line>\n'
        '   - <trigger>\n'
        '   - <trigger>',
      ),
    );
    expect(
      edgeCases.description,
      contains(
        'For several triggers, keep the `→` in the lead and join the '
        'response as indented lines, with no blank line.',
      ),
    );
    expect(
      edgeCases.description,
      contains('List the triggers as nested items.'),
    );
    for (final word in ['detect', 'report', 'handle', 'recover']) {
      expect(edgeCases.description, isNot(contains(word)), reason: word);
    }
    expect(
      '\n'.allMatches(edgeCases.description!).length + 1,
      lessThanOrEqualTo(_maxSectionDescriptionLines),
    );
  });
}

/// The edge case lines of the description, in the order it states them.
const _edgeCaseLines = <String>[
  _admissionLine,
  _responseLine,
  _leaveOutLine,
  _knownLimitsLine,
  _errorCodeLine,
  _messageLine,
];

const _admissionLine =
    'Write an edge case only for an outcome the Statement, an Input/Output '
    'row, and a table leave unstated, such as a refusal, a limit, a default, '
    "a fallback, or a \"no finding\" boundary another FR's finding takes.";

const _responseLine =
    'Write one edge case per distinct response; inputs with the same '
    'response are nested triggers of one case, one sample each.';

const _leaveOutLine =
    'Leave out a case another FR or a spec rule owns, a case outside the '
    "Statement's condition, and implementation or test detail.";

const _knownLimitsLine =
    "Put a case with no designed response in the domain's `known_limits`, "
    "with what happens then, or with no domain doc in the feature's "
    'Out-of-scope as `<case> — not planned`. A designed response, even "the '
    'file is left as it is", is an edge case.';

const _errorCodeLine =
    'In an error case, name the error code the person or caller sees and '
    'whether the run stops. State no exit status: the error catalog of the '
    "nearest feature up the FR's parent chain in the target holds it.";

const _messageLine =
    'Quote an error message only when it is part of the contract, once, in '
    'the Output row that defines it; with no catalog reaching the FR, state '
    'in words what the person sees.';

const _splitLine =
    'Split an FR that holds too many edge cases into new FRs in its story.';

/// Fragments of the description lines the edge case lines replace.
const _droppedFragments = [
  'one Edge cases item per case',
  'does not handle',
  'Exercise each Statement clause',
  'counts as exercised',
  'So does a Statement clause',
];

const _maxSectionDescriptionLines = 5;
