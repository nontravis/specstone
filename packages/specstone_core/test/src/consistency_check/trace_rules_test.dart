// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/fixture_doc_types.dart';
import '../../helpers/shipped_pins.dart';

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
            'Halve the password resets.\n### PG-03 — More\n**Serves:** PV-01\nMore.\n',
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
      '$loginFeature:2: vision_goal_unresolved',
      '$loginFeature:4: vision_goal_unresolved',
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

  test('f04/us03/fr02/e08: a feature vision or goals ID no project heading holds is vision_goal_unresolved at its key', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: edit(loginFeature, [
          ('  - PV-01\n', '  - PV-08\n'),
          ('  - PG-01\n', '  - PG-09\n'),
        ]),
      ),
    );
    expect(spots(report, FindingKind.visionGoalUnresolved), [
      '$loginFeature:2: vision_goal_unresolved',
      '$loginFeature:4: vision_goal_unresolved',
    ]);
    expect(
      report.findings
          .where((f) => f.kind == FindingKind.visionGoalUnresolved)
          .map((f) => f.toJson()['id']),
      ['PV-08', 'PG-09'],
    );
  });

  test('f04/us03/fr02/e09: a PG block with no Serves line is goal_serves_missing at its heading', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(projectDoc, '**Serves:** PV-01\n', ''),
      ),
    );
    expect(spots(report, FindingKind.goalServesMissing), [
      '$projectDoc:15: goal_serves_missing',
    ]);
    expect(
      report.findings
          .firstWhere((f) => f.kind == FindingKind.goalServesMissing)
          .toJson()['goal'],
      'PG-01',
    );
  });

  test('f04/us03/fr02/e09: prose around a Serves ID is no ID', () async {
    for (final line in [
      '**Serves:** PV-01 — product angle',
      '**Serves:** PV-01.',
    ]) {
      final report = checkOf(
        await writeCheckProject(
          extra: doc(projectDoc, '**Serves:** PV-01', line),
        ),
      );
      expect(spots(report, FindingKind.visionGoalUnresolved), isEmpty);
      expect(spots(report, FindingKind.goalServesMissing), isEmpty);
    }

    final report = checkOf(
      await writeCheckProject(
        extra: doc(
          projectDoc,
          '**Serves:** PV-01',
          '**Serves:** PV-01 and PG-02',
        ),
      ),
    );
    expect(
      report.findings
          .where((f) => f.kind == FindingKind.visionGoalUnresolved)
          .map((f) => f.toJson()['id']),
      ['PG-02'],
    );
  });

  test('f04/us03/fr02/e09: a Serves ID that is no PV heading is vision_goal_unresolved at its line', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(projectDoc, '**Serves:** PV-01', '**Serves:** PV-07, PG-01'),
      ),
    );
    expect(spots(report, FindingKind.visionGoalUnresolved), [
      '$projectDoc:16: vision_goal_unresolved',
      '$projectDoc:16: vision_goal_unresolved',
    ]);
    expect(
      report.findings
          .where((f) => f.kind == FindingKind.visionGoalUnresolved)
          .map((f) => f.toJson()['id']),
      ['PG-01', 'PV-07'],
    );
  });

  test(
    'f04/us03/fr02/e09: a bare Serves line is goal_serves_missing',
    () async {
      for (final bare in ['**Serves:**', '**Serves:**  , ,']) {
        final report = checkOf(
          await writeCheckProject(
            extra: doc(projectDoc, '**Serves:** PV-01', bare),
          ),
        );
        expect(spots(report, FindingKind.goalServesMissing), [
          '$projectDoc:15: goal_serves_missing',
        ]);
        expect(spots(report, FindingKind.visionGoalUnresolved), isEmpty);
      }
    },
  );

  test(
    'f04/us03/fr02/e09: a fenced Serves example counts for nothing',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: doc(
            projectDoc,
            '**Serves:** PV-01\n',
            '```\n**Serves:** PV-01\n```\n',
          ),
        ),
      );
      expect(spots(report, FindingKind.goalServesMissing), [
        '$projectDoc:15: goal_serves_missing',
      ]);
    },
  );

  test('f04/us03/fr02/e08: a merged set with no project doc type runs no feature ID rule', () async {
    final project = await fixtureProject({
      'docs/prds/features/f01_login/FEATURE.md':
          '---\nvision:\n  - PV-09\ngoals:\n  - PG-09\n---\n\n# Login\n',
    });
    final session = ReadSession.open(
      templates: TemplateResolver(shippedFiles: fixturePackFiles()),
      workingDirectory: project,
      homeDirectory: null,
    );
    addTearDown(session.close);
    final report = runCheck(session);
    expect(spots(report, FindingKind.visionGoalUnresolved), isEmpty);
    expect(spots(report, FindingKind.goalServesMissing), isEmpty);
  });

  test(
    'f04/us03/fr03/e01: a row naming a requirement of the feature resolves',
    () async {
      expect(
        spots(
          checkOf(await writeCheckProject()),
          FindingKind.frTraceUnresolved,
        ),
        isEmpty,
      );
    },
  );

  test('f04/us03/s3, f04/us03/fr03/e02, f04/us03/fr03/e03: a row naming a requirement the feature lacks, or written '
      'with the feature slug, is fr_trace_unresolved', () async {
    final extra = checkOf(
      await writeCheckProject(
        extra: doc(
          loginApi,
          '| email_login/check_password | `signIn` |\n',
          '| email_login/check_password | `signIn` |\n| email_login/send_otp | `sendOtp` |\n',
        ),
      ),
    );
    expect(spots(extra, FindingKind.frTraceUnresolved), [
      '$loginApi:12: fr_trace_unresolved',
    ]);
    expect(
      extra.findings
          .firstWhere((f) => f.kind == FindingKind.frTraceUnresolved)
          .toJson()['fr'],
      'email_login/send_otp',
    );
    final withSlug = checkOf(
      await writeCheckProject(
        extra: doc(
          loginApi,
          '| email_login/check_password |',
          '| login/email_login/check_password |',
        ),
      ),
    );
    expect(spots(withSlug, FindingKind.frTraceUnresolved), [
      '$loginApi:11: fr_trace_unresolved',
    ]);
  });

  test('f04/us03/fr03/e04: code with no architecture doc is architecture_missing on the feature', () async {
    final report = checkOf(
      await writeCheckProject(without: {'docs/$loginArchitecture'}),
    );
    expect(spots(report, FindingKind.architectureMissing), [
      '$loginFeature:1: architecture_missing',
    ]);
  });

  test('f04/us03/fr03/e05, f04/us03/fr04/e05, cc-s03/inv2: a prd-core-only project runs neither rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
          ...fr('implements:\n  - app/lib/login.dart:checkPassword\n', ''),
        },
      ),
    );
    expect(spots(report, FindingKind.architectureMissing), isEmpty);
    expect(spots(report, FindingKind.implementsMissing), isEmpty);
  });

  test('f04/us03/fr03/e06: a spec doc whose feature is gone gets parent_missing and no row rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          'docs/specs/f03_billing/API.md':
              '# Billing API\n\n## FR trace\n| FR | Operation |\n|----|-----------|\n'
              '| pay/charge | `charge` |\n\n## Operations\nNone.\n',
        },
      ),
    );
    expect(spots(report), ['specs/f03_billing/API.md:1: parent_missing']);
  });

  test('f04/us03/s8, f04/us03/fr04/e01, f04/us03/fr04/e02, f04/us03/fr04/e03, f04/us03/fr04/e04: implemented work '
      'with no code pointer', () async {
    expect(
      spots(checkOf(await writeCheckProject()), FindingKind.implementsMissing),
      isEmpty,
    );
    final none = checkOf(
      await writeCheckProject(
        extra: fr('implements:\n  - app/lib/login.dart:checkPassword\n', ''),
      ),
    );
    expect(spots(none, FindingKind.implementsMissing), [
      '$loginFr:2: implements_missing',
    ]);
    final empty = checkOf(
      await writeCheckProject(
        extra: fr(
          'implements:\n  - app/lib/login.dart:checkPassword\n',
          'implements: []\n',
        ),
      ),
    );
    expect(spots(empty, FindingKind.implementsMissing), [
      '$loginFr:2: implements_missing',
    ]);
    final planned = checkOf(
      await writeCheckProject(
        extra: edit(loginFr, [
          ('status: implemented', 'status: planned'),
          ('implements:\n  - app/lib/login.dart:checkPassword\n', ''),
        ]),
      ),
    );
    expect(spots(planned, FindingKind.implementsMissing), isEmpty);
  });

  test('f04/us03/fr02, cc-s03/inv2: a project layer that disables the roles section runs no role rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/project.yaml':
              'sections:\n  - id: roles\n    disabled: true\n',
          ...doc(
            projectDoc,
            '## Role\n- `Agent` — the coding agent that writes the docs.\n- `Owner` — the person who approves them.\n\n',
            '',
          ),
          'docs/prds/personas/buyer/PERSONA.md': '---\nrole: Buyer\npriority: primary\nbasis: proto\n---\n\n# Buyer\n',
        },
      ),
    );
    expect(spots(report, FindingKind.roleUnresolved), isEmpty);
  });

  test('f04/us03/fr01, cc-s03/inv2: a project layer that disables the story acceptance_criteria section runs no scenario trace rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/user_story.yaml':
              'sections:\n  - id: acceptance_criteria\n    disabled: true\n',
          ...doc(
            loginStory,
            '\n## Acceptance Criteria\n\n$loginScenario1\n\n$loginScenario2\n',
            '',
          ),
        },
      ),
    );
    expect(spots(report, FindingKind.scenarioTraceUnresolved), isEmpty);
  });

  test('f04/us03/fr02, f04/us03/fr01: a fenced example is no Role entry, no As-a line, and no project heading', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...edit(projectDoc, [
            (
              '- `Owner` — the person who approves them.\n',
              '- `Owner` — the person who approves them.\n```\n- `Reviewer` — an example.\n```\n',
            ),
            (
              '## Project goals\n',
              '## Project goals\n```\n### PG-02 — Example\n```\n',
            ),
          ]),
          ...edit(loginStory, [
            ('## Use Case\n', '## Use Case\n```\n- **As a** Stranger\n```\n'),
            ('goals:\n  - PG-01\n', 'goals:\n  - PG-01\n  - PG-02\n'),
          ]),
        },
      ),
    );
    expect(spots(report, FindingKind.roleUnresolved), isEmpty);
    expect(spots(report, FindingKind.visionGoalUnresolved), [
      '$loginStory:3: vision_goal_unresolved',
    ]);
    expect(spots(report, FindingKind.visionGoalWidened), [
      '$loginStory:3: vision_goal_widened',
    ]);
    final unresolvedReviewer = checkOf(
      await writeCheckProject(
        extra: {
          ...edit(projectDoc, [
            (
              '- `Owner` — the person who approves them.\n',
              '- `Owner` — the person who approves them.\n```\n- `Reviewer` — an example.\n```\n',
            ),
          ]),
          ...doc(
            loginStory,
            '- **As a** Agent who signs in',
            '- **As a** Reviewer',
          ),
        },
      ),
    );
    expect(spots(unresolvedReviewer, FindingKind.roleUnresolved), [
      '$loginStory:12: role_unresolved',
    ]);
  });

  test(
    'f04/us03/fr03: a fenced table in the FR trace section holds no row',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: doc(
            loginApi,
            '| email_login/check_password | `signIn` |\n',
            '| email_login/check_password | `signIn` |\n\n```\n| FR | Operation |\n|----|-----------|\n| made_up | `x` |\n```\n',
          ),
        ),
      );
      expect(spots(report, FindingKind.frTraceUnresolved), isEmpty);
    },
  );
}
