import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';

// MARK: - Constants

/// Id of the journey doc type.
const journeyTypeId = 'journey';

/// Id of the journey section that holds the flow diagram.
const flowSectionId = 'flow';

/// Id of the journey section that holds the steps.
const stepsSectionId = 'steps';

/// Kind of the generated block that draws the journey flow.
const journeyFlowKind = 'journey_flow';

/// Kind of the generated block that pastes a step's scenario.
const scenarioCopyKind = 'scenario_copy';

final _stepHeading = RegExp(r'^### ([0-9]+[a-z]*)\. (.+)$');
final _stepTarget = RegExp(r'^([a-z0-9_]+(?:/[a-z0-9_]+)*) S([0-9]+)$');
const _stepPrefix = 'step:';
const _afterPrefix = 'after:';

// MARK: - StepTarget

/// The story identity and scenario number a step names.
final class StepTarget {
  const new(this.identity, this.scenario);

  final String identity;
  final int scenario;

  /// The journey link label, `<identity>#S<scenario>`.
  String get label => '$identity#S$scenario';

  /// The scenario heading label, `S<scenario>`.
  String get scenarioLabel => 'S$scenario';
}

/// Reads [value] as `<story identity> S<N>`; returns null when it does not.
StepTarget? readStepTarget(String value) {
  final match = _stepTarget.firstMatch(value);
  final scenario = int.tryParse(match?.group(2) ?? '');
  if (match == null || scenario == null) return null;
  return StepTarget(match.group(1)!, scenario);
}

// MARK: - JourneyStep

/// One `### <number>. <heading>` step and the lines a person edits in it.
///
/// Indexes are 0-based lines of the steps section body.
final class JourneyStep {
  const new({
    required this.number,
    required this.heading,
    required this.headingIndex,
    this.stepValue,
    this.stepIndex,
    this.afterValue,
    this.afterIndex,
  });

  final String number;
  final String heading;
  final int headingIndex;

  /// The trimmed value of the first `step:` line of the step.
  final String? stepValue;
  final int? stepIndex;

  /// The trimmed value of the first `after:` line below the `step:` line.
  final String? afterValue;
  final int? afterIndex;

  /// Reads [stepValue] as a target; null when absent or unreadable.
  StepTarget? get target {
    final value = stepValue;
    return value == null ? null : readStepTarget(value);
  }

  /// The line a fault about this step points at.
  int get anchorIndex => afterIndex ?? stepIndex ?? headingIndex;
}

// MARK: - JourneySteps

/// The steps of one journey and the tree they form.
final class JourneySteps {
  new(this.steps) {
    _followed = List.filled(steps.length, null);
    _onPath = List.filled(steps.length, false);
    for (var i = 0; i < steps.length; i++) {
      _followed[i] = _followedBy(i);
      final followed = _followed[i];
      _onPath[i] = i == 0 || (followed != null && _onPath[followed]);
    }
  }

  /// The steps, in written order.
  final List<JourneyStep> steps;

  late final List<int?> _followed;
  late final List<bool> _onPath;

  /// The index of the step that step [i] follows; null for the first step and
  /// for a step whose `after:` names no step written above it.
  int? followedIndex(int i) => _followed[i];

  /// Headings whose number a heading above carries.
  List<int> get duplicateIndexes => [
    for (var i = 0; i < steps.length; i++)
      if (steps.take(i).any((s) => s.number == steps[i].number)) i,
  ];

  /// Steps whose `after:` names no step written above them.
  List<int> get unresolvedAfterIndexes => [
    for (var i = 0; i < steps.length; i++)
      if (steps[i].afterValue != null && _followed[i] == null) i,
  ];

  /// Steps that lie on no path.
  List<int> get offPathIndexes => [
    for (var i = 0; i < steps.length; i++)
      if (!_onPath[i]) i,
  ];

  /// One `(followed, follower)` pair per on-path follower, in follower order.
  List<(int from, int to)> get edges => [
    for (var i = 1; i < steps.length; i++)
      if (_onPath[i]) (_followed[i]!, i),
  ];

  /// Root-to-leaf step indexes, ordered by the written position of the leaf.
  List<List<int>> get paths {
    final hasFollower = {for (final (from, _) in edges) from};
    return [
      for (var i = 0; i < steps.length; i++)
        if (_onPath[i] && !hasFollower.contains(i)) _chainTo(i),
    ];
  }

  int? _followedBy(int i) {
    if (i == 0) return null;
    final after = steps[i].afterValue;
    if (after == null) return i - 1;
    final named = steps.take(i).toList().indexWhere((s) => s.number == after);
    return named < 0 ? null : named;
  }

  List<int> _chainTo(int leaf) {
    final chain = <int>[];
    for (int? i = leaf; i != null; i = _followed[i]) {
      chain.add(i);
    }
    return chain.reversed.toList();
  }
}

// MARK: - Reading

/// Reads the steps of [stepsBody], the body of the `steps` section.
///
/// Fenced lines and lines of generated blocks of [blockKinds] are skipped.
JourneySteps readJourneySteps(
  String stepsBody, {
  required Set<String> blockKinds,
}) {
  final lines = stepsBody.split('\n');
  final fenced = fencedLines(lines);
  final generated = generatedBlockLines(lines, blockKinds);
  final readable = [
    for (var i = 0; i < lines.length; i++) !fenced[i] && !generated[i],
  ];

  final steps = <JourneyStep>[];
  for (var i = 0; i < lines.length; i++) {
    if (!readable[i]) continue;
    final heading = _stepHeading.firstMatch(lines[i]);
    if (heading == null) continue;
    final end = _regionEnd(lines, readable, i);
    steps.add(_readStep(lines, readable, i, end, heading));
  }
  return JourneySteps(steps);
}

/// Returns the index of the next readable `### ` line after [from], or the
/// body end.
int _regionEnd(List<String> lines, List<bool> readable, int from) {
  for (var i = from + 1; i < lines.length; i++) {
    if (readable[i] && lines[i].startsWith('### ')) return i;
  }
  return lines.length;
}

JourneyStep _readStep(
  List<String> lines,
  List<bool> readable,
  int headingIndex,
  int end,
  RegExpMatch heading,
) {
  final stepIndex = _firstLine(
    lines,
    readable,
    _stepPrefix,
    headingIndex + 1,
    end,
  );
  final afterIndex = stepIndex == null
      ? null
      : _firstLine(lines, readable, _afterPrefix, stepIndex + 1, end);
  return JourneyStep(
    number: heading.group(1)!,
    heading: heading.group(2)!.trim(),
    headingIndex: headingIndex,
    stepValue: stepIndex == null
        ? null
        : _valueOf(lines[stepIndex], _stepPrefix),
    stepIndex: stepIndex,
    afterValue: afterIndex == null
        ? null
        : _valueOf(lines[afterIndex], _afterPrefix),
    afterIndex: afterIndex,
  );
}

int? _firstLine(
  List<String> lines,
  List<bool> readable,
  String prefix,
  int start,
  int end,
) {
  for (var i = start; i < end; i++) {
    if (readable[i] && lines[i].startsWith(prefix)) return i;
  }
  return null;
}

String _valueOf(String line, String prefix) =>
    line.substring(prefix.length).trim();
