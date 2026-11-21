import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart' as check;
import '../../helpers/pattern_findings.dart';
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
      ' cap line', () {
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
      for (final line in [..._edgeCaseLines, _capLine])
        description.indexOf(line),
    ];
    expect(positions, everyElement(isNonNegative));
    expect(positions, orderedEquals([...positions]..sort()));
    for (final fragment in _droppedFragments) {
      expect(description, isNot(contains(fragment)), reason: fragment);
    }
    expect(_capLine, isNot(matches(RegExp(r'\d'))));
  });

  test('fr item shape and behavior lines carry the step contract', () {
    expect(
      fr.description!.split('\n'),
      contains(
        'State what the product does, never how; leave mechanics to the spec '
        "docs, and assign no task to a person. A skill's or agent's steps are "
        'code. An FR states only when it asks, what it reports, what it takes, '
        'its limits, and what it may write.',
      ),
    );
    expect(
      sectionOf(fr, 'behavior').description!.split('\n'),
      contains(
        'State a required order of functions as a requirement, and an assumed '
        "order as an assumption. A skill's or agent's step order is neither.",
      ),
    );
  });

  test('the fr description carries the cap line its lint row names', () {
    expect(
      fr.description!.split('\n'),
      contains(
        'Trim edge cases the rules above leave out; split an FR still past '
        'the cap into new FRs in its story.',
      ),
    );
    expect(
      fr.description,
      isNot(contains('Split an FR that holds too many edge cases')),
    );
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
      '  - <a condition no edge case, the Statement, or an Input / Output row '
      'states>\n'
      '- **Level:** <level>',
    );

    expect(short, isZero);
    expect(long, greaterThan(short));
    expect(
      verification.description,
      contains(
        'Write `- **Pass criteria:** each edge case holds.`, with one nested '
        'bullet per condition that no edge case, the Statement, or an Input / '
        'Output row states; state no exit status.',
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

  group('trace and verification entries', () {
    for (final place in _places) {
      test('${place.section} flags each trace form and passes the links the '
          'story rules and other FRs take', () async {
        final forms = [
          ..._traceHits,
          if (place.flagsCodeSpanId) _codeSpanIdHit,
        ];
        final hits = await bannedLines(
          place.put([for (final form in forms) place.line(form)]),
          check.loginFr,
          'trace_outside_field',
        );
        final passes = await bannedLines(
          place.put([for (final form in _tracePasses) place.line(form)]),
          check.loginFr,
          'trace_outside_field',
        );

        expect(hits, [for (final form in forms) place.line(form)]);
        expect(passes, isEmpty);
      });
    }

    test('a code span scenario ID in an edge case is no trace', () async {
      const values = [
        '1. E01 — A move of `shop/cart#S2` under another story → the link stays.',
        '2. E02 — Two entries `S6` and `S06` naming one block → one finding.',
        '3. E03 — A step holding `traced_from: [S1, shop/cart#S3]` → it is listed.',
        '4. E04 — A move quoting ``shop/cart#S2`` in a span → the link stays.',
      ];
      const traced =
          '5. E05 — A value `S2` is kept, though prose cites (S2) → refused.';
      const stray = '6. E06 — A tick ` left open → refused (S2).';

      final found = await bannedLines(
        check.fr(
          '1. E01 — An empty password → refused.',
          [...values, traced, stray].join('\n'),
        ),
        check.loginFr,
        'trace_outside_field',
      );

      expect(found, [traced, stray]);
    });

    test('the same trace forms in an Input / Output row and in a fenced '
        'block give no finding', () async {
      final found = await bannedLines(
        check.edit(check.loginFr, [
          (
            '## Edge cases',
            '## Input / Output\n\n**Input**\n| Field | Type | Required | Notes |\n'
                '|---|---|---|---|\n'
                '| id | string | yes | `S2`, [Scenario 2](USER_STORY.md) |\n\n'
                '## Edge cases',
          ),
          (
            'A wrong password must not sign in.',
            'A wrong password must not sign in.\n\n```text\n'
                'It traces Scenario 2 as S2.\n```',
          ),
        ]),
        check.loginFr,
        'trace_outside_field',
      );

      expect(found, isEmpty);
    });

    test('exit status as a number or a pointer gives exit_status', () async {
      Future<List<String>> flagged(String edgeCase, {String rationale = ''}) =>
          bannedLines(
            check.edit(check.loginFr, [
              ('1. E01 — An empty password → refused.', edgeCase),
              if (rationale.isNotEmpty)
                ('A wrong password must not sign in.', rationale),
            ]),
            check.loginFr,
            'exit_status',
          );

      const crash = '1. E01 — A crash → the run stops with exit status 2.';
      expect(await flagged(crash), [crash]);
      expect(
        await flagged('1. E01 — A crash → the run stops, code E_RUN.'),
        isEmpty,
      );
      for (final pointer in _exitStatusPointers) {
        expect(await flagged(pointer), [pointer], reason: pointer);
      }
      for (final mention in _exitStatusMentions) {
        expect(await flagged(mention), isEmpty, reason: mention);
      }
      expect(await flagged(crash.replaceFirst('exit', 'Exit')), hasLength(1));
      expect(
        await flagged(
          '1. E01 — An empty password → refused.',
          rationale: 'The run ends with exit status 2.',
        ),
        isEmpty,
      );
    });

    test(
      'a Verification with no Level line gives pattern_missing level_line, '
      'and one with no Pass criteria line gives pass_criteria_line',
      () async {
        Future<List<String>> missing(String verification) => missingPatterns(
          check.fr(
            check.loginFrVerification,
            '## Verification\n\n$verification',
          ),
          check.loginFr,
        );

        expect(await missing(check.verificationLines), isEmpty);
        expect(await missing('- **Pass criteria:** each edge case holds.\n'), [
          'level_line',
        ]);
        expect(await missing('- **Level:** unit\n'), ['pass_criteria_line']);
        expect(
          await missing('Test: a wrong password is refused.\n'),
          unorderedEquals(['pass_criteria_line', 'level_line']),
        );
        expect(
          await missing(
            '- **Pass criteria:** the run is fast.\n- **Level:** unit\n',
          ),
          ['pass_criteria_line'],
        );
      },
    );

    test('the Rationale description no longer asks for the scenario link', () {
      expect(
        sectionOf(fr, 'rationale').description,
        isNot(contains('Link the scenario')),
      );
    });
  });
}

/// One FR section the `trace_outside_field` entry reads: how a form reads as a
/// line of it, and the fixture FR holding those lines in it.
final class _Place {
  const new(this.section, this.line, this.put, {required this.flagsCodeSpanId});

  final String section;
  final String Function(String form) line;
  final Map<String, String> Function(List<String> lines) put;

  /// Whether a scenario ID in a code span reads as a trace here; an edge case
  /// quotes one as a value.
  final bool flagsCodeSpanId;
}

final _places = [
  _Place(
    'statement',
    (form) => form,
    (lines) => check.fr(check.checkPasswordStatement, lines.join('\n')),
    flagsCodeSpanId: true,
  ),
  _Place(
    'edge_cases',
    (form) => '1. E01 — $form → refused.',
    (lines) =>
        check.fr('1. E01 — An empty password → refused.', lines.join('\n')),
    flagsCodeSpanId: false,
  ),
  _Place(
    'rationale',
    (form) => form,
    (lines) => check.fr('A wrong password must not sign in.', lines.join('\n')),
    flagsCodeSpanId: true,
  ),
];

/// The forms of a scenario trace outside `traced_from`.
const _traceHits = <String>[
  'A wrong password is refused (S2).',
  'It traces Scenario 2.',
  'It traces Scenarios 2 and 3.',
  'Traces from [Scenario 2](USER_STORY.md#scenario-2--wrong-password).',
  'Scenario 2 of [the story](USER_STORY.md) refuses it.',
  'Scenarios 2 and 3 of [the story](USER_STORY.md) refuse it.',
  'A wrong password is refused ([Scenario 2](USER_STORY.md#scenario-2)).',
];

/// A scenario ID in a code span, a trace in a Statement or the Rationale.
const _codeSpanIdHit = 'A wrong password is refused, as `S2` states.';

/// The links and words that name no scenario.
const _tracePasses = <String>[
  'It follows [BR-02](USER_STORY.md#rules).',
  'It extends [Lock the account](fr02_lock_account.md#edge-cases).',
  'A scenario with a wrong password is refused.',
  'The system shall report which story a requirement traces from.',
  'A step that names Scenario 9 of a five-scenario story gives no block.',
];

/// Edge case lines that lean on another FR's exit status.
const _exitStatusPointers = <String>[
  '1. E01 — A lock held too long → as the exit status row of another FR gives.',
  '1. E01 — A fault → no finding line ([exit status](fr02_other.md#output)).',
  '1. E01 — A crash → the run stops with exit status `2`.',
  '1. E01 — A crash → the run stops, exit status: 2.',
  '1. E01 — A crash → the run stops with exit status non-zero.',
  '1. E01 — A crash → the run stops, exit status is non-zero.',
  '1. E01 — A crash → the run stops, exit status: non-zero.',
  '1. E01 — A crash → the run stops, exit status of zero.',
  '1. E01 — A crash → the run stops with exit status nonzero.',
  '1. E01 — A crash → it ends with a non-zero exit status.',
];

/// Edge case lines that mention an exit status and give none.
const _exitStatusMentions = <String>[
  '1. E01 — An error case → it states no exit status, since the catalog does.',
  '1. E01 — A saved file → the caller acts on the exit status.',
  '1. E01 — A trim → it cuts a message text and an exit status.',
  '1. E01 — A run → the shim passes on the exit status of the program.',
];

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

const _capLine =
    'Trim edge cases the rules above leave out; split an FR still past the '
    'cap into new FRs in its story.';

/// Fragments of the description lines the edge case lines replace.
const _droppedFragments = [
  'one Edge cases item per case',
  'does not handle',
  'Exercise each Statement clause',
  'counts as exercised',
  'So does a Statement clause',
];

const _maxSectionDescriptionLines = 5;
