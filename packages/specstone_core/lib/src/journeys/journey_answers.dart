import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';

const _frType = 'fr';
const _implementsKey = 'implements';
const _tracedFromKey = 'traced_from';
const _pathsOption = '--paths';
const _codeOption = '--code';
const _noPathLabel = 'no path';

typedef _JourneyPart = ({
  List<String> lines,
  Map<String, Object?> json,
  List<String> warnings,
});

typedef _JourneyBody = _JourneyPart Function(
  DocIndex index,
  IndexedDoc journey,
  JourneySteps steps,
);

/// Returns each path of every journey [name] addresses, with its steps.
///
/// A step prints its scenario lines as the story holds them now, never the
/// pasted copy. Throws an [IndexFault] when [name] resolves to a doc that is
/// not a journey.
ReadAnswer answerJourneyPaths(DocIndex index, String name) =>
    _answerJourneys(index, name, _pathsOption, _pathsOf);

/// Returns, per step of every journey [name] addresses, the code its story and
/// the FRs traced from its scenario implement.
///
/// Throws an [IndexFault] when [name] resolves to a doc that is not a journey.
ReadAnswer answerJourneyCode(DocIndex index, String name) =>
    _answerJourneys(index, name, _codeOption, _codeOf);

ReadAnswer _answerJourneys(
  DocIndex index,
  String name,
  String option,
  _JourneyBody body,
) {
  final journeys = index.resolve(name);
  final other = journeys.where((doc) => doc.docTypeId != journeyTypeId);
  if (other.isNotEmpty) {
    final doc = other.first;
    final typeId = doc.docTypeId;
    final label = typeId == null ? doc.name : '$typeId:${doc.name}';
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '$label is not a journey; $option reads journeys only',
    );
  }

  final blocks = <String>[];
  final json = <Object>[];
  final warnings = <String>[];
  for (final journey in journeys) {
    final part = body(index, journey, stepsOfIndexed(index, journey));
    blocks.add('${[namingLine(journey), ...part.lines].join('\n')}\n');
    json.add({'name': journey.name, 'path': journey.docPath, ...part.json});
    warnings.addAll(part.warnings);
  }
  return ReadAnswer(
    text: blocks.join('\n'),
    json: {'journeys': json},
    warnings: warnings,
  );
}

// MARK: - Paths

_JourneyPart _pathsOf(DocIndex index, IndexedDoc journey, JourneySteps steps) {
  final resolved = [for (final step in steps.steps) _ResolvedStep(index, step)];
  final lines = <String>[];
  final pathsJson = <Object>[];
  for (final path in steps.paths) {
    final id = resolved[path.last].step.number;
    final cite = 'journey:${journey.name} path $id';
    lines.add(cite);
    for (final i in path) {
      lines.addAll(resolved[i].scenarioLines);
    }
    pathsJson.add({
      'id': id,
      'cite': cite,
      'steps': [for (final i in path) resolved[i].pathJson],
    });
  }
  if (steps.offPathIndexes.isNotEmpty) {
    lines.add('journey:${journey.name} $_noPathLabel');
    for (final i in steps.offPathIndexes) {
      lines.addAll(resolved[i].scenarioLines);
    }
  }

  final duplicates = {
    for (final i in steps.duplicateIndexes) steps.steps[i].number,
  };
  final warnings = [
    for (final step in resolved)
      if (step.scenario == null)
        '${journey.name}: step ${step.step.number} names no scenario',
    for (final i in steps.offPathIndexes) _offPathWarning(journey, steps, i),
    for (final number in duplicates)
      '${journey.name}: step number $number is written twice',
  ];
  return (lines: lines, json: {'paths': pathsJson}, warnings: warnings);
}

String _offPathWarning(IndexedDoc journey, JourneySteps steps, int i) {
  final number = steps.steps[i].number;
  final followed = steps.followedIndex(i);
  return followed == null
      ? '${journey.name}: step $number follows no step above it, '
            'so it is on no path'
      : '${journey.name}: step $number follows step '
            '${steps.steps[followed].number}, which is on no path';
}

// MARK: - Code

_JourneyPart _codeOf(DocIndex index, IndexedDoc journey, JourneySteps steps) {
  final lines = <String>[];
  final stepsJson = <Object>[];
  final warnings = <String>[];
  for (final step in steps.steps) {
    final resolved = _ResolvedStep(index, step);
    lines.add(resolved.line);
    final target = resolved.target;
    final story = target == null ? null : storyNamed(index, target.identity);
    if (resolved.scenario == null || story == null) {
      warnings.add('${journey.name}: step ${step.number} names no scenario');
      stepsJson.add({...resolved.baseJson, 'frs': <Object>[]});
      continue;
    }
    final frs = [
      for (final child in index.childrenOf(story))
        if (child.docTypeId == _frType &&
            child.valuesOf(_tracedFromKey).contains(target!.scenarioLabel))
          child,
    ];
    for (final doc in [story, ...frs]) {
      lines.addAll(_codeLines(doc));
    }
    stepsJson.add({
      ...resolved.baseJson,
      'story': _codeJson(story),
      'frs': [for (final fr in frs) _codeJson(fr)],
    });
  }
  return (lines: lines, json: {'steps': stepsJson}, warnings: warnings);
}

List<String> _codeLines(IndexedDoc doc) {
  final entries = doc.valuesOf(_implementsKey);
  return [
    '  ${nameWithType(doc)}',
    if (entries.isEmpty) '  - none',
    for (final entry in entries) '  - implements: $entry',
  ];
}

Map<String, Object> _codeJson(IndexedDoc doc) => {
  'name': doc.name,
  'implements': doc.valuesOf(_implementsKey),
};

// MARK: - ResolvedStep

/// One journey step with the scenario its target names, read from the Index.
final class _ResolvedStep {
  new(DocIndex index, this.step)
    : target = step.target,
      scenario = _scenarioOf(index, step.target);

  final JourneyStep step;
  final StepTarget? target;

  /// The lines of the scenario block after its heading; null when unresolved.
  final String? scenario;

  /// `<number>. <heading>`, then ` — <step:>` when the step has one.
  String get line {
    final value = step.stepValue;
    return '${step.number}. ${step.heading}'
        '${value == null ? '' : ' — $value'}';
  }

  /// The step line, then each line of its scenario.
  List<String> get scenarioLines => [
    line,
    if (scenario case final text? when text.isNotEmpty) text,
  ];

  Map<String, Object?> get baseJson => {
    'number': step.number,
    'heading': step.heading,
    'step': step.stepValue,
  };

  Map<String, Object?> get pathJson => {...baseJson, 'scenario': scenario};

  static String? _scenarioOf(DocIndex index, StepTarget? target) {
    final block = target == null ? null : scenarioBlockOf(index, target);
    return block == null ? null : scenarioCopyOf(block);
  }
}
