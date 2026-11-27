import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _antiPersona = 'prds/personas/buyer/ANTI_PERSONA.md';
const _featuresDoc = 'prds/FEATURES.md';

Future<List<Finding>> _found(
  Map<String, String> edits,
  FindingKind kind,
) async {
  final report = await checkOf(await writeCheckProject(extra: edits));
  return [
    for (final f in report.findings)
      if (f.kind == kind) f,
  ];
}

List<Object?> _patterns(List<Finding> found) => [
  for (final f in found) f.toJson()['pattern'],
];

String _scenario(int n) =>
    '\n\n### Scenario $n — [edge] Case $n\n\n'
    '- **Given** an account\n- **When** the Agent acts\n- **Then** it works';

Map<String, String> _storyWith(int scenarios) => doc(
  loginStory,
  loginScenario2,
  '$loginScenario2'
  '${[for (var n = 3; n <= scenarios; n++) _scenario(n)].join()}',
);

String _edgeCases(int count) => [
  for (var n = 1; n <= count; n++)
    '$n. E${'$n'.padLeft(2, '0')} — Case $n → refused.',
].join('\n');

Map<String, String> _verification(String text) =>
    fr('Test: a wrong password is refused.', text);

String _antiPersonaDoc(String anti, List<String> sections) =>
    '---\nanti_type: $anti\nbasis: proto\n---\n\n# Scraper\n\n'
    '## Snapshot\n\nA bot owner.\nRuns many accounts.\n\n'
    '## Goal\n\nHarvest accounts.\n\n## Sources\n\n- Assumed.\n'
    '${sections.map((s) => '\n## $s\n\n- Held.\n').join()}';

