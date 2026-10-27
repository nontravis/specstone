// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

void main() {
  test("f04/us03/s1: the fixture's requirement, override, and spec agree with the PRD", () async {
    final project = await writeCheckProject();
    expect(checkOf(project).findings, isEmpty);
    expect(
      checkOf(project, target: 'fr:login/email_login/check_password').findings,
      isEmpty,
    );
  });

  test('f04/us03/s2, f04/us03/fr01/e01, f04/us03/fr01/e04: a trace to a scenario the story lacks, or not in the '
      'S<N> form, is scenario_trace_unresolved', () async {
    for (final entry in ['S9', 'Scenario 2']) {
      final report = checkOf(
        await writeCheckProject(extra: fr('  - S2\n', '  - $entry\n')),
      );
      expect(spots(report, FindingKind.scenarioTraceUnresolved), [
        '$loginFr:3: scenario_trace_unresolved',
      ]);
      expect(
        report.findings
            .firstWhere((f) => f.kind == FindingKind.scenarioTraceUnresolved)
            .toJson()['entry'],
        entry,
      );
    }
  });

  test('f04/us03/s6, f04/us03/fr01/e02, f04/us03/fr01/e03: present scenarios and self-derived resolve', () async {
    for (final entries in ['  - S1\n  - S2\n', '  - self-derived\n']) {
      final report = checkOf(
        await writeCheckProject(extra: fr('  - S2\n', entries)),
      );
      expect(spots(report, FindingKind.scenarioTraceUnresolved), isEmpty);
    }
  });

  test('f04/us03/fr01/e05: kind and overrides that disagree are override_kind_mismatch at the kind key', () async {
    final noOverride = checkOf(
      await writeCheckProject(extra: doc(loginNf, 'overrides: NFR-P01\n', '')),
    );
    expect(spots(noOverride, FindingKind.overrideKindMismatch), [
      '$loginNf:2: override_kind_mismatch',
    ]);
    final addWithOne = checkOf(
      await writeCheckProject(
        extra: doc(loginNf, 'kind: tighten', 'kind: add'),
      ),
    );
    expect(spots(addWithOne, FindingKind.overrideKindMismatch), [
      '$loginNf:2: override_kind_mismatch',
    ]);
  });

  test('f04/us03/s4, f04/us03/fr01/e06: an override of an NFR the GNFR lacks is override_unresolved', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(loginNf, 'overrides: NFR-P01', 'overrides: NFR-P07'),
      ),
    );
    expect(spots(report, FindingKind.overrideUnresolved), [
      '$loginNf:3: override_unresolved',
    ]);
  });

  test(
    'f04/us03/fr01/e07: a requirement whose story is gone gets no trace rule',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: fr('  - S2\n', '  - S9\n'),
          without: {'docs/$loginStory'},
        ),
      );
      expect(spots(report, FindingKind.scenarioTraceUnresolved), isEmpty);
    },
  );

  test('review focus 5: a story header apart from letter case still holds its scenarios', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          loginStory,
          '## Acceptance Criteria',
          '## acceptance criteria',
        ),
      ),
    );
    expect(report.findings, isEmpty);
  });
}
