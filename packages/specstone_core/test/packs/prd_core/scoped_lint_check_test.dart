import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _antiPersona = 'prds/personas/buyer/ANTI_PERSONA.md';

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
