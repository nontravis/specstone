import 'package:specstone_core/src/doc_model/doc.dart';
import 'package:specstone_core/src/index_query/doc_index.dart';
import 'package:specstone_core/src/journeys/journey_steps.dart';
import 'package:specstone_core/src/journeys/step_scenarios.dart';
import 'package:specstone_core/src/rendering/generated_blocks.dart';
import 'package:specstone_core/src/templates/merged_doc_type.dart';

// MARK: - Registry

/// Returns the generators `format` runs for the `journey` doc type.
GeneratorRegistry<DocIndex> journeyGenerators() => GeneratorRegistry<DocIndex>({
  journeyFlowKind: journeyFlowBlocks,
  scenarioCopyKind: scenarioCopyBlocks,
});

// MARK: - journey_flow

/// Returns the Mermaid fence that draws [steps], without marker lines.
///
/// Reads the steps only, so a step that names no scenario is drawn too.
String journeyFlowText(JourneySteps steps) {
  final all = steps.steps;
  return [
    '```mermaid',
    'flowchart TD',
    for (final step in all) _nodeLine(step),
    for (var to = 0; to < all.length; to++)
      if (steps.followedIndex(to) case final from?)
        '  s${all[from].number} --> s${all[to].number}',
    '```',
  ].join('\n');
}

/// Returns the flow diagram block for the top of the `flow` section.
List<GeneratedBlock> journeyFlowBlocks(
  Doc doc,
  MergedDocType docType,
  DocIndex index,
) => [
  GeneratedBlock(
    kind: journeyFlowKind,
    sectionId: flowSectionId,
    place: const SectionTop(),
    text: journeyFlowText(_stepsOf(doc, docType)),
  ),
];

// MARK: - scenario_copy

/// Returns, for each step whose scenario resolves, the scenario's lines below
/// the step's last field line.
List<GeneratedBlock> scenarioCopyBlocks(
  Doc doc,
  MergedDocType docType,
  DocIndex index,
) => [
  for (final step in _stepsOf(doc, docType).steps)
    if (step.target case final target?)
      if (scenarioBlockOf(index, target) case final block?)
        GeneratedBlock(
          kind: scenarioCopyKind,
          sectionId: stepsSectionId,
          place: BelowBodyLine(step.anchorIndex),
          text: scenarioCopyOf(block),
        ),
];

// MARK: - Helpers

String _nodeLine(JourneyStep step) {
  final heading = step.heading.replaceAll('"', '#quot;');
  return '  s${step.number}["${step.number}. $heading"]';
}

JourneySteps _stepsOf(Doc doc, MergedDocType docType) {
  final section = sectionIndexOf(doc, docType, stepsSectionId);
  return readJourneySteps(
    section == null ? '' : doc.sections[section].body,
    blockKinds: docType.listedGenerators.toSet(),
  );
}
