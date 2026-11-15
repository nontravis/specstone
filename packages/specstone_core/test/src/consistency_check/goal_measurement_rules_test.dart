// The fixture texts are written as the docs hold them.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:specstone_core/src/consistency_check/check_report.dart';
import 'package:specstone_core/src/consistency_check/check_run.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/index_query/read_session.dart';
import 'package:specstone_core/src/templates/shipped_pack_files.dart';
import 'package:specstone_core/src/templates/template_resolver.dart';
import 'package:test/test.dart';

import '../../helpers/check_fixture.dart';

const _goal1Link = '[Fewer resets](../../prds/PROJECT.md#pg-01--fewer-resets)';
const _goal2Link =
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
};

/// A measurement doc whose head holds [head] and whose body holds [scope].
String _measurement(String head, {String scope = 'Password resets.'}) =>
    '# Fewer resets\n\n$head\n\n## Scope\n\n- $scope\n\n'
    '## Method\n\n1. Count the resets of one week.\n\n'
    '## Results\n\nNewest first. Met: resets halved.\n\n'
    '| Date | Version | Run | Resets | Met |\n|---|---|---|---|---|\n\n'
    '## Open causes\n\nN/A\n';

/// The project doc edit that gives PG-01 the Metric line [metric] and, with
/// [secondGoal], adds PG-02 with the Metric line [secondMetric].
Map<String, String> _project({
  String? metric,
  bool secondGoal = false,
  String secondMetric = '',
}) => edit(projectDoc, [
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
  test(
    'E01: a goal whose one measurement head links it gets no finding',
    () async {
      final (_, report) = await _run({});
      expect(_goalFindings(report), isEmpty);
    },
  );

  test('E02: a goal no measurement head links is goal_measurement_missing at its heading', () async {
    final project = await writeCheckProject(extra: _project(secondGoal: true));
    final report = checkOf(project);
    final finding = _goalFindings(report).single;
    expect(finding.kind, FindingKind.goalMeasurementMissing);
    expect(finding.path, projectDoc);
    expect(finding.line, _lineOf(project, projectDoc, '### PG-02'));
    expect(finding.toJson()['goal'], 'PG-02');
  });

  test('E03: two measurements that link one goal give one duplicate at the goal heading and no missing', () async {
    final project = await writeCheckProject(
      extra: {'docs/$_secondMeasurement': _measurement(_goal1Link)},
    );
    final finding = _goalFindings(checkOf(project)).single;
    expect(finding.kind, FindingKind.goalMeasurementDuplicate);
    expect(finding.path, projectDoc);
    expect(finding.line, _lineOf(project, projectDoc, '### PG-01'));
    expect(finding.toJson()['goal'], 'PG-01');
    expect(
      finding.message,
      allOf(contains('fewer_resets'), contains('faster_sign_in')),
    );
  });

  test('E04: a head that links two goals is one duplicate at its title; neither goal is missing', () async {
    final project = await writeCheckProject(
      extra: {
        ..._project(secondGoal: true),
        'docs/$measurementDoc': _measurement('$_goal1Link $_goal2Link'),
      },
    );
    final finding = _goalFindings(checkOf(project)).single;
    expect(finding.kind, FindingKind.goalMeasurementDuplicate);
    expect(finding.path, measurementDoc);
    expect(finding.line, _lineOf(project, measurementDoc, '# '));
    expect(finding.toJson()['measurement'], 'fewer_resets');
  });

  test('E05: a head with no link, or one that links another doc, is measurement_goal_unresolved at its title', () async {
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

  test('E06: a head link whose anchor no goal heading holds is unresolved, beside link_anchor_missing', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$measurementDoc': _measurement(
          '[Gone](../../prds/PROJECT.md#pg-09--gone)',
        ),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.measurementGoalUnresolved), [
      '$measurementDoc:${_lineOf(project, measurementDoc, '# ')}: measurement_goal_unresolved',
    ]);
    expect(spots(report, FindingKind.linkAnchorMissing), hasLength(1));
  });

  test('E07: a goal link inside a measurement section is no goal link', () async {
    final project = await writeCheckProject(
      extra: {
        'docs/$measurementDoc': _measurement(
          'No link here.',
          scope: _goal1Link,
        ),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.measurementGoalUnresolved), [
      '$measurementDoc:${_lineOf(project, measurementDoc, '# ')}: measurement_goal_unresolved',
    ]);
  });

  test('E08: a merged set with no measurement doc type runs no rule (the project type cannot be absent while measurement is held)', () async {
    final project = await writeCheckProject(extra: _project(secondGoal: true));
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

  test('E09: a lettered goal heading holds no goal, and a head link to it is no goal link', () async {
    final project = await writeCheckProject(
      extra: doc(projectDoc, '### PG-01 — ', '### PG-01a — '),
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.goalMeasurementMissing), isEmpty);
    expect(spots(report, FindingKind.measurementGoalUnresolved), hasLength(1));
  });

  test('E10: a head whose only link names a vision heading is measurement_goal_unresolved', () async {
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

  test('E11: a Metric that links the measurement of another goal is goal_metric_mismatch on the Metric line', () async {
    final project = await writeCheckProject(
      extra: {
        ..._project(
          secondGoal: true,
          metric: '- **Metric:** 50%, see $_secondMetricLink',
        ),
        'docs/$_secondMeasurement': _measurement(_goal2Link),
      },
    );
    final mismatch = _goalFindings(checkOf(project)).single;
    expect(mismatch.kind, FindingKind.goalMetricMismatch);
    expect(mismatch.path, projectDoc);
    expect(mismatch.line, _lineOf(project, projectDoc, '- **Metric:** 50'));
    expect(mismatch.toJson()['goal'], 'PG-01');
    expect(mismatch.message, contains('faster_sign_in'));
  });

  test('E11: a Metric line that links two mismatched measurements names each in one finding', () async {
    final project = await writeCheckProject(
      extra: {
        ..._project(
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

  test('E12: a Metric that links a measurement with no goal link is a mismatch beside its unresolved', () async {
    final project = await writeCheckProject(
      extra: {
        ..._project(metric: '- **Metric:** 50%, see $_metricLink'),
        'docs/$measurementDoc': _measurement('No link here.'),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.goalMetricMismatch), [
      '$projectDoc:${_lineOf(project, projectDoc, '- **Metric:**')}: goal_metric_mismatch',
    ]);
    expect(spots(report, FindingKind.measurementGoalUnresolved), hasLength(1));
  });

  test('E13: a Metric that links a measurement whose head links two goals including its own is no mismatch', () async {
    final project = await writeCheckProject(
      extra: {
        ..._project(
          secondGoal: true,
          metric: '- **Metric:** 50%, see $_metricLink',
        ),
        'docs/$measurementDoc': _measurement('$_goal1Link $_goal2Link'),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.goalMetricMismatch), isEmpty);
    expect(spots(report, FindingKind.goalMeasurementDuplicate), hasLength(1));
  });

  test(
    'E14: a Metric line that links no measurement gets no mismatch',
    () async {
      final project = await writeCheckProject(
        extra: _project(metric: '- **Metric:** 50%'),
      );
      expect(_goalFindings(checkOf(project)), isEmpty);
    },
  );

  test('a Metric link to a section of the measurement counts as a Metric link', () async {
    final project = await writeCheckProject(
      extra: {
        ..._project(
          secondGoal: true,
          metric: '- **Metric:** 50%, see [results](../measurements/faster_sign_in/MEASUREMENT.md#results)',
        ),
        'docs/$_secondMeasurement': _measurement(_goal2Link),
      },
    );
    final report = checkOf(project);
    expect(spots(report, FindingKind.goalMetricMismatch), [
      '$projectDoc:${_lineOf(project, projectDoc, '- **Metric:**')}: goal_metric_mismatch',
    ]);
  });

  test(
    'a bare Metric line without the bullet is read as a Metric line',
    () async {
      final project = await writeCheckProject(
        extra: {
          ..._project(
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
    final project = await writeCheckProject(extra: _project(secondGoal: true));
    expect(
      spots(
        checkOf(project, docPath: measurementDoc),
        FindingKind.goalMeasurementMissing,
      ),
      isEmpty,
    );
    expect(
      spots(
        checkOf(project, docPath: projectDoc),
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
      final baseline = await writeCheckProject();
      List<String> kinds(Directory dir) => [
        for (final finding in checkOf(dir, docPath: measurementDoc).findings)
          finding.kind.name,
      ];
      expect(kinds(project), kinds(baseline));
    },
  );
}
