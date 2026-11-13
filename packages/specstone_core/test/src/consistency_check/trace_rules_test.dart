// The expected texts are plan literals kept as written.
// ignore_for_file: lines_longer_than_80_chars

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';
import '../../helpers/fixture_doc_types.dart';
import '../../helpers/index_fixture.dart';
import '../../helpers/nested_fixture.dart';
import '../../helpers/shipped_pins.dart';
import '../../helpers/target_fixture.dart';

const _recordLayer =
    'id: implementation\n'
    'description: One feature record per target.\n'
    'path: specs/f{nn}_{slug}/IMPLEMENTATION.md\n'
    'parent: feature\n'
    'per_target: true\n'
    'fields:\n'
    '  - id: statuses\n'
    '    type: record_status\n'
    '    list: true\n'
    '  - id: implements\n'
    '    type: output_ref\n'
    '    list: true\n'
    '    pointer: item_exact\n'
    '  - id: tests\n'
    '    type: output_ref\n'
    '    list: true\n'
    '    pointer: item_test\n';

/// The record layer whose `item_test` field is named `proofs`, not `tests`.
const _proofsLayer =
    '$_recordLayer'
    '  - id: tests\n'
    '    disabled: true\n'
    '  - id: proofs\n'
    '    type: output_ref\n'
    '    list: true\n'
    '    pointer: item_test\n';

const _loginRecord = 'specs/f01_login/IMPLEMENTATION.md';
const _flutterRecord = 'specs/flutter/f01_login/IMPLEMENTATION.md';
const _jasprRecord = 'specs/jaspr/f01_login/IMPLEMENTATION.md';
const _cartRecord = 'specs/f02_shop/f01_cart/IMPLEMENTATION.md';
const _payRecord = 'specs/f02_shop/f02_pay/IMPLEMENTATION.md';

// The FR and the story of the login fixture, relative to `login`.
const _fr = 'email_login/check_password';
const _story = 'email_login';
const _loginCode = '$_fr:app/lib/login.dart:checkPassword';
const _loginTest = '$_fr:app/test/login_test.dart';

/// Returns a record: `statuses` first, then `implements`, one quoted line each.
///
/// The first `statuses` line is file line 3.
String _record({
  List<String> statuses = const [],
  List<String> code = const [],
  List<String> tests = const [],
  bool emptyCode = false,
}) {
  String list(String key, List<String> lines) => lines.isEmpty
      ? ''
      : "$key:\n${[for (final l in lines) "  - '$l'\n"].join()}";
  return '---\n${list('statuses', statuses)}${list('implements', code)}'
      '${list('tests', tests)}${emptyCode ? 'implements: []\n' : ''}---\n\n# Record\n';
}

/// The fixture files that add the record layer and one record at [path].
Map<String, String> _withRecord(String record, [String path = _loginRecord]) =>
    {
      '.specstone/templates/implementation.yaml': _recordLayer,
      'docs/$path': record,
    };

/// Checks the single-target fixture holding [record] as the login record.
///
/// The record stays unstamped so its lines keep their numbers.
Future<CheckReport> _checkLogin(
  String record, {
  Map<String, String> extra = const {},
  Set<String> without = const {},
}) async => checkOf(
  await writeCheckProject(
    extra: {..._withRecord(record), ...extra},
    without: without,
    unstamped: {'docs/$_loginRecord'},
  ),
);

/// The record layer that also holds `implements`, for the two-target project.
Map<String, String> _twinRecords({
  required String flutter,
  required String jaspr,
}) => {
  '.specstone/templates/implementation.yaml': _recordLayer,
  'docs/$_flutterRecord': flutter,
  'docs/$_jasprRecord': jaspr,
};