void main() {
  group('the story scenario cap', () {
    test('a story of seven scenarios gives subsections_over_limit', () async {
      final found = await _found(
        _storyWith(7),
        FindingKind.subsectionsOverLimit,
      );
      expect(found, hasLength(1));
      expect(
        found.single.toJson(),
        allOf(containsPair('limit', 6), containsPair('actual', 7)),
      );
    });

    test('a story of six scenarios gives none', () async {
      expect(
        await _found(_storyWith(6), FindingKind.subsectionsOverLimit),
        isEmpty,
      );
    });
  });

  group('the fr edge case cap', () {
    Future<List<Finding>> capped(int cases) => _found(
      fr('1. E01 — An empty password → refused.', _edgeCases(cases)),
      FindingKind.itemCountOutOfRange,
    );

    test('an FR of nine edge cases gives item_count_out_of_range for the '
        'Owner', () async {
      final found = await capped(9);

      expect(found, hasLength(1));
      expect(
        found.single.toJson(),
        allOf(
          containsPair('limit', 8),
          containsPair('actual', 9),
          containsPair('waitsFor', 'owner'),
        ),
      );
    });

    test('an FR of eight edge cases gives none', () async {
      expect(await capped(8), isEmpty);
    });
  });

  group('the test-file ban on an FR Verification', () {
    Future<List<Object?>> banned(String text) async =>
        _patterns(await _found(_verification(text), FindingKind.patternBanned));

    test('a test path or a test-file suffix gives test_file_named', () async {
      for (final text in [
        'Run `test/x_test.dart` to check it.',
        'Run `tests/fixtures/login.json` to check it.',
        'Run `packages/app/test/` to check it.',
        'Read `test/README` first.',
        'Level: unit, see packages/app/test/analysis for it.',
        'See login_test.dart.',
        'See login.test.ts.',
        'See login.spec.js.',
      ]) {
        expect(await banned(text), ['test_file_named'], reason: text);
      }
    });

    test('prose naming the word test gives none', () async {
      for (final text in [
        'Test: a wrong password is refused.',
        'The test passes when the sign-in is refused.',
        '- **Level:** unit/integration',
        'Level: test/analysis, per the test method.',
        'Level: test/analysis/inspection',
        'Level: analysis/test/demonstration.',
        'A test-driven check of the latest sign-in.',
      ]) {
        expect(await banned(text), isEmpty, reason: text);
      }
    });
  });

  test('a Metric link in a form the dropped regex refused gives no '
      'banned pattern', () async {
    final found = await _found(
      doc(
        goalDoc,
        'Halve the password resets.',
        '- **Metric:** at most 3 resets, see [run][m1]\n\n'
            '[m1]: ../measurements/fewer_resets/MEASUREMENT.md',
      ),
      FindingKind.patternBanned,
    );
    expect(found, isEmpty);
  });

  test(
    'a project doc-level banned word gives a finding in any section',
    () async {
      final found = await _found({
        '.specstone/templates/fr.yaml': 'lint:\n  banned_words: [simply]\n',
        ...edit(loginFr, [
          (
            'A wrong password must not sign in.',
            'A wrong password simply must not sign in.',
          ),
          (
            'Test: a wrong password is refused.',
            'Test: simply a wrong password is refused.',
          ),
        ]),
      }, FindingKind.bannedWord);

      expect(
        [for (final f in found) (f.toJson()['word'], f.toJson()['section'])],
        [('simply', 'rationale'), ('simply', 'verification')],
      );
    },
  );

  group('the shapes a count or a title decides', () {
    test('a persona titled with a digit is title_numbered', () async {
      Future<List<Finding>> numbered(String title) => _found({
        'docs/prds/personas/buyer/PERSONA.md':
            '---\nrole: Parent\npriority: primary\nbasis: proto\n---\n\n'
            '# $title\n\n## Snapshot\n\nA parent.\nOf two kids.\n',
      }, FindingKind.titleNumbered);

      final found = await numbered('Parents of 2 kids');

      expect(found, hasLength(1));
      expect(found.single.path, 'prds/personas/buyer/PERSONA.md');
      expect(await numbered('Parents of kids'), isEmpty);
    });

    test('a scenario of two When steps is prefix_count_mismatch', () async {
      final found = await _found(
        doc(
          loginStory,
          '- **When** the Agent signs in\n',
          '- **When** the Agent signs in\n'
              '- **When** the Agent signs in again\n',
        ),
        FindingKind.prefixCountMismatch,
      );

      expect(found, hasLength(1));
      expect(found.single.path, loginStory);
    });
  });

  test('a feature with no summary and a features doc with no Features section '
      'give the two findings', () async {
    final report = await checkOf(
      await writeCheckProject(
        extra: {
          ...doc(loginFeature, 'summary: Lets an agent sign in.\n', ''),
          ...doc(
            _featuresDoc,
            '## Features\n\n$featureCatalogBlock\n\nOne feature.\n\n',
            '',
          ),
        },
      ),
    );

    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.requiredFieldMissing &&
              f.path == loginFeature)
            f.toJson()['field'],
      ],
      ['summary'],
    );
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.requiredSectionMissing &&
              f.path == _featuresDoc)
            f.toJson()['section'],
      ],
      ['features'],
    );
  });

  group('the anti_persona sections scoped to a misuser', () {
    const scoped = ['Motivations', 'Actions', 'Tools', 'Needs', 'Consequences'];

    test('a misuser holding the three base sections misses each of the '
        'five', () async {
      final found = await _found({
        'docs/$_antiPersona': _antiPersonaDoc('misuser', const []),
      }, FindingKind.requiredSectionMissing);
      expect([
        for (final f in found) f.toJson()['section'],
      ], unorderedEquals([for (final s in scoped) s.toLowerCase()]));
    });

    test('a misuser holding all eight sections gives none', () async {
      final found = await _found({
        'docs/$_antiPersona': _antiPersonaDoc('misuser', scoped),
      }, FindingKind.requiredSectionMissing);
      expect(found, isEmpty);
    });

    test('a non-target holding the three base sections gives none', () async {
      final report = await checkOf(
        await writeCheckProject(
          extra: {
            'docs/$_antiPersona': _antiPersonaDoc('non-target', const []),
          },
        ),
      );
      expect(
        report.findings.where(
          (f) =>
              f.kind == FindingKind.requiredSectionMissing ||
              f.kind == FindingKind.sectionOutsideFieldValue,
        ),
        isEmpty,
      );
    });

    test(
      'a non-target holding Tools gives section_outside_field_value',
      () async {
        final found = await _found({
          'docs/$_antiPersona': _antiPersonaDoc('non-target', ['Tools']),
        }, FindingKind.sectionOutsideFieldValue);
        expect(found.single.toJson(), containsPair('section', 'tools'));
      },
    );
  });
}
