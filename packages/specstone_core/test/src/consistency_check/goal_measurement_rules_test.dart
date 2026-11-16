// The fixture texts are written as the docs hold them.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _goal2Link = '[Faster sign-in](../../prds/GOAL.md#pg-02--faster-sign-in)';
const _projectGoalLink =
    '[Faster sign-in](../../prds/PROJECT.md#pg-02--faster-sign-in)';
const _secondMeasurement = 'measurements/faster_sign_in/MEASUREMENT.md';
const _thirdMeasurement = 'measurements/third_run/MEASUREMENT.md';
const _thirdMetricLink = '[third](../measurements/third_run/MEASUREMENT.md)';
const _metricLink =
    '[measurement](../measurements/fewer_resets/MEASUREMENT.md)';
const _secondMetricLink =
    '[measurement](../measurements/faster_sign_in/MEASUREMENT.md)';
const Set<FindingKind> _goalKinds = {
  FindingKind.goalMeasurementMissing,
  FindingKind.measurementGoalUnresolved,
  FindingKind.goalMeasurementDuplicate,
  FindingKind.goalMetricMismatch,
  FindingKind.goalMetricUnlinked,
};

/// The project doc edit that holds a goal the goal doc lacks. The project type
/// declares no goals section, so the check also gives `section_undeclared`.
final Map<String, String> _projectGoal = edit(projectDoc, [
  (
    '## Role',
    '## Project goals\n\n### PG-02 — Faster sign-in\n\n**Serves:** PV-01\n'
        'Sign in under one second.\n\n## Role',
  ),
]);

/// A measurement doc whose head holds [head] and whose body holds [scope].
String _measurement(String head, {String scope = 'Password resets.'}) =>
    '# Fewer resets\n\n$head\n\n## Scope\n\n- $scope\n\n'
    '## Method\n\n1. Count the resets of one week.\n\n'
    '## Results\n\nNewest first. Met: resets halved.\n\n'
    '| Date | Version | Run | Resets | Met |\n|---|---|---|---|---|\n\n'
    '## Open causes\n\nN/A\n';

/// The goal doc edit that gives PG-01 the Metric line [metric] and, with
/// [secondGoal], adds PG-02 with the Metric line [secondMetric].
Map<String, String> _goals({
  String? metric,
  bool secondGoal = false,
  String secondMetric = '',
}) => edit(goalDoc, [
  if (metric != null)
    ('**Serves:** PV-01\nHalve', '**Serves:** PV-01\n$metric\nHalve'),
  if (secondGoal)
    (
      'Halve the password resets.\n',
      'Halve the password resets.\n\n### PG-02 — Faster sign-in\n\n'
          '**Serves:** PV-01\n$secondMetric'
          'Sign in under one second.\n',
    ),
]);

Future<(Directory, CheckReport)> _run(Map<String, String> extra) async {
  final project = await writeCheckProject(extra: extra);
  return (project, checkOf(project));
}

/// The 1-based line of the first line of [docPath] that starts with [prefix].
int _lineOf(Directory project, String docPath, String prefix) {
  final lines = File('${project.path}/docs/$docPath').readAsLinesSync();
  return lines.indexWhere((line) => line.startsWith(prefix)) + 1;
}

List<Finding> _goalFindings(CheckReport report) => [
  for (final finding in report.findings)
    if (_goalKinds.contains(finding.kind)) finding,
];

