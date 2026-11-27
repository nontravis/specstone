import 'dart:convert';

import 'package:specstone_core/src/templates/merged_doc_type.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
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

  test('fr marks statement summary', () {
    expect(
      [
        for (final s in fr.sections)
          if (s.summary == true) s.id,
      ],
      ['statement'],
    );
  });

  test('the verification template is one block, naming no test file', () {
    final verification = sectionOf(fr, 'verification');
    final template = verification.template!;

    expect(
      template,
      '- **Pass criteria:** each edge case holds.\n'
      '  - <optional: a condition no edge case, the Statement, or an Input / '
      'Output row states>\n'
      '- **Level:** <level>',
    );
    expect(
      template,
      isNot(matches(RegExp(r'_test\.|\.test\.|\.spec\.|\btests?/'))),
    );
  });

  test('the verify_method, input_output, and behavior wording is short', () {
    expect(
      sectionOf(fr, 'input_output').template,
      contains(
        '| Field | Required | Notes |\n| --- | --- | --- |\n'
        '| <field> | <yes/no> | <constraints> |',
      ),
    );
  });

  group('the input_output section keeps an FR in product words', () {
    test('the template has an Input table of Field, Required, Notes and an '
        'Output table of Field, Notes', () {
      final template = sectionOf(fr, 'input_output').template!;

      expect(template, contains('| Field | Required | Notes |\n'));
      expect(template, contains('| Field | Notes |\n'));
      expect(template, isNot(contains('| Type |')));
    });
  });

  test('the input_output description gives the line for an FR no operation '
      'traces, in product words', () {
    // D6
    final description = sectionOf(fr, 'input_output').description!;
    const line =
        'With no operation tracing the FR, the row holds each name, type, and '
        'range a caller relies on.';
    final specIds = _specDocTypeIds();

    expect(description, contains(line));
    expect(specIds, isNotEmpty);
    for (final id in specIds) {
      // `_` reads as a space too, so `tech_stack` catches "tech stack".
      final name = RegExp(
        '\\b${RegExp.escape(id).replaceAll('_', '[ _]')}\\b',
        caseSensitive: false,
      );
      expect(line, isNot(matches(name)), reason: id);
    }
  });

  test('the verification description holds no exit-status clause', () {
    // D6
    expect(
      sectionOf(fr, 'verification').description,
      isNot(contains('exit status')),
    );
  });

  test('the edge cases template shows the several-trigger shape and the'
      ' description names it', () {
    final edgeCases = sectionOf(fr, 'edge_cases');

    expect(
      edgeCases.template,
      contains(
        '2. E02 — <lead> → <response>\n'
        '   <more response>\n'
        '   - <trigger>\n'
        '   - <trigger>',
      ),
    );
    expect(
      '\n'.allMatches(edgeCases.description!).length + 1,
      lessThanOrEqualTo(_maxSectionDescriptionLines),
    );
  });

  test('edge case line gives the id form and position numbering', () {
    final edgeCases = sectionOf(fr, 'edge_cases');
    final ordinals = RegExp(
      r'^(\d+)\. E(\d+) —',
      multiLine: true,
    ).allMatches(edgeCases.template!).toList();
    expect(ordinals, isNotEmpty);
    for (final (index, match) in ordinals.indexed) {
      expect(match.group(1), '${index + 1}');
      expect(int.parse(match.group(2)!), index + 1);
    }
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
      // D6
      expect(
        await flagged(
          '1. E01 — An empty password → refused.',
          rationale: 'The run ends with exit status 2.',
        ),
        ['The run ends with exit status 2.'],
      );
    });

    test('exit status in a Behavior section or an Input / Output row gives '
        'exit_status', () async {
      // D6
      Future<List<String>> flagged(String heading, String body) => bannedLines(
        check.edit(check.loginFr, [
          ('## Edge cases', '## $heading\n\n$body\n\n## Edge cases'),
        ]),
        check.loginFr,
        'exit_status',
      );

      const step = 'A crash ends the run with exit status 2.';
      // A fenced diagram is searched by no pattern; the step beside it is.
      expect(
        await flagged(
          'Behavior',
          '$step\n\n```mermaid\nflowchart TD\n  A[Sign in] --> B[Done]\n```',
        ),
        [step],
      );
      // D6: fenced text is exempt, as for every banned pattern.
      expect(
        await flagged(
          'Behavior',
          '```text\nA crash ends the run with exit status 2.\n```',
        ),
        isEmpty,
      );
      const row = '| result | A crash ends the run with exit status 2. |';
      expect(
        await flagged(
          'Input / Output',
          '**Output**\n| Field | Notes |\n| --- | --- |\n$row',
        ),
        [row],
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

const _maxSectionDescriptionLines = 5;

final _docTypeId = RegExp(r'^id: (\S+)\s*$', multiLine: true);

/// Returns the id of every doc type of every shipped pack but `prd-core`, the
/// PRD pack, whatever its doc path.
List<String> _specDocTypeIds() => [
  for (final MapEntry(:key, :value) in shippedPackFiles.entries)
    if (!key.startsWith('prd-core/'))
      ?_docTypeId.firstMatch(utf8.decode(value))?.group(1),
];