Future<CheckReport> _checkTwin({
  required String flutter,
  required String jaspr,
  Set<String> without = const {},
}) async => checkOf(
  await writeTwinProject(
    extra: _twinRecords(flutter: flutter, jaspr: jaspr),
    without: without,
  ),
);

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
      '$loginNf:3: override_kind_mismatch',
    ]);
    final addWithOne = checkOf(
      await writeCheckProject(
        extra: doc(loginNf, 'kind: tighten', 'kind: add'),
      ),
    );
    expect(spots(addWithOne, FindingKind.overrideKindMismatch), [
      '$loginNf:3: override_kind_mismatch',
    ]);
  });

  test('f04/us03/s4, f04/us03/fr01/e06: an override of an NFR the GNFR lacks is override_unresolved', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: doc(loginNf, 'overrides: NFR-P01', 'overrides: NFR-P07'),
      ),
    );
    expect(spots(report, FindingKind.overrideUnresolved), [
      '$loginNf:4: override_unresolved',
    ]);
  });

  test(
    'f04/us03/fr01/e06, RULE-12: a lettered NFR heading keys no block, so an '
    'override of its written form is override_unresolved',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: {
            ...doc(
              gnfrDoc,
              '### NFR-P01 — Sign-in time',
              '### NFR-P01a — Sign-in time',
            ),
            ...doc(loginNf, 'overrides: NFR-P01', 'overrides: NFR-P01a'),
          },
        ),
      );
      expect(spots(report, FindingKind.overrideUnresolved), [
        '$loginNf:4: override_unresolved',
      ]);
    },
  );

  test('f04/us03/fr02/e05, RULE-12: a lettered project heading keys no block, '
      'so a goal or Serves entry of its written form is unresolved', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(projectDoc, '### PG-01 — ', '### PG-01a — '),
          ...doc(loginFeature, 'PG-01', 'PG-01a'),
        },
      ),
    );
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.visionGoalUnresolved &&
              f.path == loginFeature)
            f.toJson()['id'],
      ],
      ['PG-01a'],
    );
  });

  test('f04/us03/fr01/e06: an NFR heading key is the ID the grammar reads, '
      'as item IDs read it: a tab or no-break space ends it, an unreadable '
      'one keys nothing', () async {
    final noBreakSpace = String.fromCharCode(0x00A0);
    final unresolved = <String, List<String>>{};
    for (final heading in [
      '### NFR-P01\tx — Sign-in time',
      '### NFR-P01${noBreakSpace}x — Sign-in time',
      '### NFR-P1a1 — Sign-in time',
    ]) {
      final report = checkOf(
        await writeCheckProject(
          extra: doc(gnfrDoc, '### NFR-P01 — Sign-in time', heading),
        ),
      );
      unresolved[heading] = spots(report, FindingKind.overrideUnresolved);
    }
    expect(unresolved.values, [
      isEmpty,
      isEmpty,
      ['$loginNf:4: override_unresolved'],
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
    expect(
      report.findings.where((f) => f.kind != FindingKind.formatDrift),
      isEmpty,
    );
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
      '$loginStory:11: role_unresolved',
      'prds/personas/buyer/PERSONA.md:3: role_unresolved',
    ]);
    expect(
      report.findings
          .firstWhere((f) => f.kind == FindingKind.roleUnresolved)
          .toJson()['role'],
      'Reviewer',
    );
  });

  test(
    'f04/us03/fr02/e12: an "As an" role line reads as an "As a" one',
    () async {
      final report = checkOf(
        await writeCheckProject(
          extra: doc(
            loginStory,
            '- **As a** Agent who signs in',
            '- **As an** Intruder who signs in',
          ),
        ),
      );
      expect(spots(report, FindingKind.roleUnresolved), [
        '$loginStory:11: role_unresolved',
      ]);
      expect(
        report.findings
            .firstWhere((f) => f.kind == FindingKind.roleUnresolved)
            .toJson()['role'],
        'Intruder',
      );
      final known = checkOf(
        await writeCheckProject(
          extra: doc(
            loginStory,
            '- **As a** Agent who signs in',
            '- **As an** Agent who signs in',
          ),
        ),
      );
      expect(spots(known, FindingKind.roleUnresolved), isEmpty);
    },
  );

  test('f04/us03/s5, f04/us03/fr02/e04: a story goal its feature does not cite is vision_goal_widened', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(loginStory, '  - PG-01\n', '  - PG-03\n'),
          ...doc(
            projectDoc,
            'Halve the password resets.\n',
            'Halve the password resets.\n\n### PG-03 — More\n\n**Serves:** PV-01\nMore.\n',
          ),
        },
      ),
    );
    expect(spots(report), ['$loginStory:3: vision_goal_widened']);
    expect(report.findings.single.toJson()['id'], 'PG-03');
    expect(
      report.findings.single.message,
      'PG-03 is not in the goals of the feature',
    );
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
      '$loginStory:11: role_unresolved',
    ]);
    expect(spots(report, FindingKind.visionGoalUnresolved), [
      '$loginFeature:3: vision_goal_unresolved',
      '$loginFeature:5: vision_goal_unresolved',
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
      '$loginFeature:3: vision_goal_unresolved',
      '$loginFeature:5: vision_goal_unresolved',
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
      '$projectDoc:20: goal_serves_missing',
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
      '$projectDoc:22: vision_goal_unresolved',
      '$projectDoc:22: vision_goal_unresolved',
    ]);
    expect(
      report.findings
          .where((f) => f.kind == FindingKind.visionGoalUnresolved)
          .map((f) => f.toJson()['id']),
      ['PG-01', 'PV-07'],
    );
  });

  test('f04/us03/fr02/e09: a lettered or unreadable Serves ID is read '
      'whole through the grammar and is vision_goal_unresolved', () async {
    final unresolved = <String, List<Object?>>{};
    for (final line in [
      '**Serves:** PV-01, PV-09a',
      '**Serves:** PV-01 and PV-1é',
      '**Serves:** PV-09a',
      '**Serves:** PV-01, PV-1a1',
    ]) {
      final report = checkOf(
        await writeCheckProject(
          extra: doc(projectDoc, '**Serves:** PV-01', line),
        ),
      );
      expect(spots(report, FindingKind.goalServesMissing), isEmpty);
      unresolved[line] = [
        for (final f in report.findings)
          if (f.kind == FindingKind.visionGoalUnresolved) f.toJson()['id'],
      ];
    }
    expect(unresolved, {
      '**Serves:** PV-01, PV-09a': ['PV-09a'],
      '**Serves:** PV-01 and PV-1é': ['PV-1é'],
      '**Serves:** PV-09a': ['PV-09a'],
      '**Serves:** PV-01, PV-1a1': ['PV-1a1'],
    });
  });

  test('f04/us03/fr02/e05: a project heading ID is read through the grammar, '
      'so an unreadable heading names no goal a feature may list', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          ...doc(projectDoc, '### PG-01 — ', '### PG-1a1 — '),
          ...doc(loginFeature, 'PG-01', 'PG-1a1'),
        },
      ),
    );
    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.visionGoalUnresolved &&
              f.path == loginFeature)
            f.toJson()['id'],
      ],
      ['PG-1a1'],
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
          '$projectDoc:20: goal_serves_missing',
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
        '$projectDoc:20: goal_serves_missing',
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
      '$loginApi:14: fr_trace_unresolved',
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
      '$loginApi:13: fr_trace_unresolved',
    ]);
  });

  test('f04/us03/fr03/e07: a row naming an FR by its path below the api feature resolves', () async {
    final report = checkOf(await writeNestedProject(), docPath: shopApi);

    expect(spots(report, FindingKind.frTraceUnresolved), isEmpty);
  });

  test('f04/us03/fr03/e08: a row that drops the sub-feature slug is fr_trace_unresolved', () async {
    final report = checkOf(
      await writeNestedProject(
        extra: {
          'docs/$shopApi': nestedFiles()['docs/$shopApi']!.replaceFirst(
            '| cart/add_item/check_stock |',
            '| add_item/check_stock |',
          ),
        },
      ),
      docPath: shopApi,
    );

    expect(spots(report, FindingKind.frTraceUnresolved), [
      '$shopApi:12: fr_trace_unresolved',
    ]);
    expect(
      report.findings
          .firstWhere((f) => f.kind == FindingKind.frTraceUnresolved)
          .toJson()['fr'],
      'add_item/check_stock',
    );
  });

  test('f04/us03/fr03/e04: a record entry that names code and no architecture doc is architecture_missing on the feature', () async {
    final report = await _checkLogin(
      _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
      without: {'docs/$loginArchitecture'},
    );
    expect(spots(report, FindingKind.architectureMissing), [
      '$loginFeature:1: architecture_missing',
    ]);
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.architectureMissing,
    );
    expect(finding.keys, isEmpty);
    expect(
      finding.message,
      'code is pointed at but no architecture doc covers the feature',
    );
  });

  test('f04/us03/fr03/e04: the architecture doc, or a record that names no code, gives no architecture_missing', () async {
    final withDoc = await _checkLogin(
      _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
    );
    expect(spots(withDoc, FindingKind.architectureMissing), isEmpty);
    final noCode = await _checkLogin(
      _record(statuses: ['$_fr:planned']),
      without: {'docs/$loginArchitecture'},
    );
    expect(spots(noCode, FindingKind.architectureMissing), isEmpty);
  });

  test("f04/us03/fr03/e09, sf-c12: cart with a record entry that names code and only shop's ARCHITECTURE gives no architecture_missing", () async {
    final report = checkOf(
      await writeNestedProject(
        extra: {
          ..._withRecord(
            _record(
              statuses: ['add_item:implemented'],
              code: ['add_item:app/lib/shop.dart:Shop'],
            ),
            _cartRecord,
          ),
        },
      ),
    );

    expect(spots(report, FindingKind.architectureMissing), isEmpty);
  });

  test("f04/us03/fr03/e09, sf-c12: without shop's ARCHITECTURE, cart, pay, and shop each get architecture_missing; a sub-feature whose record names no code gets none", () async {
    final report = checkOf(
      await writeNestedProject(
        extra: {
          ..._withRecord(
            _record(
              statuses: ['add_item:implemented'],
              code: ['add_item:app/lib/shop.dart:Shop'],
            ),
            _cartRecord,
          ),
          'docs/$_payRecord': _record(
            statuses: ['card:implemented'],
            code: ['card:app/lib/shop.dart:Shop'],
          ),
        },
        without: {'docs/$shopArchitecture'},
      ),
    );

    expect(spots(report, FindingKind.architectureMissing), [
      '$shopFeature:1: architecture_missing',
      '$cartFeature:1: architecture_missing',
      '$payFeature:1: architecture_missing',
    ]);

    final quiet = checkOf(
      await writeNestedProject(
        extra: {
          ..._withRecord(_record(statuses: ['add_item:planned']), _cartRecord),
        },
        without: {'docs/$shopArchitecture'},
      ),
    );
    expect(spots(quiet, FindingKind.architectureMissing), isEmpty);
  });

  test("f04/us03/fr03/e10: jaspr's record names code and jaspr holds no architecture doc of login: one architecture_missing, target jaspr", () async {
    final report = await _checkTwin(
      flutter: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
      jaspr: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
      without: {'docs/$jasprArchitecture'},
    );

    expect(spots(report, FindingKind.architectureMissing), [
      '$loginFeature:1: architecture_missing',
    ]);
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.architectureMissing,
    );
    expect(finding.keys, {'target': 'jaspr'});
    expect(finding.message, contains('jaspr'));
  });

  test('f04/us03/fr03/e10: with both twins, or a jaspr record that names no code yet, there is no architecture_missing', () async {
    final both = await _checkTwin(
      flutter: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
      jaspr: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
    );
    expect(spots(both, FindingKind.architectureMissing), isEmpty);

    final noCode = await _checkTwin(
      flutter: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
      jaspr: _record(statuses: ['$_fr:planned']),
      without: {'docs/$jasprArchitecture'},
    );
    expect(spots(noCode, FindingKind.architectureMissing), isEmpty);
  });

  test('f04/us03/fr03/e10: both targets lack their twin: one architecture_missing per target, each with its key', () async {
    final report = await _checkTwin(
      flutter: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
      jaspr: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
      without: {'docs/$flutterArchitecture', 'docs/$jasprArchitecture'},
    );

    expect(
      [
        for (final f in report.findings)
          if (f.kind == FindingKind.architectureMissing) f.keys,
      ],
      [
        {'target': 'flutter'},
        {'target': 'jaspr'},
      ],
    );
  });

  test('f04/us03/fr03 trade-off: a target that skips the feature needs no architecture doc, as an item skipped by it counts no code', () async {
    final report = await _checkTwin(
      flutter: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
      jaspr: _record(statuses: [':skipped:no web client'], code: [_loginCode]),
      without: {'docs/$jasprArchitecture'},
    );

    expect(spots(report, FindingKind.architectureMissing), isEmpty);
  });

  test(
    'f04/us03/fr03/e10: --target jaspr runs the rule for jaspr only',
    () async {
      final project = await writeTwinProject(
        extra: _twinRecords(
          flutter: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
          jaspr: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
        ),
        without: {'docs/$flutterArchitecture', 'docs/$jasprArchitecture'},
      );
      final session = openSession(project);
      addTearDown(session.close);
      final report = runCheck(session, codeTarget: 'jaspr');

      expect(
        [
          for (final f in report.findings)
            if (f.kind == FindingKind.architectureMissing) f.keys,
        ],
        [
          {'target': 'jaspr'},
        ],
      );
    },
  );

  test('f04/us03/fr03/e05, f04/us03/fr04/e05, cc-s03/inv2: a prd-core-only project runs neither rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
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
              '# Billing API\n\n## FR trace\n\n| FR | Operation |\n|---|---|\n'
              '| pay/charge | `charge` |\n\n## Operations\n\nNone.\n',
        },
      ),
    );
    expect(spots(report), ['specs/f03_billing/API.md:1: parent_missing']);
  });

  test('f04/us03/fr04/e01, f04/us03/fr04/e04: an implemented entry that names code, a planned entry with none, and an item with no entry give no implements_missing', () async {
    final report = await _checkLogin(
      _record(
        statuses: ['$_fr:implemented', '$_story:planned'],
        code: [_loginCode],
      ),
    );
    expect(spots(report, FindingKind.implementsMissing), isEmpty);
    final planned = await _checkLogin(_record(statuses: ['$_fr:planned']));
    expect(spots(planned, FindingKind.implementsMissing), isEmpty);
    final none = await _checkLogin(_record());
    expect(spots(none, FindingKind.implementsMissing), isEmpty);
  });

  test('f04/us03/s8, f04/us03/fr04/e02: an implemented entry that names no code is implements_missing at its statuses line', () async {
    final report = await _checkLogin(
      _record(statuses: ['$_story:planned', '$_fr:implemented']),
    );
    expect(spots(report, FindingKind.implementsMissing), [
      '$_loginRecord:4: implements_missing',
    ]);
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.implementsMissing,
    );
    expect(finding.name, 'login');
    expect(finding.keys, isEmpty);
    expect(finding.message, '$_fr is implemented and names no code path');
  });

  test('f04/us03/fr04/e03: an implemented entry whose code list is empty is implements_missing', () async {
    final report = await _checkLogin(
      _record(statuses: ['$_fr:implemented'], emptyCode: true),
    );
    expect(spots(report, FindingKind.implementsMissing), [
      '$_loginRecord:3: implements_missing',
    ]);
  });

  test('f04/us03/fr04/e04: code for another item does not stand for an implemented entry', () async {
    final report = await _checkLogin(
      _record(statuses: ['$_story:implemented'], code: [_loginCode]),
    );
    expect(spots(report, FindingKind.implementsMissing), [
      '$_loginRecord:3: implements_missing',
    ]);
  });

  test('f04/us03/fr04: a second statuses line for an item draws record_entry_duplicate alone, never implements_missing', () async {
    final report = await _checkLogin(
      _record(statuses: ['$_fr:planned', '$_fr:implemented']),
    );
    expect(spots(report, FindingKind.implementsMissing), isEmpty);
    expect(spots(report, FindingKind.recordEntryDuplicate), [
      '$_loginRecord:4: record_entry_duplicate',
    ]);
  });

  test('f04/us03/fr03/fr04: a project naming one target keeps the one-target messages and no target key', () async {
    final report = await _checkLogin(
      _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
      extra: {
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n  flutter:\n    code_root: app\n',
      },
      without: {'docs/$loginArchitecture'},
    );
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.architectureMissing,
    );
    expect(finding.keys, isEmpty);
    expect(
      finding.message,
      'code is pointed at but no architecture doc covers the feature',
    );
    final none = await _checkLogin(
      _record(statuses: ['$_fr:implemented']),
      extra: {
        '.specstone/config.yaml':
            '${shippedPinsConfig()}targets:\n  flutter:\n    code_root: app\n',
      },
    );
    expect(
      none.findings
          .singleWhere((f) => f.kind == FindingKind.implementsMissing)
          .message,
      '$_fr is implemented and names no code path',
    );
  });

  test('f04/us03/fr04/e07: a skipped entry holds no code path and gives no implements_missing', () async {
    final report = await _checkLogin(
      _record(statuses: ['$_fr:skipped:not in this client']),
    );
    expect(spots(report, FindingKind.implementsMissing), isEmpty);
  });

  test('an implemented FR entry verified by test and naming no test is '
      'tests_missing at its statuses line', () async {
    final report = await _checkLogin(
      _record(
        statuses: ['$_story:planned', '$_fr:implemented'],
        code: [_loginCode],
      ),
    );

    expect(spots(report, FindingKind.testsMissing), [
      '$_loginRecord:4: tests_missing',
    ]);
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.testsMissing,
    );
    expect(finding.name, 'login');
    expect(finding.waitsFor.wire, 'agent');
    expect(finding.keys, isEmpty);
    expect(finding.message, '$_fr is implemented and names no test');
    final named = await _checkLogin(
      _record(
        statuses: ['$_fr:implemented'],
        code: [_loginCode],
        tests: [_loginTest],
      ),
    );
    expect(spots(named, FindingKind.testsMissing), isEmpty);
  });

  test('a test field not named tests still ends tests_missing', () async {
    String record(String tail) =>
        "---\nstatuses:\n  - '$_fr:implemented'\nimplements:\n"
        "  - '$_loginCode'\n$tail---\n\n# Record\n";
    Future<CheckReport> check(String tail) => _checkLogin(
      record(tail),
      extra: {'.specstone/templates/implementation.yaml': _proofsLayer},
    );

    final named = await check("proofs:\n  - '$_loginTest'\n");
    final none = await check('');

    expect(spots(named, FindingKind.testsMissing), isEmpty);
    expect(spots(none, FindingKind.testsMissing), [
      '$_loginRecord:3: tests_missing',
    ]);
  });

  test('a record type with no test field has no tests_missing', () async {
    final report = await _checkLogin(
      _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
      extra: {
        '.specstone/templates/implementation.yaml':
            '$_recordLayer'
            '  - id: tests\n'
            '    disabled: true\n',
      },
    );

    expect(spots(report, FindingKind.testsMissing), isEmpty);
  });

  test('an FR entry with a code path and no test, and one with a test and '
      'no code path, each give their own finding', () async {
    final noCode = await _checkLogin(
      _record(statuses: ['$_fr:implemented'], tests: [_loginTest]),
    );
    expect(spots(noCode, FindingKind.testsMissing), isEmpty);
    expect(spots(noCode, FindingKind.implementsMissing), [
      '$_loginRecord:3: implements_missing',
    ]);
    final neither = await _checkLogin(_record(statuses: ['$_fr:implemented']));
    expect(spots(neither, FindingKind.testsMissing), [
      '$_loginRecord:3: tests_missing',
    ]);
    expect(spots(neither, FindingKind.implementsMissing), [
      '$_loginRecord:3: implements_missing',
    ]);
  });

  test('an implemented FR verified by analysis, inspection, or demonstration '
      'gives no tests_missing', () async {
    for (final method in ['analysis', 'inspection', 'demonstration']) {
      final report = await _checkLogin(
        _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
        extra: edit(
          'prds/features/f01_login/us01_email_login/fr01_check_password.md',
          [('verify_method: test', 'verify_method: $method')],
        ),
      );

      expect(spots(report, FindingKind.testsMissing), isEmpty, reason: method);
    }
  });

  test('an implemented story entry with no tests line gives no tests_missing '
      'and may hold one', () async {
    final bare = await _checkLogin(
      _record(
        statuses: ['$_story:implemented'],
        code: ['$_story:app/lib/login.dart'],
      ),
    );
    expect(spots(bare, FindingKind.testsMissing), isEmpty);
    final held = await _checkLogin(
      _record(
        statuses: ['$_story:implemented'],
        code: ['$_story:app/lib/login.dart'],
        tests: ['$_story:app/test/login_test.dart'],
      ),
    );
    expect(spots(held, FindingKind.testsMissing), isEmpty);
  });

  test('a planned or skipped FR entry with no tests line gives no '
      'tests_missing', () async {
    for (final status in ['planned', 'skipped:not in this client']) {
      final report = await _checkLogin(_record(statuses: ['$_fr:$status']));

      expect(spots(report, FindingKind.testsMissing), isEmpty, reason: status);
    }
  });

  test('flutter holding a test and jaspr implemented with none: one '
      'tests_missing on the jaspr record, naming jaspr', () async {
    final report = await _checkTwin(
      flutter: _record(
        statuses: ['$_fr:implemented'],
        code: [_loginCode],
        tests: [_loginTest],
      ),
      jaspr: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
    );

    expect(spots(report, FindingKind.testsMissing), [
      '$_jasprRecord:3: tests_missing',
    ]);
    expect(
      report.findings
          .singleWhere((f) => f.kind == FindingKind.testsMissing)
          .message,
      '$_fr is implemented in target jaspr and names no test',
    );
  });

  test('f04/us03/fr04/e05: a merged set with no record doc type runs no implemented-status rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/config.yaml': shippedPinsConfig(['prd-core']),
        },
      ),
    );
    expect(spots(report, FindingKind.implementsMissing), isEmpty);
  });

  test('f04/us03/fr04/e06: flutter implemented with code and jaspr implemented with none: one implements_missing, on the jaspr record, naming jaspr', () async {
    final report = await _checkTwin(
      flutter: _record(statuses: ['$_fr:implemented'], code: [_loginCode]),
      jaspr: _record(statuses: ['$_fr:implemented']),
    );

    expect(spots(report, FindingKind.implementsMissing), [
      '$_jasprRecord:3: implements_missing',
    ]);
    final finding = report.findings.singleWhere(
      (f) => f.kind == FindingKind.implementsMissing,
    );
    expect(
      finding.message,
      '$_fr is implemented in target jaspr and names no code path',
    );
  });

  test(
    'f04/us03/fr04/e06: --target flutter leaves the jaspr record out',
    () async {
      final project = await writeTwinProject(
        extra: _twinRecords(
          flutter: _record(statuses: ['$_fr:implemented']),
          jaspr: _record(statuses: ['$_fr:implemented']),
        ),
      );
      final session = openSession(project);
      addTearDown(session.close);
      final report = runCheck(session, codeTarget: 'flutter');

      expect(spots(report, FindingKind.implementsMissing), [
        '$_flutterRecord:3: implements_missing',
      ]);
    },
  );

  test('f04/us03/fr02, cc-s03/inv2: a project layer that disables the roles section runs no role rule', () async {
    final report = checkOf(
      await writeCheckProject(
        extra: {
          '.specstone/templates/project.yaml':
              'sections:\n  - id: roles\n    disabled: true\n',
          ...doc(
            projectDoc,
            '## Role\n\n- `Agent` — the coding agent that writes the docs.\n- `Owner` — the person who approves them.\n\n',
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
      '$loginStory:11: role_unresolved',
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

  group('goal sets of a nested feature', () {
    final projectWithPg02 = edit(projectDoc, [
      (
        'Halve the password resets.\n\n',
        'Halve the password resets.\n### PG-02 — Fewer lockouts\n**Serves:** PV-01\nHalve the lockouts.\n\n',
      ),
    ]);
    final cartGoalsWithPg02 = nestedFiles()['docs/$cartFeature']!.replaceFirst(
      'goals:\n  - PG-01',
      'goals:\n  - PG-01\n  - PG-02',
    );

    test("f04/us03/fr02/e10, sf-c12: cart's PG-02 outside shop's goals gives vision_goal_widened, PG-02 is not in the goals of the parent feature", () async {
      final report = checkOf(
        await writeNestedProject(
          extra: {...projectWithPg02, 'docs/$cartFeature': cartGoalsWithPg02},
        ),
      );

      expect(spots(report, FindingKind.visionGoalWidened), [
        '$cartFeature:5: vision_goal_widened',
      ]);
      final finding = report.findings.firstWhere(
        (f) => f.kind == FindingKind.visionGoalWidened,
      );
      expect(finding.toJson()['id'], 'PG-02');
      expect(
        finding.message,
        'PG-02 is not in the goals of the parent feature',
      );
    });

    test("f04/us03/fr02/e10, sf-c12: a feature under cart is held to cart's goals, not shop's", () async {
      const deepFeature = 'prds/features/f02_shop/f01_cart/f01_deep/FEATURE.md';
      final report = checkOf(
        await writeNestedProject(
          extra: {
            ...projectWithPg02,
            'docs/$shopFeature': nestedFiles()['docs/$shopFeature']!
                .replaceFirst(
                  'goals:\n  - PG-01',
                  'goals:\n  - PG-01\n  - PG-02',
                ),
            'docs/$deepFeature': nestedFiles()['docs/$cartFeature']!
                .replaceFirst(
                  'goals:\n  - PG-01',
                  'goals:\n  - PG-01\n  - PG-02',
                ),
          },
        ),
      );

      expect(spots(report, FindingKind.visionGoalWidened), [
        '$deepFeature:5: vision_goal_widened',
      ]);
    });

    test(
      'f04/us03/fr02/e11: shop is checked against the project only',
      () async {
        final report = checkOf(
          await writeNestedProject(
            extra: {
              ...projectWithPg02,
              'docs/$shopFeature': nestedFiles()['docs/$shopFeature']!
                  .replaceFirst(
                    'goals:\n  - PG-01',
                    'goals:\n  - PG-01\n  - PG-02',
                  ),
            },
          ),
        );

        expect(spots(report, FindingKind.visionGoalWidened), isEmpty);
        expect(spots(report, FindingKind.visionGoalUnresolved), isEmpty);
      },
    );
  });

  group('sibling-story traces', () {
    Future<List<String>> unresolvedWith(String entry) async {
      final report = checkOf(
        await writeNestedProject(
          extra: {
            'docs/$cartAddFr': nestedFiles()['docs/$cartAddFr']!.replaceFirst(
              'traced_from:\n  - S1\n',
              'traced_from:\n  - S1\n  - $entry\n',
            ),
          },
        ),
      );
      return [
        for (final f in report.findings)
          if (f.kind == FindingKind.scenarioTraceUnresolved)
            '${f.path}:${f.line} ${f.toJson()['entry']}',
      ];
    }

    test('f04/us03/fr01/e08: a scenario of a sibling story resolves', () async {
      expect(await unresolvedWith('shop/cart/drop_item#S1'), isEmpty);
    });

    test('f04/us03/fr01/e09: a story of another feature is scenario_trace_unresolved', () async {
      expect(await unresolvedWith('shop/pay/card#S1'), [
        '$cartAddFr:3 shop/pay/card#S1',
      ]);
    });

    test('f04/us03/fr01/e10: a sibling story with no such scenario is scenario_trace_unresolved', () async {
      expect(await unresolvedWith('shop/cart/drop_item#S9'), [
        '$cartAddFr:3 shop/cart/drop_item#S9',
      ]);
    });

    test('f04/us03/fr01/e04: a story that no doc carries is scenario_trace_unresolved', () async {
      expect(await unresolvedWith('shop/cart/nothing#S1'), [
        '$cartAddFr:3 shop/cart/nothing#S1',
      ]);
    });

    test('f04/us03/fr01/e04: a lettered scenario number is scenario_trace_unresolved', () async {
      expect(await unresolvedWith('S6a'), ['$cartAddFr:3 S6a']);
    });

    test('f04/us03/fr01/e09: two stories whose feature doc is gone are no siblings', () async {
      const other = 'prds/features/f01_login/us02_reset/USER_STORY.md';
      final report = checkOf(
        await writeCheckProject(
          extra: {
            ...fr('  - S2\n', '  - S2\n  - login/reset#S1\n'),
            'docs/$other': checkProjectFiles()['docs/$loginStory']!,
          },
          without: {'docs/$loginFeature'},
        ),
        docPath: loginFr,
      );
      expect(spots(report, FindingKind.scenarioTraceUnresolved), [
        '$loginFr:3: scenario_trace_unresolved',
      ]);
    });
  });
}
