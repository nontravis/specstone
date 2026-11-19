import 'package:specstone_core/src/consistency_check/check_context.dart';
import 'package:specstone_core/src/consistency_check/finding.dart';
import 'package:specstone_core/src/consistency_check/models/goal_block.dart';
import 'package:specstone_core/src/consistency_check/section_rules.dart'
    show titleLineOf;
import 'package:specstone_core/src/doc_model/models/body_line.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/item_links.dart'
    show HeadingBlockTarget, anchorTargetOf;

const _goalType = 'goal';
const _measurementType = 'measurement';
final _metricLine = RegExp(r'^(?:- )?\*\*Metric:\*\*');
const _unlinkedMessage =
    "Metric line links no measurement; guide line: link the goal's measurement";

/// A `### PG-` heading of a goal doc: its doc, file line, and ID.
typedef _Goal = ({String docPath, int line, String key});

/// What a goal doc's goal blocks and a measurement's goal links say, read once
/// per check run.
typedef _GoalLinks = ({
  Map<_Goal, List<BodyLine>> goals,
  Map<String, List<_Goal>> goalsOfMeasurement,
  Map<_Goal, List<IndexedDoc>> measurementsOfGoal,
});

final _goalLinksOf = Expando<_GoalLinks>();

/// Returns the findings of a goal or measurement [doc] that join a goal to its
/// measurement.
///
/// A goal needs one measurement whose head links it, and a head needs one goal
/// link. A Metric line that links no measurement is unlinked, and a Metric
/// link to a measurement that does not link the goal is a mismatch. Runs only
/// when the merged set holds the goal and measurement doc types.
Iterable<Finding> checkGoalMeasurements(
  CheckContext context,
  IndexedDoc doc,
) sync* {
  if (!context.hasGoal || !context.hasMeasurement) return;
  switch (doc.docTypeId) {
    case _goalType:
      yield* _goalFindings(context, doc);
    case _measurementType:
      yield* _measurementFindings(context, doc);
  }
}

_GoalLinks _linksOf(CheckContext context) =>
    _goalLinksOf[context] ??= _readGoalLinks(context);

_GoalLinks _readGoalLinks(CheckContext context) {
  final goals = _goalsOf(context);
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

Map<_Goal, List<BodyLine>> _goalsOf(CheckContext context) => {
  for (final GoalBlock(:docPath, :key, :lines) in context.goalBlocks())
    (docPath: docPath, line: lines.first.line, key: key): lines,
};

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
  final linked = context.index.at(target);
  if (linked == null || anchor == null || anchor.isEmpty) return null;
  final named = anchorTargetOf(context.contentOf(linked).lineFacts, anchor);
  if (named is! HeadingBlockTarget) return null;
  return known
      .where(
        (goal) =>
            goal.docPath == linked.docPath && goal.line == named.headingLine,
      )
      .firstOrNull;
}

Iterable<Finding> _goalFindings(CheckContext context, IndexedDoc doc) sync* {
  final links = _linksOf(context);
  for (final MapEntry(key: goal, value: lines) in links.goals.entries) {
    if (goal.docPath != doc.docPath) continue;
    final named = links.measurementsOfGoal[goal] ?? const <IndexedDoc>[];
    yield* _coverageFinding(context, doc, goal, named);
    yield* _metricFindings(context, doc, goal, lines);
  }
}

Iterable<Finding> _coverageFinding(
  CheckContext context,
  IndexedDoc doc,
  _Goal goal,
  List<IndexedDoc> named,
) sync* {
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
}

Iterable<Finding> _metricFindings(
  CheckContext context,
  IndexedDoc doc,
  _Goal goal,
  List<BodyLine> block,
) sync* {
  final metricAt = _metricLineOf(block);
  if (metricAt == null) return;
  final linked = _metricMeasurementsOf(context, doc, metricAt);
  if (linked.isEmpty) {
    yield context.finding(
      doc,
      FindingKind.goalMetricUnlinked,
      line: metricAt,
      message: _unlinkedMessage,
      keys: {'goal': goal.key},
    );
    return;
  }
  final goalsOfMeasurement = _linksOf(context).goalsOfMeasurement;
  final mismatched = [
    for (final measurement in linked)
      if (!(goalsOfMeasurement[measurement.docPath] ?? const <_Goal>[])
          .contains(goal))
        measurement,
  ];
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

int? _metricLineOf(List<BodyLine> block) => block
    .where((line) => !line.fenced && _metricLine.hasMatch(line.text))
    .map((line) => line.line)
    .firstOrNull;

/// The measurements the links on the Metric line [metricAt] of [doc] resolve
/// to, each once, whatever the link's form or anchor.
List<IndexedDoc> _metricMeasurementsOf(
  CheckContext context,
  IndexedDoc doc,
  int metricAt,
) {
  final linked = <IndexedDoc>[];
  for (final place in context.contentOf(doc).lineFacts.links) {
    if (place.line != metricAt) continue;
    final target = context.index.at(place.target);
    if (target == null || target.docTypeId != _measurementType) continue;
    if (!linked.contains(target)) linked.add(target);
  }
  return linked;
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
      message: 'the head links no goal of the goal doc',
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
