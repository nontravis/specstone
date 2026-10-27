// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/fixture_doc_types.dart';

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

  test(
    'f04/us03/fr02/e01: an "As a" role with a Role entry resolves',
    () async {
      expect(
        spots(checkOf(await writeCheckProject()), FindingKind.roleUnresolved),
        isEmpty,
      );
    },
  );

  test('f04/us03/s7, f04/us03/fr02/e02, f04/us03/fr02/e03: a story or persona role the project lacks', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(
            loginStory,
            '- **As a** Agent who signs in',
            '- **As a** Reviewer',
          ),
          'docs/prds/personas/buyer/PERSONA.md': '---\nrole: Buyer\npriority: primary\nbasis: proto\n---\n\n# Buyer\n',
        },
      ),
    );
    expect(spots(report, FindingKind.roleUnresolved), [
      '$loginStory:12: role_unresolved',
      'prds/personas/buyer/PERSONA.md:2: role_unresolved',
    ]);
    expect(
      report.findings
          .firstWhere((f) => f.kind == FindingKind.roleUnresolved)
          .toJson()['role'],
      'Reviewer',
    );
  });

  test('f04/us03/s5, f04/us03/fr02/e04: a story goal its feature does not cite is vision_goal_widened', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(loginStory, '  - PG-01\n', '  - PG-03\n'),
          ...doc(
            projectDoc,
            'Halve the password resets.\n',
            'Halve the password resets.\n### PG-03 — More\nMore.\n',
          ),
        },
      ),
    );
    expect(spots(report), ['$loginStory:3: vision_goal_widened']);
    expect(report.findings.single.toJson()['id'], 'PG-03');
  });

  test('f04/us03/fr02/e05: an ID no project heading holds is unresolved, and widened too', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(loginStory, '  - PG-01\n', '  - PG-09\n'),
      ),
    );
    expect(spots(report), [
      '$loginStory:3: vision_goal_unresolved',
      '$loginStory:3: vision_goal_widened',
    ]);
  });

  test("f04/us03/fr02/e06, f04/us03/fr02/e07: a subset of the feature's IDs passes; with no PROJECT.md every role "
      'and ID is unresolved', () async {
    expect(
      spots(checkOf(await writeCheckProject()), FindingKind.visionGoalWidened),
      isEmpty,
    );
    final report = checkOf(
      await writeCheckProject(without: {'docs/$projectDoc'}),
    );
    expect(spots(report, FindingKind.roleUnresolved), [
      '$loginStory:12: role_unresolved',
    ]);
    expect(spots(report, FindingKind.visionGoalUnresolved), [
      '$loginStory:3: vision_goal_unresolved',
    ]);
  });

  test('f04/us03/fr02/e07: a merged set with no project doc type runs no role rule', () async {
    final project = await fixtureProject({
      'docs/prds/features/f01_login/us01_email_login/USER_STORY.md':
          '# Sign in\n\n## Use Case\n- **As a** Stranger who signs in\n',
    });
    final session = ReadSession.open(
      templates: TemplateResolver(shippedFiles: fixturePackFiles()),
      workingDirectory: project,
      homeDirectory: null,
    );
    addTearDown(session.close);
    expect(spots(runCheck(session), FindingKind.roleUnresolved), isEmpty);
  });
}