void main() {
  test('a goal whose one measurement head links it gets no finding', () async {
    final (_, report) = await _run({});
    expect(_goalFindings(report), isEmpty);
  });

  test('a goal no measurement head links is goal_measurement_missing at its heading', () async {
    final project = await writeCheckProject(extra: _goals(secondGoal: true));
    final report = checkOf(project);
    final finding = _goalFindings(report).single;
    expect(finding.kind, FindingKind.goalMeasurementMissing);
    expect(finding.path, goalDoc);
    expect(finding.line, _lineOf(project, goalDoc, '### PG-02'));
    expect(finding.toJson()['goal'], 'PG-02');
  });

  test('two measurements that link one goal give one duplicate at the goal heading and no missing', () async {
    final project = await writeCheckProject(
      extra: {'docs/$_secondMeasurement': _measurement(measurementHeadLink)},
    );
    final finding = _goalFindings(checkOf(project)).single;
    expect(finding.kind, FindingKind.goalMeasurementDuplicate);
    expect(finding.path, goalDoc);
    expect(finding.line, _lineOf(project, goalDoc, '### PG-01'));
    expect(finding.toJson()['goal'], 'PG-01');
    expect(
      finding.message,
      allOf(contains('fewer_resets'), contains('faster_sign_in')),
    );
  });

  test('a head that links two goals is one duplicate at its title; neither goal is missing', () async {
    final project = await writeCheckProject(
      extra: {
        ..._goals(secondGoal: true),
        'docs/$measurementDoc': _measurement(
          '$measurementHeadLink $_goal2Link',
        ),
      },
    );
    final finding = _goalFindings(checkOf(project)).single;
    expect(finding.kind, FindingKind.goalMeasurementDuplicate);
    expect(finding.path, measurementDoc);
    expect(finding.line, _lineOf(project, measurementDoc, '# '));
    expect(finding.toJson()['measurement'], 'fewer_resets');
  });

  test('a head with no link, or one that links another doc, is measurement_goal_unresolved at its title', () async {
    for (final head in [
      'No link here.',
      '[Features](../../prds/FEATURES.md)',
    ]) {
      final project = await writeCheckProject(
        extra: {'docs/$measurementDoc': _measurement(head)},
      );
      final report = checkOf(project);
      final finding = _goalFindings(report)
          .singleWhere((f) => f.kind == FindingKind.measurementGoalUnresolved);
      expect(finding.path, measurementDoc, reason: head);
      expect(
        finding.line,
        _lineOf(project, measurementDoc, '# '),
        reason: head,
      );
      expect(finding.toJson()['measurement'], 'fewer_resets', reason: head);
    }
  });

  test('a head link whose anchor no goal heading holds is unresolved, beside link_anchor_missing', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$measurementDoc': _measurement(
          '[Gone](../../prds/GOAL.md#pg-09--gone)',
        ),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.measurementGoalUnresolved), [
      '$measurementDoc:${_lineOf(project, measurementDoc, '# ')}: measurement_goal_unresolved',
    ]);
    expect(spots(report, FindingKind.linkAnchorMissing), hasLength(1));
  });

  test('a goal link inside a measurement section is no goal link', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$measurementDoc': _measurement(
          'No link here.',
          scope: measurementHeadLink,
        ),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.measurementGoalUnresolved), [
      '$measurementDoc:${_lineOf(project, measurementDoc, '# ')}: measurement_goal_unresolved',
    ]);
  });

  test('a merged set with no measurement doc type runs no rule', () async {
    final project = await writeCheckProject(extra: _goals(secondGoal: true));
    final session = ReadSession.open(
      templates: TemplateResolver(
        shippedFiles: {
          for (final MapEntry(:key, :value) in shippedPackFiles.entries)
            if (key != 'prd-core/measurement.yaml') key: value,
        },
      ),
      workingDirectory: project,
      homeDirectory: null,
    );
    addTearDown(session.close);
    expect(_goalFindings(runCheck(session)), isEmpty);
  });

  test('a lettered goal heading holds no goal, and a head link to it is no goal link', () async {
    final project = await writeCheckProject(
      extra: {
        ...doc(goalDoc, '### PG-01 — ', '### PG-01a — '),
        'docs/$measurementDoc': _measurement(
          '[Fewer resets](../../prds/GOAL.md#pg-01a--fewer-resets)',
        ),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.goalMeasurementMissing), isEmpty);
    expect(spots(report, FindingKind.measurementGoalUnresolved), hasLength(1));
  });

  test('a head whose only link names a vision heading is measurement_goal_unresolved', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$measurementDoc': _measurement(
          '[Vision](../../prds/PROJECT.md#pv-01--one-sign-in)',
        ),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.measurementGoalUnresolved), hasLength(1));
    expect(spots(report, FindingKind.goalMeasurementMissing), hasLength(1));
  });

  test('a head whose only link names a goal heading the project doc still holds is measurement_goal_unresolved', () async {
    final project = await writeCheckProject(
      extra: {
        ..._projectGoal,
        'docs/$measurementDoc': _measurement(_projectGoalLink),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.measurementGoalUnresolved), [
      '$measurementDoc:${_lineOf(project, measurementDoc, '# ')}: measurement_goal_unresolved',
    ]);
    expect(spots(report, FindingKind.goalMeasurementMissing), hasLength(1));
  });

  test('a goal held in PROJECT and GOAL links one measurement once', () async {
    final project = await writeCheckProject(
      extra: {
        ..._projectGoal,
        'docs/$measurementDoc': _measurement(
          '$measurementHeadLink $_projectGoalLink',
        ),
      },
    );
    expect(_goalFindings(checkOf(project)), isEmpty);
  });

  test('a merged set with no goal doc type runs no rule', () async {
    final project = await writeCheckProject(
      extra: {'docs/$measurementDoc': _measurement('No link here.')},
    );
    final session = ReadSession.open(
      templates: TemplateResolver(
        shippedFiles: {
          for (final MapEntry(:key, :value) in shippedPackFiles.entries)
            if (key != 'prd-core/goal.yaml')
              key: key == 'prd-core/measurement.yaml'
                  ? utf8.encode(
                      utf8
                          .decode(value)
                          .replaceFirst('[project, goal]', '[project]'),
                    )
                  : value,
        },
      ),
      workingDirectory: project,
      homeDirectory: null,
    );
    addTearDown(session.close);
    expect(_goalFindings(runCheck(session)), isEmpty);
  });

  test('a Metric that links the measurement of another goal is goal_metric_mismatch on the Metric line', () async {
    final project = await writeCheckProject(
      extra: {
        ..._goals(
          secondGoal: true,
          metric: '- **Metric:** 50%, see $_secondMetricLink',
        ),
        'docs/$_secondMeasurement': _measurement(_goal2Link),
      },
    );
    final mismatch = _goalFindings(checkOf(project)).single;
    expect(mismatch.kind, FindingKind.goalMetricMismatch);
    expect(mismatch.path, goalDoc);
    expect(mismatch.line, _lineOf(project, goalDoc, '- **Metric:** 50'));
    expect(mismatch.toJson()['goal'], 'PG-01');
    expect(mismatch.message, contains('faster_sign_in'));
  });

  test('a Metric line that links two mismatched measurements names each in one finding', () async {
    final project = await writeCheckProject(
      extra: {
        ..._goals(
          secondGoal: true,
          metric:
              '- **Metric:** 50%, see $_secondMetricLink and $_thirdMetricLink',
        ),
        'docs/$_secondMeasurement': _measurement(_goal2Link),
        'docs/$_thirdMeasurement': _measurement('No link here.'),
      },
    );
    final mismatches = checkOf(project).findings
        .where((f) => f.kind == FindingKind.goalMetricMismatch);
    expect(mismatches, hasLength(1));
    expect(
      mismatches.single.message,
      allOf(contains('faster_sign_in'), contains('third_run')),
    );
  });

  test('a Metric that links a measurement with no goal link is a mismatch beside its unresolved', () async {
    final project = await writeCheckProject(
      extra: {
        ..._goals(metric: '- **Metric:** 50%, see $_metricLink'),
        'docs/$measurementDoc': _measurement('No link here.'),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.goalMetricMismatch), [
      '$goalDoc:${_lineOf(project, goalDoc, '- **Metric:**')}: goal_metric_mismatch',
    ]);
    expect(spots(report, FindingKind.measurementGoalUnresolved), hasLength(1));
  });

  test('a Metric that links a measurement whose head links two goals including its own is no mismatch', () async {
    final project = await writeCheckProject(
      extra: {
        ..._goals(
          secondGoal: true,
          metric: '- **Metric:** 50%, see $_metricLink',
        ),
        'docs/$measurementDoc': _measurement(
          '$measurementHeadLink $_goal2Link',
        ),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.goalMetricMismatch), isEmpty);
    expect(spots(report, FindingKind.goalMeasurementDuplicate), hasLength(1));
  });

  test('a Metric line with no link is one goal_metric_unlinked on that line and no mismatch', () async {
    final project = await writeCheckProject(
      extra: _goals(metric: '- **Metric:** 50%'),
    );
    final finding = _goalFindings(checkOf(project)).single;
    expect(finding.kind, FindingKind.goalMetricUnlinked);
    expect(finding.path, goalDoc);
    expect(finding.line, _lineOf(project, goalDoc, '- **Metric:**'));
    expect(finding.toJson()['goal'], 'PG-01');
    expect(finding.message, contains('guide line: link the goal'));
  });

  test('a Metric line that links only non-measurement docs or URLs is goal_metric_unlinked', () async {
    for (final metric in [
      '- **Metric:** 50%, see [project](PROJECT.md)',
      '- **Metric:** 50%, see [site](https://example.com/a)',
      '- **Metric:** 50%, see <https://example.com/a>',
      '- **Metric:** 50%, see [features](FEATURES.md#top) and [site](https://example.com/a)',
    ]) {
      final project = await writeCheckProject(extra: _goals(metric: metric));
      final report = checkOf(project);
      expect(spots(report, FindingKind.goalMetricUnlinked), [
        '$goalDoc:${_lineOf(project, goalDoc, '- **Metric:**')}: goal_metric_unlinked',
      ], reason: metric);
      expect(
        spots(report, FindingKind.goalMetricMismatch),
        isEmpty,
        reason: metric,
      );
    }
  });

  test('a Metric link with a single-quoted title, a paren title, or a spaced angle destination counts', () async {
    for (final metric in [
      "- **Metric:** 50%, see [m](../measurements/fewer_resets/MEASUREMENT.md 'Results')",
      '- **Metric:** 50%, see [m](../measurements/fewer_resets/MEASUREMENT.md (Results))',
      '- **Metric:** 50%, see [m](<../measurements/fewer_resets/MEASUREMENT.md#grounding cost>)',
      '- **Metric:** 50%, see [m][ref]\n\n[ref]: ../measurements/fewer_resets/MEASUREMENT.md',
    ]) {
      final project = await writeCheckProject(extra: _goals(metric: metric));
      final report = checkOf(project);
      expect(
        spots(report, FindingKind.goalMetricUnlinked),
        isEmpty,
        reason: metric,
      );
      expect(
        spots(report, FindingKind.goalMetricMismatch),
        isEmpty,
        reason: metric,
      );
    }
  });

  test('a Metric line whose only link names a missing file is goal_metric_unlinked beside link_unresolved', () async {
    final project = await writeCheckProject(
      extra: _goals(
        metric:
            '- **Metric:** 50%, see [m](../measurements/gone/MEASUREMENT.md)',
      ),
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.goalMetricUnlinked), [
      '$goalDoc:${_lineOf(project, goalDoc, '- **Metric:**')}: goal_metric_unlinked',
    ]);
    expect(spots(report, FindingKind.goalMetricMismatch), isEmpty);
    expect(spots(report, FindingKind.linkUnresolved), hasLength(1));
  });

  test('a Metric link with an anchor the measurement lacks gets neither kind, only link_anchor_missing', () async {
    final project = await writeCheckProject(
      extra: _goals(
        metric: '- **Metric:** 50%, see [m](../measurements/fewer_resets/MEASUREMENT.md#nope)',
      ),
    );
    final report = checkOf(project);
    expect(_goalFindings(report), isEmpty);
    expect(spots(report, FindingKind.linkAnchorMissing), hasLength(1));
  });

  test(
    'a goal block with no Metric line, or only a fenced one, gets neither kind',
    () async {
      for (final metric in [null, '```\n- **Metric:** 50%\n```']) {
        final project = await writeCheckProject(extra: _goals(metric: metric));
        expect(_goalFindings(checkOf(project)), isEmpty, reason: '$metric');
      }
    },
  );

  test('a Metric line that links no measurement gets no finding when the merged set has no measurement type', () async {
    final project = await writeCheckProject(
      extra: _goals(metric: '- **Metric:** 50%'),
    );
    final session = ReadSession.open(
      templates: TemplateResolver(
        shippedFiles: {
          for (final MapEntry(:key, :value) in shippedPackFiles.entries)
            if (key != 'prd-core/measurement.yaml') key: value,
        },
      ),
      workingDirectory: project,
      homeDirectory: null,
    );
    addTearDown(session.close);
    expect(_goalFindings(runCheck(session)), isEmpty);
  });

  test('a Metric link to a section of the measurement counts as a Metric link', () async {
    final project = await writeCheckProject(
      extra: {
        ..._goals(
          secondGoal: true,
          metric: '- **Metric:** 50%, see [results](../measurements/faster_sign_in/MEASUREMENT.md#results)',
        ),
        'docs/$_secondMeasurement': _measurement(_goal2Link),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.goalMetricMismatch), [
      '$goalDoc:${_lineOf(project, goalDoc, '- **Metric:**')}: goal_metric_mismatch',
    ]);
  });

  test(
    'a bare Metric line without the bullet is read as a Metric line',
    () async {
      final project = await writeCheckProject(
        extra: {
          ..._goals(
            secondGoal: true,
            metric: '**Metric:** 50%, see $_secondMetricLink',
          ),
          'docs/$_secondMeasurement': _measurement(_goal2Link),
        },
      );
      expect(
        spots(checkOf(project), FindingKind.goalMetricMismatch),
        hasLength(1),
      );
    },
  );

  test("checking one doc reports that doc's goal findings alone", () async {
    final project = await writeCheckProject(extra: _goals(secondGoal: true));
    expect(
      spots(
        checkOf(project, docPath: measurementDoc),
        FindingKind.goalMeasurementMissing,
      ),
      isEmpty,
    );
    expect(
      spots(
        checkOf(project, docPath: goalDoc),
        FindingKind.goalMeasurementMissing,
      ),
      hasLength(1),
    );
  });

  test(
    'a Results written as prose gives the measurement doc no finding',
    () async {
      const table =
          '| Date | Version | Run | Resets | Met |\n|---|---|---|---|---|\n\n';
      final project = await writeCheckProject(
        extra: edit(measurementDoc, [
          (table, 'Run one halved the resets.\n\n'),
        ]),
      );
      expect(checkOf(project, docPath: measurementDoc).findings, isEmpty);
    },
  );
}
