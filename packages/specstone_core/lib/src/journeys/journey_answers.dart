import 'package:specstone_core/src/doc_model/reference_grammar.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/indexed_doc.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';
import 'package:specstone_core/src/templates/doc_type_layer.dart';

const _frType = 'fr';
const _implementsLabel = 'implements';
const _skippedLabel = 'skipped';
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
  String? codeTarget,
);

/// Returns each path of every journey [name] addresses, with its steps.
///
/// A step prints its scenario lines as the story holds them now, never the
/// pasted copy. [codeTarget], when given, keeps [name] to that code target's
/// docs and the shared docs. Throws an [IndexFault] when [name] resolves to a
/// doc that is not a journey.
ReadAnswer answerJourneyPaths(
  DocIndex index,
  String name, {
  String? codeTarget,
}) => _answerJourneys(index, name, _pathsOption, _pathsOf, codeTarget);

/// Returns, per step of every journey [name] addresses, the record code paths
/// of its story and of the FRs traced from its scenario.
///
/// With two or more code targets each path reads under its target's name;
/// [codeTarget], when given, keeps [name] and the paths to that target.
/// Throws an [IndexFault] when [name] is not a journey.
ReadAnswer answerJourneyCode(
  DocIndex index,
  String name, {
  String? codeTarget,
}) => _answerJourneys(index, name, _codeOption, _codeOf, codeTarget);

ReadAnswer _answerJourneys(
  DocIndex index,
  String name,
  String option,
  _JourneyBody body,
  String? codeTarget,
) {
  final journeys = index.resolve(name, codeTarget: codeTarget);
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
    final part = body(
      index,
      journey,
      stepsOfIndexed(index, journey),
      codeTarget,
    );
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

_JourneyPart _pathsOf(
  DocIndex index,
  IndexedDoc journey,
  JourneySteps steps,
  String? codeTarget,
) {
  final resolved = [
    for (final step in steps.steps)
      _ResolvedStep(index, step, codeTarget: codeTarget),
  ];
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

/// Returns the `fr` docs whose `traced_from` names [target] of [story]: the
/// story's own first, then those of any other story in tree order.
///
/// Entries compare by resolved story and scenario number, never by label
/// (P10); a story of another feature counts, as only `check` limits to
/// siblings.
List<IndexedDoc> _frsTracing(
  DocIndex index,
  IndexedDoc story,
  StepTarget target,
) {
  final tracing = [
    for (final fr in index.docs)
      if (fr.docTypeId == _frType && _traces(index, fr, story, target)) fr,
  ];
  bool isOwn(IndexedDoc fr) => fr.parentPath == story.docPath;
  return [...tracing.where(isOwn), ...tracing.where((fr) => !isOwn(fr))];
}

bool _traces(
  DocIndex index,
  IndexedDoc fr,
  IndexedDoc story,
  StepTarget target,
) {
  for (final entry in fr.valuesOf(_tracedFromKey)) {
    final ref = readScenarioRef(entry);
    if (ref?.scenario != BigInt.from(target.scenario)) continue;
    final name = ref!.storyName;
    final tracedStory = name == null
        ? index.parentOf(fr)
        : storyNamed(index, name);
    if (tracedStory?.docPath == story.docPath) return true;
  }
  return false;
}

_JourneyPart _codeOf(
  DocIndex index,
  IndexedDoc journey,
  JourneySteps steps,
  String? codeTarget,
) {
  final lines = <String>[];
  final stepsJson = <Object>[];
  final warnings = <String>[];
  for (final step in steps.steps) {
    final resolved = _ResolvedStep(index, step, codeTarget: codeTarget);
    lines.add(resolved.line);
    final target = resolved.target;
    final story = target == null
        ? null
        : storyNamed(index, target.identity, codeTarget: codeTarget);
    if (resolved.scenario == null || story == null) {
      warnings.add('${journey.name}: step ${step.number} names no scenario');
      stepsJson.add({...resolved.baseJson, 'frs': <Object>[]});
      continue;
    }
    final frs = _frsTracing(index, story, target!);
    for (final doc in [story, ...frs]) {
      lines.addAll(_codeLines(index, doc, codeTarget));
    }
    stepsJson.add({
      ...resolved.baseJson,
      'story': _codeJson(index, story, codeTarget),
      'frs': [for (final fr in frs) _codeJson(index, fr, codeTarget)],
    });
  }
  return (lines: lines, json: {'steps': stepsJson}, warnings: warnings);
}

/// One code target's record paths for a doc, and whether its record skips it.
typedef _TargetCode = ({String? target, List<String> paths, bool skipped});

/// Returns the code of [doc] per code target: every target in `targets:`
/// order with two or more and no [codeTarget], else the one.
List<_TargetCode> _targetCodeOf(
  DocIndex index,
  IndexedDoc doc,
  String? codeTarget,
) {
  final targets = _isGrouped(index, codeTarget)
      ? index.targetNames
      : [codeTarget];
  final hasRecords = index.set.recordDocType != null;
  return [
    for (final target in targets)
      _targetCodeFor(index, doc, target, hasRecords: hasRecords),
  ];
}

/// A skipped item holds no paths, so text and JSON agree on it.
_TargetCode _targetCodeFor(
  DocIndex index,
  IndexedDoc doc,
  String? target, {
  required bool hasRecords,
}) {
  final skipped =
      hasRecords &&
      index.itemStatus(doc, codeTarget: target) == RecordStatus.skipped;
  final entry = index.recordEntryOf(doc, codeTarget: target);
  return (
    target: target,
    paths: skipped ? const [] : entry?.codePaths ?? const [],
    skipped: skipped,
  );
}

bool _isGrouped(DocIndex index, String? codeTarget) =>
    codeTarget == null && index.targetNames.length > 1;

List<String> _codeLines(DocIndex index, IndexedDoc doc, String? codeTarget) {
  final grouped = _isGrouped(index, codeTarget);
  final entries = [
    for (final code in _targetCodeOf(index, doc, codeTarget)) ...[
      if (code.skipped)
        '  - ${grouped ? '${code.target}: ' : ''}$_skippedLabel'
      else
        for (final path in code.paths)
          '  - ${grouped ? code.target : _implementsLabel}: $path',
    ],
  ];
  return [
    '  ${nameWithType(doc)}',
    if (entries.isEmpty) '  - none' else ...entries,
  ];
}

Map<String, Object> _codeJson(
  DocIndex index,
  IndexedDoc doc,
  String? codeTarget,
) {
  final code = _targetCodeOf(index, doc, codeTarget);
  return {
    'name': doc.name,
    if (_isGrouped(index, codeTarget))
      'implementsByTarget': {for (final c in code) c.target!: c.paths}
    else
      _implementsLabel: code.single.paths,
  };
}

// MARK: - ResolvedStep

/// One journey step with the scenario its target names, read from the Index.
final class _ResolvedStep {
  new(DocIndex index, this.step, {String? codeTarget})
    : target = step.target,
      scenario = _scenarioOf(index, step.target, codeTarget: codeTarget);

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

  static String? _scenarioOf(
    DocIndex index,
    StepTarget? target, {
    String? codeTarget,
  }) {
    final block = target == null
        ? null
        : scenarioBlockOf(index, target, codeTarget: codeTarget);
    return block == null ? null : scenarioCopyOf(block);
  }
}
