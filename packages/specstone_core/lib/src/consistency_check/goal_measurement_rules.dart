import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/consistency_check/section_rules.dart'
    show titleLineOf;
import 'package:specstone_core/src/consistency_check/trace_rules.dart'
    show goalKeyOf;
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart'
    show HeadingBlockTarget, anchorTargetOf;

const _projectType = 'project';
const _measurementType = 'measurement';
const _goalsSection = 'goals';
final _metricLine = RegExp(r'^(?:- )?\*\*Metric:\*\*');

/// A `### PG-` heading of a project doc: its doc, file line, and ID.
typedef _Goal = ({String docPath, int line, String key});

/// What a project's goal blocks and a measurement's goal links say, read once
/// per check run.
typedef _GoalLinks = ({
  Map<_Goal, List<BodyLine>> goals,
  Map<String, List<_Goal>> goalsOfMeasurement,
  Map<_Goal, List<IndexedDoc>> measurementsOfGoal,
});

final _goalLinksOf = Expando<_GoalLinks>();

/// Returns the findings of a project or measurement [doc] that join a goal to
/// its measurement.
///
/// A project goal needs one measurement whose head links it, and each
/// measurement head needs one goal link. A goal whose Metric link names a
/// measurement that does not link it is a mismatch. Runs only when the merged
/// set holds the project and measurement doc types.
Iterable<Finding> checkGoalMeasurements(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (!context.hasProject || !context.hasMeasurement) return;
  switch (doc.docTypeId) {
    case _projectType:
      yield* _goalFindings(context, doc);
    case _measurementType:
      yield* _measurementFindings(context, doc);
  }
}

_GoalLinks _linksOf(CheckContext context) =>
    _goalLinksOf[context] ??= _readGoalLinks(context);

_GoalLinks _readGoalLinks(CheckContext context) {
  final goals = <_Goal, List<BodyLine>>{};
  for (final project in context.index.docs) {
    if (project.docTypeId != _projectType) continue;
    for (final (:key, :lines) in _goalBlocksOf(context, project)) {
      goals[(docPath: project.docPath, line: lines.first.line, key: key)] =
          lines;
    }
  }
  final goalsOfMeasurement = <String, List<_Goal>>{};
  final measurementsOfGoal = <_Goal, List<IndexedDoc>>{};
  for (final measurement in context.index.docs) {
    if (measurement.docTypeId != _measurementType) continue;
    final linked = _goalsLinkedByHead(context, measurement, goals.keys);
    goalsOfMeasurement[measurement.docPath] = linked;
    for (final goal in linked) {
      (measurementsOfGoal[goal] ??= []).add(measurement);
    }
  }
  return (
    goals: goals,
    goalsOfMeasurement: goalsOfMeasurement,
    measurementsOfGoal: measurementsOfGoal,
  );
}

List<({String key, List<BodyLine> lines})> _goalBlocksOf(
  CheckContext context,
  IndexedDoc project,
) {
  final section = context.heldIndexOf(project, _goalsSection);
  if (section == null) return const [];
  return headingBlocksOf(context.bodyLinesOf(project, section), goalKeyOf);
}

/// The goals of [known] that a link in the head of [measurement] names, each
/// once, in link order.
///
/// The head is the text between the title line and the first section.
List<_Goal> _goalsLinkedByHead(
  CheckContext context,
  IndexedDoc measurement,
  Iterable<_Goal> known,
) {
  final facts = context.contentOf(measurement).lineFacts;
  final headStart = titleLineOf(context, measurement);
  final headEnd = facts.sectionLines.firstOrNull;
  final linked = <_Goal>[];
  for (final place in facts.links) {
    if (place.line <= headStart) continue;
    if (headEnd != null && place.line >= headEnd) continue;
    final goal = _goalNamedBy(context, place.target, place.anchor, known);
    if (goal != null && !linked.contains(goal)) linked.add(goal);
  }
  return linked;
}

_Goal? _goalNamedBy(
  CheckContext context,
  String target,
  String? anchor,
  Iterable<_Goal> known,
) {
  final project = context.index.at(target);
  if (project == null || anchor == null || anchor.isEmpty) return null;
  final named = anchorTargetOf(context.contentOf(project).lineFacts, anchor);
  if (named is! HeadingBlockTarget) return null;
  return known
      .where(
        (goal) =>
            goal.docPath == project.docPath && goal.line == named.headingLine,
      )
      .firstOrNull;
}

Iterable<Finding> _goalFindings(CheckContext context, IndexedDoc doc) sync* {
  final links = _linksOf(context);
  for (final MapEntry(key: goal, value: lines) in links.goals.entries) {
    if (goal.docPath != doc.docPath) continue;
    final named = links.measurementsOfGoal[goal] ?? const <IndexedDoc>[];
    if (named.isEmpty) {
      yield context.finding(
        doc,
        FindingKind.goalMeasurementMissing,
        line: goal.line,
        message: '${goal.key} is linked by no measurement head',
        keys: {'goal': goal.key},
      );
    } else if (named.length > 1) {
      yield context.finding(
        doc,
        FindingKind.goalMeasurementDuplicate,
        line: goal.line,
        message:
            '${goal.key} is linked by ${named.length} measurements: '
            '${_namesOf(named)}',
        keys: {'goal': goal.key},
      );
    }
    yield* _metricMismatch(context, doc, goal, lines);
  }
}

Iterable<Finding> _metricMismatch(
  CheckContext context,
  IndexedDoc doc,
  _Goal goal,
  List<BodyLine> block,
) sync* {
  final metricAt = block
      .where((line) => !line.fenced && _metricLine.hasMatch(line.text))
      .map((line) => line.line)
      .firstOrNull;
  if (metricAt == null) return;
  final links = _linksOf(context);
  final mismatched = <IndexedDoc>[];
  for (final place in context.contentOf(doc).lineFacts.links) {
    if (place.line != metricAt) continue;
    final target = context.index.at(place.target);
    if (target == null || target.docTypeId != _measurementType) continue;
    final held = links.goalsOfMeasurement[target.docPath] ?? const <_Goal>[];
    if (!held.contains(goal) && !mismatched.contains(target)) {
      mismatched.add(target);
    }
  }
  if (mismatched.isEmpty) return;
  yield context.finding(
    doc,
    FindingKind.goalMetricMismatch,
    line: metricAt,
    message:
        '${goal.key} Metric links ${_namesOf(mismatched)}, whose head does '
        'not link ${goal.key}',
    keys: {'goal': goal.key},
  );
}

Iterable<Finding> _measurementFindings(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  final linked = _linksOf(context).goalsOfMeasurement[doc.docPath] ?? const [];
  if (linked.isEmpty) {
    yield context.finding(
      doc,
      FindingKind.measurementGoalUnresolved,
      line: titleLineOf(context, doc),
      message: 'the head links no goal of the project',
      keys: {'measurement': doc.name},
    );
  } else if (linked.length > 1) {
    yield context.finding(
      doc,
      FindingKind.goalMeasurementDuplicate,
      line: titleLineOf(context, doc),
      message:
          'the head links ${linked.length} goals: '
          '${linked.map((goal) => goal.key).join(', ')}',
      keys: {'measurement': doc.name},
    );
  }
}

String _namesOf(List<IndexedDoc> docs) =>
    docs.map((doc) => doc.name).join(', ');
