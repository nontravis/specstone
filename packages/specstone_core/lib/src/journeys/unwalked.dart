import 'package:specstone_core/src/consistency_check/scenario_blocks.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/index_query/index_fault.dart';
import 'package:specstone_core/src/index_query/read_answer.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';

const _storyType = 'user_story';
final _headingPrefix = RegExp(r'^### Scenario [0-9]+(?![0-9])\s*(?:—\s*)?');

/// Keeps each story of [listed] that holds a scenario no journey walks.
///
/// [listed] is what `answerList` returned for [docTypeId], so its faults come
/// first. A scenario is walked when a `step:` line of any journey, draft or
/// not, names a story that holds it. Prints each kept story's line, then
/// `  S<N> <heading text>` per unwalked scenario; `--json` adds `unwalked`,
/// the `S<N>` labels, to each kept doc.
///
/// Throws an [IndexFault] when [docTypeId] is not `user_story`.
ReadAnswer answerListUnwalked(
  DocIndex index,
  String docTypeId,
  ReadAnswer listed,
) {
  if (docTypeId != _storyType) {
    throw IndexFault(
      IndexFaultCode.argumentInvalid,
      '--unwalked lists user_story docs only, not $docTypeId',
    );
  }
  final walked = _walkedScenarios(index);
  final text = StringBuffer();
  final docs = <Map<String, Object>>[];
  for (final entry in listed.json['docs']! as List) {
    final doc = index.at((entry as Map)['path']! as String);
    if (doc == null) continue;
    final unwalked = [
      for (final MapEntry(:key, :value) in storyScenarioBlocks(
        index,
        doc,
      ).entries)
        if (!walked.contains((doc.docPath, key))) (label: key, block: value),
    ];
    if (unwalked.isEmpty) continue;
    text.writeln(docLine(index, doc));
    for (final (:label, :block) in unwalked) {
      text.writeln('  $label ${_headingText(block)}');
    }
    docs.add({
      ...entry.cast<String, Object>(),
      'unwalked': [for (final scenario in unwalked) scenario.label],
    });
  }
  return ReadAnswer(text: text.toString(), json: {'docs': docs});
}

// The (story DocPath, `S<N>`) pairs a step of any journey names.
Set<(String, String)> _walkedScenarios(DocIndex index) {
  final walked = <(String, String)>{};
  for (final journey in index.docs) {
    if (journey.docTypeId != journeyTypeId) continue;
    for (final step in stepsOfIndexed(index, journey).steps) {
      final target = step.target;
      if (target == null) continue;
      final story = storyNamed(index, target.identity);
      if (story != null) walked.add((story.docPath, target.scenarioLabel));
    }
  }
  return walked;
}

String _headingText(String block) {
  final heading = block.split('\n').first;
  return heading.replaceFirst(_headingPrefix, '');
}
